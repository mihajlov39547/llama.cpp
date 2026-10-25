# Local server inspection/control helpers. Never stop a process by name alone.
. (Join-Path $PSScriptRoot 'runtime-paths.ps1')
function Get-ServerFailureDetails {
    param([string]$LogPath)
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return "No startup log available at $LogPath" }
    $tail = @(Get-Content -LiteralPath $LogPath -Tail 60 -ErrorAction SilentlyContinue)
    $errors = @($tail | Where-Object { $_ -match '(?i)error|failed|fatal|unsupported|invalid|unknown argument' } | Select-Object -Last 6)
    if (-not $errors.Count) { $errors=@($tail | Select-Object -Last 8) }
    return ("Startup log: $LogPath`n" + ($errors -join "`n"))
}
function Get-LocalServerProcess {
    param([int]$Port = 8080)
    $owners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
        Where-Object { $_.LocalPort -eq $Port -and $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::','::1') } |
        Select-Object -ExpandProperty OwningProcess -Unique)
    if (-not $owners.Count) { return $null }
    if ($owners.Count -ne 1) { throw "Multiple processes listen on port $Port; cannot manage it safely." }
    Get-CimInstance Win32_Process -Filter "ProcessId = $($owners[0])" -ErrorAction Stop
}

function Assert-LocalServerIdentity {
    param($Expected, [int]$Port)
    $current = Get-LocalServerProcess -Port $Port
    if (-not $Expected -or -not $current -or $current.ProcessId -ne $Expected.ProcessId -or
        $current.CreationDate -ne $Expected.CreationDate -or
        -not (Test-WorkspaceServerExecutable $current.ExecutablePath)) {
        throw 'Server identity changed or this port belongs to another application. Refresh status before retrying.'
    }
    $current
}

function Read-ServerEndpoint {
    param([int]$Port, [string]$Path, [switch]$Text)
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/$Path" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($Text) { return [string]$r.Content }
        return ($r.Content | ConvertFrom-Json)
    } catch { return $null }
}

function ConvertFrom-ServerMetrics {
    param([string]$Text)
    $values = [ordered]@{}
    foreach ($line in ($Text -split "`n")) {
        if ($line -match '^(llamacpp[:_][a-zA-Z0-9_]+)(?:\{[^}]*\})?\s+([-+0-9.eE]+)(?:\s|$)') {
            $name = $matches[1]; $value = 0.0
            if ([double]::TryParse($matches[2], [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
                if ($values.Contains($name)) { $values[$name] += $value } else { $values[$name] = $value }
            }
        }
    }
    return $values
}

function Save-ServerLogRecord {
    param($Process, [int]$Port, [string]$Stdout, [string]$Stderr)
    $dir = Join-Path $PSScriptRoot 'logs'
    [void][IO.Directory]::CreateDirectory($dir)
    @{ ProcessId=$Process.Id; StartTime=$Process.StartTime.ToUniversalTime().ToString('o'); Stdout=$Stdout; Stderr=$Stderr } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir "server-$Port.json") -Encoding UTF8
}

function Get-ServerLaunchOptions {
    param([string]$CommandLine)
    $options = @{}
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $options }
    # Use Windows argument parsing so quoted paths/JSON cannot masquerade as flags.
    if (-not ('LlamaStatus.CommandLine' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace LlamaStatus {
    public static class CommandLine {
        [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
        static extern IntPtr CommandLineToArgvW(string command, out int count);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
        public static string[] Split(string command) {
            int count; IntPtr memory = CommandLineToArgvW(command, out count);
            if (memory == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
            try {
                var result = new string[count];
                for (int i=0; i<count; i++) result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory, i * IntPtr.Size));
                return result;
            } finally { LocalFree(memory); }
        }
    }
}
'@
    }
    $tokens = [LlamaStatus.CommandLine]::Split($CommandLine)
    $aliases = @{
        '-rea'='--reasoning'; '-fa'='--flash-attn'; '-ctk'='--cache-type-k'; '-ctv'='--cache-type-v'
        '-n'='--n-predict'; '--predict'='--n-predict'; '-c'='--ctx-size'
        '-b'='--batch-size'; '-ub'='--ubatch-size'; '-t'='--threads'
        '-ngl'='--gpu-layers'; '--n-gpu-layers'='--gpu-layers'
        '-kvo'='--kv-offload'; '-nkvo'='--no-kv-offload'
    }
    for ($i=1; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -notmatch '^(-{1,2}[a-zA-Z][\w-]*)(?:=(.*))?$') { continue }
        $key=$matches[1]; $value=$true
        if ($matches.ContainsKey(2)) { $value=$matches[2] }
        elseif ($i+1 -lt $tokens.Count -and $tokens[$i+1] -notmatch '^--?[a-zA-Z]') { $value=$tokens[++$i] }
        if ($aliases.ContainsKey($key)) { $key=$aliases[$key] }
        switch ($key) {
            '--no-cache-prompt' { $key='--cache-prompt'; $value='off' }
            '--cache-prompt' { $value='on' }
            '--no-kv-offload' { $key='--kv-offload'; $value='off' }
            '--kv-offload' { $value='on' }
        }
        $options[$key]=$value
    }
    return $options
}

function Format-ServerValue {
    param($Value, [string]$Missing='unavailable')
    if ($null -eq $Value -or [string]$Value -eq '') { return $Missing }
    if ($Value -is [bool]) { return ([string]$Value).ToLowerInvariant() }
    if ($Value -is [array]) { return ($Value -join ', ') }
    return [string]$Value
}

function Get-ServerInferenceLines {
    param($Options, $Props)
    $missing='not set (runtime/model default)'
    $reasoning=Format-ServerValue $Options['--reasoning'] $missing
    $budget=Format-ServerValue $Options['--reasoning-budget'] $missing
    if ($budget -eq '-1') { $budget='-1 (no separate thinking cap)' }
    elseif ($budget -eq '0') { $budget='0 (immediate end of thinking)' }
    "Launch reasoning: $reasoning | Thinking budget: $budget"
    "Launch output allowance: $(Format-ServerValue $Options['--n-predict'] $missing) tokens (thinking + answer; requests may override)"
    "Launch KV cache: K=$(Format-ServerValue $Options['--cache-type-k'] $missing), V=$(Format-ServerValue $Options['--cache-type-v'] $missing) | Offload: $(Format-ServerValue $Options['--kv-offload'] $missing)"
    "Launch prompt cache: $(Format-ServerValue $Options['--cache-prompt'] $missing) | Cache RAM MiB: $(Format-ServerValue $Options['--cache-ram'] $missing) | Reuse threshold: $(Format-ServerValue $Options['--cache-reuse'] $missing)"
    "Launch compute: Flash Attention=$(Format-ServerValue $Options['--flash-attn'] $missing), GPU layers=$(Format-ServerValue $Options['--gpu-layers'] $missing), threads=$(Format-ServerValue $Options['--threads'] $missing), batch=$(Format-ServerValue $Options['--batch-size'] $missing), microbatch=$(Format-ServerValue $Options['--ubatch-size'] $missing)"
    "Launch template: $(Format-ServerValue $Options['--chat-template-file'] 'embedded/default (unless otherwise overridden)')"
    $params=$Props.default_generation_settings.params
    "API reasoning defaults: format=$(Format-ServerValue $params.reasoning_format), in content=$(Format-ServerValue $params.reasoning_in_content), budget=$(Format-ServerValue $params.reasoning_budget)"
    "API output defaults: n_predict=$(Format-ServerValue $params.n_predict), max_tokens=$(Format-ServerValue $params.max_tokens) (-1 means no explicit cap)"
    "API template capabilities: tools=$(Format-ServerValue $Props.chat_template_caps.supports_tools), tool calls=$(Format-ServerValue $Props.chat_template_caps.supports_tool_calls), preserve reasoning=$(Format-ServerValue $Props.chat_template_caps.supports_preserve_reasoning)"
}

function Get-ServerStatusLines {
    param($Server, [int]$Port)
    "Address: http://127.0.0.1:$Port | Snapshot: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if (-not $Server) { 'No local listening process found.'; return }
    "Process: $($Server.Name) | PID: $($Server.ProcessId)"
    if (-not (Test-WorkspaceServerExecutable $Server.ExecutablePath)) {
        'This is not this workspace''s llama-server. Stop/restart are blocked.'; return
    }
    try {
        $process = Get-Process -Id $Server.ProcessId -ErrorAction Stop
        $age = (Get-Date) - $process.StartTime
        'Uptime: {0}d {1:00}:{2:00}:{3:00} | RAM: {4:N0} MiB | Private: {5:N0} MiB | CPU time: {6:N1}s | Threads: {7}' -f
            $age.Days,$age.Hours,$age.Minutes,$age.Seconds,($process.WorkingSet64 / 1MB),($process.PrivateMemorySize64 / 1MB),$process.CPU,$process.Threads.Count
    } catch { 'Process statistics unavailable (it may have exited).' }
    $health = Read-ServerEndpoint $Port 'health'
    "Health: $(if ($health) { $health.status } else { 'unavailable/loading/unresponsive' })"
    $props = Read-ServerEndpoint $Port 'props'
    $models = Read-ServerEndpoint $Port 'v1/models'
    try { $launch = Get-ServerLaunchOptions $Server.CommandLine }
    catch { $launch=@{}; 'Launch argument parsing unavailable.' }
    Get-ServerInferenceLines $launch $props
    if ($props) {
        "Model: $($props.model_alias) | File: $($props.model_path)"
        "Context per slot: $($props.default_generation_settings.n_ctx) | Slots: $($props.total_slots) | Web UI: $($props.webui) | Build: $($props.build_info)"
        $sampling = $props.default_generation_settings.params
        "Default sampling: temperature=$($sampling.temperature), top_k=$($sampling.top_k), top_p=$($sampling.top_p), min_p=$($sampling.min_p)"
        "Default penalties: repeat=$(Format-ServerValue $sampling.repeat_penalty), presence=$(Format-ServerValue $sampling.presence_penalty), frequency=$(Format-ServerValue $sampling.frequency_penalty) | Samplers: $(Format-ServerValue $sampling.samplers)"
    }
    foreach ($model in $models.data) {
        "API model: $($model.id)"
        if ($model.meta) {
            'Metadata: {0:N2}B parameters | {1:N2} GiB weights | Training context: {2} | Embedding: {3} | Vocabulary: {4}' -f
                ($model.meta.n_params / 1e9),($model.meta.size / 1GB),$model.meta.n_ctx_train,$model.meta.n_embd,$model.meta.n_vocab
        }
    }
    $slots = Read-ServerEndpoint $Port 'slots'
    foreach ($slot in $slots) {
        if ($null -eq $slot.id) { continue }
        "Slot $($slot.id): $(if ($slot.is_processing) { 'BUSY' } else { 'idle' }) | Task: $($slot.id_task) | Context: $($slot.n_ctx)"
        "  Current/last task: output limit=$(Format-ServerValue $slot.params.n_predict), reasoning format=$(Format-ServerValue $slot.params.reasoning_format), thinking budget=$(Format-ServerValue $slot.params.reasoning_budget), cache_prompt=$(Format-ServerValue $slot.params.cache_prompt)"
        "  Reported cache/task tokens: cached=$(Format-ServerValue $slot.tokens_cached), past=$(Format-ServerValue $slot.n_past), prompt=$(Format-ServerValue $slot.n_prompt_tokens)"
        foreach ($token in $slot.next_token) {
            "  Current/last task decoded tokens: $($token.n_decoded) | Remaining: $($token.n_remain) (not lifetime totals)"
        }
    }
    $metrics = ConvertFrom-ServerMetrics (Read-ServerEndpoint $Port 'metrics' -Text)
    $cacheTokens=$null; $cacheRatio=$null
    foreach ($prefix in @('llamacpp:', 'llamacpp_')) {
        if ($metrics.Contains($prefix+'kv_cache_tokens')) { $cacheTokens=$metrics[$prefix+'kv_cache_tokens'] }
        if ($metrics.Contains($prefix+'kv_cache_usage_ratio')) { $cacheRatio=$metrics[$prefix+'kv_cache_usage_ratio'] }
    }
    $cachePercent=if ($null -ne $cacheRatio) { '{0:N1}%' -f ($cacheRatio * 100) } else { 'unavailable' }
    "Live KV cache metrics: tokens=$(Format-ServerValue $cacheTokens) | Usage: $cachePercent (not exposed by every build)"
    if ($metrics.Count) {
        'Metrics since this server started (token totals may lag active requests):'
        foreach ($key in $metrics.Keys) { '  {0}: {1}' -f ($key -replace '^llamacpp[:_]',''), $metrics[$key] }
    } else { 'Lifetime token totals unavailable. Restart here to enable --metrics; counters begin at zero.' }
    # Only associate persisted log paths with the exact process, not a recycled PID.
    $recordPath = Join-Path $PSScriptRoot "logs\server-$Port.json"
    $logPath = $null
    if (Test-Path -LiteralPath $recordPath) {
        try {
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            if ($record.ProcessId -eq $Server.ProcessId -and
                [math]::Abs(([datetime]::Parse($record.StartTime).ToUniversalTime().Ticks - $Server.CreationDate.ToUniversalTime().Ticks)) -lt 10) {
                $logPath = $record.Stderr
                "Logs: $($record.Stdout) | $logPath"
            }
        } catch { }
    }
    if (-not $logPath) {
        # Legacy server: show a clearly labeled candidate, never infer lifetime totals.
        $candidates = @('logs\llama-server.stderr.log','logs\opencode-server.stderr.log','llama-server.stderr.log','opencode-server.stderr.log')
        $candidate = $candidates | ForEach-Object { Get-Item -LiteralPath (Join-Path $PSScriptRoot $_) -ErrorAction SilentlyContinue } |
            Where-Object { $_.LastWriteTime -ge $Server.CreationDate } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) { $logPath=$candidate.FullName; "Possible legacy log (not process-verified): $logPath" }
    }
    if ($logPath -and (Test-Path -LiteralPath $logPath)) {
        $logTail = @(Get-Content -LiteralPath $logPath -Tail 1000 -ErrorAction SilentlyContinue)
        $cacheLines = @($logTail | Where-Object { $_ -match 'cache state:|KV buffer size|KV self size|flash_attn\s*=' } | Select-Object -Last 3)
        if ($cacheLines.Count) { 'Recent cache/attention observations in that log (may be stale):'; $cacheLines }
        $timings = @($logTail |
            Where-Object { $_ -match '(?:^|\s)(prompt )?eval time\s*=' } | Select-Object -Last 2)
        if ($timings.Count) { 'Latest timings in that log:'; $timings }
    }
}

function Stop-LocalServer {
    param($Server, [int]$Port)
    $current = Assert-LocalServerIdentity $Server $Port
    $process = Get-Process -Id $current.ProcessId -ErrorAction Stop
    # Acquire the handle before checking time, preventing PID reuse between check and Kill.
    $null = $process.Handle
    # Win32_Process timestamps have microsecond precision; Process has 100ns precision.
    if ([math]::Abs(($process.StartTime.ToUniversalTime().Ticks - $current.CreationDate.ToUniversalTime().Ticks)) -ge 10) { throw 'Process identity changed.' }
    $process.Kill()
    if (-not $process.WaitForExit(10000)) { throw 'Server has not exited after 10 seconds.' }
    Write-Host "Stopped llama-server PID $($current.ProcessId)." -ForegroundColor Green
}

function Restart-LocalServer {
    param($Server, [int]$Port)
    $current = Assert-LocalServerIdentity $Server $Port
    # Strip only the executable. Preserve native Windows argument quoting, without a shell.
    $match = [regex]::Match($current.CommandLine, '^\s*(?:"[^"]+"|\S+)\s+(.+)$')
    if (-not $match.Success) { throw 'Cannot recover launch arguments; server left running.' }
    $nativeArguments = $match.Groups[1].Value
    if ($nativeArguments -notmatch '(?<!\S)--metrics(?!\S)') { $nativeArguments += ' --metrics' }
    $nativeArguments = $nativeArguments -replace '(?<!\S)--no-slots(?!\S)', '--slots'
    if ($nativeArguments -notmatch '(?<!\S)--slots(?!\S)') { $nativeArguments += ' --slots' }
    $dir = Join-Path $PSScriptRoot 'logs'
    [void][IO.Directory]::CreateDirectory($dir)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $out = Join-Path $dir "llama-server-$Port-$stamp.stdout.log"
    $err = Join-Path $dir "llama-server-$Port-$stamp.stderr.log"
    Stop-LocalServer $current $Port
    if (Get-LocalServerProcess $Port) { throw "Port $Port was taken by another process; restart cancelled." }
    $process = Start-Process -FilePath $current.ExecutablePath -ArgumentList $nativeArguments -WorkingDirectory (Split-Path -Parent $current.ExecutablePath) -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    Save-ServerLogRecord $process $Port $out $err
    Write-Host "Restarting PID $($process.Id); logs: $err"
    for ($attempt=0; $attempt -lt 180; $attempt++) {
        $process.Refresh()
        if ($process.HasExited) { throw "Restart failed (exit $($process.ExitCode)). See $err" }
        $health = Read-ServerEndpoint $Port 'health'
        if ($health.status -eq 'ok') {
            $owner = Get-LocalServerProcess $Port
            if ($owner.ProcessId -eq $process.Id) { Write-Host 'Server ready.' -ForegroundColor Green; return }
        }
        if ($attempt % 15 -eq 0) { Write-Host 'Waiting for the model to load...' }
        Start-Sleep -Seconds 1
    }
    Write-Warning "Server still not healthy. Process left running; inspect $err"
}

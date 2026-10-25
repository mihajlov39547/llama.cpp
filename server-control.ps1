# Local server inspection/control helpers. Never stop a process by name alone.
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
    $exe = Join-Path $PSScriptRoot 'bin\llama-server.exe'
    if (-not $Expected -or -not $current -or $current.ProcessId -ne $Expected.ProcessId -or
        $current.CreationDate -ne $Expected.CreationDate -or
        -not [string]::Equals($current.ExecutablePath, $exe, [StringComparison]::OrdinalIgnoreCase)) {
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

function Get-ServerStatusLines {
    param($Server, [int]$Port)
    "Address: http://127.0.0.1:$Port | Snapshot: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if (-not $Server) { 'No local listening process found.'; return }
    "Process: $($Server.Name) | PID: $($Server.ProcessId)"
    $expectedExe = Join-Path $PSScriptRoot 'bin\llama-server.exe'
    if (-not [string]::Equals($Server.ExecutablePath, $expectedExe, [StringComparison]::OrdinalIgnoreCase)) {
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
    if ($props) {
        "Model: $($props.model_alias) | File: $($props.model_path)"
        "Context per slot: $($props.default_generation_settings.n_ctx) | Slots: $($props.total_slots) | Web UI: $($props.webui) | Build: $($props.build_info)"
        $sampling = $props.default_generation_settings.params
        "Default sampling: temperature=$($sampling.temperature), top_k=$($sampling.top_k), top_p=$($sampling.top_p), min_p=$($sampling.min_p)"
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
        foreach ($token in $slot.next_token) {
            "  Current/last task decoded tokens: $($token.n_decoded) | Remaining: $($token.n_remain) (not lifetime totals)"
        }
    }
    $metrics = ConvertFrom-ServerMetrics (Read-ServerEndpoint $Port 'metrics' -Text)
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
        $timings = @(Get-Content -LiteralPath $logPath -Tail 1000 -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\s*(prompt )?eval time\s*=' } | Select-Object -Last 2)
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
    $process = Start-Process -FilePath $current.ExecutablePath -ArgumentList $nativeArguments -WorkingDirectory (Join-Path $PSScriptRoot 'bin') -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
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

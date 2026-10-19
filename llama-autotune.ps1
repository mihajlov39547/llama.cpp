# llama.cpp local server autotuner - Windows PowerShell 5.1 / PowerShell 7+
# Run from C:\llama.cpp (or place script beside the bin and models folders).
# Runs until the configured time budget is reached, or all configurations have
# been tested with enough repetitions. Does not modify model files or launchers.
param(
    [int]$Minutes = 120,
    [int]$Port = 18081,
    [int]$MaxGpuTempC = 85,
    [int]$StartTimeoutSec = 120,
    [int]$RequestTimeoutSec = 120,
    [int]$MaxRounds = 3
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$exe = Join-Path $root 'bin\llama-server.exe'
$modelDir = Join-Path $root 'models'
$runDir = Join-Path $root ('benchmark-results\run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$apiBase = "http://127.0.0.1:$Port"
$startTime = Get-Date
$deadline = $startTime.AddMinutes($Minutes)
$serverProcess = $null
$stopRequested = $false

if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing executable: $exe" }
if (!(Test-Path -LiteralPath $modelDir -PathType Container)) { throw "Missing models directory: $modelDir" }
if ($Minutes -le 0 -or $Port -lt 1 -or $Port -gt 65535) { throw 'Invalid Minutes or Port' }
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$rawCsv = Join-Path $runDir 'requests.csv'
$summaryCsv = Join-Path $runDir 'config-summary.csv'
$bestCsv = Join-Path $runDir 'best-per-model.csv'
$runLog = Join-Path $runDir 'run.log'

$names = @(
    'google_gemma-4-E2B-it-Q4_K_M.gguf',
    'Qwen3.5-4B-Q4_K_M.gguf',
    'Qwen3-4B-Q4_K_M.gguf'
)
$models = @()
foreach ($name in $names) {
    $found = @(Get-ChildItem -LiteralPath $modelDir -Filter $name -File -Recurse | Select-Object -First 1)
    if ($found.Count) { $models += $found[0] }
    else { Write-Warning "Model not found, skipping: $name" }
}
if ($models.Count -eq 0) { throw 'None of the specified models were found.' }

# Fixed, realistic short tasks. More than one language and answer type prevents
# optimizing for a single toy prompt. Each response has a token limit.
$testPrompts = @(
    @{ id='fact'; prompt='What is the capital of France? Answer clearly, then provide two additional geographic facts in three sentences.' },
    @{ id='joke'; prompt='Tell me one original, family-friendly joke, then explain why it is funny in two or three sentences.' },
    @{ id='to-english'; prompt='Translate this into natural English and then explain two translation choices: "Danas je lepo vreme, ali sutra ocekujemo jaku kisu."' },
    @{ id='to-serbian'; prompt='Translate this sentence into natural Serbian in Latin script and explain two word choices: "The researcher carefully compared the performance of three small language models."' },
    @{ id='improve'; prompt='Improve this prompt so it is precise and testable, then briefly explain your changes: "Tell me about encryption."' }
)

function Add-Log([string]$msg) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8
}
function Get-GpuInfo {
    try {
        $lines = @(& nvidia-smi --query-gpu=temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null)
        if ($LASTEXITCODE -ne 0 -or !$lines.Count) { return $null }
        $parts = $lines[0] -split '\s*,\s*'
        if ($parts.Count -lt 3) { return $null }
        return [pscustomobject]@{ TempC = [int]$parts[0]; UsedMiB=[int]$parts[1]; TotalMiB=[int]$parts[2] }
    } catch { return $null }
}
function Assert-Temperature {
    $gpu = Get-GpuInfo
    if ($null -ne $gpu -and $gpu.TempC -ge $MaxGpuTempC) {
        throw "GPU temperature $($gpu.TempC) C reached safety threshold $MaxGpuTempC C; stopping benchmark."
    }
}
function Stop-BenchServer {
    if ($null -ne $script:serverProcess) {
        try {
            $script:serverProcess.Refresh()
            if (!$script:serverProcess.HasExited) {
                Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction Stop
                $script:serverProcess.WaitForExit(10000) | Out-Null
            }
        } catch { Add-Log "Warning: stopping benchmark server: $_" }
        $script:serverProcess = $null
    }
}
function Wait-Ready {
    param([int]$Seconds)
    $until = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $until -and (Get-Date) -lt $script:deadline) {
        Assert-Temperature
        if ($null -eq $script:serverProcess) { return $false }
        $script:serverProcess.Refresh()
        if ($script:serverProcess.HasExited) { return $false }
        try {
            $h = Invoke-RestMethod -Uri "$script:apiBase/health" -Method Get -TimeoutSec 3
            if ($h.status -eq 'ok' -or $h.status -eq 'no slot available') { return $true }
        } catch { }
        Start-Sleep -Seconds 2
    }
    return $false
}
function Start-BenchServer {
    param($model, $cfg, [string]$tag)
    $stdout = Join-Path $script:runDir ("server-$tag.out.log")
    $stderr = Join-Path $script:runDir ("server-$tag.err.log")
    $args = @(
        '-m', ('"' + $model.FullName + '"'),
        '--host', '127.0.0.1', '--port', [string]$script:Port,
        '--no-webui', '--gpu-layers', [string]$cfg.GpuLayers,
        '--fit', 'on', '--parallel', '1',
        '-c', '4096', '-b', '512', '-ub', [string]$cfg.UBatch,
        '-t', [string]$cfg.Threads, '--cache-ram', '0'
    )
    # Keep Qwen in non-thinking mode to compare useful visible responses.
    if ($model.Name -match 'Qwen3') {
        $args += @('--reasoning', 'off', '--reasoning-budget', '0')
    }
    $script:serverProcess = Start-Process -FilePath $script:exe -ArgumentList $args -WorkingDirectory (Join-Path $script:root 'bin') -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    return (Wait-Ready -Seconds $script:StartTimeoutSec)
}
function Invoke-Test {
    param($model, $cfg, $promptItem, [string]$phase, [int]$round)
    $gpuBefore = Get-GpuInfo
    $payload = @{
        model = $model.Name
        messages = @(@{role='user';content=$promptItem.prompt})
        stream = $false
        temperature = 0
        seed = 2003
        max_tokens = 96
        cache_prompt = $false
    } | ConvertTo-Json -Depth 6 -Compress
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $ok = $false; $err = ''; $resp = $null
    try {
        $resp = Invoke-RestMethod -Uri "$script:apiBase/v1/chat/completions" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec $script:RequestTimeoutSec
        $ok = $true
    } catch {
        $err = $_.Exception.Message
    } finally { $watch.Stop() }
    $gpuAfter = Get-GpuInfo
    $predictionTps = $null; $promptTps = $null; $predicted = $null; $promptTokens = $null
    $responseText = ''
    if ($ok) {
        if ($resp.timings) {
            $predictionTps = $resp.timings.predicted_per_second
            $promptTps = $resp.timings.prompt_per_second
            $predicted = $resp.timings.predicted_n
            $promptTokens = $resp.timings.prompt_n
        }
        if ($resp.usage) {
            if ($null -eq $predicted) { $predicted = $resp.usage.completion_tokens }
            if ($null -eq $promptTokens) { $promptTokens = $resp.usage.prompt_tokens }
        }
        if ($resp.choices -and $resp.choices.Count -gt 0 -and $resp.choices[0].message) {
            $responseText = [string]$resp.choices[0].message.content
        }
        if ([string]::IsNullOrWhiteSpace($responseText) -and $phase -ne 'warmup') {
            $ok = $false
            $err = 'Empty visible answer'
        }
    }
    return [pscustomobject]@{
        timestamp=(Get-Date -Format 'o'); model=$model.Name; gpu_layers=[string]$cfg.GpuLayers;
        ubatch=$cfg.UBatch; threads=$cfg.Threads; phase=$phase; round=$round;
        prompt_id=$promptItem.id; ok=$ok; latency_s=[math]::Round($watch.Elapsed.TotalSeconds,3);
        prompt_tokens=$promptTokens; completion_tokens=$predicted;
        prompt_tps=$promptTps; generation_tps=$predictionTps;
        gpu_temp_c=if ($null -ne $gpuAfter) {$gpuAfter.TempC} else {$null};
        gpu_used_mib=if ($null -ne $gpuAfter) {$gpuAfter.UsedMiB} else {$null};
        error=$err; answer_excerpt=if ($responseText.Length -gt 160) {$responseText.Substring(0,160)} else {$responseText}
    }
}
function Get-Median([object[]]$values) {
    $s = @($values | Where-Object { $null -ne $_ -and [string]$_ -ne '' } | ForEach-Object { [double]$_ } | Sort-Object)
    if (!$s.Count) { return $null }
    $k = [int][math]::Floor($s.Count / 2)
    if (($s.Count % 2) -eq 1) { return $s[$k] }
    return ($s[$k - 1] + $s[$k]) / 2.0
}
function Export-Summaries {
    if (!(Test-Path $script:rawCsv)) { return }
    $all = @(Import-Csv -LiteralPath $script:rawCsv | Where-Object { $_.phase -eq 'test' })
    $summaries = @()
    foreach ($g in ($all | Group-Object model,gpu_layers,ubatch,threads)) {
        $items = @($g.Group)
        $good = @($items | Where-Object { $_.ok -eq 'True' -and $_.generation_tps -ne '' -and [double]$_.generation_tps -gt 0 })
        $med = Get-Median -values @($good | ForEach-Object { $_.generation_tps })
        $medLatency = Get-Median -values @($good | ForEach-Object { $_.latency_s })
        $medPrompt = Get-Median -values @($good | ForEach-Object { $_.prompt_tps })
        $parts = $items[0]
        $summaries += [pscustomobject]@{
            model=$parts.model; gpu_layers=$parts.gpu_layers; ubatch=$parts.ubatch; threads=$parts.threads;
            attempts=$items.Count; success=$good.Count;
            success_rate=[math]::Round(($good.Count / [double]$items.Count),3);
            median_generation_tps=if ($null -ne $med) {[math]::Round($med,3)} else {$null};
            median_prompt_tps=if ($null -ne $medPrompt) {[math]::Round($medPrompt,3)} else {$null};
            median_latency_s=if ($null -ne $medLatency) {[math]::Round($medLatency,3)} else {$null};
            max_gpu_used_mib=if ($good.Count) { ($good | Measure-Object gpu_used_mib -Maximum).Maximum } else {$null}
        }
    }
    $summaries | Sort-Object model,@{Expression='median_generation_tps';Descending=$true} | Export-Csv -LiteralPath $summaryCsv -NoTypeInformation -Encoding UTF8
    $best = @()
    foreach ($group in ($summaries | Where-Object { $_.success_rate -eq 1 -and $_.success -ge 3 } | Group-Object model)) {
        $best += @($group.Group | Sort-Object -Property @{Expression='median_generation_tps';Descending=$true} | Select-Object -First 1)
    }
    if ($best.Count) { $best | Export-Csv -LiteralPath $bestCsv -NoTypeInformation -Encoding UTF8 }
}

# Dedicated benchmark port: never terminate someone else's application.
$tcp = New-Object Net.Sockets.TcpClient
try {
    $task = $tcp.ConnectAsync('127.0.0.1',$Port)
    if ($task.Wait(500) -and $tcp.Connected) { throw "Port $Port is busy. Stop that service or use -Port 18082." }
} finally { $tcp.Dispose() }

# Up to 3 rounds, same configuration evaluated across independent launches.
# GPU layer settings are deliberately bounded to avoid full-VRAM overrides.
$configs = @()
foreach ($layers in @('auto','12','24','all')) {
    foreach ($ub in @(128,256)) {
        foreach ($threads in @(4,6)) {
            $configs += [pscustomobject]@{ GpuLayers=$layers; UBatch=$ub; Threads=$threads }
        }
    }
}
Add-Log "Starting autotune: $($models.Count) models, $($configs.Count) configs/model, budget $Minutes minutes, deadline $deadline"
Add-Log "Results: $runDir"
Add-Log 'Close any existing GPU-heavy apps; benchmark runs one server at a time.'
$counter = 0
try {
    :outer foreach ($round in 1..$MaxRounds) {
        foreach ($cfg in $configs) {
            foreach ($model in $models) {
                if ((Get-Date) -ge $deadline) { break outer }
                Assert-Temperature
                $counter++
                $tag = ('{0:000}-{1}-{2}-{3}-{4}' -f $counter, ($model.BaseName -replace '[^a-zA-Z0-9-]','_'),$cfg.GpuLayers,$cfg.UBatch,$cfg.Threads)
                Add-Log "Round $round | $($model.Name) | gpu=$($cfg.GpuLayers) ubatch=$($cfg.UBatch) threads=$($cfg.Threads)"
                try {
                    $started = Start-BenchServer -model $model -cfg $cfg -tag $tag
                    if (!$started) {
                        Add-Log "Failed to start server (see server-$tag.err.log)"
                        $failed = [pscustomobject]@{ timestamp=(Get-Date -Format 'o'); model=$model.Name; gpu_layers=[string]$cfg.GpuLayers; ubatch=$cfg.UBatch; threads=$cfg.Threads; phase='test'; round=$round; prompt_id='startup'; ok=$false; latency_s=''; prompt_tokens=''; completion_tokens=''; prompt_tps=''; generation_tps=''; gpu_temp_c=''; gpu_used_mib=''; error='Server did not become ready'; answer_excerpt='' }
                        $failed | Export-Csv -LiteralPath $rawCsv -Append -NoTypeInformation -Encoding UTF8
                        continue
                    }
                    # Always warm up the first GPU kernels/graph before measurements.
                    $warm = Invoke-Test -model $model -cfg $cfg -promptItem $testPrompts[0] -phase 'warmup' -round $round
                    $warm | Export-Csv -LiteralPath $rawCsv -Append -NoTypeInformation -Encoding UTF8
                    if (!$warm.ok) { Add-Log "Warmup problem: $($warm.error)"; continue }
                    foreach ($p in $testPrompts) {
                        if ((Get-Date) -ge $deadline) { break }
                        Assert-Temperature
                        $result = Invoke-Test -model $model -cfg $cfg -promptItem $p -phase 'test' -round $round
                        $result | Export-Csv -LiteralPath $rawCsv -Append -NoTypeInformation -Encoding UTF8
                        Add-Log ("  {0}: {1} | {2}s | {3} gen tokens/s | GPU {4} MiB" -f $p.id, $(if($result.ok){'OK'}else{'FAIL'}),$result.latency_s,$result.generation_tps,$result.gpu_used_mib)
                    }
                } catch {
                    Add-Log "Configuration failed: $($_.Exception.Message)"
                    if ($_.Exception.Message -match 'temperature.*threshold') { throw }
                } finally {
                    Stop-BenchServer
                    Export-Summaries
                    Start-Sleep -Seconds 2
                }
            }
        }
    }
} finally {
    Stop-BenchServer
    Export-Summaries
    Add-Log "Finished. Open $summaryCsv and $bestCsv"
}

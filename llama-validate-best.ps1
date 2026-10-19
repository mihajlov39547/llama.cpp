# Focused follow-up benchmark for llama.cpp build b8729, Windows PowerShell 5.1+.
# Does NOT modify the existing CLI/server launchers or models.
param(
    [int]$Minutes = 45,
    [int]$Port = 18082,
    [int]$Rounds = 2,
    [int]$MaxGpuTempC = 85,
    [int]$StartupTimeoutSec = 120,
    [int]$RequestTimeoutSec = 180
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$exe = Join-Path $root 'bin\llama-server.exe'
$modelDir = Join-Path $root 'models'
$runDir = Join-Path $root ('benchmark-results\validation-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$endpoint = "http://127.0.0.1:$Port"
$deadline = (Get-Date).AddMinutes($Minutes)
$proc = $null
if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "llama-server.exe missing at $exe" }
if (!(Test-Path -LiteralPath $modelDir -PathType Container)) { throw "Models folder missing at $modelDir" }
if ($Minutes -lt 1 -or $Rounds -lt 1 -or $Port -lt 1 -or $Port -gt 65535) { throw 'Invalid benchmark parameters.' }

# Confirm flags on the INSTALLED build rather than assuming a newer llama.cpp build.
# PowerShell 5.1 treats native stderr as a terminating error when ErrorActionPreference=Stop.
# llama-server prints CUDA initialization messages to stderr even for --help.
# Capture stdout and stderr in separate temporary files to avoid NativeCommandError.
$helpStdout = Join-Path ([IO.Path]::GetTempPath()) ("llama-help-{0}.out.txt" -f [guid]::NewGuid().ToString('N'))
$helpStderr = Join-Path ([IO.Path]::GetTempPath()) ("llama-help-{0}.err.txt" -f [guid]::NewGuid().ToString('N'))
try {
    $helpProc = Start-Process -FilePath $exe -ArgumentList '--help' -WorkingDirectory (Join-Path $root 'bin') -NoNewWindow -Wait -PassThru -RedirectStandardOutput $helpStdout -RedirectStandardError $helpStderr
    $helpOutput = ((Get-Content -LiteralPath $helpStdout -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content -LiteralPath $helpStderr -Raw -ErrorAction SilentlyContinue))
    if ([string]::IsNullOrWhiteSpace($helpOutput)) { throw "llama-server --help produced no output; exit code $($helpProc.ExitCode)." }
} finally {
    Remove-Item -LiteralPath $helpStdout,$helpStderr -Force -ErrorAction SilentlyContinue
}
foreach ($flag in @('--cache-type-k','--cache-type-v','--reasoning-budget','--gpu-layers','--fit')) {
    if (!$helpOutput.Contains($flag)) { throw "Installed llama-server.exe does not advertise $flag; benchmark not started." }
}

# Never attach to, replace, or stop somebody else's server.
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,$Port)
try { $listener.Start() } catch { throw "Port $Port is already in use. Choose another port with -Port." } finally { $listener.Stop() }

New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$rowsPath = Join-Path $runDir 'requests.csv'
$summaryPath = Join-Path $runDir 'summary.csv'
$rankingPath = Join-Path $runDir 'best-per-model.csv'
$logPath = Join-Path $runDir 'run.log'
$responsesDir = Join-Path $runDir 'responses'
New-Item -ItemType Directory -Path $responsesDir | Out-Null
function Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
function Gpu {
    try {
        $line = @(& nvidia-smi --query-gpu=temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null)[0]
        $p = $line -split '\s*,\s*'
        if ($p.Count -ge 3) { return [pscustomobject]@{temp=[int]$p[0];used=[int]$p[1];total=[int]$p[2]} }
    } catch {}
    return $null
}
function CheckTemp {
    $g = Gpu
    if ($null -ne $g -and $g.temp -ge $MaxGpuTempC) { throw "GPU TEMPERATURE LIMIT: $($g.temp) >= $MaxGpuTempC C" }
}
function StopServer {
    if ($null -ne $script:proc) {
        try {
            $script:proc.Refresh()
            if (!$script:proc.HasExited) { Stop-Process -Id $script:proc.Id -Force -ErrorAction Stop; $script:proc.WaitForExit(10000) | Out-Null }
        } catch { Log "Cannot stop spawned process: $_" }
        $script:proc = $null
    }
}
function Median($values) {
    $sorted = @($values | Where-Object { $_ -ne $null -and [string]$_ -ne '' } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $i = [int][math]::Floor($sorted.Count/2)
    if (($sorted.Count % 2) -eq 1) { return $sorted[$i] }
    return ($sorted[$i-1]+$sorted[$i])/2
}
function SaveSummary {
    if (!(Test-Path -LiteralPath $rowsPath)) { return }
    $all = @(Import-Csv -LiteralPath $rowsPath | Where-Object { $_.phase -eq 'test' })
    $summary = @()
    foreach ($group in ($all | Group-Object model,config)) {
        $xs = @($group.Group)
        $valid = @($xs | Where-Object { $_.http_ok -eq 'True' -and $_.generation_tps -ne '' -and [double]$_.generation_tps -gt 0 })
        $finished = @($xs | Where-Object { $_.completed -eq 'True' })
        $first = $xs[0]
        $summary += [pscustomobject]@{
            model=$first.model; config=$first.config; gpu_layers=$first.gpu_layers; threads=$first.threads;
            ubatch=$first.ubatch; cache_k=$first.cache_k; cache_v=$first.cache_v;
            total=$xs.Count; speed_samples=$valid.Count; completed=$finished.Count;
            completion_rate=[math]::Round($finished.Count/[double]$xs.Count,3);
            median_generation_tps=Median @($valid | ForEach-Object generation_tps);
            median_latency_s=Median @($valid | ForEach-Object latency_s);
            median_gpu_used_mib=Median @($valid | ForEach-Object gpu_used_mib);
            max_gpu_used_mib=if ($valid.Count) { ($valid | Measure-Object -Property gpu_used_mib -Maximum).Maximum } else { '' }
        }
    }
    $summary | Sort-Object model,config | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
    # Always produce best-per-model.csv. Rank ONLY configurations with fully completed answers and >=2 valid samples.
    $best = @()
    foreach ($group in ($summary | Where-Object { $_.completed -eq $_.total -and $_.speed_samples -ge 2 } | Group-Object model)) {
        $best += @($group.Group | Sort-Object -Property @{Expression='median_generation_tps';Descending=$true} | Select-Object -First 1)
    }
    if ($best.Count -eq 0) {
        # Empty file with schema; no misleading winner if nothing completed.
        'model,config,gpu_layers,threads,ubatch,cache_k,cache_v,total,speed_samples,completed,completion_rate,median_generation_tps,median_latency_s,median_gpu_used_mib,max_gpu_used_mib' |
            Set-Content -LiteralPath $rankingPath -Encoding UTF8
    } else { $best | Export-Csv -LiteralPath $rankingPath -NoTypeInformation -Encoding UTF8 }
}

# Configs: baseline plus cache quantization for Qwen, and a smaller ubatch for Gemma.
$specs = @(
    @{name='google_gemma-4-E2B-it-Q4_K_M.gguf'; key='gemma'; variants=@(
        @{id='baseline';layers='auto';ub=256;threads=4;k='f16';v='f16'},
        @{id='ub128';layers='auto';ub=128;threads=4;k='f16';v='f16'}
    )},
    @{name='Qwen3.5-4B-Q4_K_M.gguf'; key='qwen35'; variants=@(
        @{id='baseline';layers='all';ub=256;threads=6;k='f16';v='f16'},
        @{id='q8kv';layers='all';ub=256;threads=6;k='q8_0';v='q8_0'},
        @{id='q4kv';layers='all';ub=256;threads=6;k='q4_0';v='q4_0'},
        @{id='layer24';layers='24';ub=256;threads=6;k='f16';v='f16'}
    )},
    @{name='Qwen3-4B-Q4_K_M.gguf'; key='qwen3'; variants=@(
        @{id='baseline';layers='all';ub=256;threads=6;k='f16';v='f16'},
        @{id='q8kv';layers='all';ub=256;threads=6;k='q8_0';v='q8_0'},
        @{id='q4kv';layers='all';ub=256;threads=6;k='q4_0';v='q4_0'},
        @{id='layer24';layers='24';ub=256;threads=6;k='f16';v='f16'}
    )}
)
# English prompts avoid PowerShell 5.1 source-encoding pitfalls; test substantive long completions.
$prompts = @(
    @{id='explain';text='Explain the difference between AES-CBC and AES-GCM for a developer. Write 6 short paragraphs. Include confidentiality, integrity, nonce/IV handling, parallelism, error handling, and a concrete recommendation. No preamble.'},
    @{id='rewrite';text='Rewrite the following rough research note as a clear technical explanation in approximately 220 to 300 English words. Then provide a 4-item checklist. Note: GPU kernel-only timing excludes transfers; end-to-end timing includes transfers, host orchestration, and synchronization; compare matched input sizes, warm up first, use medians, and check correctness before any timing.'}
)
$models = @()
foreach ($spec in $specs) {
    $file = @(Get-ChildItem -LiteralPath $modelDir -File -Recurse -Filter $spec.name | Select-Object -First 1)
    if (!$file.Count) { throw "Model missing: $($spec.name)" }
    $models += [pscustomobject]@{file=$file[0]; key=$spec.key; variants=$spec.variants}
}

function StartServer($model, $cfg, [string]$tag) {
    $out = Join-Path $runDir "server-$tag.out.log"
    $err = Join-Path $runDir "server-$tag.err.log"
    $args = @(
        '-m',('"'+$model.file.FullName+'"'), '--host','127.0.0.1','--port',[string]$Port,
        '--no-webui','--gpu-layers',[string]$cfg.layers,'--fit','on','--parallel','1',
        '-c','4096','-b','512','-ub',[string]$cfg.ub,'-t',[string]$cfg.threads,
        '--cache-ram','0','--cache-type-k',[string]$cfg.k,'--cache-type-v',[string]$cfg.v,
        '--reasoning','off','--reasoning-budget','0'
    )
    $script:proc = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory (Join-Path $root 'bin') -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    $until = (Get-Date).AddSeconds($StartupTimeoutSec)
    while ((Get-Date) -lt $until -and (Get-Date) -lt $deadline) {
        CheckTemp
        $script:proc.Refresh()
        if ($script:proc.HasExited) { return $false }
        try {
            $health = Invoke-RestMethod -Uri "$endpoint/health" -TimeoutSec 3
            if ($health.status -eq 'ok' -or $health.status -eq 'no slot available') { return $true }
        } catch {}
        Start-Sleep -Seconds 2
    }
    return $false
}
function Request($model, $cfg, $p, [int]$round, [string]$phase, [string]$tag) {
    $data = @{model=$model.file.Name; messages=@(@{role='user';content=$p.text}); temperature=0;seed=2003;stream=$false;max_tokens=512;cache_prompt=$false} | ConvertTo-Json -Depth 6 -Compress
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $response = $null; $errorText='';$httpOk=$false
    try {
        $response = Invoke-RestMethod -Method Post -Uri "$endpoint/v1/chat/completions" -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($data)) -TimeoutSec $RequestTimeoutSec
        $httpOk=$true
    } catch { $errorText=$_.Exception.Message } finally { $timer.Stop() }
    $gpu = Gpu
    $finish='';$answer='';$genTps=$null;$promptTps=$null;$usedTokens=$null
    if ($httpOk) {
        if ($response.choices.Count -gt 0) {
            $finish=[string]$response.choices[0].finish_reason
            $answer=[string]$response.choices[0].message.content
        }
        if ($response.timings) { $genTps=$response.timings.predicted_per_second; $promptTps=$response.timings.prompt_per_second; $usedTokens=$response.timings.predicted_n }
        if ($null -eq $usedTokens -and $response.usage) { $usedTokens=$response.usage.completion_tokens }
        if ([string]::IsNullOrWhiteSpace($answer)) { $errorText='Empty visible answer' }
        elseif ($finish -ne 'stop') { $errorText="Not completed: finish_reason=$finish" }
        if ($phase -eq 'test') {
            $path = Join-Path $responsesDir ("$tag-$($p.id).txt")
            [IO.File]::WriteAllText($path, $answer, (New-Object Text.UTF8Encoding($false)))
        }
    }
    $complete = $httpOk -and $finish -eq 'stop' -and ![string]::IsNullOrWhiteSpace($answer)
    $item = [pscustomobject]@{
        timestamp=(Get-Date -Format o); round=$round; phase=$phase; model=$model.file.Name;config=$cfg.id;
        gpu_layers=$cfg.layers;threads=$cfg.threads;ubatch=$cfg.ub;cache_k=$cfg.k;cache_v=$cfg.v;
        prompt_id=$p.id;http_ok=$httpOk;completed=$complete;finish_reason=$finish;
        latency_s=[math]::Round($timer.Elapsed.TotalSeconds,3);completion_tokens=$usedTokens;
        generation_tps=$genTps;prompt_tps=$promptTps;
        gpu_temp_c=if($gpu){$gpu.temp}else{$null};gpu_used_mib=if($gpu){$gpu.used}else{$null};
        error=$errorText;answer_chars=$answer.Length
    }
    $item | Export-Csv -LiteralPath $rowsPath -Append -NoTypeInformation -Encoding UTF8
    Log ("  {0} {1}: {2}, {3}s, {4} tok/s, {5} MiB, finish={6}" -f $phase,$p.id,$(if($complete){'OK'}else{'INCOMPLETE'}),$item.latency_s,$genTps,$item.gpu_used_mib,$finish)
    return $item
}

Log "Validation benchmark: 3 models, 10 configurations per round, $Rounds rounds, $Minutes minute limit"
Log "Results: $runDir"
Log 'GPU baseline and KV variants are tested independently; no existing server is touched.'
$counter=0
try {
    :outer foreach ($round in 1..$Rounds) {
        foreach ($model in $models) {
            foreach ($cfg in $model.variants) {
                if ((Get-Date) -ge $deadline) { break outer }
                CheckTemp
                $counter++
                $tag = ('{0:000}-{1}-{2}-r{3}' -f $counter,$model.key,$cfg.id,$round)
                Log "Round ${round}: $($model.file.Name) | $($cfg.id) | ngl=$($cfg.layers) ub=$($cfg.ub) t=$($cfg.threads) kv=$($cfg.k)/$($cfg.v)"
                try {
                    $started = StartServer $model $cfg $tag
                    if (!$started) { Log "  START FAILED - inspect server-$tag.err.log"; continue }
                    Request $model $cfg $prompts[0] $round 'warmup' $tag | Out-Null
                    foreach ($promptItem in $prompts) {
                        if ((Get-Date) -ge $deadline) { break }
                        CheckTemp
                        Request $model $cfg $promptItem $round 'test' $tag | Out-Null
                    }
                } catch {
                    Log "  ERROR: $($_.Exception.Message)"
                    if ($_.Exception.Message -match '^GPU TEMPERATURE LIMIT') { throw }
                } finally {
                    StopServer
                    SaveSummary
                    Start-Sleep -Seconds 2
                }
            }
        }
    }
} finally {
    StopServer
    SaveSummary
    Log "Finished. See $summaryPath , $rankingPath and server logs."
}

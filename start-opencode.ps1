# Local OpenCode + llama.cpp launcher - fixed model contexts (PowerShell 5.1 and 7+)
# Save to C:\llama.cpp\start-opencode.ps1
# Run from PowerShell: .\start-opencode.ps1
# Profiles and token budgets are maintained in model-profiles.ps1.
[CmdletBinding()]
param(
    [string]$ProjectDir = '',
    [int]$Port = 8080,
    [switch]$ServerOnly
)
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$logDir = Join-Path $root 'logs'
[void][IO.Directory]::CreateDirectory($logDir)
$serverExe = Join-Path $root 'bin\llama-server.exe'
$modelDir = Join-Path $root 'models'
$project = if ([string]::IsNullOrWhiteSpace($ProjectDir)) { Join-Path $root 'opencode' } else { $ProjectDir }
$settingsPath = Join-Path $root 'opencode-launcher-settings.json'
$serverUrl = 'http://127.0.0.1:' + $Port

if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) { throw "Cannot find llama-server.exe: $serverExe" }
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { throw "Cannot find model directory: $modelDir" }
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port must be 1024..65535' }

. (Join-Path $root 'model-profiles.ps1')
. (Join-Path $root 'server-control.ps1')
# Fail rather than silently connecting OpenCode to a wrong/different server.
$tcp = $null
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connected = $false
    try { $connected = $tcp.ConnectAsync('127.0.0.1', $Port).Wait(600) -and $tcp.Connected } catch { }
    if ($connected) {
        Write-Host "Port $Port is already in use. Opening server status and controls."
        & (Join-Path $root 'start-llama-status.ps1') -Port $Port
        return
    }
} finally { if ($tcp) { $tcp.Dispose() } }


$profiles = @(Get-LocalModelProfiles -ModelDirectory $modelDir)
if (-not $profiles.Count) { throw "No GGUF models in $modelDir" }

. (Join-Path $root 'launcher-menu.ps1')

$index = Show-ModelMenu -Items $profiles -Title 'OpenCode + llama.cpp launcher'
if ($index -lt 0) { return }
$p = $profiles[$index]
$modelPath = $p.File
if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) { throw "Missing model: $modelPath" }
$context = [int]$p.Context
$outputLimit = [int]$p.Output
$reserved = [int]$p.Reserved

# The project's opencode.json is only changed after a healthy server is confirmed.
if (-not (Test-Path -LiteralPath $project -PathType Container)) {
    New-Item -Path $project -ItemType Directory -Force | Out-Null
}
$configPath = Join-Path $project 'opencode.json'

$serverArgs = @(
    '-m', ('"' + $modelPath + '"'),
    '--alias', $p.Alias,
    '--metrics',
    '--slots',
    '--host', '127.0.0.1',
    '--port', [string]$Port,
    '--no-webui',
    '--jinja',
    '--gpu-layers', $p.Gpu,
    '--fit', 'on',
    '--parallel', '1',
    '-t', [string]$p.Threads,
    '-c', [string]$context,
    '-n', [string]$outputLimit,
    '-b', [string]$p.Batch,
    '-ub', [string]$p.UBatch,
    '--cache-type-k', $p.KV,
    '--cache-type-v', $p.KV
)
$serverArgs += @(Get-ModelInferenceArguments -Profile $p)
Write-Host "`nModel: $($p.File)" -ForegroundColor Green
Write-Host "Context: $context | GPU: $($p.Gpu) | CPU threads: $($p.Threads) | KV: $($p.KV) | output limit: $outputLimit"
Write-Host "API: $serverUrl/v1 | Project: $project"
Write-Host ("Inference: " + ((Get-ModelInferenceArguments -Profile $p) -join ' '))
if ($p.Reasoning -eq 'on') { Write-Host 'The response allowance includes thinking plus the final answer.' }
if ($p.Label -match 'Qwen') { Write-Warning 'Qwen with larger OpenCode context may exceed 4 GiB VRAM even with the original GPU profile.' }
Write-Host 'Starting llama-server; logs: logs\opencode-server.stdout.log / logs\opencode-server.stderr.log' -ForegroundColor Cyan

# Capture background server output in local log files.
$proc = Start-Process -FilePath $serverExe -ArgumentList $serverArgs -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'opencode-server.stdout.log') -RedirectStandardError (Join-Path $logDir 'opencode-server.stderr.log') -PassThru
Save-ServerLogRecord $proc $Port (Join-Path $logDir 'opencode-server.stdout.log') (Join-Path $logDir 'opencode-server.stderr.log')
Write-Host 'Checking /health (up to 180 seconds)...'
$healthy = $false
for ($attempt = 0; $attempt -lt 180; $attempt++) {
    Start-Sleep -Seconds 1
    try {
        $health = Invoke-RestMethod -Uri "$serverUrl/health" -TimeoutSec 3
        if ($health.status -eq 'ok') { $healthy = $true; break }
    } catch { }
    $proc.Refresh()
    if ($proc.HasExited) { break }
}
if (-not $healthy) { throw "llama-server did not become healthy. Inspect logs\opencode-server.stderr.log; the OpenCode config was not changed." }

# Check the model alias published by the server, not just /health.
$api = Invoke-RestMethod -Uri "$serverUrl/v1/models" -TimeoutSec 10
$apiText = $api | ConvertTo-Json -Depth 10 -Compress
if ($apiText -notmatch [regex]::Escape($p.Alias)) {
    throw "Server is healthy but model alias $($p.Alias) was not found in /v1/models. OpenCode config unchanged."
}

$config = [ordered]@{
    '$schema' = 'https://opencode.ai/config.json'
    model = ('local-llama/' + $p.Alias)
    enabled_providers = @('local-llama')
    provider = [ordered]@{
        'local-llama' = [ordered]@{
            npm = '@ai-sdk/openai-compatible'
            name = 'Local llama.cpp (OpenCode)'
            options = [ordered]@{ baseURL = "$serverUrl/v1" }
            models = [ordered]@{}
        }
    }
    compaction = [ordered]@{ auto = $true; prune = $true; reserved = [int]$reserved }
    permission = [ordered]@{ edit = 'allow'; bash = 'allow'; webfetch  = 'allow'; websearch = 'allow' }
}
$config.provider['local-llama'].models[$p.Alias] = [ordered]@{
    name = $p.Label
    limit = [ordered]@{ context = $context; output = [int]$outputLimit }
}
if ($p.SystemPromptFile) {
    if (-not (Test-Path -LiteralPath $p.SystemPromptFile -PathType Leaf)) { throw "Missing coding instructions: $($p.SystemPromptFile)" }
    # Add guidance without replacing OpenCode's built-in agent/tool instructions.
    $config.instructions = @($p.SystemPromptFile)
    $config.agent = [ordered]@{
        build = [ordered]@{ temperature=$p.Temperature; top_p=$p.TopP }
        plan = [ordered]@{ temperature=$p.Temperature; top_p=$p.TopP }
    }
    $config.provider['local-llama'].models[$p.Alias].reasoning = $true
}
$json = $config | ConvertTo-Json -Depth 15
$updateConfig = $true
# Update opencode.json without creating backup files.
# The user maintains their own manual backup.
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $existing = Get-Content -LiteralPath $configPath -Raw
    if ($existing.Trim() -eq $json.Trim()) {
        $updateConfig = $false
    }
}
if ($updateConfig) {
    # UTF-8 WITHOUT BOM works for both PowerShell 5.1 and 7.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, $utf8)
}
$saved = @{ modelKey = $p.Key; context = $context } | ConvertTo-Json
[System.IO.File]::WriteAllText($settingsPath, $saved, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`nServer ready. OpenCode model: local-llama/$($p.Alias)" -ForegroundColor Green
Write-Host "Config: $configPath" -ForegroundColor Green
Write-Host 'Tool permissions: edit=allow; bash=allow'
Write-Host 'Jinja: on (GGUF chat template); prompt caching: default enabled'
Write-Host "Compaction: auto/prune; reserved=$reserved"
if ($ServerOnly) {
    Write-Host "ServerOnly requested. To run OpenCode: cd `"$project`"; opencode"
    return
}

$openCode = Get-Command 'opencode' -ErrorAction SilentlyContinue
if (-not $openCode) {
    Write-Warning 'Cannot find opencode command on PATH. Server is running and config was written.'
    Write-Host "Run: cd `"$project`"; opencode (after installation / adding it to PATH)"
    return
}
Write-Host "`nLaunching OpenCode in the current console. Exit OpenCode to return to PowerShell." -ForegroundColor Cyan
Write-Host 'The llama-server process remains running after OpenCode exits.' -ForegroundColor DarkGray
Push-Location -LiteralPath $project
$clientLog = Join-Path $logDir ('opencode-client-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $PID + '.log')
Write-Host "OpenCode stderr log: $clientLog"
$savedErrorPreference = $ErrorActionPreference
try {
    # Preserve interactive stdin/stdout; only stderr is redirected.
    # PowerShell 5.1 wraps native stderr as errors, so do not terminate on log lines.
    $ErrorActionPreference = 'Continue'
    & opencode --print-logs 2> $clientLog
} finally {
    $ErrorActionPreference = $savedErrorPreference
    Pop-Location
}

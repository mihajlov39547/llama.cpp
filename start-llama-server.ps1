# llama.cpp server launcher - Windows PowerShell 5.1 / PowerShell 7+
# Save as C:\llama.cpp\start-llama-server.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
. (Join-Path $root 'model-profiles.ps1')
. (Join-Path $root 'launcher-menu.ps1')
$exe = Join-Path $root 'bin\llama-server.exe'
$modelDir = Join-Path $root 'models'
$settingsFile = Join-Path $root 'llama-server-settings.json'
$cliSettingsFile = Join-Path $root 'llama-cli-settings.json'
$hostAddress = '127.0.0.1' # Use 0.0.0.0 only when you intend to allow LAN access
$port = 8080
$serverUrl = "http://127.0.0.1:$port"

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing server: $exe" }
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { throw "Missing models directory: $modelDir" }

$profiles = @(Get-LocalModelProfiles -ModelDirectory $modelDir)
$models = @($profiles | ForEach-Object { Get-Item -LiteralPath $_.File })
if ($models.Count -eq 0) { throw "No .gguf models in $modelDir" }

# Restore the last selected model (fall back to CLI settings on first run).
$lastModel = $null
foreach ($path in @($settingsFile, $cliSettingsFile)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ($data.lastModel) { $lastModel = [string]$data.lastModel; break }
        } catch { Write-Warning "Cannot read saved settings: $path" }
    }
}

$defaultIndex = 0
for ($i = 0; $i -lt $models.Count; $i++) {
    if ([string]::Equals($models[$i].FullName, $lastModel, [StringComparison]::OrdinalIgnoreCase)) {
        $defaultIndex = $i
        break
    }
}

$selectedIndex = Show-ModelMenu -Items $profiles -DefaultIndex $defaultIndex -Title 'llama.cpp - SERVER model launcher'
if ($selectedIndex -lt 0) { return }

$modeIndex = Show-LauncherMenu -Title 'Server mode' -Items @('API only (no Web UI)', 'Web UI + API (open browser)')
if ($modeIndex -lt 0) { return }
$apiOnly = ($modeIndex -eq 0)

# Avoid starting a second server on an occupied port.
$listener = $null
try {
    $listener = New-Object System.Net.Sockets.TcpClient
    $connected = $false
    try { $connected = $listener.ConnectAsync('127.0.0.1', $port).Wait(600) } catch { }
    if ($connected -and $listener.Connected) {
        throw "Port $port is already in use. Stop the existing server or change `$port in this script."
    }
} finally {
    if ($listener) { $listener.Dispose() }
}

$selectedModel = $models[$selectedIndex]
# Shared Gemma-4 defaults; existing Qwen profiles retain their tuned settings.
$p = $profiles[$selectedIndex]
$gpuLayers = $p.Gpu
$cpuThreads = $p.Threads
$contextSize = $p.Context
$outputLimit = $p.Output
$batchSize = $p.Batch
$microBatchSize = $p.UBatch
$cacheTypeK = $p.KV
$cacheTypeV = $p.KV
$disableReasoning = $true
$profileName = $p.Label
$chatTemplateArguments = @('--jinja')
if ($p.SingleTemplate) {
    $templatePath = Join-Path $root 'templates\gemma4-single.jinja'
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw "Missing template: $templatePath" }
    $chatTemplateArguments += @('--chat-template-file', ('"' + $templatePath + '"'))
}
Write-Host "Response allowance: $outputLimit | Input budget (including template): $($contextSize - $p.Reserved)"
Write-Host 'API clients must leave the response allowance free in the context.'

@{ lastModel = $selectedModel.FullName } | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8

$modeLabel = if ($apiOnly) { 'API only' } else { 'Web UI + API' }
Write-Host "`nStarting server with: $($selectedModel.Name)" -ForegroundColor Green
Write-Host "Mode: $modeLabel | URL: $serverUrl | Context: $contextSize | batch: $batchSize | microbatch: $microBatchSize | GPU layers: $gpuLayers | threads: $(if ($null -eq $cpuThreads) { 'default' } else { $cpuThreads }) | KV: $(if ($cacheTypeK) { $cacheTypeK } else { 'default' })"
Write-Host "Profile: $profileName" -ForegroundColor Yellow
Write-Host "Chat template: $(if ($chatTemplateArguments.Count) { $chatTemplateArguments -join ' ' } else { 'default (model metadata)' })"
Write-Host 'Server logs: llama-server.stdout.log / llama-server.stderr.log'

# Start executable directly; no cmd.exe quoting problems.
$arguments = @(
    '-m', ('"' + $selectedModel.FullName + '"'),
    '--alias', $p.Alias,
    '--parallel', '1',
    '--host', $hostAddress,
    '--port', "$port",
    '--gpu-layers', $gpuLayers,
    '--fit', 'on',
    '-n', [string]$outputLimit,
    '-c', "$contextSize",
    '-b', "$batchSize",
    '-ub', "$microBatchSize"
)
if ($null -ne $cpuThreads) { $arguments += @('-t', [string]$cpuThreads) }
if ($cacheTypeK) { $arguments += @('--cache-type-k', $cacheTypeK, '--cache-type-v', $cacheTypeV) }
if ($disableReasoning) { $arguments += @('--reasoning', 'off', '--reasoning-budget', '0') }
$arguments += $chatTemplateArguments
if ($apiOnly) { $arguments += '--no-webui' }

Write-Host ('Command: & "{0}" {1}' -f $exe, ($arguments -join ' '))
$process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Join-Path $root 'bin') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'llama-server.stdout.log') -RedirectStandardError (Join-Path $root 'llama-server.stderr.log') -PassThru

Write-Host 'Waiting for the server to become ready (up to 180 seconds)...'
$ready = $false
for ($attempt = 0; $attempt -lt 180; $attempt++) {
    Start-Sleep -Seconds 1
    try {
        $response = Invoke-WebRequest -Uri "$serverUrl/health" -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    $process.Refresh()
    if ($process.HasExited) { break }
}

if (-not $ready) {
    Write-Warning "Server not confirmed ready. Check llama-server.stderr.log. Address: $serverUrl"
    exit 1
}

Write-Host "Server ready: $serverUrl" -ForegroundColor Green
Write-Host "OpenAI-compatible API: $serverUrl/v1" -ForegroundColor Cyan
if ($apiOnly) {
    Write-Host 'API-only mode: browser will not be opened.'
    exit 0
}

$chromeCandidates = @()
if ($env:ProgramFiles) {
    $chromeCandidates += (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
}
if (${env:ProgramFiles(x86)}) {
    $chromeCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
}
if ($env:LocalAppData) {
    $chromeCandidates += (Join-Path $env:LocalAppData 'Google\Chrome\Application\chrome.exe')
}
$chromePaths = @($chromeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($chromePaths.Count -gt 0) {
    Start-Process -FilePath $chromePaths[0] -ArgumentList $serverUrl
} else {
    Start-Process $serverUrl
}

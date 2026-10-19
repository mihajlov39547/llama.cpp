# llama.cpp server launcher - Windows PowerShell 5.1 / PowerShell 7+
# Save as C:\llama.cpp\llama-server.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$exe = Join-Path $root 'bin\llama-server.exe'
$modelDir = Join-Path $root 'models'
$settingsFile = Join-Path $root 'llama-server-settings.json'
$cliSettingsFile = Join-Path $root 'llama-cli-settings.json'
$hostAddress = '127.0.0.1' # Use 0.0.0.0 only when you intend to allow LAN access
$port = 8080
$contextSize = 4096
$batchSize = 512
$microBatchSize = 128
$serverUrl = "http://127.0.0.1:$port"

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing server: $exe" }
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { throw "Missing models directory: $modelDir" }

$models = @(Get-ChildItem -LiteralPath $modelDir -Filter '*.gguf' -File -Recurse | Sort-Object FullName)
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

Write-Host "`nllama.cpp - SERVER model launcher" -ForegroundColor Cyan
Write-Host '----------------------------------'
for ($i = 0; $i -lt $models.Count; $i++) {
    $size = '{0:N2}' -f ($models[$i].Length / 1GB)
    $mark = if ($i -eq $defaultIndex) { ' [default]' } else { '' }
    Write-Host ('{0,2}. {1} ({2} GiB){3}' -f ($i + 1), $models[$i].Name, $size, $mark)
}
Write-Host ' Q. Quit'

while ($true) {
    $answer = (Read-Host "Select model [Enter = $($defaultIndex + 1)]").Trim()
    if ($answer -match '^[qQ]$') { exit 0 }
    if ($answer -eq '') { $selectedIndex = $defaultIndex; break }
    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $models.Count) {
        $selectedIndex = $number - 1
        break
    }
    Write-Host 'Invalid selection. Try again.' -ForegroundColor Yellow
}

Write-Host "`nServer mode:" -ForegroundColor Cyan
Write-Host ' 1. API only (no Web UI) [default]'
Write-Host ' 2. Web UI + API (open browser)'
while ($true) {
    $modeAnswer = (Read-Host 'Select mode [Enter = 1]').Trim()
    if ($modeAnswer -eq '' -or $modeAnswer -eq '1') { $apiOnly = $true; break }
    if ($modeAnswer -eq '2') { $apiOnly = $false; break }
    if ($modeAnswer -match '^[qQ]$') { exit 0 }
    Write-Host 'Invalid selection. Enter 1, 2, or Q.' -ForegroundColor Yellow
}

# Avoid starting a second server on an occupied port.
$listener = $null
try {
    $listener = New-Object System.Net.Sockets.TcpClient
    $connected = $listener.ConnectAsync('127.0.0.1', $port).Wait(600)
    if ($connected -and $listener.Connected) {
        throw "Port $port is already in use. Stop the existing server or change `$port in this script."
    }
} finally {
    if ($listener) { $listener.Dispose() }
}

$selectedModel = $models[$selectedIndex]
@{ lastModel = $selectedModel.FullName } | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8

$modeLabel = if ($apiOnly) { 'API only' } else { 'Web UI + API' }
Write-Host "`nStarting server with: $($selectedModel.Name)" -ForegroundColor Green
Write-Host "Mode: $modeLabel | URL: $serverUrl | Context: $contextSize | batch: $batchSize | microbatch: $microBatchSize | GPU layers: auto"
Write-Host 'The server opens in a separate console window.'

# Start executable directly; no cmd.exe quoting problems.
$arguments = @(
    '-m', ('"' + $selectedModel.FullName + '"'),
    '--host', $hostAddress,
    '--port', "$port",
    '--gpu-layers', 'auto',
    '--fit', 'on',
    '-c', "$contextSize",
    '-b', "$batchSize",
    '-ub', "$microBatchSize"
)
if ($apiOnly) { $arguments += '--no-webui' }

$process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Join-Path $root 'bin') -PassThru

Write-Host 'Waiting for the server to become ready (up to 120 seconds)...'
$ready = $false
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    Start-Sleep -Seconds 1
    try {
        $response = Invoke-WebRequest -Uri "$serverUrl/health" -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    if ($process.HasExited) { break }
}

if (-not $ready) {
    Write-Warning "Server not confirmed ready. Check the server console. Address: $serverUrl"
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

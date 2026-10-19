# llama.cpp server launcher - Windows PowerShell 5.1 / PowerShell 7+
# Save to C:\llama.cpp\llama-server.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$exe = Join-Path $root 'bin\llama-server.exe'
$modelDir = Join-Path $root 'models'
$settingsFile = Join-Path $root 'llama-server-settings.json'
$cliSettingsFile = Join-Path $root 'llama-cli-settings.json'
$hostAddress = '127.0.0.1' # Change to '0.0.0.0' only if LAN access is required
$port = 8080
$contextSize = 4096
$serverUrl = "http://127.0.0.1:$port"

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing server: $exe" }
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { throw "Missing models directory: $modelDir" }

$models = @(Get-ChildItem -LiteralPath $modelDir -Filter '*.gguf' -File -Recurse | Sort-Object FullName)
if ($models.Count -eq 0) { throw "No .gguf models in $modelDir" }

# Use the server's last choice; on first run, optionally reuse the CLI choice.
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

# Do not start another server if port 8080 is already occupied.
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

Write-Host "`nStarting server with: $($selectedModel.Name)" -ForegroundColor Green
Write-Host "URL: $serverUrl | Context: $contextSize | GPU layers: auto"
Write-Host 'The server opens in a separate console window.'

# Keep stderr/stdout attached to that console for easy diagnostics.
# Start-Process with -PassThru allows checking whether loading failed.
$arguments = @(
    '-m', ('"' + $selectedModel.FullName + '"'),
    '--host', $hostAddress,
    '--port', "$port",
    '--gpu-layers', 'auto',
    '--fit', 'on',
    '-c', "$contextSize"
) -join ' '
$cmd = '"' + $exe + '" ' + $arguments
$process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', $cmd) -WorkingDirectory (Join-Path $root 'bin') -PassThru

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

$chromePaths = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LocalAppData 'Google\Chrome\Application\chrome.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

Write-Host "Server ready: $serverUrl" -ForegroundColor Green
if ($chromePaths.Count -gt 0) {
    Start-Process -FilePath $chromePaths[0] -ArgumentList $serverUrl
} else {
    Start-Process $serverUrl # default browser
}

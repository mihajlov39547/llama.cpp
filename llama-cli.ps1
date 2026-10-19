# llama.cpp CLI launcher - PowerShell 5.1 / 7+
# Put this script in C:\llama.cpp\llama-cli.ps1.
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$exe = Join-Path $root 'bin\llama-cli.exe'
$modelDir = Join-Path $root 'models'
$settingsFile = Join-Path $root 'llama-cli-settings.json'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Write-Host "Executable not found: $exe" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) {
    Write-Host "Models folder not found: $modelDir" -ForegroundColor Red
    exit 1
}

$models = @(Get-ChildItem -LiteralPath $modelDir -Filter '*.gguf' -File -Recurse |
    Sort-Object FullName)
if ($models.Count -eq 0) {
    Write-Host "No GGUF models found in $modelDir" -ForegroundColor Yellow
    exit 1
}

$lastModel = $null
if (Test-Path -LiteralPath $settingsFile -PathType Leaf) {
    try {
        $settings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
        $lastModel = [string]$settings.lastModel
    } catch {
        Write-Warning 'Cannot read saved settings; model selection will use the first model.'
    }
}

$defaultIndex = 0
for ($i = 0; $i -lt $models.Count; $i++) {
    if ($models[$i].FullName -eq $lastModel) {
        $defaultIndex = $i
        break
    }
}

Write-Host ''
Write-Host 'llama.cpp - CLI model launcher' -ForegroundColor Cyan
Write-Host '--------------------------------'
for ($i = 0; $i -lt $models.Count; $i++) {
    $size = '{0:N2}' -f ($models[$i].Length / 1GB)
    $marker = if ($i -eq $defaultIndex) { ' [default]' } else { '' }
    Write-Host ('{0,2}. {1} ({2} GiB){3}' -f ($i + 1), $models[$i].Name, $size, $marker)
}
Write-Host ' Q. Quit'

while ($true) {
    $answer = (Read-Host "Select model [Enter = $($defaultIndex + 1)]").Trim()
    if ($answer -match '^[qQ]$') { exit 0 }
    if ($answer -eq '') {
        $selectedIndex = $defaultIndex
        break
    }
    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $models.Count) {
        $selectedIndex = $number - 1
        break
    }
    Write-Host 'Invalid selection. Try again.' -ForegroundColor Yellow
}

$selectedModel = $models[$selectedIndex]
# Save preference before launch, so it persists even if the user interrupts the CLI.
@{ lastModel = $selectedModel.FullName } |
    ConvertTo-Json |
    Set-Content -LiteralPath $settingsFile -Encoding UTF8

Write-Host ''
Write-Host "Starting: $($selectedModel.Name)" -ForegroundColor Green
Write-Host "Model path: $($selectedModel.FullName)"
Write-Host 'GPU: automatic | context: 4096'
Write-Host 'Press Ctrl+C to stop the model.'
Write-Host ''

Push-Location (Join-Path $root 'bin')
try {
    & $exe -m $selectedModel.FullName --gpu-layers auto --fit on -c 4096
} finally {
    Pop-Location
}

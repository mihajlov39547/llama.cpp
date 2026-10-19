# llama.cpp CLI launcher - PowerShell 5.1 / 7+
# Save as C:\llama.cpp\llama-cli.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$exe = Join-Path $root 'bin\llama-cli.exe'
$modelDir = Join-Path $root 'models'
$settingsFile = Join-Path $root 'llama-cli-settings.json'
$contextSize = 6144
$batchSize = 512
$microBatchSize = 128

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Executable not found: $exe"
}
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) {
    throw "Models folder not found: $modelDir"
}

$models = @(Get-ChildItem -LiteralPath $modelDir -Filter '*.gguf' -File -Recurse |
    Sort-Object FullName)
if ($models.Count -eq 0) {
    throw "No GGUF models found in $modelDir"
}

$lastModel = $null
if (Test-Path -LiteralPath $settingsFile -PathType Leaf) {
    try {
        $settings = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
        if ($settings.lastModel) { $lastModel = [string]$settings.lastModel }
    } catch {
        Write-Warning 'Cannot read saved settings; using the first model.'
    }
}

$defaultIndex = 0
for ($i = 0; $i -lt $models.Count; $i++) {
    if ([string]::Equals($models[$i].FullName, $lastModel,
            [StringComparison]::OrdinalIgnoreCase)) {
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
    if ([int]::TryParse($answer, [ref]$number) -and
        $number -ge 1 -and $number -le $models.Count) {
        $selectedIndex = $number - 1
        break
    }
    Write-Host 'Invalid selection. Try again.' -ForegroundColor Yellow
}

$selectedModel = $models[$selectedIndex]
@{ lastModel = $selectedModel.FullName } |
    ConvertTo-Json |
    Set-Content -LiteralPath $settingsFile -Encoding UTF8

# The tested Q4_K_M Gemma 4 E2B model has large embedding tensors that
# llama.cpp normally leaves in system RAM. Explicitly send them to CUDA0.
# Do NOT force this for Q5/Q6: their weights exceed practical 4 GiB VRAM capacity.
$fullGpuQ4 = $selectedModel.Name -eq 'google_gemma-4-E2B-it-Q4_K_M.gguf'

$arguments = @(
    '-m', $selectedModel.FullName,
    '--gpu-layers', 'all',
    '-c', [string]$contextSize,
    '-b', [string]$batchSize,
    '-ub', [string]$microBatchSize
)

if ($fullGpuQ4) {
    $arguments += @('--fit', 'off', '--override-tensor', 'token_embd\.weight=CUDA0')
    Write-Host ''
    Write-Host 'GPU mode: Q4 embedding weights forced to CUDA0' -ForegroundColor Yellow
    Write-Host 'WARNING: 6144 context may run out of VRAM on a 4 GB GPU.' -ForegroundColor Yellow
} else {
    $arguments += @('--fit', 'on')
    Write-Host ''
    Write-Host 'GPU mode: automatic memory fitting (larger model)' -ForegroundColor Yellow
}

Write-Host "Starting: $($selectedModel.Name)" -ForegroundColor Green
Write-Host "Model path: $($selectedModel.FullName)"
Write-Host "Context: $contextSize | batch: $batchSize | microbatch: $microBatchSize"
Write-Host 'Press Ctrl+C to stop.'
Write-Host ''

Push-Location (Join-Path $root 'bin')
try {
    & $exe @arguments
} finally {
    Pop-Location
}

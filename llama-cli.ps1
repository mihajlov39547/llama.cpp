# llama.cpp CLI launcher - PowerShell 5.1 / 7+
# Save as C:\llama.cpp\llama-cli.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$exe = Join-Path $root 'bin\llama-cli.exe'
$modelDir = Join-Path $root 'models'
$settingsFile = Join-Path $root 'llama-cli-settings.json'
$contextSize = 4096
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

# Benchmark-validated profiles for the GTX 1650 Ti (4 GiB), October 2026.
# Exact filename matching ensures other models retain the original safe defaults.
$gpuLayers = 'auto'
$cpuThreads = $null
$microBatchSize = 128
$cacheTypeK = $null
$cacheTypeV = $null
$disableReasoning = ($selectedModel.Name -match 'Qwen3')
$profileName = 'Default (untested model)'
switch -Regex ($selectedModel.Name) {
    '^google_gemma-4-E2B-it-Q4_K_M\.gguf$' {
        $gpuLayers = 'auto'; $cpuThreads = 4; $microBatchSize = 128
        $cacheTypeK = 'f16'; $cacheTypeV = 'f16'
        $disableReasoning = $true
        $profileName = 'Gemma 4 E2B benchmark profile'
        break
    }
    '^Qwen3\.5-4B-Q4_K_M\.gguf$' {
        $gpuLayers = 'all'; $cpuThreads = 6; $microBatchSize = 256
        $cacheTypeK = 'f16'; $cacheTypeV = 'f16'
        $disableReasoning = $true
        $profileName = 'Qwen3.5 4B benchmark profile'
        break
    }
    '^Qwen3-4B-Q4_K_M\.gguf$' {
        $gpuLayers = 'all'; $cpuThreads = 6; $microBatchSize = 256
        $cacheTypeK = 'q8_0'; $cacheTypeV = 'q8_0'
        $disableReasoning = $true
        $profileName = 'Qwen3 4B balanced VRAM profile'
        break
    }
}
$arguments = @(
    '-m', $selectedModel.FullName,
    '--gpu-layers', $gpuLayers,
    '--fit', 'on',
    '-c', [string]$contextSize,
    '-b', [string]$batchSize,
    '-ub', [string]$microBatchSize
)
if ($null -ne $cpuThreads) { $arguments += @('-t', [string]$cpuThreads) }
if ($cacheTypeK) { $arguments += @('--cache-type-k', $cacheTypeK, '--cache-type-v', $cacheTypeV) }
if ($disableReasoning) { $arguments += @('--reasoning', 'off', '--reasoning-budget', '0') }

Write-Host ''
Write-Host "Profile: $profileName | GPU layers: $gpuLayers | threads: $(if ($null -eq $cpuThreads) { 'default' } else { $cpuThreads }) | KV: $(if ($cacheTypeK) { $cacheTypeK } else { 'default' })" -ForegroundColor Yellow
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

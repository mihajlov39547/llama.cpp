# llama.cpp CLI launcher - PowerShell 5.1 / 7+
# Save as C:\llama.cpp\llama-cli.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
. (Join-Path $root 'model-profiles.ps1')
$exe = Join-Path $root 'bin\llama-cli.exe'
$modelDir = Join-Path $root 'models'
$settingsFile = Join-Path $root 'llama-cli-settings.json'

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Executable not found: $exe"
}
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) {
    throw "Models folder not found: $modelDir"
}

$profiles = @(Get-LocalModelProfiles -ModelDirectory $modelDir)
$models = @($profiles | ForEach-Object { Get-Item -LiteralPath $_.File })
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
    $chatTemplateArguments += @('--chat-template-file', $templatePath)
}
Write-Host "Response allowance: $outputLimit | Input budget (including template): $($contextSize - $p.Reserved)"
Write-Host 'Keep prompts within the input budget to leave the full response allowance.'

$arguments = @(
    '-m', $selectedModel.FullName,
    '--gpu-layers', $gpuLayers,
    '--fit', 'on',
    '-n', [string]$outputLimit,
    '-c', [string]$contextSize,
    '-b', [string]$batchSize,
    '-ub', [string]$microBatchSize
)
if ($null -ne $cpuThreads) { $arguments += @('-t', [string]$cpuThreads) }
if ($cacheTypeK) { $arguments += @('--cache-type-k', $cacheTypeK, '--cache-type-v', $cacheTypeV) }
if ($disableReasoning) { $arguments += @('--reasoning', 'off', '--reasoning-budget', '0') }
$arguments += $chatTemplateArguments

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

# llama.cpp CLI launcher - PowerShell 5.1 / 7+
# Save as C:\llama.cpp\start-llama-cli.ps1
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$logDir = Join-Path $root 'logs'
[void][IO.Directory]::CreateDirectory($logDir)
. (Join-Path $root 'model-profiles.ps1')
. (Join-Path $root 'launcher-menu.ps1')
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

$selectedIndex = Show-ModelMenu -Items $profiles -DefaultIndex $defaultIndex -Title 'llama.cpp - CLI model launcher'
if ($selectedIndex -lt 0) { return }

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

$cliLog = Join-Path $logDir ('llama-cli-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $PID + '.log')
Write-Host "Engine log: $cliLog"
$arguments = @(
    '--log-file', $cliLog,
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

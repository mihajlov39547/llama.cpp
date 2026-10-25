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
$serverExe = Join-Path $root 'bin\llama-server.exe'
$modelDir = Join-Path $root 'models'
$project = if ([string]::IsNullOrWhiteSpace($ProjectDir)) { Join-Path $root 'opencode' } else { $ProjectDir }
$settingsPath = Join-Path $root 'opencode-launcher-settings.json'
$serverUrl = 'http://127.0.0.1:' + $Port

if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) { throw "Cannot find llama-server.exe: $serverExe" }
if (-not (Test-Path -LiteralPath $modelDir -PathType Container)) { throw "Cannot find model directory: $modelDir" }
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Port must be 1024..65535' }

. (Join-Path $root 'model-profiles.ps1')
$profiles = @(Get-LocalModelProfiles -ModelDirectory $modelDir)
if (-not $profiles.Count) { throw "No GGUF models in $modelDir" }

function Show-ModelMenu {
    param([object[]]$Items)
    $selection = 0  # Always start on Gemma; no remembered last selection.
    $interactive = $false
    try {
        $interactive = (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    } catch { $interactive = $false }

    if ($interactive) {
        try {
            [Console]::CursorVisible = $false
            while ($true) {
                [Console]::Clear()
                Write-Host 'OpenCode + llama.cpp launcher' -ForegroundColor Cyan
                Write-Host 'Use Up/Down arrows, then Enter. Esc or Q to quit.'
                Write-Host 'Default selection: Gemma 4 E2B - 48K context' -ForegroundColor DarkGray
                Write-Host ''
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    $item = $Items[$i]
                    $path = $item.File
                    $status = if (Test-Path -LiteralPath $path -PathType Leaf) { '' } else { ' [MODEL MISSING]' }
                    $prefix = if ($i -eq $selection) { ' > ' } else { '   ' }
                    $line = ('{0}{1}. {2} | {3}K context ({4} tokens){5}' -f $prefix, ($i + 1), $item.Label, [int]($item.Context / 1024), $item.Context, $status)
                    if ($i -eq $selection) {
                        Write-Host $line -ForegroundColor Black -BackgroundColor Cyan
                    } else { Write-Host $line }
                }
                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    'UpArrow' { $selection = ($selection + $Items.Count - 1) % $Items.Count }
                    'DownArrow' { $selection = ($selection + 1) % $Items.Count }
                    'Enter' { return $selection }
                    'Escape' { return -1 }
                    default {
                        if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { return -1 }
                        if ($key.KeyChar -match '^[1-9]$' -and [int]::Parse([string]$key.KeyChar) -le $Items.Count) { return ([int]::Parse([string]$key.KeyChar) - 1) }
                    }
                }
            }
        } finally { try { [Console]::CursorVisible = $true } catch {} }
    }

    # Fallback for hosts which don't support Console.ReadKey / interactive arrows.
    Write-Host "`nOpenCode + llama.cpp launcher" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host (' {0}. {1} | {2}K context' -f ($i + 1), $Items[$i].Label, [int]($Items[$i].Context / 1024))
    }
    while ($true) {
        $answer = (Read-Host "Choose 1-$($Items.Count) [Enter=1, Q=quit]").Trim()
        if ($answer -eq '') { return 0 }
        if ($answer -match '^[qQ]$') { return -1 }
        if ($answer -match '^[1-9][0-9]*$' -and [int]$answer -le $Items.Count) { return ([int]$answer - 1) }
    }
}

$index = Show-ModelMenu -Items $profiles
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

# Fail rather than silently connecting OpenCode to a wrong/different server.
$tcp = $null
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connected = $false
    try { $connected = $tcp.ConnectAsync('127.0.0.1', $Port).Wait(600) -and $tcp.Connected } catch { }
    if ($connected) {
        throw "Port $Port is already in use. Stop the old llama-server.exe first, then rerun this launcher."
    }
} finally { if ($tcp) { $tcp.Dispose() } }

$serverArgs = @(
    '-m', ('"' + $modelPath + '"'),
    '--alias', $p.Alias,
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
    '--cache-type-v', $p.KV,
    '--reasoning', 'off',
    '--reasoning-budget', '0'
)
Write-Host "`nModel: $($p.File)" -ForegroundColor Green
Write-Host "Context: $context | GPU: $($p.Gpu) | CPU threads: $($p.Threads) | KV: $($p.KV) | output limit: $outputLimit"
Write-Host "API: $serverUrl/v1 | Project: $project"
if ($p.Label -match 'Qwen') { Write-Warning 'Qwen with larger OpenCode context may exceed 4 GiB VRAM even with the original GPU profile.' }
Write-Host 'Starting llama-server; logs: opencode-server.stdout.log / opencode-server.stderr.log' -ForegroundColor Cyan

# Capture background server output in local log files.
$proc = Start-Process -FilePath $serverExe -ArgumentList $serverArgs -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'opencode-server.stdout.log') -RedirectStandardError (Join-Path $root 'opencode-server.stderr.log') -PassThru
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
if (-not $healthy) { throw "llama-server did not become healthy. Inspect opencode-server.stderr.log; the OpenCode config was not changed." }

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
try { & opencode } finally { Pop-Location }

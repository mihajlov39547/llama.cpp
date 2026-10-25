# Inspect and manage this workspace's background llama-server, PowerShell 5.1+.
[CmdletBinding()]
param(
    [ValidateRange(1,65535)][int]$Port = 8080,
    [ValidateSet('Menu','Status','Stop','Restart')][string]$Action = 'Menu'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'launcher-menu.ps1')
. (Join-Path $PSScriptRoot 'server-control.ps1')
while ($true) {
    $server = Get-LocalServerProcess -Port $Port
    $lines = @(Get-ServerStatusLines -Server $server -Port $Port)
    if ($Action -eq 'Status') { $lines | ForEach-Object { Write-Host $_ }; return }
    $choice = $Action
    if ($Action -eq 'Menu') {
        $index = Show-LauncherMenu -Title 'llama-server status and controls' -Header $lines -Items @(
            'Continue / leave server running', 'Refresh status',
            'Stop server (interrupts active requests)', 'Restart same model/settings + enable metrics (interrupts active requests)'
        )
        switch ($index) { 1 { continue }; 2 { $choice='Stop' }; 3 { $choice='Restart' }; default { return } }
        if ($index -eq 1) { continue }
    }
    if (-not $server) { Write-Host "No server listening on port $Port."; return }
    try {
        if ($choice -eq 'Stop') { Stop-LocalServer $server $Port; return }
        if ($choice -eq 'Restart') { Restart-LocalServer $server $Port }
    } catch {
        if ($Action -ne 'Menu') { throw }
        Write-Warning $_.Exception.Message
        [void](Read-Host 'Press Enter to return to status')
    }
    if ($Action -ne 'Menu') { return }
}

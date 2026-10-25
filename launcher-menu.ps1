# Shared keyboard menu for Windows PowerShell 5.1 / PowerShell 7+.
function Show-LauncherMenu {
    param(
        [Parameter(Mandatory=$true)][string[]]$Items,
        [string]$Title = 'Select model',
        [int]$DefaultIndex = 0
    )
    if (-not $Items.Count) { throw 'The menu has no items.' }
    if ($DefaultIndex -lt 0 -or $DefaultIndex -ge $Items.Count) { throw 'Invalid default menu selection.' }
    $selection = $DefaultIndex
    $interactive = $false
    try {
        $interactive = (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    } catch { }

    if ($interactive) {
        $previousCursor = $true
        try {
            $previousCursor = [Console]::CursorVisible
            [Console]::CursorVisible = $false
            while ($true) {
                [Console]::Clear()
                Write-Host $Title -ForegroundColor Cyan
                Write-Host 'Up/Down: move | Enter: select | Esc/Q: quit'
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    $prefix = if ($i -eq $selection) { ' > ' } else { '   ' }
                    $line = '{0}{1}. {2}' -f $prefix, ($i + 1), $Items[$i]
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
                        if ($key.KeyChar -match '^[qQ]$') { return -1 }
                        # Number shortcuts move the highlight; Enter confirms.
                        if ($key.KeyChar -match '^[1-9]$') {
                            $number = [int]::Parse([string]$key.KeyChar)
                            if ($number -le $Items.Count) { $selection = $number - 1 }
                        }
                    }
                }
            }
        } catch {
            Write-Verbose "Console keyboard unavailable; using numbered selection: $_"
        } finally {
            try { [Console]::CursorVisible = $previousCursor } catch { }
        }
    }

    Write-Host "`n$Title" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host (' {0}. {1}' -f ($i + 1), $Items[$i])
    }
    while ($true) {
        $answer = Read-Host "Choose 1-$($Items.Count) [Enter=$($selection + 1), Q=quit]"
        if ($null -eq $answer) { return -1 }
        $answer = $answer.Trim()
        if ($answer -eq '') { return $selection }
        if ($answer -match '^[qQ]$') { return -1 }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count) {
            return ($number - 1)
        }
        Write-Host 'Invalid selection. Try again.' -ForegroundColor Yellow
    }
}

function Show-ModelMenu {
    param([object[]]$Items, [int]$DefaultIndex = 0, [string]$Title = 'Select model')
    $labels = @($Items | ForEach-Object {
        '{0} | {1}K context | {2:N2} GiB' -f $_.Label, ($_.Context / 1024), ((Get-Item -LiteralPath $_.File).Length / 1GB)
    })
    Show-LauncherMenu -Items $labels -DefaultIndex $DefaultIndex -Title $Title
}

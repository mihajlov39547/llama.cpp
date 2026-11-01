#requires -Version 5.1
<#
.SYNOPSIS
  Interactive updater for Windows developer tools.
.DESCRIPTION
  For each manager in turn: inventory -> discover -> choose -> apply -> next manager.
  Supported: npm global, winget, pip (current Python), pipx, Scoop, Chocolatey,
  WSL component and APT packages in installed Debian/Ubuntu WSL distros.
  No changes are made during the discovery phase (except apt-get update: cache metadata).
  The WSL APT metadata refresh is a package-index operation, not an upgrade.
  Run interactively in Windows PowerShell 5.1 or PowerShell 7+.
.EXAMPLE
  .\Update-WindowsTools.ps1
.EXAMPLE
  .\Update-WindowsTools.ps1 -SkipWSL -SkipWinget
.EXAMPLE
  .\Update-WindowsTools.ps1 -IncludeVenv
#>
[CmdletBinding()]
param(
    [switch]$SkipWSL,
    [switch]$SkipWinget,
    [switch]$SkipNpm,
    [switch]$SkipPython,
    [switch]$IncludeVenv,
    [switch]$SkipPipx,
    [switch]$SkipScoop,
    [switch]$SkipChoco,
    [switch]$NoTranscript
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:LastCommandExitCode = 0
$script:ScanErrors = [System.Collections.Generic.List[string]]::new()
$script:Groups = [System.Collections.Generic.List[object]]::new()
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Write-Section([string]$message) {
    Write-Host "`n===== $message =====" -ForegroundColor Cyan
}
function Has-Command([string]$name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Get-Text([string]$exe, [string[]]$arguments, [int[]]$allowedExitCodes = @()) {
    # Preserve CLI output as plain text; callers may tolerate non-zero exit codes (npm outdated).
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Handle expected nonzero native exit codes ourselves in PowerShell 7 too.
    $PSNativeCommandUseErrorActionPreference = $false
    $stderrFile = [IO.Path]::GetTempFileName()
    try {
        $raw = & $exe @arguments 2> $stderrFile
        $script:LastCommandExitCode = $LASTEXITCODE
        $stderr = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
        if ($allowedExitCodes.Count -gt 0 -and $script:LastCommandExitCode -notin $allowedExitCodes) {
            throw "$exe $($arguments -join ' ') failed (exit $script:LastCommandExitCode): $stderr $raw"
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Warning $stderr.Trim() }
        return (($raw | ForEach-Object { $_.ToString() }) -join "`n")
    } finally {
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $saved
    }
}
function To-JsonObject([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try { return (ConvertFrom-Json -InputObject $s -ErrorAction Stop) } catch { throw "Cannot parse JSON: $($_.Exception.Message)" }
}
function Add-Group([string]$manager, [object[]]$items, [string]$note = '') {
    $clean = @($items | Where-Object { $_ -and $_.Name } | Sort-Object -Property Name -Unique)
    $script:Groups.Add([pscustomobject]@{ Manager=$manager; Items=$clean; Note=$note })
    Write-Host ("{0}: {1} available update(s). {2}" -f $manager,$clean.Count,$note)
}
function Register-ScanError([string]$manager, [string]$message) {
    $script:ScanErrors.Add("$manager`: $message")
    Write-Warning "${manager}: $message"
}
function New-ItemRecord([string]$manager,[string]$name,[string]$current,[string]$latest,[string]$id = '',[string]$distro = '') {
    return [pscustomobject]@{ Manager=$manager; Name=$name; Current=$current; Latest=$latest; Id=$id; Distro=$distro }
}
function Read-ArrowMenu([string]$prompt,[string[]]$options) {
    if ($options.Count -eq 0) { return -1 }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        Write-Host $prompt
        for ($i=0;$i -lt $options.Count;$i++) { Write-Host ("  {0}. {1}" -f ($i+1),$options[$i]) }
        $answer = Read-Host 'Number'
        $num = 0
        if ([int]::TryParse($answer,[ref]$num) -and $num -ge 1 -and $num -le $options.Count) { return $num-1 }
        return $options.Count-1
    }
    $index=0
    $top=[Console]::CursorTop
    $rowWidth=[Math]::Max(20,[Console]::WindowWidth-1)
    Write-Host $prompt
    $start=[Console]::CursorTop
    for ($j=0;$j -lt $options.Count;$j++) { Write-Host '' }
    try {
        while ($true) {
            for ($i=0;$i -lt $options.Count;$i++) {
                [Console]::SetCursorPosition(0,$start+$i)
                $prefix=if ($i -eq $index) { '> ' } else { '  ' }
                $line=$prefix+$options[$i]
                if ($line.Length -gt $rowWidth) { $line=$line.Substring(0,$rowWidth) }
                Write-Host $line.PadRight($rowWidth) -NoNewline -ForegroundColor $(if($i -eq $index){'Yellow'}else{'Gray'})
            }
            [Console]::SetCursorPosition(0,$start+$options.Count)
            $key=[Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $index=($index-1+$options.Count)%$options.Count }
                'DownArrow' { $index=($index+1)%$options.Count }
                'Enter'     { return $index }
                'Escape'    { return ($options.Count-1) }
            }
        }
    } catch {
        Write-Host "`nArrow-key mode unavailable; using numeric input."
        for ($i=0;$i -lt $options.Count;$i++) { Write-Host ("  {0}. {1}" -f ($i+1),$options[$i]) }
        $choice=Read-Host 'Number'
        $num=0
        if ([int]::TryParse($choice,[ref]$num) -and $num -ge 1 -and $num -le $options.Count) { return $num-1 }
        return $options.Count-1
    }
}
function Select-Individual([object[]]$items) {
    $selected = New-Object 'bool[]' $items.Count
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        foreach ($i in 0..($items.Count-1)) {
            $x=Read-Host "Update $($items[$i].Name) ($($items[$i].Current) -> $($items[$i].Latest))? [y/N]"
            $selected[$i]=$x -match '^(y|yes|d|da)$'
        }
    } else {
        $page=0
        while ($true) {
            Clear-Host
            Write-Host 'Up/Down = navigate | Space = toggle | A = all | N = none | Enter = confirm | Esc = cancel' -ForegroundColor Cyan
            $pageSize=[Math]::Max(5,[Math]::Min(18,[Console]::WindowHeight-5))
            $offset=[int]([Math]::Floor($page/$pageSize)*$pageSize)
            $end=[Math]::Min($offset+$pageSize,$items.Count)
            Write-Host "Items $($offset+1)-$end of $($items.Count)"
            for ($i=$offset;$i -lt $end;$i++) {
                $flag=if($selected[$i]){'x'}else{' '}
                $cursor=if($i -eq $page){'>'}else{' '}
                $line="${cursor} [$flag] $($items[$i].Name)  $($items[$i].Current) -> $($items[$i].Latest)"
                Write-Host $line -ForegroundColor $(if($i -eq $page){'Yellow'}else{'Gray'})
            }
            $key=[Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $page=($page-1+$items.Count)%$items.Count }
                'DownArrow' { $page=($page+1)%$items.Count }
                'Spacebar'  { $selected[$page]= -not $selected[$page] }
                'A'         { for($i=0;$i -lt $items.Count;$i++){$selected[$i]=$true} }
                'N'         { for($i=0;$i -lt $items.Count;$i++){$selected[$i]=$false} }
                'Enter'     { return @($items | Where-Object { $selected[[array]::IndexOf($items,$_)] }) }
                'Escape'    { return @() }
            }
        }
    }
    $result=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt $items.Count;$i++){if($selected[$i]){$result.Add($items[$i])}}
    return @($result.ToArray())
}
# Winget renders a fixed-width table. This parser supports English headers;
# unsupported formats must report an error instead of silently returning no updates.
function Parse-WingetTable([string]$data) {
    if ($data -match '(?i)no applicable update|no installed package|no available upgrade|no upgrades available') { return @() }
    # winget prints ONE continuous dashed separator, not separate dashed blocks.
    # Determine column starts from the header row instead of separator matches.
    $lines = @($data -split "`r?`n")
    $headerIndex = -1
    $idStart = -1; $versionStart = -1; $availableStart = -1; $sourceStart = -1
    for ($i=0; $i -lt $lines.Count-1; $i++) {
        $line = $lines[$i]
        if ($line -match '(?i)^\s*Name\s+Id\s+Version\s+Available\s+Source\s*$' -and
            $lines[$i+1] -match '^\s*-{20,}\s*$') {
            $headerIndex = $i
            $idStart = $line.IndexOf('Id')
            $versionStart = $line.IndexOf('Version')
            $availableStart = $line.IndexOf('Available')
            $sourceStart = $line.IndexOf('Source')
            break
        }
    }
    if ($headerIndex -lt 0) { throw 'Could not identify winget upgrade columns. The output format may have changed.' }
    $found = [System.Collections.Generic.List[object]]::new()
    for ($i=$headerIndex+2; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Length -le $sourceStart) { continue }
        $source = $line.Substring($sourceStart).Trim()
        if ($source -notin @('winget','msstore')) { continue }
        $name = $line.Substring(0,$idStart).Trim()
        $id = $line.Substring($idStart,$versionStart-$idStart).Trim()
        $current = $line.Substring($versionStart,$availableStart-$versionStart).Trim()
        $latest = $line.Substring($availableStart,$sourceStart-$availableStart).Trim()
        if (-not $name -or -not $id -or -not $latest -or $id -match '(\.{3}|\u2026)$') {
            Write-Warning "Skipped incomplete winget record: $line"
            continue
        }
        if ($current -eq $latest) { continue }
        # Winget already selected these upgrades. Versions such as '< 4.3' are
        # valid display values; installation uses the exact package ID.
        $found.Add((New-ItemRecord 'winget' $name $current $latest $id))
    }
    return @($found.ToArray())
}

function Ask-Choice([string]$question, [string[]]$options, [int]$default = 0) {
    Write-Host "`n$question" -ForegroundColor Cyan
    for ($i=0; $i -lt $options.Count; $i++) {
        $mark = if ($i -eq $default) { ' (default)' } else { '' }
        Write-Host ("  {0}. {1}{2}" -f ($i + 1), $options[$i], $mark)
    }
    while ($true) {
        $answer = (Read-Host ("Enter 1-{0} [Enter={1}]" -f $options.Count, ($default + 1))).Trim()
        if (-not $answer) { return $default }
        $num = 0
        if ([int]::TryParse($answer, [ref]$num) -and $num -ge 1 -and $num -le $options.Count) { return ($num - 1) }
        Write-Host 'Invalid choice. Enter the number shown.' -ForegroundColor Yellow
    }
}
function Choose-Items([string]$manager, [object[]]$items) {
    if ($items.Count -eq 0) { return @() }
    $choice = Ask-Choice "Updates found for ${manager}: $($items.Count). What do you want to do?" @(
        'ALL - update everything listed',
        'INDIVIDUAL - ask about each package',
        'NONE - skip this manager'
    ) 2
    if ($choice -eq 2) { return @() }
    if ($choice -eq 0) { return @($items) }
    $chosen = [System.Collections.Generic.List[object]]::new()
    foreach ($it in $items) {
        $answer = (Read-Host ("Update {0} ({1} -> {2})? [y/N/q=stop]" -f $it.Name, $it.Current, $it.Latest)).Trim()
        if ($answer -match '^(q|quit|stop)$') { break }
        if ($answer -match '^(y|yes|d|da)$') { $chosen.Add($it) }
    }
    return @($chosen.ToArray())
}
function Apply-Updates([string]$manager, [object[]]$items, [bool]$allSelected = $false) {
    if ($items.Count -eq 0) { Write-Host 'Skipped (nothing selected).'; return }
    Write-Host "`nSelected in ${manager}:" -ForegroundColor Cyan
    foreach ($it in $items) { Write-Host ("  {0}: {1} -> {2}" -f $it.Name,$it.Current,$it.Latest) }
    $confirm=Ask-Choice "Apply these $($items.Count) update(s) now?" @('YES - run updates now','NO - skip and continue') 1
    if ($confirm -ne 0) { Write-Host 'Skipped. Moving to next manager.';return }
    # For APT, a single apt-get upgrade solves dependency coupling safely; no dist/full-upgrade.
    if ($manager -like 'WSL:*' -and $allSelected -and $items.Count -gt 1) {
        $distro=$items[0].Distro
        Write-Section "Updating WSL:$distro (apt-get upgrade)"
        try {
            & wsl -d $distro -u root -- apt-get upgrade -y 2>&1 | Out-Host
            $ec=$LASTEXITCODE
            if ($ec -ne 0) { throw "Exit code $ec" }
            $script:Results.Add([pscustomobject]@{Manager=$manager;Name="APT: $($items.Count) packages";Status='SUCCESS'})
        } catch { Write-Warning "FAILED: $_"; $script:Results.Add([pscustomobject]@{Manager=$manager;Name='APT upgrade';Status='FAILED'}) }
        return
    }
    foreach ($it in $items) {
        Write-Section "Updating [$manager] $($it.Name)"
        $cmd=$null; $arg=@()
        switch -Regex ($manager) {
            '^npm$' { $cmd='npm'; $arg=@('install','-g',"$($it.Name)@latest"); break }
            '^winget$' { $cmd='winget'; $arg=@('upgrade','--id',$it.Id,'--exact','--accept-source-agreements','--accept-package-agreements','--disable-interactivity'); break }
            '^pip$' { $cmd='python'; $arg=@('-m','pip','install','--upgrade',$it.Name); break }
            '^pipx$' { $cmd='pipx'; $arg=@('upgrade',$it.Name); break }
            '^scoop$' { $cmd='scoop'; $arg=@('update',$it.Name); break }
            '^choco$' { $cmd='choco'; $arg=@('upgrade',$it.Name,'-y','--no-progress'); break }
            '^WSL component$' { $cmd='wsl'; $arg=@('--update'); break }
            '^WSL:' { $cmd='wsl'; $arg=@('-d',$it.Distro,'-u','root','--','apt-get','install','--only-upgrade','-y','--',$it.Id); break }
        }
        if (-not $cmd) { Write-Warning 'Unknown manager';continue }
        try {
            & $cmd @arg 2>&1 | Out-Host
            $ec=$LASTEXITCODE
            if ($ec -ne 0) { throw "Exit code $ec" }
            Write-Host 'SUCCESS' -ForegroundColor Green
            $script:Results.Add([pscustomobject]@{Manager=$manager;Name=$it.Name;Status='SUCCESS'})
        } catch {
            Write-Warning "FAILED: $($_.Exception.Message)"
            $script:Results.Add([pscustomobject]@{Manager=$manager;Name=$it.Name;Status='FAILED'})
        }
    }
}
function Run-Manager([string]$manager, [scriptblock]$inventory, [scriptblock]$discover) {
    Write-Section "MANAGER: $manager"
    try { & $inventory } catch { Register-ScanError $manager "Inventory: $($_.Exception.Message)" }
    Write-Host "`nChecking available updates for $manager ..." -ForegroundColor Cyan
    try {
        $items = @(& $discover | Where-Object { $_ -and $_.Name } | Sort-Object Name -Unique)
    } catch { Register-ScanError $manager "Updates: $($_.Exception.Message)"; return }
    Write-Host ("Found {0} update(s)." -f $items.Count) -ForegroundColor Green
    if ($items.Count -eq 0) { Write-Host "No updates offered by $manager; moving to next manager."; return }
    foreach ($it in $items) { Write-Host ("  {0}: {1} -> {2}" -f $it.Name, $it.Current, $it.Latest) }
    $choice=Ask-Choice "Choose how to update $manager" @('ALL - update all','INDIVIDUAL - yes/no per package','NONE - skip') 2
    if ($choice -eq 2) { Write-Host 'Skipped. Moving to next manager.'; return }
    $selected = @()
    if ($choice -eq 0) { $selected = $items }
    else {
        $chosen = [System.Collections.Generic.List[object]]::new()
        foreach($it in $items) {
            $answer=(Read-Host ("Update {0} ({1} -> {2})? [y/N/q=stop]" -f $it.Name,$it.Current,$it.Latest)).Trim()
            if ($answer -match '^(q|quit|stop)$') { break }
            if ($answer -match '^(y|yes|d|da)$') { $chosen.Add($it) }
        }
        $selected=@($chosen.ToArray())
    }
    Apply-Updates $manager $selected ($choice -eq 0)
}

if(-not $NoTranscript) {
    try {
        $logDir=Join-Path $env:LOCALAPPDATA 'WindowsToolsUpdater\logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $script:LogFile=Join-Path $logDir ("updates-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Start-Transcript -Path $script:LogFile -ErrorAction Stop | Out-Null
    } catch { Write-Warning "Transcript disabled: $($_.Exception.Message)" }
}
try {
    Write-Section 'SEQUENTIAL UPDATE CHECK'
    Write-Host 'Each manager: 1) installed packages  2) available updates  3) choose  4) apply  5) next manager'
    Write-Host 'Menu uses numbers (1, 2, 3). Enter defaults to NONE / NO: safe to skip.'
    Write-Host "Administrator: $script:IsAdmin"
    foreach ($managerCheck in @(
        @{Name='npm'; Skip=$SkipNpm},
        @{Name='winget'; Skip=$SkipWinget},
        @{Name='python'; Skip=$SkipPython},
        @{Name='pipx'; Skip=$SkipPipx},
        @{Name='scoop'; Skip=$SkipScoop},
        @{Name='choco'; Skip=$SkipChoco},
        @{Name='wsl'; Skip=$SkipWSL}
    )) {
        if ($managerCheck.Skip) { Write-Host "Skipping $($managerCheck.Name): disabled by script parameter." }
        elseif (-not (Has-Command $managerCheck.Name)) { Write-Host "Skipping $($managerCheck.Name): command not found in PATH." }
    }
    if ($env:VIRTUAL_ENV) { Write-Warning "Active Python virtual environment: $env:VIRTUAL_ENV. Its pip packages are skipped by default; use -IncludeVenv to include them." }

    if (-not $SkipNpm -and (Has-Command npm)) {
        Run-Manager 'npm' {
            Write-Host "Node: $(Get-Text node @('--version')) | npm: $(Get-Text npm @('--version'))"
            Write-Host (Get-Text npm @('list','-g','--depth=0','--unicode=false') @(0))
        } {
            # npm uses exit 1 when updates exist; stderr notices are not JSON.
            $raw=Get-Text npm @('outdated','-g','--depth=0','--json') @(0,1)
            $j=To-JsonObject $raw
            if ($j -and $j.PSObject.Properties['error']) { throw "npm discovery failed: $raw" }
            if($j) { foreach($p in $j.PSObject.Properties) { $v=$p.Value
                if($v.latest -and $v.current -and $v.latest -ne $v.current) { New-ItemRecord 'npm' $p.Name ([string]$v.current) ([string]$v.latest) }
            }}
        }
    }
    if (-not $SkipWinget -and (Has-Command winget)) {
        Run-Manager 'winget' {
            Write-Host "winget: $(Get-Text winget @('--version'))"
            $installed = Get-Text winget @('list','--accept-source-agreements','--disable-interactivity')
            $lines = @($installed -split "`r?`n" | Where-Object { $_ -match '\S' })
            Write-Host "Installed application list collected ($($lines.Count) output lines). Showing only AVAILABLE UPDATES below."
        } {
            $out=Get-Text winget @('upgrade','--accept-source-agreements','--disable-interactivity')
            $items=@(Parse-WingetTable $out)
            foreach ($line in ($out -split "`r?`n")) {
                if ($line -match '(?i)include-unknown|include-pinned|explicit targeting') { Write-Warning $line.Trim() }
            }
            if ($items.Count -eq 0 -and $out -notmatch '(?i)no applicable update|no installed package|no available upgrade|no upgrades available') {
                Write-Warning 'No winget updates were parsed; inspect winget upgrade manually if necessary.'
            }
            $items
        }
    }
    if (-not $SkipPython -and (Has-Command python) -and ($IncludeVenv -or -not $env:VIRTUAL_ENV)) {
        Run-Manager 'pip' {
            Write-Host "Python: $(Get-Text python @('--version'))"
            Write-Host "Executable: $(Get-Text python @('-c','import sys; print(sys.executable)'))"
            Write-Host (Get-Text python @('-m','pip','list','--format=columns','--disable-pip-version-check'))
        } {
            $j=To-JsonObject (Get-Text python @('-m','pip','list','--outdated','--format=json','--disable-pip-version-check') @(0))
            foreach($p in @($j)) { if($p.name -and $p.latest_version) { New-ItemRecord 'pip' ([string]$p.name) ([string]$p.version) ([string]$p.latest_version) } }
        }
    }
    if (-not $SkipPython -and $env:VIRTUAL_ENV -and -not $IncludeVenv) { Write-Host "`nSkipping pip: active virtual environment $env:VIRTUAL_ENV (use -IncludeVenv to opt in)." -ForegroundColor Yellow }
    if (-not $SkipPipx -and (Has-Command pipx)) {
        Run-Manager 'pipx' {
            Write-Host (Get-Text pipx @('list','--short'))
        } {
            $output=Get-Text pipx @('list','--outdated','--short')
            if($script:LastCommandExitCode -ne 0) { throw "pipx list --outdated failed: $output" }
            foreach($line in ($output -split "`r?`n")) {
                if($line -match '^\s*([A-Za-z0-9][A-Za-z0-9_.-]*)\s+([0-9][^\s]*)') { New-ItemRecord 'pipx' $matches[1] $matches[2] 'latest' }
            }
        }
    }
    if (-not $SkipScoop -and (Has-Command scoop)) {
        Run-Manager 'scoop' {
            Write-Host (Get-Text scoop @('list'))
        } {
            $out=Get-Text scoop @('status')
            foreach($line in ($out -split "`r?`n")) {
                if($line -match '^\s*([A-Za-z0-9_.-]+)\s+([0-9][^\s]*)\s+([0-9][^\s]*)\s*$') {
                    New-ItemRecord 'scoop' $matches[1] $matches[2] $matches[3]
                }
            }
        }
    }
    if (-not $SkipChoco -and (Has-Command choco)) {
        Run-Manager 'choco' {
            Write-Host (Get-Text choco @('list','--limit-output'))
        } {
            $out=Get-Text choco @('outdated','--limit-output','--no-progress')
            foreach($line in ($out -split "`r?`n")) {
                if($line -match '^([^|]+)\|([^|]+)\|([^|]+)\|') { New-ItemRecord 'choco' $matches[1] $matches[2] $matches[3] }
            }
        }
    }
    if (-not $SkipWSL -and (Has-Command wsl)) {
        Write-Section 'WSL runtime/kernel (optional)'
        Write-Host (Get-Text wsl @('--version'))
        Write-Host 'WSL runtime online update check is not reliably available without running the update command.'
        $wslChoice=Ask-Choice 'Would you like to run wsl --update? (optional)' @('YES - run wsl --update','NO - skip runtime update') 1
        if($wslChoice -eq 0) { Apply-Updates 'WSL component' @((New-ItemRecord 'WSL component' 'WSL runtime/kernel' 'installed' 'check/apply')) $false }
        Write-Section 'WSL distributions'
        $distros=(Get-Text wsl @('--list','--quiet')) -replace "`0",''
        foreach($d in ($distros -split "`r?`n")) {
            $d=$d.Trim().Trim([char]0)
            if(-not $d -or $d -match '(?i)no installed distributions|windows subsystem for linux') {continue}
            $aptCheck=Get-Text wsl @('-d',$d,'-u','root','--','sh','-lc','command -v apt-get >/dev/null && echo APT_OK')
            if($aptCheck -notmatch 'APT_OK') { Write-Host "WSL distro ${d}: not an APT distro, skipped.";continue }
            $distro=$d
            Run-Manager "WSL:$distro" {
                Write-Host "Distro: $distro | Ubuntu/Debian APT"
                Write-Host (Get-Text wsl @('-d',$distro,'--','sh','-lc','cat /etc/os-release | head -n 4'))
                Write-Host 'Installed APT packages (summary):'
                $count=Get-Text wsl @('-d',$distro,'--','sh','-lc','dpkg-query -W | wc -l')
                Write-Host "Installed package count: $count"
            } {
                Write-Host "Refreshing APT indexes for $distro ..."
                $metadata=Get-Text wsl @('-d',$distro,'-u','root','--','apt-get','update','-qq')
                if($script:LastCommandExitCode -ne 0) { throw "apt-get update failed: $metadata" }
                $out=Get-Text wsl @('-d',$distro,'--','apt','list','--upgradable')
                foreach($line in ($out -split "`r?`n")) {
                    if($line -match '^([^/\s]+)/\S+\s+(\S+)\s+\S+\s+\[upgradable from:\s*([^\]]+)\]') {
                        New-ItemRecord "WSL:$distro" $matches[1] $matches[3] $matches[2] $matches[1] $distro
                    }
                }
            }
        }
    }
    Write-Section 'SUMMARY'
    if ($script:Results.Count -gt 0) { $script:Results | Format-Table -AutoSize | Out-Host }
    else { Write-Host 'No updates applied.' }
    if ($script:ScanErrors.Count -gt 0) { $script:ScanErrors | ForEach-Object { Write-Warning $_ } }
    Write-Host 'Done. Some upgrades may require restarting the terminal, WSL or Windows.'
} finally {
    if($script:LogFile) { Write-Host "Log: $script:LogFile"; try { Stop-Transcript | Out-Null } catch {} }
}

# Full SHA-256 verification of EFU files with the same name and size.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [double]$MinMB = 1,
    [int]$Top = 30,
    [switch]$IncludeProjects,
    [string[]]$Exclude = @(),
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$scriptFile = Join-Path $PSScriptRoot 'Find-EfuDuplicates.py'
if (-not (Test-Path -LiteralPath $scriptFile)) { throw "Missing Find-EfuDuplicates.py next to PS1" }
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) { $exe = $python.Source; $prefix = @() }
else {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if (-not $launcher) { throw 'Python 3 not found in PATH.' }
    $exe = $launcher.Source; $prefix = @('-3')
}
$argsList = @($prefix) + @($scriptFile, $Path, '--min-mb', $MinMB.ToString([Globalization.CultureInfo]::InvariantCulture), '--top', "$Top")
if ($IncludeProjects) { $argsList += '--include-projects' }
foreach ($item in $Exclude) { $argsList += @('--exclude', $item) }
if ($OutputDirectory) { $argsList += @('--output', $OutputDirectory) }
& $exe @argsList
if ($LASTEXITCODE -ne 0) { throw "Duplicate analysis failed (exit $LASTEXITCODE)" }

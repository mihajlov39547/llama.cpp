#requires -Version 5.1
<#
Audit both book-refinement stages from their line-by-line JSONL checkpoints.
Read-only. Does not contact llama.cpp and does not modify checkpoint files.
Usage: .\check-book-refinement.ps1 [-Book Roderick.txt] [-ShowIssues 15]
#>
[CmdletBinding()]
param(
    [string]$RootDirectory = $PSScriptRoot,
    [string]$Book,
    [ValidateRange(0,10000)][int]$ShowIssues = 10,
    [string]$CsvPath
)
$ErrorActionPreference = 'Stop'
$booksRoot = Join-Path ([IO.Path]::GetFullPath($RootDirectory)) 'books'
$englishInput = Join-Path $booksRoot 'prepared-en'
if (-not (Test-Path -LiteralPath $englishInput -PathType Container)) {
    throw "English book folder not found: $englishInput"
}
$sourceBooks = @(Get-ChildItem -LiteralPath $englishInput -Filter '*.txt' -File | Sort-Object Name)
if ($Book) {
    $sourceBooks = @($sourceBooks | Where-Object { $_.Name -ieq $Book })
    if ($sourceBooks.Count -eq 0) { throw "Book not found in prepared-en: $Book" }
}
$stages = @(
    @{ Name='English'; State=(Join-Path $booksRoot 'refinement-runs'); Output=(Join-Path $booksRoot 'refined-en') },
    @{ Name='Serbian'; State=(Join-Path $booksRoot 'translation-refinement-runs'); Output=(Join-Path $booksRoot 'refined-sr-latn') }
)
$results = New-Object System.Collections.Generic.List[object]
$problems = New-Object System.Collections.Generic.List[object]
foreach ($stage in $stages) {
    foreach ($source in $sourceBooks) {
        $bookState = Join-Path $stage.State $source.BaseName
        $fullRuns = @()
        if (Test-Path -LiteralPath $bookState -PathType Container) {
            foreach ($dir in @(Get-ChildItem -LiteralPath $bookState -Directory)) {
                $manifestPath = Join-Path $dir.FullName 'manifest.json'
                if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
                try {
                    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ([int]$manifest.settings.max_lines -ne 0) { continue } # exclude pilot checkpoints
                    $declaredName = if ($manifest.file) { [string]$manifest.file } elseif ($manifest.book) { [string]$manifest.book } else { '' }
                    if ($declaredName -and $declaredName -ine $source.Name) { continue }
                    $checkpointPath = Join-Path $dir.FullName 'progress.jsonl'
                    $lastChanged = if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) {
                        (Get-Item -LiteralPath $checkpointPath).LastWriteTimeUtc
                    } else { (Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc }
                    $fullRuns += [pscustomobject]@{
                        Path = $dir.FullName
                        Progress = $checkpointPath
                        Expected = [int]$manifest.total_lines
                        Changed = $lastChanged
                    }
                } catch {
                    $problems.Add([pscustomobject]@{Stage=$stage.Name;Book=$source.Name;Line='';Status='manifest_error';Reason=$_.Exception.Message})
                }
            }
        }
        # If multiple full runs exist, use only the most recently updated one. Report the count separately.
        $chosen = @($fullRuns | Sort-Object Changed -Descending | Select-Object -First 1)
        $accepted=0; $unchanged=0; $review=0; $errors=0; $unknown=0; $badJson=0; $duplicates=0
        $expected=0; $completed=0; $missing=0; $checkpoint=''; $runCount=$fullRuns.Count
        if ($chosen.Count -gt 0) {
            $run=$chosen[0]; $expected=$run.Expected; $checkpoint=$run.Path
            $rows=@{}
            if (Test-Path -LiteralPath $run.Progress -PathType Leaf) {
                $fileLine=0
                foreach ($jsonLine in [IO.File]::ReadLines($run.Progress)) {
                    $fileLine++
                    if ([string]::IsNullOrWhiteSpace($jsonLine)) { continue }
                    try {
                        $r = $jsonLine | ConvertFrom-Json
                        $n = [int]$r.line
                        if ($n -lt 1 -or $n -gt $expected) { throw "Line number out of range: $n" }
                        if ($rows.ContainsKey($n)) { $duplicates++ }
                        $rows[$n]=$r # same behavior as Python resume: last entry wins
                    } catch {
                        $badJson++
                        $problems.Add([pscustomobject]@{Stage=$stage.Name;Book=$source.Name;Line="JSONL:$fileLine";Status='invalid_record';Reason=$_.Exception.Message})
                    }
                }
            }
            $completed=$rows.Count
            $missing=[math]::Max(0,$expected-$completed)
            foreach ($n in $rows.Keys) {
                $r=$rows[$n]
                switch ([string]$r.status) {
                    'accepted'  { $accepted++ }
                    'unchanged' { $unchanged++ }
                    'review'    { $review++; $problems.Add([pscustomobject]@{Stage=$stage.Name;Book=$source.Name;Line=$n;Status='review';Reason=[string]$r.why}) }
                    'error'     { $errors++; $problems.Add([pscustomobject]@{Stage=$stage.Name;Book=$source.Name;Line=$n;Status='error';Reason=[string]$r.why}) }
                    default     { $unknown++; $problems.Add([pscustomobject]@{Stage=$stage.Name;Book=$source.Name;Line=$n;Status='unknown';Reason=[string]$r.status}) }
                }
            }
        }
        $outputPath=Join-Path $stage.Output $source.Name
        $hasOutput=Test-Path -LiteralPath $outputPath -PathType Leaf
        $state=if ($chosen.Count -eq 0) {'NOT_STARTED'} elseif ($missing -gt 0) {'IN_PROGRESS'} elseif ($badJson -gt 0 -or $unknown -gt 0) {'CHECK_DATA'} elseif (-not $hasOutput) {'NO_OUTPUT'} elseif ($errors -gt 0) {'ERRORS'} elseif ($review -gt 0) {'REVIEW'} else {'OK'}
        $results.Add([pscustomobject]@{
            Stage=$stage.Name;Book=$source.Name;State=$state;Completed=$completed;Expected=$expected
            Accepted=$accepted;Unchanged=$unchanged;Review=$review;Errors=$errors;Missing=$missing
            InvalidRecords=$badJson;DuplicateRecords=$duplicates;OtherStatuses=$unknown
            OutputExists=$hasOutput;FullRuns=$runCount;Checkpoint=$checkpoint
        })
    }
}
Write-Host "`nBOOK REFINEMENT CHECK | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host 'Only full runs (max_lines=0) are counted. Pilot previews are excluded.'
foreach ($stageName in @('English','Serbian')) {
    $group=@($results | Where-Object Stage -eq $stageName)
    if ($group.Count -eq 0) {continue}
    $sumProcessed=($group | Measure-Object -Property Completed -Sum).Sum
    $sumErrors=($group | Measure-Object -Property Errors -Sum).Sum
    $sumReview=($group | Measure-Object -Property Review -Sum).Sum
    $sumMissing=($group | Measure-Object -Property Missing -Sum).Sum
    Write-Host "`n=== $stageName ===" -ForegroundColor Yellow
    Write-Host "Books: $($group.Count) | Processed: $sumProcessed | Errors: $sumErrors | Review: $sumReview | Remaining in started runs: $sumMissing"
    $group | Select-Object Book,State,Completed,Expected,Errors,Review,Missing,OutputExists | Format-Table -AutoSize | Out-Host
}
$issueCount = @($problems).Count
if ($issueCount -gt 0 -and $ShowIssues -gt 0) {
    Write-Host "`nSample of $([math]::Min($ShowIssues,$issueCount)) / $issueCount flagged records:" -ForegroundColor Yellow
    $problems | Sort-Object Stage,Book,Line | Select-Object -First $ShowIssues Stage,Book,Line,Status,Reason | Format-Table -Wrap -AutoSize | Out-Host
}
if ($CsvPath) {
    $dest=[IO.Path]::GetFullPath($CsvPath)
    $parent=Split-Path -Parent $dest
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    $results | Export-Csv -LiteralPath $dest -NoTypeInformation -Encoding UTF8
    Write-Host "`nSummary saved: $dest"
}
Write-Host "`nInterpretation: error=failed call; review=rejected/uncertain proposal; missing=incomplete checkpoint."
Write-Host 'An OK result means technical checks passed, not that every sentence is linguistically correct.'

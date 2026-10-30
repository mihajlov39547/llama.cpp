#requires -Version 5.1
<#
Run two independent, resumable book refinement passes.
Stage 1: prepared-en -> refined-en (English repair_books.py)
Stage 2: refined-en + translated -> refined-sr-latn (Serbian reference-based revision)

Prerequisites: Python 3.12+, llama.cpp API server already running at 127.0.0.1:8080
with --alias gemma-4-local and the single-turn Jinja template.
Copy this file, repair_books.py and refine_serbian.py to C:\llama.cpp.
#>
[CmdletBinding()]
param(
    [ValidateSet('English','Serbian','All')][string]$Stage = 'All',
    [string]$Book,
    [ValidateRange(0,2147483647)][int]$MaxLines = 0,
    [string]$SerbianDraftDirectory,
    [string]$RootDirectory = $PSScriptRoot,
    [string]$Python = 'python',
    [string]$ApiUrl = 'http://127.0.0.1:8080',
    [string]$ModelAlias = 'gemma-4-local'
)
$ErrorActionPreference = 'Stop'
$root=[IO.Path]::GetFullPath($RootDirectory)
$books=Join-Path $root 'books'
$enInput=Join-Path $books 'prepared-en'
$enOut=Join-Path $books 'refined-en'
$enState=Join-Path $books 'refinement-runs'
$srDraft=if ($SerbianDraftDirectory) { [IO.Path]::GetFullPath($SerbianDraftDirectory) } else { Join-Path $books 'translated' }
$srOut=Join-Path $books 'refined-sr-latn'
$srState=Join-Path $books 'translation-refinement-runs'

if (-not (Test-Path -LiteralPath $enInput -PathType Container)) { throw "Missing English source folder: $enInput" }
if ($Stage -in @('Serbian','All') -and -not (Test-Path -LiteralPath $srDraft -PathType Container)) {
    throw "Missing Serbian drafts folder: $srDraft. Supply -SerbianDraftDirectory if yours is named differently."
}
foreach ($folder in @($enOut,$enState,$srOut,$srState)) {
    [void][IO.Directory]::CreateDirectory($folder)
}
if (([IO.Path]::GetFullPath($srDraft)).TrimEnd('\') -eq ([IO.Path]::GetFullPath($srOut)).TrimEnd('\')) {
    throw 'Serbian draft and output directories must be different.'
}
try {
    $health=Invoke-RestMethod -Uri ($ApiUrl.TrimEnd('/')+'/health') -TimeoutSec 8
    $models=Invoke-RestMethod -Uri ($ApiUrl.TrimEnd('/')+'/v1/models') -TimeoutSec 8
} catch {
    throw "llama.cpp server is not responding at $ApiUrl. Start the server first. $($_.Exception.Message)"
}
$ids=@($models.data | ForEach-Object { $_.id })
if ($ids -cnotcontains $ModelAlias) {
    throw "Expected model alias '$ModelAlias', server reports: $($ids -join ', '). Start the correct server/model or use -ModelAlias."
}
$enScript=Join-Path $root 'repair_books.py'
$srScript=Join-Path $root 'refine_serbian.py'
if ($Stage -in @('English','All') -and -not (Test-Path -LiteralPath $enScript -PathType Leaf)) { throw "Missing $enScript" }
if ($Stage -in @('Serbian','All') -and -not (Test-Path -LiteralPath $srScript -PathType Leaf)) { throw "Missing $srScript" }
Write-Host "`nBOOK REFINEMENT | Stage: $Stage" -ForegroundColor Cyan
Write-Host "Original English:    $enInput"
Write-Host "Refined English:     $enOut"
Write-Host "Existing Serbian:    $srDraft"
Write-Host "Refined Serbian:     $srOut"
Write-Host "English checkpoints: $enState"
Write-Host "Serbian checkpoints: $srState"
if ($MaxLines -gt 0) { Write-Warning "PILOT MODE: only first $MaxLines lines; output is in checkpoint preview, not final folders." }

if ($Stage -in @('English','All')) {
    $enArgs=@($enScript,'--input-dir',$enInput,'--output-dir',$enOut,'--state-dir',$enState,
        '--url',$ApiUrl,'--model',$ModelAlias,'--template-tag','single')
    if ($Book) { $enArgs+=@('--book',$Book) }
    if ($MaxLines -gt 0) { $enArgs+=@('--max-lines',"$MaxLines") }
    Write-Host "`n=== STAGE 1: ENGLISH REFINEMENT ===" -ForegroundColor Yellow
    & $Python @enArgs
    if ($LASTEXITCODE -ne 0) { throw "English refinement failed with exit code $LASTEXITCODE" }
}
if ($Stage -in @('Serbian','All')) {
    $required=if ($Book) { @(Get-Item -LiteralPath (Join-Path $enInput $Book)) } else { @(Get-ChildItem -LiteralPath $enInput -Filter '*.txt' -File) }
    if ($MaxLines -eq 0) {
        foreach ($f in $required) {
            if (-not (Test-Path -LiteralPath (Join-Path $enOut $f.Name) -PathType Leaf)) {
                throw "English stage is not complete for $($f.Name). First run -Stage English."
            }
        }
    } elseif ($Stage -eq 'All') {
        throw 'For pilot stage 2, run -Stage Serbian with an already completed refined-en input; pilot English output is only in preview.'
    }
    $srArgs=@($srScript,'--english-dir',$enOut,'--draft-dir',$srDraft,'--output-dir',$srOut,
        '--state-dir',$srState,'--url',$ApiUrl,'--model',$ModelAlias,'--template-tag','single')
    if ($Book) { $srArgs+=@('--book',$Book) }
    if ($MaxLines -gt 0) { $srArgs+=@('--max-lines',"$MaxLines") }
    Write-Host "`n=== STAGE 2: SERBIAN REFINEMENT ===" -ForegroundColor Yellow
    & $Python @srArgs
    if ($LASTEXITCODE -ne 0) { throw "Serbian refinement failed with exit code $LASTEXITCODE" }
}
Write-Host "`nPipeline command finished." -ForegroundColor Green
Write-Host 'IMPORTANT: Review all review.csv entries before treating outputs as training-ready.'

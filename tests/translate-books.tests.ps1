# Dependency-free tests; all network boundaries are mocked.
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'translate-books.ps1') -FunctionsOnly
$ModelId='translategemma-4b-it-Q4_K_M.gguf'
$passed=0
function Check([bool]$Ok,[string]$Name) {
    if (-not $Ok) { throw "FAIL: $Name" }
    $script:passed++; Write-Host "PASS: $Name"
}
function Throws([scriptblock]$Action,[string]$Pattern,[string]$Name) {
    $message=''
    try { & $Action } catch { $message=$_.Exception.Message }
    Check ($message -match $Pattern) $Name
}
function U([int[]]$Codes) { return (($Codes | ForEach-Object { [string][char]$_ }) -join '') }
function Response([string]$Text,[string]$Finish='stop') {
    return [pscustomobject]@{model=$ModelId;choices=@([pscustomobject]@{
        message=[pscustomobject]@{content=$Text};finish_reason=$Finish
    });usage=[pscustomobject]@{prompt_tokens=20;completion_tokens=10}
    timings=[pscustomobject]@{prompt_n=20;predicted_n=10;prompt_ms=100;predicted_ms=200;
        prompt_per_second=200;predicted_per_second=50}}
}
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'translate-books.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'PowerShell syntax'
$discoveredIds=@('other-model-Q8_0.gguf')
function Invoke-TBJson($Uri,$Body,$Timeout) {
    if ($Uri.EndsWith('/health')) { return [pscustomobject]@{status='ok'} }
    if ($Uri.EndsWith('/v1/models')) {
        return [pscustomobject]@{data=@($discoveredIds | ForEach-Object { [pscustomobject]@{id=$_} })}
    }
    return [pscustomobject]@{chat_template='chatml';default_generation_settings=[pscustomobject]@{n_ctx=8192}}
}
$discovered=Get-TBServer 'http://127.0.0.1:8080' '' 0
Check ($discovered.ModelId -ceq $discoveredIds[0] -and $discovered.ChatTemplate -eq 'chatml' -and $discovered.ContextRetrieved -eq 8192) 'Auto discovery accepts another model template and context'
Throws { Get-TBServer 'http://127.0.0.1:8080' 'missing' 0 } 'Cannot select' 'Explicit model mismatch rejected'
Throws { Get-TBServer 'http://127.0.0.1:8080' '' 4096 } 'Server context' 'Explicit context mismatch rejected'
$discoveredIds=@('model-a','model-b')
Throws { Get-TBServer 'http://127.0.0.1:8080' '' 0 } 'Cannot select' 'Multiple models require explicit selection'
Check ((Get-TBServer 'http://127.0.0.1:8080' 'model-b' 0).ModelId -ceq 'model-b') 'Explicit multi-model selection'
$discoveredIds=@()
Throws { Get-TBServer 'http://127.0.0.1:8080' '' 0 } 'Cannot select' 'Empty model list rejected'
$lower=U @(0x459,0x45A,0x45F,0x452,0x45B,0x447,0x448,0x436)
$expected='ljnjd'+(U @(0x17E,0x111,0x107,0x10D,0x161,0x17E))
Check ((Convert-TBSerbianLatin $lower) -ceq $expected) 'All special Serbian mappings'
$alphabet=U @(0x430,0x431,0x432,0x433,0x434,0x452,0x435,0x436,0x437,0x438,0x458,0x43A,0x43B,0x459,0x43C,0x43D,0x45A,0x43E,0x43F,0x440,0x441,0x442,0x45B,0x443,0x444,0x445,0x446,0x447,0x45F,0x448)
$alphabetLatin='abvgd'+[char]0x111+'e'+[char]0x17E+'zijklljmnnjoprst'+[char]0x107+'ufhc'+[char]0x10D+'d'+[char]0x17E+[char]0x161
Check ((Convert-TBSerbianLatin $alphabet) -ceq $alphabetLatin) 'Full lowercase alphabet'
Check ((Convert-TBSerbianLatin $alphabet.ToUpperInvariant()) -ceq $alphabetLatin.ToUpperInvariant()) 'Full uppercase alphabet and uppercase digraphs'
$title=(U @(0x409,0x443,0x431,0x430))+' '+(U @(0x40A,0x435,0x433,0x43E,0x448))+' '+(U @(0x40F,0x435,0x43C))
Check ((Convert-TBSerbianLatin $title) -ceq ('Ljuba Njego'+[char]0x161+' D'+[char]0x17E+'em')) 'Title-case digraphs'
Check ((Convert-TBSerbianLatin (U @(0x409,0x423,0x411,0x410))) -ceq 'LJUBA') 'All-capital word'
Check ((Convert-TBSerbianLatin ([string][char]0x40A)) -ceq 'NJ') 'Standalone uppercase digraph'
$latin='Latin C:\books\file.txt https://example.org/a?b=1 $x; '+(U @(0x10D,0x107,0x17E,0x161,0x111))
Check ((Convert-TBSerbianLatin $latin) -ceq $latin) 'Latin text paths URLs and diacritics unchanged'
$mixed='Hello, '+$title+'! (42) '+$latin
Check ((Convert-TBSerbianLatin $mixed) -ceq ('Hello, '+(Convert-TBSerbianLatin $title)+'! (42) '+$latin)) 'Mixed scripts and punctuation'
$v=Test-TBTranslation 'English source.' (Response ($title+"`r`n")) $ModelId
Check ($v.Valid -and $v.WasTransliterated -and $v.OriginalScript -eq 'Cyrillic' -and $v.TransliterationTimeMs -ge 0) 'Valid Cyrillic accepted after timed postprocessing'
Check ($v.RawText -ceq ($title+"`r`n") -and -not $v.AcceptedWithoutModification) 'Raw model response preserved exactly'
$v=Test-TBTranslation 'English source.' (Response $latin) $ModelId
Check ($v.Valid -and $v.AcceptedWithoutModification -and -not $v.WasTransliterated -and $v.TransliterationTimeMs -eq 0) 'Latin accepted without modification'
Check ((Test-TBTranslation 'English.' (Response $mixed) $ModelId).OriginalScript -eq 'Mixed') 'Mixed script classification'
Check (-not (Test-TBTranslation 'English.' (Response ([string][char]0x44B)) $ModelId).Valid) 'Unsupported Cyrillic remains invalid'
Check (-not (Test-TBTranslation 'English.' (Response $title 'length') $ModelId).Valid) 'Cyrillic truncated output remains invalid'
Check (-not (Test-TBTranslation 'English.' (Response '') $ModelId).Valid) 'Empty output invalid'
Check (-not (Test-TBTranslation 'English.' (Response ("$title`n$title")) $ModelId).Valid) 'Interior newline invalid'
Check (-not (Test-TBTranslation 'English.' (Response ('Prevod: '+$title)) $ModelId).Valid) 'Instruction leakage invalid'
Check ((Get-TBPrompt '  C:\path $1 {SOURCE_TEXT}  ').EndsWith('  C:\path $1 {SOURCE_TEXT}  ')) 'Exact source insertion'
Check ((Get-TBStats @(1,2,3,4)).Median -eq 2.5 -and $null -eq (Get-TBRate $null 100)) 'Median and missing telemetry'
$testRoot=Join-Path $project ('books\translation-benchmarks\transliteration-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$SourceDirectory=Join-Path $testRoot 'source';$DestinationDirectory=Join-Path $testRoot 'output'
$BenchmarkDirectory=Join-Path $testRoot 'runs'
[void][IO.Directory]::CreateDirectory($SourceDirectory)
$Book='fixture.txt';$MaxSegments=1;$NewRun=$true;$Resume=$false
$fixturePath=Join-Path $SourceDirectory $Book
Write-TBAtomic $fixturePath "Source one.`r`n`r`nSource two.`n `t`nSource three.`r`n"
$source=Read-TBSource $fixturePath
Check ($source.SegmentCount -eq 3 -and $source.Lines.Count -eq 5) 'Blank lines and line endings retained'
$script:requests=[Collections.Generic.List[object]]::new()
$mockTemplate='gemma'; $mockContext=4096
function Get-TBServer {
    return [pscustomobject]@{ModelId=$ModelId;ModelMeta=$null;ModelIdentitySource='mock';
        ContextRetrieved=$mockContext;Quantization='Q4_K_M';BuildVersion='mock';ChatTemplate=$mockTemplate;Props=$null}
}
function Invoke-TBJson($Uri,$Body,$Timeout) {
    $script:requests.Add($Body)
    return Response $title
}
Start-TBMain
$cpPath=(Get-ChildItem $BenchmarkDirectory -Filter '*.checkpoint.json' -Recurse).FullName
$run=Split-Path $cpPath;$state=Read-TBJson $cpPath
$firstPath=Get-TBSegmentPath $run 1;$first=Read-TBJson $firstPath
$savedModel=$ModelId;$ModelId='different-model';$Resume=$true;$NewRun=$false
Throws { Start-TBMain } 'Resume refused' 'Resume refuses silently switching models'
$ModelId=$savedModel;$Resume=$false;$NewRun=$true
Check ($requests.Count -eq 1 -and $first.Status -eq 'completed' -and $first.Attempts.Count -eq 1) 'Cyrillic success uses one inference request'
Check ($first.Attempts[0].RawTranslatedText -ceq $title -and $first.Attempts[0].TranslatedText -ceq (Convert-TBSerbianLatin $title)) 'Stored raw and final text separate'
Check ($first.Attempts[0].TokenGenerationMs -eq 200 -and $first.Attempts[0].TransliterationTimeMs -ge 0) 'Inference timing separate from transliteration'
Check (-not (Test-Path $state.Metadata.OutputPath)) 'Partial final book not published'
Check ($requests[0].temperature -eq 0 -and $requests[0].seed -eq 0 -and $requests[0].stream -eq $false -and $requests[0].max_tokens -eq 512 -and $requests[0].messages[0].content -ceq (Get-TBPrompt 'Source one.')) 'Inference settings and prompt unchanged'
# Legacy failure fixture: three immutable failed attempts with only a script violation.
$line=$source.Lines[2];$attempts=@()
for ($i=1;$i -le 3;$i++) {
    $a=New-TBAttempt $line $i $state.Metadata.ExperimentId
    $a.TranslationStatus='invalid';$a.ScriptValidationResult='cyrillic_violation'
    $a.ErrorMessage='Cyrillic script violation';$a.RawTranslatedText=$title
    $a.TranslatedText=$title;$a.FinishReason='stop';$a.EndToEndLatencyMs=400;$a.TokenGenerationMs=200
    foreach ($field in @('OriginalScript','WasTransliterated','TransliterationTimeMs','AcceptedWithoutModification','PostprocessingVersion')) { $a.PSObject.Properties.Remove($field) }
    $attempts+=@($a)
}
$legacy=[pscustomobject]@{ExperimentId=$state.Metadata.ExperimentId;SegmentId=2;SourceLineNumber=3;
    SourceText=$line.Text;Translation=$null;Status='failed';Attempts=$attempts}
$secondPath=Get-TBSegmentPath $run 2
Write-TBAtomic $secondPath (Get-TBJson $legacy)
$originalHash=Get-TBFileHash $secondPath;$firstHash=Get-TBFileHash $firstPath
$records=@{1=$first;2=$legacy};$state.Status='failed'
Write-TBAtomic $cpPath (Get-TBJson $state)
Write-TBReports $state $source $records $run 'fixture.sr-latn'
# Refuse unsafe candidates even when their stored failure text claims script-only.
foreach ($kind in @('empty','length','error','other-error','leak','unsupported')) {
    $bad=Read-TBJson $secondPath;$a=$bad.Attempts[0]
    switch ($kind) {
        empty { $a.RawTranslatedText='' }
        length { $a.Truncated=$true }
        error { $a.TranslationStatus='error' }
        other-error { $a.ErrorMessage='Cyrillic script violation; Truncated response' }
        leak { $a.RawTranslatedText='Prevod: '+$title }
        unsupported { $a.RawTranslatedText=[string][char]0x44B }
    }
    Check ($null -eq (Get-TBRepairValidation $bad $a $ModelId)) "Repair refuses $kind"
}
$beforeRequests=$requests.Count
$originalSourceBytes=[IO.File]::ReadAllBytes($fixturePath)
Write-TBAtomic $fixturePath 'Changed source'
Throws { Repair-TBExperiment $run } 'Repair refused' 'Changed source refuses offline repair'
[IO.File]::WriteAllBytes($fixturePath,$originalSourceBytes)
$originalPrompt=$script:TBPromptTemplate
$script:TBPromptTemplate+=' changed'
Throws { Repair-TBExperiment $run } 'Repair refused' 'Changed prompt refuses offline repair'
$script:TBPromptTemplate=$originalPrompt
Repair-TBExperiment $run
Check ($requests.Count -eq $beforeRequests) 'Repair sends no HTTP requests'
Check ((Get-TBFileHash $secondPath) -ceq $originalHash -and (Get-TBFileHash $firstPath) -ceq $firstHash) 'Repair leaves original attempt files byte-identical'
$audit=Read-TBJson (Get-TBRepairPath $run 2)
Check ($audit.OriginalAttempt.ErrorMessage -ceq 'Cyrillic script violation' -and $audit.RawTranslatedText -ceq $title -and $audit.TranslatedText -ceq (Convert-TBSerbianLatin $title) -and -not $audit.HttpRequest) 'Audit retains original failure raw response and accepted result'
$summary=Read-TBJson (Join-Path $run 'fixture.sr-latn.summary.json')
Check ($summary.SuccessfulSegments -eq 1 -and $summary.FailedSegments -eq 1 -and $summary.EffectiveCompletedSegments -eq 2 -and $summary.RepairedSegments -eq 1) 'Historical statistics distinct from effective completion'
Check ($summary.CyrillicGenerationCount -eq 4 -and $summary.TransliteratedSegments -eq 2 -and $summary.HttpAttempts -eq 4) 'Generation and transliteration counts do not add inference attempts'
Check (Test-Path (Join-Path $run 'repairs\before-repair\fixture.sr-latn.summary.json')) 'Original summary snapshot retained'
$auditHash=Get-TBFileHash (Get-TBRepairPath $run 2)
Repair-TBExperiment $run
Check ((Get-TBFileHash (Get-TBRepairPath $run 2)) -ceq $auditHash -and $requests.Count -eq $beforeRequests) 'Repeated repair is idempotent'
# Simulate interruption after audit publication but before checkpoint progress update.
$state.ConfirmedSegments=1;Write-TBAtomic $cpPath (Get-TBJson $state)
$Resume=$true;$NewRun=$false;$MaxSegments=0
Start-TBMain
$after=Read-TBJson $cpPath
Check ($requests.Count -eq 2 -and $after.Status -eq 'completed' -and $after.ConfirmedSegments -eq 3) 'Resume recovers audit and only translates pending segment'
Check ((Get-TBFileHash $secondPath) -ceq $originalHash) 'Resume does not overwrite repaired historical record'
$output=Read-TBSource $after.Metadata.OutputPath
Check ($output.SegmentCount -eq 3 -and $output.Lines.Count -eq 5 -and $output.Lines[3].Text -ceq " `t") 'Final assembly has no duplicate or missing lines'
$bytes=[IO.File]::ReadAllBytes($after.Metadata.OutputPath)
Check (-not ($bytes[0] -eq 239 -and $bytes[1] -eq 187) -and $output.Lines[0].Text.Contains([string][char]0x17E)) 'UTF-8 without BOM preserves diacritics'
$csv=@(Import-Csv (Join-Path $run 'fixture.sr-latn.segments.csv') -Encoding UTF8)
Check ($csv.Count -eq 5 -and @($csv | Where-Object TranslationStatus -eq 'invalid').Count -eq 3 -and $csv[0].WasTransliterated -eq 'True') 'CSV retains failed rows and new postprocessing fields'
Throws { Start-TBMain } 'refusing overwrite' 'Completed output protected'
$finalHash=Get-TBFileHash $after.Metadata.OutputPath
& (Join-Path $project 'translate-books.ps1') -ExperimentDirectory $run -RepairOnly
Check ((Get-TBFileHash $after.Metadata.OutputPath) -ceq $finalHash) 'Public RepairOnly option is offline idempotent and preserves final output'
# Tampering fails closed before reuse.
$tampered=Read-TBJson (Get-TBRepairPath $run 2);$tampered.TranslatedText='Changed'
Write-TBAtomic (Get-TBRepairPath $run 2) (Get-TBJson $tampered)
Throws { Read-TBRepairOverlay (Read-TBJson $secondPath) $run $ModelId } 'Invalid repaired' 'Altered audit rejected'
Write-TBAtomic (Get-TBRepairPath $run 2) (Get-TBJson $audit)
$Book='another-model.txt';$ModelId='another-model-Q8_0.gguf'
$mockTemplate='chatml';$mockContext=8192;$ContextSize=0;$Resume=$false;$NewRun=$true;$MaxSegments=1
Write-TBAtomic (Join-Path $SourceDirectory $Book) 'A new source line.'
Start-TBMain
$otherCp=Read-TBJson (Get-ChildItem $BenchmarkDirectory -Filter 'another-model.sr-latn.checkpoint.json' -Recurse).FullName
Check ($otherCp.Status -eq 'completed' -and $otherCp.Metadata.Model.ModelId -eq $ModelId -and $otherCp.Metadata.Configuration.ContextSize -eq 8192) 'Other model completes translation with detected context'
Check ($requests[$requests.Count-1].model -eq $ModelId -and $otherCp.Metadata.Configuration.ChatTemplate -like 'server-configured*') 'Request and metadata use selected model and server template'
$result=[ordered]@{Passed=$passed;PowerShell=$PSVersionTable.PSVersion.ToString();Artifacts=$testRoot}
Write-TBAtomic (Join-Path $testRoot 'test-results.json') (Get-TBJson $result)
Write-Host "ALL $passed TESTS PASSED. Artifacts: $testRoot"

#requires -Version 5.1
<#
.SYNOPSIS
Sequential en -> sr-Latn literary translation and reproducible measurement.
.DESCRIPTION
One non-empty source line per completion. Does not start a server.
Interactive by default. -Book selects exactly one filename non-interactively.
-MaxSegments pauses after N unfinished segments (0 = unlimited).
-Resume resumes the newest experiment for that book; -NewRun explicitly starts
a separate experiment. Neither option overwrites a completed destination.
Checkpoints/attempts are authoritative; CSV/JSONL/reports are derived snapshots.
Run artifacts: BenchmarkDirectory\<book>.sr-latn.<UTC>-<GUID>\...
UTF-8 (strict, BOM optional) and BOM-marked UTF-16 are accepted. Output is UTF-8
without BOM. Original line endings/blank lines are preserved. Terminal newline
characters returned by the model are removed for line alignment, and raw output
is retained in attempt records. Interior newlines fail validation.

Examples:
  .\translate-books.ps1
  .\translate-books.ps1 -Book Adventures.txt -Resume
  .\translate-books.ps1 -Book Adventures.txt -NewRun -MaxTokens 768

Benchmark definitions:
  Word = Unicode letter/number word, including internal apostrophes/hyphens.
  Character counts = .NET UTF-16 code units; segmentation is source lines.
  Successful throughput uses successful first attempts (no retries).
  Active wall time excludes time between invocations; calendar span includes it.
  HTTP latency includes Invoke-RestMethod transport/deserialization, not checkpoint
  I/O. Server token rates are never inferred from HTTP latency.
  Percentiles use nearest-rank; median averages the middle pair for even samples.
  Missing telemetry remains null/empty.
  Cache reuse is disabled, seed is fixed, and no warm-up inference is performed.

No automatic language-quality scores are calculated. Latin-script validation
does NOT establish Serbian fluency, faithfulness or literary translation quality.
#>
[CmdletBinding()]
param(
    [string] $SourceDirectory,
    [string] $DestinationDirectory,
    [string] $BenchmarkDirectory,
    [string] $ApiBase = 'http://127.0.0.1:8080',
    [string] $ModelId = 'translategemma-4b-it-Q4_K_M.gguf',
    [ValidateRange(1, 32768)][int] $MaxTokens = 512,
    [ValidateRange(1, 3600)][int] $TimeoutSeconds = 180,
    [ValidateRange(128, 131072)][int] $ContextSize = 4096,
    [string] $Book,
    [switch] $Resume,
    [switch] $NewRun,
    [ValidateRange(0, 2147483647)][int] $MaxSegments = 0,
    [switch] $FunctionsOnly
)
$ErrorActionPreference = 'Stop'
if (-not $SourceDirectory) { $SourceDirectory = Join-Path $PSScriptRoot 'books\prepared-en' }
if (-not $DestinationDirectory) { $DestinationDirectory = Join-Path $PSScriptRoot 'books\gemma-translated-sr-latn' }
if (-not $BenchmarkDirectory) { $BenchmarkDirectory = Join-Path $PSScriptRoot 'books\translation-benchmarks' }
$script:TBEncoding = New-Object System.Text.UTF8Encoding($false, $true)
$script:TBDiacritics = ((@(0x010D,0x0107,0x017E,0x0161) | ForEach-Object { [string][char]$_ }) -join ', ') + ', and ' + [char]0x0111
$script:TBPromptTemplate = @"
You are a professional English-to-Serbian literary translator.

Translate the following English text into natural, fluent Serbian using exclusively the Serbian Latin alphabet.

Preserve the original meaning, literary style, tone, tense, character names, and punctuation as accurately as possible.

Use correct Serbian grammar and spelling, including $script:TBDiacritics.

Do not use Serbian Cyrillic.

Return ONLY the Serbian latin translation, without explanations, introductions, quotation wrappers, markdown, or additional text.

English text:

{SOURCE_TEXT}
"@
# Canonical prompt line endings are independent of the script file's encoding.
$script:TBPromptTemplate = $script:TBPromptTemplate.Replace("`r`n", "`n")

function Get-TBValue($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}
function Get-TBHash([byte[]] $Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-TBFileHash([string] $Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-TBJson($Value) { return ConvertTo-Json -InputObject $Value -Depth 40 -Compress }
function Write-TBAtomic([string] $Path, [string] $Text) {
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $bytes = $script:TBEncoding.GetBytes($Text)
        $stream = [IO.FileStream]::new($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
function Read-TBJson([string] $Path) {
    return ([IO.File]::ReadAllText($Path, $script:TBEncoding) | ConvertFrom-Json)
}
function Read-TBSource([string] $Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $encodingName = 'UTF-8 (strict, no BOM)'
    $offset = 0; $decoder = $script:TBEncoding
    if ($bytes.Length -ge 4 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) -or
        ($bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 254 -and $bytes[3] -eq 255))) {
        throw 'UTF-32 is not supported; convert the input explicitly to UTF-8 before benchmarking.'
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $offset = 3; $encodingName = 'UTF-8 with BOM'
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        $offset = 2; $encodingName = 'UTF-16 LE with BOM'; $decoder = [Text.UnicodeEncoding]::new($false, $true, $true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
        $offset = 2; $encodingName = 'UTF-16 BE with BOM'; $decoder = [Text.UnicodeEncoding]::new($true, $true, $true)
    }
    try { $text = $decoder.GetString($bytes, $offset, $bytes.Length - $offset) }
    catch { throw "Input encoding is invalid/ambiguous. Convert explicitly to UTF-8: $Path. $($_.Exception.Message)" }
    if ($text.Contains([string][char]0)) { throw 'NUL in source; possible BOM-less UTF-16 or non-text input. Refusing to guess encoding.' }
    $lines = [Collections.Generic.List[object]]::new()
    $segmentId = 0; $lineNumber = 0
    foreach ($match in [regex]::Matches($text, '([^\r\n]*)(\r\n|\n|\r|$)')) {
        if ($match.Length -eq 0) { continue }
        $lineNumber++
        $lineText = $match.Groups[1].Value
        $id = $null
        if (-not [string]::IsNullOrWhiteSpace($lineText)) { $segmentId++; $id = $segmentId }
        $lines.Add([pscustomobject]@{ LineNumber = $lineNumber; SegmentId = $id; Text = $lineText; Ending = $match.Groups[2].Value })
    }
    return [pscustomobject]@{ Hash = (Get-TBHash $bytes); Encoding = $encodingName; Lines = $lines.ToArray(); SegmentCount = $segmentId }
}
function Get-TBWords([string] $Text) {
    return [regex]::Matches($Text, "\p{L}[\p{L}\p{M}\p{Nd}'\u2019-]*|\p{Nd}+").Count
}
function Get-TBPrompt([string] $SourceText) {
    # Replace is literal, not a regex/replacement-language expansion.
    return $script:TBPromptTemplate.Replace('{SOURCE_TEXT}', $SourceText)
}
function Invoke-TBJson([string] $Uri, $Body = $null, [int] $Timeout = 15) {
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec $Timeout -MaximumRedirection 0 }
    $bytes = $script:TBEncoding.GetBytes((Get-TBJson $Body))
    return Invoke-RestMethod -Uri $Uri -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $Timeout -MaximumRedirection 0
}
function Get-TBServer([string] $Base, [string] $ExpectedModel, [int] $ExpectedContext) {
    try {
        $health = Invoke-TBJson "$Base/health"
        if ($health.status -ne 'ok') { throw "Health status: $($health.status)" }
    } catch { throw "Local llama.cpp server unavailable at $Base. No server was started. $($_.Exception.Message)" }
    $identity = $ExpectedModel; $identitySource = 'configured (models endpoint unavailable)'
    $modelMeta = $null
    try { $modelsResponse = Invoke-TBJson "$Base/v1/models" }
    catch { $modelsResponse = $null; Write-Warning "Cannot discover model; recording explicitly configured identity: $ExpectedModel" }
    if ($null -ne $modelsResponse) {
        $available = @(Get-TBValue $modelsResponse 'data')
        $selected = @($available | Where-Object { $_.id -ceq $ExpectedModel })
        if ($selected.Count -ne 1) { throw "Expected model '$ExpectedModel' not found in /v1/models. Available: $($available.id -join ', ')" }
        $identity = $selected[0].id; $identitySource = '/v1/models'; $modelMeta = Get-TBValue $selected[0] 'meta'
    }
    try { $props = Invoke-TBJson "$Base/props" } catch { $props = $null }
    $actualContext = Get-TBValue (Get-TBValue $props 'default_generation_settings') 'n_ctx'
    if ($null -ne $actualContext -and [int]$actualContext -ne $ExpectedContext) {
        throw "Server context is $actualContext, but experiment requires $ExpectedContext. Do not change the server silently."
    }
    $template = Get-TBValue $props 'chat_template'
    if ($template -and $template -cne 'gemma') { throw "Expected generic gemma chat template, received '$template'. Use --no-jinja --chat-template gemma in your server launcher." }
    $quantization = $null
    if ($identity -match '(?i)(Q\d+_[A-Z0-9_]+|BF16|F16)') { $quantization = $Matches[1].ToUpperInvariant() }
    return [pscustomobject]@{
        ModelId = $identity; ModelIdentitySource = $identitySource; ModelMeta = $modelMeta
        Quantization = $quantization; ContextRetrieved = $actualContext
        BuildVersion = (Get-TBValue $props 'build_info'); Props = $props
        ChatTemplate = $template
    }
}
function Test-TBTranslation([string] $SourceText, $Response, [string] $ExpectedModel) {
    $issues = [Collections.Generic.List[string]]::new()
    $choice = @((Get-TBValue $Response 'choices')) | Select-Object -First 1
    $raw = Get-TBValue (Get-TBValue $choice 'message') 'content'
    $finish = Get-TBValue $choice 'finish_reason'
    $text = ''
    if ($raw -isnot [string] -or [string]::IsNullOrWhiteSpace($raw)) { $issues.Add('Empty or non-string translation') }
    else { $text = $raw.TrimEnd([char[]]"`r`n") }
    $cyrillic = [regex]::IsMatch($text, '[\u0400-\u052F\u2DE0-\u2DFF\uA640-\uA69F]')
    if ($cyrillic) { $issues.Add('Cyrillic script violation') }
    $otherScript = [regex]::IsMatch(($text -replace '[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]', ''), '\p{L}')
    if ($otherScript -and -not $cyrillic) { $issues.Add('Non-Latin letters detected') }
    $truncated = ($finish -eq 'length' -or (Get-TBValue $Response 'truncated') -eq $true)
    if ($truncated) { $issues.Add('Truncated response') }
    elseif ($finish -ne 'stop') { $issues.Add("Unexpected finish reason: $finish") }
    if ($text -match '[\r\n]') { $issues.Add('Interior newline breaks source-line alignment') }
    if ($text -match '(?i)^\s*(English text:|You are a professional|Here is (the|your) translation|Translation:|Serbian translation:|Prevod:|Srpski prevod:)' -or
        $text.Contains('```') -or $text -match '<\|.*?\|>|<start_of_turn>|<end_of_turn>') { $issues.Add('Obvious instruction leakage or formatting wrapper') }
    if ($text -ceq $SourceText -and (Get-TBWords $SourceText) -ge 4) { $issues.Add('Unchanged source text; possible untranslated output') }
    if ($text -match '^".*"$' -and $SourceText -notmatch '^".*"$') { $issues.Add('Possible added quotation wrapper') }
    $responseModel = Get-TBValue $Response 'model'
    if ($responseModel -and $responseModel -cne $ExpectedModel) { $issues.Add("Response model changed: $responseModel") }
    return [pscustomobject]@{
        Valid = ($issues.Count -eq 0); Text = $text; RawText = $raw; FinishReason = $finish
        ScriptResult = $(if ($cyrillic) { 'cyrillic_violation' } elseif ($otherScript) { 'non_latin_violation' } elseif (-not $text) { 'not_checked' } else { 'latin_pass' })
        Truncated = $truncated; Error = ($issues -join '; ')
    }
}
function Get-TBRate($Count, $Milliseconds) {
    if ($null -eq $Count -or $null -eq $Milliseconds -or [double]$Milliseconds -le 0) { return $null }
    return [double]$Count * 1000.0 / [double]$Milliseconds
}
function New-TBAttempt($Line, [int] $Number, [string] $ExperimentId) {
    return [pscustomobject][ordered]@{
        ExperimentId = $ExperimentId; SegmentId = $Line.SegmentId; SourceLineNumber = $Line.LineNumber
        AttemptNumber = $Number; RetryCount = ($Number - 1); StartedUtc = [DateTime]::UtcNow.ToString('o')
        SourceText = $Line.Text; TranslatedText = ''; RawTranslatedText = $null
        SourceCharacterCount = $Line.Text.Length; TargetCharacterCount = $null
        SourceWordCount = (Get-TBWords $Line.Text); TargetWordCount = $null
        PromptTokenCount = $null; GeneratedTokenCount = $null
        PromptEvaluatedTokens = $null; GenerationTimingTokens = $null
        PromptProcessingMs = $null; TokenGenerationMs = $null; EndToEndLatencyMs = $null
        PromptTokensPerSecond = $null; GeneratedTokensPerSecond = $null
        SourceWordsPerMinute = $null; OutputExpansionRatio = $null
        FinishReason = $null; ScriptValidationResult = 'not_checked'; Truncated = $false
        TranslationStatus = 'in_flight'; ErrorMessage = $null; HttpRequest = $true
        PromptByteUpperBound = $null; ServerTimings = $null
    }
}
function Get-TBSegmentPath([string] $RunDirectory, [int] $Id) {
    return Join-Path (Join-Path $RunDirectory 'segments') ('{0:D8}.json' -f $Id)
}
function Save-TBCheckpoint($State, [string] $Path, $Clock, [double] $BaseWallMs) {
    $State.ActiveWallMs = $BaseWallMs + $Clock.Elapsed.TotalMilliseconds
    $State.UpdatedUtc = [DateTime]::UtcNow.ToString('o')
    Write-TBAtomic $Path (Get-TBJson $State)
}
function Get-TBStats([object[]] $Values) {
    $numbers = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if (-not $numbers.Count) { return [pscustomobject]@{ Count=0; Mean=$null; Median=$null; Min=$null; Max=$null; P90=$null; P95=$null; P99=$null } }
    $sum = 0.0; foreach ($n in $numbers) { $sum += $n }
    return [pscustomobject]@{
        Count=$numbers.Count; Mean=($sum/$numbers.Count)
        Median=$(if ($numbers.Count % 2) { $numbers[[int][Math]::Floor($numbers.Count/2)] }
            else { ($numbers[$numbers.Count/2-1]+$numbers[$numbers.Count/2])/2.0 })
        Min=$numbers[0]; Max=$numbers[-1]
        P90=$numbers[[int][Math]::Ceiling($numbers.Count*0.90)-1]
        P95=$numbers[[int][Math]::Ceiling($numbers.Count*0.95)-1]
        P99=$numbers[[int][Math]::Ceiling($numbers.Count*0.99)-1]
    }
}
function Get-TBSum($Rows, [string] $Property) {
    $sum = 0.0; $count = 0
    foreach ($row in $Rows) {
        $value = Get-TBValue $row $Property
        if ($null -ne $value) { $sum += [double]$value; $count++ }
    }
    if (-not $count) { return $null }
    return $sum
}
function Get-TBAggregateRate($Rows, [string] $CountField, [string] $TimeField) {
    $paired = @($Rows | Where-Object { $null -ne (Get-TBValue $_ $CountField) -and (Get-TBValue $_ $TimeField) -gt 0 })
    return [pscustomobject]@{ Samples = $paired.Count; TokensPerSecond = (Get-TBRate (Get-TBSum $paired $CountField) (Get-TBSum $paired $TimeField)) }
}
function Write-TBReports($State, $Source, $Records, [string] $RunDirectory, [string] $Stem) {
    $attempts = @($Records.Values | Sort-Object SegmentId | ForEach-Object { $_.Attempts })
    $success = @($attempts | Where-Object { $_.TranslationStatus -eq 'success' })
    $throughput = @($success | Where-Object { $_.RetryCount -eq 0 })
    $throughputHttp = Get-TBSum $throughput 'EndToEndLatencyMs'
    $throughputWords = Get-TBSum $throughput 'SourceWordCount'
    $http = @($attempts | Where-Object { $_.HttpRequest })
    $failedRecords = @($Records.Values | Where-Object { $_.Status -eq 'failed' })
    $retriedRecords = @($Records.Values | Where-Object { @($_.Attempts).Count -gt 1 })
    $wordLengths = @($Source.Lines | Where-Object { $null -ne $_.SegmentId } | ForEach-Object { Get-TBWords $_.Text })
    $charLengths = @($Source.Lines | Where-Object { $null -ne $_.SegmentId } | ForEach-Object { $_.Text.Length })
    $sourceWords = 0; foreach ($w in $wordLengths) { $sourceWords += $w }
    $sourceChars = 0; foreach ($c in $charLengths) { $sourceChars += $c }
    $acceptedWords = Get-TBSum $success 'SourceWordCount'
    $targetWords = Get-TBSum $success 'TargetWordCount'
    $acceptedHttp = Get-TBSum $success 'EndToEndLatencyMs'
    $acceptedChars = Get-TBSum $success 'SourceCharacterCount'
    $targetChars = Get-TBSum $success 'TargetCharacterCount'
    $inferencePairs = @($http | Where-Object { $null -ne $_.PromptProcessingMs -and $null -ne $_.TokenGenerationMs })
    $inferenceMs = $null
    if ($inferencePairs.Count) { $inferenceMs = (Get-TBSum $inferencePairs 'PromptProcessingMs') + (Get-TBSum $inferencePairs 'TokenGenerationMs') }
    $summary = [ordered]@{
        ExperimentId=$State.Metadata.ExperimentId; Status=$State.Status; Metadata=$State.Metadata
        UpdatedUtc=$State.UpdatedUtc; TotalSourceSegments=$Source.SegmentCount
        SuccessfulSegments=$success.Count; FailedSegments=$failedRecords.Count
        PendingSegments=($Source.SegmentCount-$success.Count-$failedRecords.Count)
        TotalSourceWords=$sourceWords; SuccessfulSourceWords=$acceptedWords; TotalTranslatedWords=$targetWords
        TotalSourceCharacters=$sourceChars; SuccessfulTargetCharacters=$targetChars
        SegmentLengthWords=(Get-TBStats $wordLengths); SegmentLengthCharacters=(Get-TBStats $charLengths)
        ActiveWallClockMs=$State.ActiveWallMs
        CalendarSpanMs=([DateTime]::Parse($State.UpdatedUtc)-[DateTime]::Parse($State.Metadata.CreatedUtc)).TotalMilliseconds
        TotalHttpRequestMs=(Get-TBSum $http 'EndToEndLatencyMs')
        SuccessfulHttpRequestMs=$acceptedHttp
        AllAttemptsServerInferenceMs=$inferenceMs; ServerInferenceMeasuredAttempts=$inferencePairs.Count
        ServerPromptProcessingMs=(Get-TBSum $http 'PromptProcessingMs')
        ServerGenerationMs=(Get-TBSum $http 'TokenGenerationMs')
        SuccessfulLatencyMs=(Get-TBStats @($success | ForEach-Object { $_.EndToEndLatencyMs }))
        AllMeasuredHttpLatencyMs=(Get-TBStats @($http | ForEach-Object { $_.EndToEndLatencyMs }))
        SuccessfulThroughputSegments=$throughput.Count
        SuccessfulGenerationTokensPerSecond=(Get-TBStats @($throughput | ForEach-Object { $_.GeneratedTokensPerSecond }))
        AggregateSuccessfulGeneration=(Get-TBAggregateRate $throughput 'GenerationTimingTokens' 'TokenGenerationMs')
        AggregateSuccessfulPromptProcessing=(Get-TBAggregateRate $throughput 'PromptEvaluatedTokens' 'PromptProcessingMs')
        SuccessfulSourceWordsPerMinute=$(if ($throughputHttp -gt 0) { $throughputWords*60000.0/$throughputHttp } else { $null })
        OverallSourceWordsPerActiveMinute=$(if ($State.ActiveWallMs -gt 0) { $acceptedWords*60000.0/$State.ActiveWallMs } else { $null })
        SuccessfulCharacterExpansionRatio=$(if ($acceptedChars -gt 0) { $targetChars/$acceptedChars } else { $null })
        SuccessfulWordExpansionRatio=$(if ($acceptedWords -gt 0) { $targetWords/$acceptedWords } else { $null })
        Attempts=$attempts.Count; HttpAttempts=$http.Count; RetriedSegments=$retriedRecords.Count
        RetryAttemptCount=@($attempts | Where-Object { $_.RetryCount -gt 0 }).Count
        RetryHttpOverheadMs=(Get-TBSum @($http | Where-Object { $_.RetryCount -gt 0 }) 'EndToEndLatencyMs')
        UnsuccessfulHttpOverheadMs=(Get-TBSum @($http | Where-Object { $_.TranslationStatus -ne 'success' }) 'EndToEndLatencyMs')
        RetryRatePerAttemptedSegment=$(if ($Records.Count) { $retriedRecords.Count/[double]$Records.Count } else { $null })
        FailureRatePerAttemptedSegment=$(if ($Records.Count) { $failedRecords.Count/[double]$Records.Count } else { $null })
        CyrillicViolations=@($attempts | Where-Object { $_.ScriptValidationResult -eq 'cyrillic_violation' }).Count
        TruncatedResponses=@($attempts | Where-Object { $_.Truncated }).Count
        InterruptedAttempts=@($attempts | Where-Object { $_.TranslationStatus -eq 'interrupted' }).Count
        PercentileMethod='nearest-rank P90/P95/P99; median averages middle pair for even samples'
        Notes=@('Segments are non-empty source lines, not linguistically detected sentences.',
            'Successful throughput uses only successful first attempts: RetryCount=0. All retry attempts are excluded; accepted word totals and successful latency include eventual successes.',
            'Aggregate token rates pair only records with server timing token counts and measured positive times.',
            'Missing telemetry is null. Active wall time includes translation, checkpoint and periodic report work; excludes setup and final report export. Crash gaps are not estimated.',
            'No warm-up requests. cache_prompt=false, seed=0. Other server users and hardware scheduling can affect reproducibility.',
            'Latin-script checks do not prove Serbian language or translation quality. No reference-based quality metrics computed.')
    }
    Write-TBAtomic (Join-Path $RunDirectory "$Stem.summary.json") (Get-TBJson $summary)
    $csv = ''
    if ($attempts.Count) { $csv = (@($attempts | ConvertTo-Csv -NoTypeInformation) -join "`r`n") + "`r`n" }
    Write-TBAtomic (Join-Path $RunDirectory "$Stem.segments.csv") $csv
    $aligned = [Text.StringBuilder]::new()
    foreach ($line in $Source.Lines) {
        $status = 'blank'; $target = $line.Text
        if ($null -ne $line.SegmentId) {
            $status = 'pending'; $target = $null
            if ($Records.ContainsKey([int]$line.SegmentId)) {
                $record = $Records[[int]$line.SegmentId]; $status = $record.Status
                if ($status -eq 'completed') { $target = $record.Translation }
            }
        }
        [void]$aligned.AppendLine((Get-TBJson ([ordered]@{
            SegmentId=$line.SegmentId; SourceLineNumber=$line.LineNumber
            SourceText=$line.Text; TranslatedText=$target; LineEnding=$line.Ending; Status=$status
        })))
    }
    Write-TBAtomic (Join-Path $RunDirectory "$Stem.aligned.jsonl") $aligned.ToString()
    $report = @(
        "Translation benchmark: $($State.Metadata.ExperimentId)",
        "Status: $($State.Status) | Direction: en -> sr-Latn",
        "Source: $($State.Metadata.InputPath)",
        "Model: $($State.Metadata.Model.ModelId)",
        "Source lines/segments: $($Source.SegmentCount); completed: $($success.Count); failed: $($failedRecords.Count)",
        'All lengths below describe source lines, not necessarily sentences.',
        'Detailed measurements (null means unavailable):',
        (ConvertTo-Json -InputObject $summary -Depth 40)
    ) -join "`r`n"
    Write-TBAtomic (Join-Path $RunDirectory "$Stem.report.txt") $report
}
function Complete-TBOutput($State, $Source, $Records) {
    $builder = [Text.StringBuilder]::new()
    foreach ($line in $Source.Lines) {
        if ($null -eq $line.SegmentId) { [void]$builder.Append($line.Text) }
        else {
            $record = $Records[[int]$line.SegmentId]
            if ($null -eq $record -or $record.Status -ne 'completed') { throw 'Cannot assemble a final output while any source segment is unsuccessful.' }
            [void]$builder.Append($record.Translation)
        }
        [void]$builder.Append($line.Ending)
    }
    $bytes = $script:TBEncoding.GetBytes($builder.ToString())
    $hash = Get-TBHash $bytes
    $destination = $State.Metadata.OutputPath
    if ([IO.File]::Exists($destination)) {
        # Recovery from a crash between final-file publication and checkpoint update.
        if ((Get-TBFileHash $destination) -cne $hash) { throw "Destination exists with different content; it will NOT be overwritten: $destination" }
    } else {
        $temporary = $destination + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        try {
            $stream = [IO.FileStream]::new($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
            [IO.File]::Move($temporary, $destination) # Fails if another process created the destination.
        } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    }
    $State.OutputSha256 = $hash; $State.Status = 'completed'
}
function Start-TBMain {
    if ($Resume -and $NewRun) { throw 'Choose -Resume or -NewRun, not both.' }
    $base = $ApiBase.TrimEnd('/')
    if ($base -ne 'http://127.0.0.1:8080') { throw 'This experiment requires http://127.0.0.1:8080. No alternate origin is accepted.' }
    if ($MaxTokens -ge $ContextSize) { throw 'MaxTokens must be smaller than the context.' }
    foreach ($directory in @($DestinationDirectory, $BenchmarkDirectory)) {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($directory))
    }
    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) { throw "Source directory missing: $SourceDirectory" }
    $SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
    $DestinationDirectory = [IO.Path]::GetFullPath($DestinationDirectory)
    $BenchmarkDirectory = [IO.Path]::GetFullPath($BenchmarkDirectory)
    $checkpoints = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $BenchmarkDirectory -Filter '*.checkpoint.json' -File -Recurse)) {
        try { $cp = Read-TBJson $file.FullName; $checkpoints += [pscustomobject]@{ Path=$file.FullName; State=$cp } }
        catch { throw "Unreadable checkpoint (resolve or move it before continuing): $($file.FullName)" }
    }
    $choices = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $SourceDirectory -Filter '*.txt' -File | Sort-Object Name)) {
        $outputPath = Join-Path $DestinationDirectory ($file.BaseName + '.sr-latn.txt')
        $runs = @($checkpoints | Where-Object { $_.State.Metadata.InputPath -eq $file.FullName -and $_.State.Metadata.OutputPath -eq $outputPath } |
            Sort-Object { $_.State.Metadata.CreatedUtc } -Descending)
        $completed = $false
        if (Test-Path -LiteralPath $outputPath) {
            foreach ($run in $runs) {
                if ($run.State.Status -eq 'completed' -and $run.State.Metadata.SourceSha256 -eq (Get-TBFileHash $file.FullName) -and
                    $run.State.OutputSha256 -eq (Get-TBFileHash $outputPath)) { $completed = $true; break }
            }
        }
        if ($completed) {
            if ($Book -and $Book -eq $file.Name) { throw "Already completed and hash-verified; refusing overwrite: $outputPath" }
            continue
        }
        $choices += [pscustomobject]@{ File=$file; Output=$outputPath; Runs=$runs; ExistingOutput=(Test-Path -LiteralPath $outputPath) }
    }
    if (-not $choices.Count) { Write-Host 'No untranslated books remain.'; return }
    if ($Book) {
        $matchesBook = @($choices | Where-Object { $_.File.Name -eq $Book })
        if ($matchesBook.Count -ne 1) { throw "-Book must name exactly one available .txt file, not a path: $Book" }
        $choice = $matchesBook[0]
    } else {
        Write-Host "`nEnglish -> Serbian Latin | one non-empty source line per request" -ForegroundColor Cyan
        for ($i=0; $i -lt $choices.Count; $i++) {
            $item = $choices[$i]
            $note = $(if ($item.Runs.Count) { " | checkpoint: $($item.Runs[0].State.Status)" } else { '' })
            if ($item.ExistingOutput) { $note += ' | existing output is NOT confirmed complete' }
            Write-Host ('{0,2}. {1} ({2:N1} KiB){3}' -f ($i+1),$item.File.Name,($item.File.Length/1KB),$note)
        }
        while ($true) {
            $answer = (Read-Host 'Select ONE book [Enter=1, Q=quit]').Trim()
            if ($answer -match '^[qQ]$') { return }
            if (-not $answer) { $answer = '1' }
            $number = 0
            if ([int]::TryParse($answer,[ref]$number) -and $number -ge 1 -and $number -le $choices.Count) { $choice=$choices[$number-1]; break }
            Write-Warning 'Invalid book number.'
        }
    }
    $resumeChoice = [bool]$Resume
    if ($choice.Runs.Count -and -not $Resume -and -not $NewRun) {
        $answer = (Read-Host 'Existing checkpoint: R/Enter=resume newest, N=new experiment, Q=quit').Trim()
        if ($answer -match '^[qQ]$') { return }
        if ($answer -eq '' -or $answer -match '^[rR]$') { $resumeChoice=$true }
        elseif ($answer -notmatch '^[nN]$') { throw 'Invalid checkpoint action.' }
    }
    if ($resumeChoice -and -not $choice.Runs.Count) { throw 'No checkpoint exists to resume.' }
    if ($choice.ExistingOutput -and -not $resumeChoice) { throw "Existing output will not be overwritten. Move/archive it explicitly before starting a new experiment: $($choice.Output)" }
    $source = Read-TBSource $choice.File.FullName
    if (-not $source.SegmentCount) { throw 'The source contains no non-empty segments.' }
    $server = Get-TBServer $base $ModelId $ContextSize
    $configuration = [ordered]@{
        ApiEndpoint="$base/v1/chat/completions"; Temperature=0; MaxTokens=$MaxTokens
        ContextSize=$ContextSize; TimeoutSeconds=$TimeoutSeconds; MaxRetries=2; Seed=0; CachePrompt=$false
        Stream=$false; TimingsPerToken=$true; Direction='en -> sr-Latn'
        ChatTemplate='gemma (server-side --no-jinja; no chat_template_kwargs)'
        Segmentation='v1: each non-whitespace-only source line is one segment; no splitting/merging; blank lines/endings preserved'
        TargetNormalization='remove terminal CR/LF only; raw response retained; interior newlines rejected'
        ContextGuard='UTF-8 byte upper bound for generic Gemma-formatted prompt + 64 safety tokens + MaxTokens <= ContextSize'
        WordCountPolicy="Unicode letter/number words, including internal apostrophes/hyphens"
        InputEncoding=$source.Encoding; WarmupRequests=0
    }
    $identity = [ordered]@{
        SourceSha256=$source.Hash; Configuration=$configuration
        PromptSha256=(Get-TBHash $script:TBEncoding.GetBytes($script:TBPromptTemplate))
        ModelId=$server.ModelId; ModelMeta=$server.ModelMeta; IdentitySource=$server.ModelIdentitySource
        ServerContext=$server.ContextRetrieved; Build=$server.BuildVersion; ChatTemplate=$server.ChatTemplate
        ServerDefaults=(Get-TBValue $server.Props 'default_generation_settings')
    }
    $fingerprint = Get-TBHash $script:TBEncoding.GetBytes((Get-TBJson $identity))
    $stem = $choice.File.BaseName + '.sr-latn'
    if ($resumeChoice) {
        $checkpointPath = $choice.Runs[0].Path; $state = $choice.Runs[0].State
        if ($state.SchemaVersion -ne 1 -or $state.Metadata.ResumeFingerprint -cne $fingerprint) {
            throw 'Resume refused: source, prompt, model identity, context, server defaults/build or translation settings changed. Review metadata and explicitly start -NewRun if intended.'
        }
        $runDirectory = Split-Path -Parent $checkpointPath
    } else {
        $experimentId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        $runDirectory = Join-Path $BenchmarkDirectory "$stem.$experimentId"
        [void][IO.Directory]::CreateDirectory((Join-Path $runDirectory 'segments'))
        $checkpointPath = Join-Path $runDirectory "$stem.checkpoint.json"
        $state = [pscustomobject]@{
            SchemaVersion=1; Status='pending'; UpdatedUtc=[DateTime]::UtcNow.ToString('o')
            ActiveWallMs=0.0; OutputSha256=$null; ConfirmedSegments=0
            Metadata=[pscustomobject]@{
                ExperimentId=$experimentId; CreatedUtc=[DateTime]::UtcNow.ToString('o')
                InputPath=$choice.File.FullName; OutputPath=$choice.Output; SourceSha256=$source.Hash
                SourceEncoding=$source.Encoding; TotalSourceLines=$source.Lines.Count; TotalSourceSegments=$source.SegmentCount
                ResumeFingerprint=$fingerprint; ResumeIdentity=$identity; Configuration=$configuration
                PromptTemplate=$script:TBPromptTemplate; PromptSha256=$identity.PromptSha256; Model=$server
                PowerShellVersion=$PSVersionTable.PSVersion.ToString(); OperatingSystem=[Environment]::OSVersion.ToString()
                ScriptSha256=(Get-TBFileHash (Join-Path $PSScriptRoot 'translate-books.ps1'))
            }
        }
    }
    # Exclusive run lock prevents simultaneous resume/duplicate writes. OS releases it on crash.
    $lock = [IO.FileStream]::new((Join-Path $runDirectory 'run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $records = @{}; $baseWallMs=[double]$state.ActiveWallMs; $clock=[Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($line in $source.Lines) {
            if ($null -eq $line.SegmentId) { continue }
            $segmentPath=Get-TBSegmentPath $runDirectory $line.SegmentId
            if (-not (Test-Path -LiteralPath $segmentPath)) { continue }
            $record=Read-TBJson $segmentPath
            if ($record.SegmentId -ne $line.SegmentId -or $record.SourceLineNumber -ne $line.LineNumber -or
                $record.SourceText -cne $line.Text -or $record.ExperimentId -cne $state.Metadata.ExperimentId) { throw "Checkpoint alignment mismatch: $segmentPath" }
            $record.Attempts=@($record.Attempts)
            foreach ($attempt in $record.Attempts) {
                if ($attempt.TranslationStatus -eq 'in_flight') {
                    $attempt.TranslationStatus='interrupted'; $attempt.ErrorMessage='No confirmed response before interruption; HTTP duration and server outcome unknown.'
                    $record.Status='pending'
                }
            }
            if ($record.Status -eq 'completed') {
                $accepted=@($record.Attempts | Where-Object { $_.TranslationStatus -eq 'success' })
                if ($accepted.Count -ne 1 -or $record.Translation -cne $accepted[0].TranslatedText) { throw "Invalid completed segment: $segmentPath" }
            } elseif ($record.Attempts.Count -ge 3) { $record.Status='failed' }
            $records[[int]$line.SegmentId]=$record
            Write-TBAtomic $segmentPath (Get-TBJson $record)
        }
        $state.Status='running'
        $state.ConfirmedSegments=@($records.Values | Where-Object { $_.Status -eq 'completed' }).Count
        Save-TBCheckpoint $state $checkpointPath $clock $baseWallMs
        Write-Host "Experiment: $($state.Metadata.ExperimentId) | model: $($server.ModelId) | context: $ContextSize"
        Write-Host "Checkpoint: $checkpointPath"
        Write-Host 'Sequential run; avoid other inference clients during this benchmark. Ctrl+C stops without creating a partial final book.'
        $processed=0
        foreach ($line in $source.Lines) {
            if ($null -eq $line.SegmentId) { continue }
            $record=$records[[int]$line.SegmentId]
            if ($record -and $record.Status -in @('completed','failed')) { continue }
            if ($MaxSegments -gt 0 -and $processed -ge $MaxSegments) { break }
            if (-not $record) {
                $record=[pscustomobject]@{
                    ExperimentId=$state.Metadata.ExperimentId; SegmentId=$line.SegmentId; SourceLineNumber=$line.LineNumber
                    SourceText=$line.Text; Translation=$null; Status='pending'; Attempts=@()
                }
                $records[[int]$line.SegmentId]=$record
            }
            $segmentPath=Get-TBSegmentPath $runDirectory $line.SegmentId
            $prompt=Get-TBPrompt $line.Text
            $formatted="<bos><start_of_turn>user`n$prompt<end_of_turn>`n<start_of_turn>model`n"
            $bound=$script:TBEncoding.GetByteCount($formatted)+64
            while ($record.Attempts.Count -lt 3 -and $record.Status -ne 'completed') {
                $attempt=New-TBAttempt $line ($record.Attempts.Count+1) $state.Metadata.ExperimentId
                $attempt.PromptByteUpperBound=$bound
                $record.Attempts=@($record.Attempts)+@($attempt)
                if ($bound+$MaxTokens -gt $ContextSize) {
                    $attempt.HttpRequest=$false; $attempt.TranslationStatus='preflight_failed'
                    $attempt.ErrorMessage="Conservative context guard: prompt byte bound $bound + output reserve $MaxTokens exceeds $ContextSize. Source retained, not truncated or split."
                    $record.Status='failed'
                    Write-TBAtomic $segmentPath (Get-TBJson $record)
                    break
                }
                # Persist intent before dispatch: an unconfirmed request is never called a success.
                Write-TBAtomic $segmentPath (Get-TBJson $record)
                $httpClock=[Diagnostics.Stopwatch]::StartNew()
                try {
                    $body=[ordered]@{
                        model=$server.ModelId; stream=$false; temperature=0; max_tokens=$MaxTokens
                        seed=0; cache_prompt=$false; timings_per_token=$true
                        messages=@(@{ role='user'; content=$prompt })
                    }
                    $response=Invoke-TBJson "$base/v1/chat/completions" $body $TimeoutSeconds
                    $httpClock.Stop(); $attempt.EndToEndLatencyMs=$httpClock.Elapsed.TotalMilliseconds
                    $validation=Test-TBTranslation $line.Text $response $server.ModelId
                    $attempt.TranslatedText=$validation.Text; $attempt.RawTranslatedText=$validation.RawText
                    $attempt.FinishReason=$validation.FinishReason; $attempt.ScriptValidationResult=$validation.ScriptResult
                    $attempt.Truncated=$validation.Truncated; $attempt.ErrorMessage=$validation.Error
                    $attempt.TargetCharacterCount=$validation.Text.Length; $attempt.TargetWordCount=Get-TBWords $validation.Text
                    $usage=Get-TBValue $response 'usage'; $timings=Get-TBValue $response 'timings'
                    $attempt.PromptTokenCount=Get-TBValue $usage 'prompt_tokens'
                    $attempt.GeneratedTokenCount=Get-TBValue $usage 'completion_tokens'
                    $attempt.PromptEvaluatedTokens=Get-TBValue $timings 'prompt_n'
                    $attempt.GenerationTimingTokens=Get-TBValue $timings 'predicted_n'
                    $attempt.PromptProcessingMs=Get-TBValue $timings 'prompt_ms'
                    $attempt.TokenGenerationMs=Get-TBValue $timings 'predicted_ms'
                    $attempt.PromptTokensPerSecond=Get-TBValue $timings 'prompt_per_second'
                    $attempt.GeneratedTokensPerSecond=Get-TBValue $timings 'predicted_per_second'
                    if ($null -eq $attempt.PromptTokensPerSecond) { $attempt.PromptTokensPerSecond=Get-TBRate $attempt.PromptEvaluatedTokens $attempt.PromptProcessingMs }
                    if ($null -eq $attempt.GeneratedTokensPerSecond) { $attempt.GeneratedTokensPerSecond=Get-TBRate $attempt.GenerationTimingTokens $attempt.TokenGenerationMs }
                    if ($null -ne $timings) { $attempt.ServerTimings=Get-TBJson $timings }
                    if ($attempt.EndToEndLatencyMs -gt 0) { $attempt.SourceWordsPerMinute=$attempt.SourceWordCount*60000.0/$attempt.EndToEndLatencyMs }
                    $attempt.OutputExpansionRatio=$attempt.TargetCharacterCount/[double]$attempt.SourceCharacterCount
                    if ($validation.Valid) {
                        $attempt.TranslationStatus='success'; $record.Status='completed'; $record.Translation=$validation.Text
                    } else { $attempt.TranslationStatus='invalid' }
                } catch {
                    $httpClock.Stop(); $attempt.EndToEndLatencyMs=$httpClock.Elapsed.TotalMilliseconds
                    $attempt.TranslationStatus='error'; $attempt.ErrorMessage=$_.Exception.Message
                    if ($_.ErrorDetails.Message) { $attempt.ErrorMessage += ' | ' + $_.ErrorDetails.Message }
                }
                if ($record.Status -ne 'completed' -and $record.Attempts.Count -ge 3) { $record.Status='failed' }
                Write-TBAtomic $segmentPath (Get-TBJson $record)
                $state.ConfirmedSegments=@($records.Values | Where-Object { $_.Status -eq 'completed' }).Count
                Save-TBCheckpoint $state $checkpointPath $clock $baseWallMs
                if ($attempt.TranslationStatus -ne 'success') { Write-Warning "Segment $($line.SegmentId), attempt $($attempt.AttemptNumber): $($attempt.ErrorMessage)" }
            }
            $processed++
            if ($processed % 25 -eq 0) {
                $remaining=$source.SegmentCount-$state.ConfirmedSegments
                $eta=$(if ($processed -gt 0) { [Math]::Round(($clock.Elapsed.TotalSeconds/$processed)*$remaining) } else { $null })
                Write-Host ('Progress {0:N1}% | completed {1}/{2} | session elapsed {3:N1}s | estimated remaining {4}s' -f
                    (100.0*$state.ConfirmedSegments/$source.SegmentCount),$state.ConfirmedSegments,$source.SegmentCount,$clock.Elapsed.TotalSeconds,$eta)
                Write-TBReports $state $source $records $runDirectory $stem
            }
        }
        $state.Status='paused'
        if (@($records.Values | Where-Object { $_.Status -eq 'failed' }).Count) { $state.Status='failed' }
        if ($state.ConfirmedSegments -eq $source.SegmentCount) { Complete-TBOutput $state $source $records }
    } finally {
        # Atomic segment files already preserve confirmed work if Ctrl+C prevents
        # PowerShell from executing these best-effort derived exports.
        try {
            if ($state.Status -eq 'running') { $state.Status='paused' }
            $clock.Stop()
            Save-TBCheckpoint $state $checkpointPath $clock $baseWallMs
            Write-TBReports $state $source $records $runDirectory $stem
        } finally { $clock.Stop(); $lock.Dispose() }
    }
    Write-Host "Run status: $($state.Status) | confirmed: $($state.ConfirmedSegments)/$($source.SegmentCount)" -ForegroundColor Cyan
    Write-Host "Benchmarks: $runDirectory"
    if ($state.Status -eq 'completed') { Write-Host "UTF-8 output: $($state.Metadata.OutputPath)" -ForegroundColor Green }
    else { Write-Host 'No final book was published. Resume preserves successes; exhausted failures require review and an explicit new experiment.' }
}
if (-not $FunctionsOnly) { Start-TBMain }

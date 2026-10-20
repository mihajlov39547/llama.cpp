# Book translation benchmark

Run in PowerShell with the existing TranslateGemma server already listening:

```powershell
cd C:\llama.cpp
.\translate-books.ps1
```

Choose one numbered book; Enter selects the first, Q quits. An existing experiment
offers Resume or a new run. A new run gets a unique directory and never replaces
an existing translated book. No server is started by this tool.

```powershell
# Explicit book selection and bounded smoke test:
.\translate-books.ps1 -Book Adventures.txt -NewRun -MaxSegments 3
# Continue the newest experiment with the same settings:
.\translate-books.ps1 -Book Adventures.txt -Resume
```

Defaults: `MaxTokens=512`, `ContextSize=4096`, `TimeoutSeconds=180`.
Temperature is fixed at zero, seed at zero, streaming off, prompt caching off.
The generic `gemma` template must be configured on the server; requests contain
one user message, not `chat_template_kwargs`.

Input: `books\prepared-en\Adventures.txt`.
Final output: `books\gemma-translated-sr-latn\Adventures.sr-latn.txt`.
Each non-whitespace-only source line is one segment, even when it contains
several sentences. Blank lines, their whitespace, and line endings are preserved.
Strict UTF-8 and BOM-marked UTF-16 input are accepted. Output uses UTF-8 without BOM.

Each experiment writes under
`books\translation-benchmarks\<book>.sr-latn.<UTC timestamp>-<run ID>\`:

- `*.checkpoint.json`: metadata, source/settings/model fingerprint, progress.
- `segments\00000001.json`, etc.: authoritative source, translation, and every
  attempt, including failures or unconfirmed requests.
- `*.segments.csv`: one row per attempt with source/target alignment and metrics.
- `*.aligned.jsonl`: one record per source line, including blank and pending lines.
- `*.summary.json` and `*.report.txt`: aggregate measurements and metadata.

Segment records are atomically saved before dispatch and after each response.
Resume skips confirmed successes, recognizes unconfirmed requests as interrupted,
and counts them against the maximum of three attempts per segment. A failed
segment is never silently copied into the translation as English. Exhausted
failures require review; legacy Cyrillic-only failures can be repaired explicitly
as described below. Ordinary resume does not reset the retry budget. The final output is assembled only after every
segment succeeds. Keep the whole experiment directory for resume.

Resume refuses changes to source bytes, prompt, relevant request settings,
discovered model identity, server build/defaults or context. Model discovery is
not a cryptographic hash of the model weights. Record hardware, driver, offload
and KV-cache configuration separately when comparing machines; the current API
does not reliably expose all of them.

HTTP latency includes transport and JSON decoding. Server prompt/generation
times are recorded separately when available. Successful throughput excludes
all retry attempts; accepted word totals include eventual successes. Retry
overhead includes every dispatched retry, including successful retries.
Missing timings remain empty/null. Active wall time includes translation,
checkpoint writes and periodic reports, but excludes setup, time between
invocations, and final export. Unknown time lost in a crash is not estimated.

No other inference client should use the server during a benchmark. A fixed seed
and sampling settings do not guarantee identical GPU results across builds or
hardware. There is no warm-up inference.

Long source lines are conservatively rejected if a UTF-8-byte upper bound for
the formatted prompt plus output reserve exceeds the context. This can reject
some lines that would actually fit; it prevents silently splitting or truncating
them. Interior newlines in a model response are rejected to retain physical line
alignment. Trailing CR/LF is removed, with the raw response retained for auditing.

Latin-script and leakage checks are heuristics, not an evaluation of Serbian
fluency or literary quality. Valid Serbian Cyrillic responses are now
transliterated locally into Latin, including mixed-script responses. Latin
characters and punctuation are preserved. Digraphs use `Lj`, `Nj`, and `Dž`
in title-case words and `LJ`, `NJ`, and `DŽ` in all-capital words. A standalone
uppercase digraph is treated as all-capital; casing ambiguity cannot always be
resolved from a single letter. Unsupported Cyrillic letters remain invalid.
BLEU, chrF, TER and COMET are not calculated.

## Transliteration and safe repair

The fixed prompt and inference settings are unchanged. New requests accept
otherwise valid Cyrillic output after transliteration, without another model
request. Empty, truncated, errored, multiline, or otherwise invalid results
still fail validation.

Each new attempt records `OriginalScript` (`Latin`, `Cyrillic`, `Mixed`, or
`OtherOrNone`), `WasTransliterated`, `TransliterationTimeMs`,
`AcceptedWithoutModification`, and `PostprocessingVersion`. `RawTranslatedText`
is the exact model content; `TranslatedText` is the postprocessed Latin result.
`AcceptedWithoutModification` is true only if an accepted result exactly equals
the raw content, including whitespace. HTTP and model generation times exclude
transliteration; postprocessing time is measured separately.

Summary `CyrillicGenerationCount` counts all Cyrillic/mixed generation attempts,
including historical failures and retries. `TransliteratedSegments` counts
distinct accepted segments converted in normal processing or by repair.
Transliteration never adds an HTTP/inference attempt.

To repair an exact existing experiment **without any network requests**:

```powershell
$run = 'C:\llama.cpp\books\translation-benchmarks\Adventures.sr-latn.20261020T175541710Z-514627db'
.\translate-books.ps1 -ExperimentDirectory $run -RepairOnly
```

To explicitly repair and then continue inference for pending segments:

```powershell
.\translate-books.ps1 -ExperimentDirectory $run -RepairAndResume
# Optionally bound new work:
.\translate-books.ps1 -ExperimentDirectory $run -RepairAndResume -MaxSegments 3
```

`-ExperimentDirectory` chooses that exact run, not the newest experiment.
Saved model, token limit, timeout and context are reused unless explicitly
overridden. Before any new inference, normal resume checks still verify the
full settings/model/server fingerprint. `-RepairOnly` does not require a running
server; it verifies the source hash, fixed prompt and record alignment.

Repair considers only failed segments with stored attempts whose **only**
recorded failure was `Cyrillic script violation`, whose finish reason was `stop`,
and whose truncation flag was false. It revalidates the raw response after
conversion and selects the earliest eligible attempt. Other failures are not
automatically repaired or retried. A repaired segment is skipped on resume.

Original segment files and attempt histories are left byte-for-byte unchanged.
`repairs\00000001.json`, etc., store the original attempt/failure, exact raw
response, accepted result, action version, timestamp, source alignment and
original segment hash. These atomic audit files act as completion overlays.
They are validated on every resume, including after an interruption between
audit creation and checkpoint update. Repeated repair is idempotent.
`repairs\before-repair\` retains the original checkpoint and benchmark exports;
`*.repairs.json` exports the repair audit records separately.

Historical `SuccessfulSegments`, `FailedSegments`, failure rate, and inference
statistics do not retrospectively count repairs as model successes.
`EffectiveCompletedSegments`, `RepairedSegments`, `RemainingFailedSegments`,
and `EffectiveTranslatedWords` describe the repaired result. Original attempt
CSV rows retain their failed statuses; old rows have empty newly introduced
fields where these were not measured. Final assembly and progress use effective
completion, so repaired lines appear once in their original position.
No final book is published while any segment remains unsuccessful or pending.

## Validation on 2026-10-20

The live test used exactly three source segments from the beginning of
`Adventures.txt`, in an isolated fixture with blank lines. Two segments passed
Latin-script validation and preserved Serbian diacritics. Segment 1 produced
Cyrillic on both recorded retries and failed; no final test book was published.
Its initial request was left unconfirmed by a Windows PowerShell atomic-replace
compatibility defect found during testing. That defect is fixed; the checkpoint
retains this attempt as interrupted with unknown timing. There were five
dispatched attempts across the three distinct source segments.

The current native regression runner uses mocked responses for transliteration,
repair, recovery, final assembly and overwrite checks; it sends no live requests:

```powershell
.\tests\translate-books.tests.ps1
```

It writes `test-results.json` inside an isolated
`books\translation-benchmarks\transliteration-tests-<ID>` directory.
Tests ran on Windows PowerShell 5.1. PowerShell 7 compatibility is intended but
was not executed locally. Checkpoint interruption was simulated; a real
interactive Ctrl+C was not tested. No complete book translation was started.

The requested `Adventures.sr-latn.20261020T175541710Z-514627db` directory and
earlier regression runner were absent from the workspace during this update.
Repair was verified with representative legacy records, not that actual run.

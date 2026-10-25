# Local model launchers

Run `./start-llama-server.ps1` for the API or Web UI, `./start-llama-cli.ps1` for a
terminal conversation, or `./start-opencode.ps1` for OpenCode.

`model-profiles.ps1` supplies the launcher profiles. All launchers and both
benchmark tools discover the current GGUF files recursively in `models`;
deleted files disappear automatically. Gemma E2B is first in the menu.
Server/CLI retain an available saved selection; OpenCode starts on E2B.

Current inventory:

| Model | Context | Output | Reserved input headroom |
| --- | ---: | ---: | ---: |
| google_gemma-4-E2B-it-Q4_K_M.gguf | 49152 | 12288 | 12288 |
| gemma-4-E4B-it-UD-IQ2_M.gguf | 49152 | 12288 | 12288 |
| qwen3.5-4B-super-coder.Q4_0.gguf | 32768 | 12288 | 12288 |
| Qwen3.5-4B-Q4_K_M.gguf | 32768 | 4096 | 8192 |
| Qwen3-4B-Q4_K_M.gguf | 16384 | 4096 | 4096 |

The default baseline is automatic GPU layers, fit enabled, 4 CPU threads,
512 batch, 128 microbatch, F16 K/V cache, Jinja enabled and reasoning disabled
with a zero thinking budget. Servers use one slot so the context is not divided
between concurrent slots. Existing Qwen profiles retain their previous tuning.
E4B inherits the baseline. Super Coder has the model-specific settings below;
its performance has not been measured locally.

48K means 49152 tokens; 12K means 12288 tokens. `-n 12288` sets the server's
generation allowance. It does not enforce an input reservation: API clients must
keep the rendered prompt (including template/system text) within 36864 tokens to
leave the full allowance. OpenCode also gets `limit.output=12288` and
`compaction.reserved=12288`, with automatic compaction and pruning enabled.

Standalone Gemma server/CLI use `templates/gemma4-single.jinja`. This template
keeps the initial system instruction and the last user message, ignores earlier
conversation turns, and rejects tools. OpenCode retains the model's embedded
template for conversation history and tool calls. Other model families use their
embedded templates in all launchers.

Servers run in the background, with stdout/stderr written to
`logs/llama-server.stdout.log` / `logs/llama-server.stderr.log` or
`logs/opencode-server.stdout.log` / `logs/opencode-server.stderr.log`. Logs are overwritten
on the next launch. Stop the existing server before relaunching on the same port.
The default address remains `http://127.0.0.1:8080/v1`.

Use Up/Down to highlight a model and Enter to select it. Esc or Q cancels.
The server mode menu uses the same controls. Hosts without console keyboard
support use numbered input instead. All three launchers share `launcher-menu.ps1`.

Benchmark entry points are `./start-llama-autotune.ps1` and
`./start-llama-validate-best.ps1`. Settings filenames stay unchanged so saved
model selections are preserved.

All launcher-managed engine logs are rooted at `logs/`, created automatically and
excluded from Git. CLI engine diagnostics use timestamped `llama-cli-*.log`
files through native `--log-file`, preserving interactive console input/output.
These are diagnostic logs, not complete conversation transcripts. OpenCode's
`--print-logs` stderr goes to timestamped `opencode-client-*.log`; its internal
application/session storage remains managed by OpenCode. Codex uses `logs/codex`
via its per-launch `log_dir` setting (see
[official documentation](https://learn.chatgpt.com/docs/config-file/config-basic#log-directory)).
Benchmark and Python study logs use `logs/benchmark-results/<run>/`; CSVs and
response artifacts remain in `benchmark-results/<run>/`. Existing benchmark
history is preserved. Already-running processes keep their original log handles;
restart through the updated launcher to use the new paths.

Run `./start-llama-status.ps1` to inspect or manage the server on port 8080.
Up/Down and Enter select Leave, Refresh, Stop, or Restart. Esc/Q leaves it running.
The status stays visible above the menu. Alternate ports use `-Port 8081`.
Noninteractive commands are also available:

```powershell
.\start-llama-status.ps1 -Action Status
.\start-llama-status.ps1 -Action Stop
.\start-llama-status.ps1 -Action Restart
```

Status combines `/health`, `/v1/models`, `/props`, `/slots`, `/metrics`, Windows
process statistics, and recent timing lines from the server log. Missing metrics
are shown as unavailable; slot token counts are for the current/last task, not
lifetime totals. Metrics include prompt/generated token totals, processing time,
throughput and active/queued requests when supported by the installed server.
The server APIs are described in the
[upstream documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md).

Both server launchers now enable `--metrics --slots` and record the process/log
association under `logs/server-<port>.json`. If their port is occupied, they open
the manager before showing model selection. After stopping the old server, rerun
the launcher to choose another model.

Stop interrupts active requests and terminates only the verified local listener
running this workspace's `bin/llama-server.exe`. Restart reuses its native command
line, enables monitoring, writes timestamped logs, and waits for health. It does
not start another OpenCode client. Counters and prompt caches reset on restart.
Opening status or choosing Leave never stops the server. Old servers without a
log record show any recent candidate log explicitly as unverified.

Status also shows launch reasoning mode/budget, total output allowance, K/V cache
types and offload, prompt-cache settings, Flash Attention, GPU layers, CPU threads,
and batch sizes. These are the actual process arguments, not the current profile
file, and are labeled separately from API defaults and current/last-task values.
KV-cache tokens/usage are shown when the metrics endpoint exposes them; recent
cache/attention log lines are labeled as potentially stale. Missing values remain
unavailable or unspecified; zero/false are retained. A thinking budget of -1 means
no separate thinking cap, while 0 requests immediate end of thinking.

Super Coder Q4_0 uses a 32768-token context, temperature 0.6, top-p 0.95,
top-k 20, min-p 0, Flash Attention on, and reasoning on with no separate thinking
cap (`--reasoning-budget -1`). Its 12288-token output allowance includes thinking
and the final answer; the input budget is 20480 tokens including system/template
text. GPU layers remain auto with fit enabled, 4 threads, batch 512, microbatch
128 and F16 KV cache. These hardware settings are a baseline, not new benchmarks.

All three launchers use the embedded Qwen chat template for history and tools.
The CLI loads `templates/super-coder-system.txt`. OpenCode adds that file as
instructions and sets build/plan temperature/top-p explicitly; its existing agent
instructions remain in effect. The standalone HTTP server has no system-prompt
flag: clients should send a system message such as `You are a helpful coding
assistant.` Requests can override server sampling defaults.

To apply a changed profile, stop the old server with `start-llama-status.ps1`,
then select Super Coder in the desired launcher. The status manager's Restart
replays the previous command, so it does not pick up edited profile settings.

Super Coder requires the isolated official [llama.cpp b11883 CUDA 12.4 runtime](https://github.com/ggml-org/llama.cpp/releases/tag/b11883)
in `bin/runtimes/b11883-cuda12.4`. `runtime-paths.ps1` selects it for Super Coder
in all three launchers. Other models continue using the original `bin` runtime.
The status manager accepts only these two exact server executable paths.

The original b8729 runtime misreads the GGUF's additional MTP prediction head as
an ordinary recurrent layer and requests the nonexistent
`blk.32.ssm_conv1d.weight`. Inspection confirmed that the file contains 32 normal
layers plus the MTP tensors in block 32. The new runtime loads the model without
editing GGUF metadata or weights. Lowering context does not fix that load error.

The isolated runtime consists of the official
`llama-b11883-bin-win-cuda-12.4-x64.zip` and
`cudart-llama-bin-win-cuda-12.4-x64.zip`, extracted into the same directory.
Downloads were verified against the release's SHA-256 digests; release metadata
is saved in `logs/verification/runtime-download.json`. Startup failures now show
relevant stderr lines directly in the launcher, in addition to the log path.

Validation with b11883: Super Coder loaded at 32768 context, exposed the requested
sampling defaults, and completed a short coding request with reasoning and a
correct Python addition function. The full OpenCode launcher generated its config
and reached healthy status on an isolated test port; the status manager inspected
and stopped it successfully. This is a smoke test, not a coding benchmark.

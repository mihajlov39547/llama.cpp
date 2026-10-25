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
| qwen3.5-4B-super-coder.Q4_0.gguf | 49152 | 12288 | 12288 |
| Qwen3.5-4B-Q4_K_M.gguf | 32768 | 4096 | 8192 |
| Qwen3-4B-Q4_K_M.gguf | 16384 | 4096 | 4096 |

The default baseline is automatic GPU layers, fit enabled, 4 CPU threads,
512 batch, 128 microbatch, F16 K/V cache, Jinja enabled and reasoning disabled
with a zero thinking budget. Servers use one slot so the context is not divided
between concurrent slots. Existing Qwen profiles retain their previous tuning.
E4B and Super Coder inherit the baseline; their performance has not been measured.

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
`llama-server.stdout.log` / `llama-server.stderr.log` or
`opencode-server.stdout.log` / `opencode-server.stderr.log`. Logs are overwritten
on the next launch. Stop the existing server before relaunching on the same port.
The default address remains `http://127.0.0.1:8080/v1`.

Use Up/Down to highlight a model and Enter to select it. Esc or Q cancels.
The server mode menu uses the same controls. Hosts without console keyboard
support use numbered input instead. All three launchers share `launcher-menu.ps1`.

Benchmark entry points are `./start-llama-autotune.ps1` and
`./start-llama-validate-best.ps1`. Settings filenames stay unchanged so saved
model selections are preserved.

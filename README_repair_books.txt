CONSERVATIVE LITERARY TEXT RESTORATION — WINDOWS / LLAMA.CPP

Files:
  repair_books.py        Python 3.10+ script; Python standard library only

Prerequisites:
  1. llama-server running at http://127.0.0.1:8080
  2. Model alias gemma-4-local (verified by /v1/models)
  3. English .txt files in C:\llama.cpp\books\prepared-en
  4. All input TXT files must be valid UTF-8; BOM, CRLF and final newline preserved.

INSTALL:
  Copy repair_books.py to C:\llama.cpp\repair_books.py
  No pip install necessary.

SAFE FIRST RUN — 20 LINES OF ONE BOOK:
  cd C:\llama.cpp
  python .\repair_books.py --book Roderick.txt --max-lines 20

This creates a preview under:
  C:\llama.cpp\books\refinement-runs\Roderick\<run-id>\preview\Roderick.txt
and review.csv, manifest.json, progress.jsonl in the same run directory.
The production refined-en directory is NOT written for pilots.

FULL BOOK:
  python .\repair_books.py --book Roderick.txt

ALL 26 BOOKS:
  python .\repair_books.py

RESUME AFTER INTERRUPTION:
  Run the EXACT SAME command again. Each completed line is checkpointed.
  Altering the model, prompt, source, --max-lines, --max-tokens or --max-char-change
  changes the checkpoint identity and starts an independent experiment.
  Any interrupted request may be recomputed.

WHERE OUTPUTS GO:
  C:\llama.cpp\books\refined-en\BookName.txt          (complete runs only)
  C:\llama.cpp\books\refinement-runs\BookName\<run-id>\review.csv
  C:\llama.cpp\books\refinement-runs\BookName\<run-id>\progress.jsonl

ACCEPTANCE POLICY:
  Formatting and punctuation changes that retain exactly the same sequence
  of letters/digits, ignoring whitespace/punctuation, can be auto-accepted
  if below the configured change threshold and the model is confident.
  Any added/deleted/replaced letters or digits is routed to review and NOT applied.
  The model can still propose them in review.csv. A model error preserves source.
  A model-declared uncertainty preserves source.

IMPORTANT:
  A completed refined-en file may still include unresolved suspicious lines:
  review.csv contains these. Inspect before training or publication.
  A line-preserving output does not guarantee restored literary accuracy.
  The model is offline/local; no request is sent to Alibaba/Oracle.

TEST FILE HANDLING WITHOUT MODEL:
  python .\repair_books.py --book Roderick.txt --max-lines 20 --mock

HELP:
  python .\repair_books.py --help

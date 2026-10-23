#!/usr/bin/env python3
"""Balanced line-preserving literary editing via local llama.cpp.

Standard library only. Original files never modified. Run --help for instructions.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from difflib import SequenceMatcher
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

PROMPT_VERSION = 'training-readable-v2.1'
SYSTEM = """You edit ONE line of damaged English fiction to create CLEAN ENGLISH training text.

Primary goal: a grammatically clear, self-contained, readable English record. You may reconstruct damaged grammar, split run-ons into complete sentences, insert missing words, repair OCR/formatting, and lightly rephrase where needed. Exact wording and historical punctuation are NOT required.

Hard rules:
1. TARGET_LINE is the only text you edit. PREVIOUS and NEXT are context only; do not copy their text.
2. Return precisely ONE physical line (no newline); multiple complete sentences on that line are fine.
3. Keep the same scene, main events, referents, and approximate information coverage. Do not invent new actions or omit whole clauses.
4. Correct obvious word merges, possessives, quotations, punctuation, and grammar. Do NOT output Markdown italics, headings, comments, or notes within the edited line.
5. If input starts with CHAPTER plus a numeral: it contains a CHAPTER TITLE merged with the first narrative sentence. Reconstruct readable title clauses, then separate the narrative with a period or em dash; do not put them on separate physical lines.
6. Do not preserve broken constructions merely because they occur in the input. Prefer clear grammar over exact original wording.
7. If input is already fluent, repeat it unchanged.

Examples:
Input: 'Sir you have made the grand touryou are a polite gentlemana very pretty gentleman I wish you joy.'
Output: 'Sir, you have made the grand tour. You are a polite gentleman, a very pretty gentleman. I wish you joy.'
Input: 'The troubles were such as to excite mirth than compassion.'
Output: 'The troubles were more likely to excite mirth than compassion.'
Input: 'My father his youngest son fell in love with her.'
Output: 'My father, his youngest son, fell in love with her.'
Input: 'He arrived late.He went home.'
Output: 'He arrived late. He went home.'

Return ONLY JSON: {"corrected":"one complete edited line","needs_review":false,"reason":"short note"}.
Set needs_review=true only if content is too corrupt to reconstruct confidently. No other keys are needed.
"""

# A deliberately conservative *automatic* acceptance policy within balanced editing:
# substantial edits stay in review.csv with original safely retained.
PROTECTED_NUMBER = re.compile(r'(?<!\w)\d+(?:[.,]\d+)*(?!\w)')
PROTECTED_CAPITAL = re.compile(r'(?<![.!?]\s)(?<!\w)[A-Z][a-z]{2,}\b')


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def read_book(path):
    data = path.read_bytes()
    # Preserve UTF-8 BOM, original CRLF/LF/CR and final newline state.
    bom = b'\xef\xbb\xbf' if data.startswith(b'\xef\xbb\xbf') else b''
    content = data[len(bom):]
    text = content.decode('utf-8', errors='strict')
    records = []
    for physical_line in text.splitlines(keepends=True):
        if physical_line.endswith('\r\n'):
            records.append((physical_line[:-2], '\r\n'))
        elif physical_line.endswith(('\n', '\r')):
            records.append((physical_line[:-1], physical_line[-1]))
        else:
            records.append((physical_line, ''))
    if not records and text:
        records = [(text, '')]
    return data, bom, records


def write_atomic(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_bytes(raw)
    os.replace(tmp, path)


def unpack_json(text):
    stripped = text.strip()
    if stripped.startswith('```'):
        stripped = re.sub(r'^```(?:json)?\s*', '', stripped, flags=re.I)
        stripped = re.sub(r'\s*```$', '', stripped)
    try:
        value = json.loads(stripped)
    except json.JSONDecodeError:
        # Sometimes small models add prose; only accept one self-contained object.
        start, end = stripped.find('{'), stripped.rfind('}')
        if start < 0 or end <= start:
            raise ValueError('No JSON object in response')
        value = json.loads(stripped[start:end + 1])
    if not isinstance(value, dict) or not isinstance(value.get('corrected'), str):
        raise ValueError('Response missing corrected string')
    if type(value.get('needs_review')) is not bool:
        raise ValueError('Response missing boolean needs_review')
    return value


def classify(original, proposed, wants_review, max_char_change):
    if any(ch in proposed for ch in ('\n', '\r', '\x00')):
        return original, 'review', 'newline_or_control'
    if proposed == original:
        return original, 'unchanged', 'no_change'
    if not proposed.strip():
        return original, 'review', 'blank_output'
    if wants_review:
        return original, 'review', 'model_uncertain'
    similarity = SequenceMatcher(None, original, proposed, autojunk=False).ratio()
    if 1 - similarity > max_char_change:
        return original, 'review', 'large_edit'
    if PROTECTED_NUMBER.findall(original) != PROTECTED_NUMBER.findall(proposed):
        return original, 'review', 'numbers_changed'
    # Capitalized proper nouns are hard to identify without NLP. This heuristic is
    # deliberately sensitive and sends potentially risky edits to manual review.
    old_caps = PROTECTED_CAPITAL.findall(original)
    new_caps = PROTECTED_CAPITAL.findall(proposed)
    missing_caps = [word for word in old_caps if word not in new_caps]
    if missing_caps:
        return original, 'review', 'capitalized_words_changed'
    # Never silently change explicit negation or polarity expressions.
    polarity = re.compile(r"\b(?:not|no|never|nor|without|cannot|can't|won't|don't|isn't|wasn't)\b", re.I)
    if polarity.findall(original.lower()) != polarity.findall(proposed.lower()):
        return original, 'review', 'negation_changed'
    # Whitespace-only corrections are safe even when tokenization changes
    # because a previously joined word becomes two tokens.
    if ''.join(original.split()) == ''.join(proposed.split()):
        return proposed, 'accepted', 'whitespace_only'
    old_tokens = re.findall(r"[A-Za-z]+", original.lower())
    new_tokens = re.findall(r"[A-Za-z]+", proposed.lower())
    lexical_overlap = SequenceMatcher(None, old_tokens, new_tokens, autojunk=False).ratio()
    if lexical_overlap < 0.88:
        return original, 'review', 'lexical_change_high'
    # A small set of high-precision quality alarms: these should not silently enter the training corpus.
    if re.search(r"\bsuch as to [^.!?]{0,85}\bthan\b", proposed, re.I):
        return original, 'review', 'broken_comparison'
    if proposed.count('"') % 2:
        return original, 'review', 'unbalanced_quotes'
    if re.search(r"\*[^*]+\*|__[A-Za-z]|\[[^\]]+\]\([^)]*\)", proposed):
        return original, 'review', 'markdown_markup'
    if re.match(r'^\s*CHAPTER\s+[IVXLCDM0-9]+\b', original, re.I) and (not re.match(r'^\s*CHAPTER\s+[IVXLCDM0-9]+\b', proposed, re.I)):
        return original, 'review', 'chapter_marker_missing'
    # Quality warnings are heuristic, not linguistic proof.
    # Balanced mode permits modest punctuation, grammar and rephrasing changes.
    # Warning: this is *not* a semantic equivalence proof; approved lines need QA.
    return proposed, 'accepted', 'balanced_small_edit'


def chat(endpoint, model, previous, target, following, timeout, max_tokens, retries):
    payload = {
        'model': model,
        'temperature': 0.1,
        'max_tokens': max_tokens,
        'stream': False,
        'cache_prompt': True,
        'messages': [
            {'role': 'system', 'content': SYSTEM},
            {'role': 'user', 'content': json.dumps({
                'PREVIOUS_CONTEXT_READ_ONLY': previous,
                'TARGET_LINE_EDIT_THIS_ONLY': target,
                'NEXT_CONTEXT_READ_ONLY': following
            }, ensure_ascii=False)},
        ],
    }
    body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
    for attempt in range(retries + 1):
        try:
            req = Request(endpoint.rstrip('/') + '/v1/chat/completions', data=body,
                          headers={'Content-Type': 'application/json'}, method='POST')
            with urlopen(req, timeout=timeout) as res:
                response = json.load(res)
            choice = response['choices'][0]
            if choice.get('finish_reason') == 'length':
                raise ValueError('model_response_truncated')
            content = choice['message'].get('content')
            if not isinstance(content, str) or not content.strip():
                raise ValueError('empty_model_output')
            result = unpack_json(content)
            return result, response.get('usage', {})
        except (HTTPError, URLError, TimeoutError, KeyError, IndexError, ValueError, json.JSONDecodeError) as exc:
            if attempt == retries:
                raise RuntimeError(str(exc)) from exc
            time.sleep(min(2 ** attempt, 6))


def append_jsonl(path, item):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a', encoding='utf-8', newline='\n') as stream:
        stream.write(json.dumps(item, ensure_ascii=False) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def load_progress(path):
    found = {}
    if not path.exists():
        return found
    with path.open('r', encoding='utf-8') as stream:
        for line in stream:
            try:
                obj = json.loads(line)
                found[obj['line']] = obj
            except (json.JSONDecodeError, KeyError):
                # tolerate an interrupted append; all earlier records are retained
                continue
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--input-dir', default=r'C:\llama.cpp\books\prepared-en')
    parser.add_argument('--output-dir', default=r'C:\llama.cpp\books\refined-en')
    parser.add_argument('--state-dir', default=r'C:\llama.cpp\books\refinement-runs')
    parser.add_argument('--book', help='Only process this filename, e.g. Roderick.txt')
    parser.add_argument('--max-lines', type=int, default=0, help='Pilot only: process first N lines per book, 0=all')
    parser.add_argument('--url', default='http://127.0.0.1:8080')
    parser.add_argument('--model', default='gemma4-book-cleaner')
    parser.add_argument('--max-tokens', type=int, default=1500)
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--retries', type=int, default=2)
    parser.add_argument('--max-char-change', type=float, default=0.25)
    parser.add_argument('--template-tag', default='default', help='Label checkpoint by server chat template, e.g. single or gguf')
    parser.add_argument('--sleep', type=float, default=0.0)
    parser.add_argument('--mock', action='store_true', help='Offline pipeline test, does NOT call Gemma')
    args = parser.parse_args()
    input_dir = Path(args.input_dir)
    state_dir = Path(args.state_dir)
    output_dir = Path(args.output_dir)
    if not input_dir.is_dir():
        parser.error(f'Input directory not found: {input_dir}')
    if input_dir.resolve() == output_dir.resolve():
        parser.error('Input and output directory must differ')
    if args.book:
        files = [input_dir / args.book]
        if not files[0].is_file() or files[0].parent.resolve() != input_dir.resolve():
            parser.error(f'Book not found in input directory: {args.book}')
    else:
        files = sorted(input_dir.glob('*.txt'))
    if not files:
        parser.error('No .txt files found')

    print(f'Books: {len(files)} | Model: {args.model} | Mock: {args.mock}')
    print('INPUTS ARE READ-ONLY. Small balanced edits are applied; high-risk edits are reviewed.')
    for file in files:
        raw, bom, lines = read_book(file)
        fingerprint = sha256(raw)
        # Isolate checkpoints by source hash, prompt version, model, run mode and settings.
        settings = {'source_sha256': fingerprint, 'model': args.model, 'prompt': PROMPT_VERSION,
                    'max_lines': args.max_lines, 'max_tokens': args.max_tokens,
                    'max_char_change': args.max_char_change, 'mock': args.mock, 'temperature': 0.1, 'template_tag': args.template_tag}
        run_id = sha256(json.dumps(settings, sort_keys=True).encode())[:16]
        run_dir = state_dir / file.stem / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        meta_path = run_dir / 'manifest.json'
        if not meta_path.exists():
            write_atomic(meta_path, json.dumps({'file': file.name, 'total_lines': len(lines),
                                              'settings': settings}, indent=2).encode())
        progress_path = run_dir / 'progress.jsonl'
        progress = load_progress(progress_path)
        count = min(len(lines), args.max_lines) if args.max_lines else len(lines)
        print(f'\n{file.name}: {len(lines)} physical lines, processing {count}, resumed {len(progress)}')
        for idx in range(count):
            line_no = idx + 1
            if line_no in progress:
                continue
            original = lines[idx][0]
            if not original.strip():
                row = {'line': line_no, 'original': original, 'proposed': original,
                       'applied': original, 'status': 'unchanged', 'why': 'blank_line'}
            else:
                try:
                    if args.mock:
                        result, usage = ({'corrected': original, 'needs_review': False, 'reason': 'mock'}, {})
                    else:
                        result, usage = chat(args.url, args.model,
                                             lines[idx - 1][0] if idx else '', original,
                                             lines[idx + 1][0] if idx + 1 < len(lines) else '',
                                             args.timeout, args.max_tokens, args.retries)
                    proposed = result['corrected']
                    applied, status, why = classify(original, proposed, result['needs_review'],
                                                    args.max_char_change)
                    row = {'line': line_no, 'original': original, 'proposed': proposed,
                           'applied': applied, 'status': status, 'why': why,
                           'model_reason': str(result.get('reason', ''))[:500], 'usage': usage}
                except Exception as error:
                    row = {'line': line_no, 'original': original, 'proposed': original,
                           'applied': original, 'status': 'error', 'why': str(error)[:500]}
            append_jsonl(progress_path, row)
            progress[line_no] = row
            if line_no % 20 == 0 or line_no == count:
                print(f'  completed {line_no}/{count}', flush=True)
            if args.sleep:
                time.sleep(args.sleep)
        # Reconstruct every source line, preserving its own newline suffix and UTF-8 BOM.
        output = []
        for idx, (original, newline) in enumerate(lines):
            row = progress.get(idx + 1)
            output.append((row['applied'] if row else original) + newline)
        output_bytes = bom + ''.join(output).encode('utf-8')
        # Pilot files always go to preview directory, never to production refined-en.
        target = (run_dir / 'preview' / file.name) if args.max_lines else (output_dir / file.name)
        # Verify physical-line preservation before publication.
        target_text = output_bytes[len(bom):].decode('utf-8')
        if len(target_text.splitlines(keepends=True)) != len(lines):
            raise RuntimeError(f'Line count changed: {file.name}')
        if args.max_lines == 0 and len(progress) != len(lines):
            raise RuntimeError(f'Incomplete book: {file.name}')
        write_atomic(target, output_bytes)
        csv_path = run_dir / 'review.csv'
        with csv_path.open('w', encoding='utf-8-sig', newline='') as out:
            writer = csv.writer(out)
            writer.writerow(['line', 'status', 'why', 'original', 'proposal', 'applied', 'model_reason'])
            for i in sorted(progress):
                row = progress[i]
                if row['status'] in ('review', 'error'):
                    writer.writerow([i, row['status'], row['why'], row['original'],
                                     row['proposed'], row['applied'], row.get('model_reason', '')])
        totals = {key: sum(r['status'] == key for r in progress.values())
                  for key in ['accepted', 'unchanged', 'review', 'error']}
        print(f'  output: {target}\n  review: {csv_path}\n  results: {totals}')
    print('\nFinished. Review flagged lines before using the files as training data.')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Identify EFU duplicates by (case-insensitive basename, size), then full SHA-256.
Read-only: never removes or modifies source files. Excludes C:\\Projects by default.
"""
import argparse
import csv
import hashlib
import os
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path, PureWindowsPath

DEFAULT_EXCLUDES = [r'C:\Projects']

def norm(path):
    return path.replace('/', '\\').rstrip('\\').casefold()

def excluded(path, prefixes):
    p = norm(path)
    return any(p == x or p.startswith(x + '\\') for x in prefixes)

def entries(efu):
    with open(efu, 'r', encoding='utf-8-sig', errors='replace', newline='') as stream:
        for row in csv.DictReader(stream):
            p = row.get('Filename') or row.get('filename')
            sz = row.get('Size') or row.get('size')
            if not p or sz is None or not sz.strip():
                yield None
                continue
            try:
                size = int(sz)
            except (ValueError, TypeError):
                yield None
                continue
            if size < 0:
                yield None
                continue
            yield p, size

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb', buffering=0) as stream:
        while True:
            buf = stream.read(4 * 1024 * 1024)
            if not buf:
                break
            h.update(buf)
    return h.hexdigest()

def write_csv(filename, header, rows):
    with open(filename, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

def main():
    a = argparse.ArgumentParser(description='Find real duplicate files in an Everything EFU export using name + size + full SHA-256.')
    a.add_argument('efu')
    a.add_argument('--min-mb', type=float, default=1.0, help='Minimum size, MiB (default: 1; use 0 for all sizes)')
    a.add_argument('--top', type=int, default=30)
    a.add_argument('--include-projects', action='store_true')
    a.add_argument('--exclude', action='append', default=[])
    a.add_argument('--output', default=None)
    args = a.parse_args()
    if args.min_mb < 0 or args.top < 1:
        a.error('Minimum size must be >= 0 and top >= 1')
    efu = Path(args.efu).resolve()
    if not efu.is_file():
        a.error('EFU not found: ' + str(efu))
    dest = Path(args.output).resolve() if args.output else efu.parent / 'efu-duplicates-verified'
    dest.mkdir(parents=True, exist_ok=True)
    threshold = int(args.min_mb * 1048576)
    prefixes = [norm(x) for x in (([] if args.include_projects else DEFAULT_EXCLUDES) + args.exclude)]
    print('EFU:', efu, '| minimum:', f'{args.min_mb:g}', 'MiB', '| excluded:', prefixes, flush=True)
    print('PASS 1: count identical FILENAME + SIZE combinations', flush=True)
    counts = Counter()
    total = ignored = eligible = 0
    started = time.monotonic()
    for item in entries(efu):
        total += 1
        if item:
            path, size = item
            if excluded(path, prefixes):
                ignored += 1
            elif size >= threshold:
                key = (PureWindowsPath(path).name.casefold(), size)
                counts[key] += 1
                eligible += 1
        if total % 500000 == 0:
            print(f'  {total:,} rows ({time.monotonic()-started:.1f}s)', flush=True)
    repeated = {key for key, n in counts.items() if n > 1}
    del counts
    print(f'  {total:,} rows; {ignored:,} excluded; {eligible:,} eligible; {len(repeated):,} candidate name+size groups', flush=True)
    print('PASS 2: gather paths only for candidates', flush=True)
    groups = defaultdict(dict)
    for item in entries(efu):
        if item is None:
            continue
        path, size = item
        if excluded(path, prefixes):
            continue
        key = (PureWindowsPath(path).name.casefold(), size)
        if key in repeated:
            groups[key][norm(path)] = path
    candidates = [(key, list(paths.values())) for key, paths in groups.items() if len(paths) > 1]
    candidates.sort(key=lambda t: t[0][1] * (len(t[1])-1), reverse=True)
    print(f'  {len(candidates):,} groups after duplicate-path removal', flush=True)
    candidate_rows = []
    for i, ((name, size), paths) in enumerate(candidates, 1):
        for path in paths:
            candidate_rows.append((i, name, size, len(paths), path))
    write_csv(dest/'same-name-same-size.csv', ['CandidateGroup','FileName','SizeBytes','CandidateCount','FullPath'], candidate_rows)
    print('PASS 3: verify complete SHA-256 of existing candidate files', flush=True)
    errors = []
    verified = []
    hashed = 0
    hash_bytes = 0
    for idx, ((name, size), paths) in enumerate(candidates, 1):
        by_hash = defaultdict(list)
        for path in paths:
            try:
                before = os.stat(path)
                if not os.path.isfile(path):
                    raise ValueError('not a regular file')
                if before.st_size != size:
                    raise ValueError(f'size changed since EFU: expected {size}, now {before.st_size}')
                digest = sha256(path)
                after = os.stat(path)
                if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
                    raise ValueError('file changed while hashing')
                by_hash[digest].append((path, (after.st_dev, after.st_ino)))
                hash_bytes += size
                hashed += 1
            except (OSError, ValueError) as exc:
                errors.append((path, name, size, str(exc)))
        for digest, matches in by_hash.items():
            if len(matches) >= 2:
                # File IDs: a pair of hard links already shares disk blocks.
                unique_file_ids = len({fileid for _, fileid in matches})
                verified.append((name, size, digest, matches, unique_file_ids))
        if idx % 25 == 0 or idx == len(candidates):
            print(f'  groups {idx:,}/{len(candidates):,}; files hashed {hashed:,}; hashed {hash_bytes/1073741824:,.2f} GiB; verified groups {len(verified):,}', flush=True)
    verified.sort(key=lambda x: x[1] * max(0, x[4]-1), reverse=True)
    records = []
    totals = []
    savings = 0
    for i, (name, size, digest, matches, unique_ids) in enumerate(verified, 1):
        potential = size * max(0, unique_ids-1)
        savings += potential
        totals.append((i, name, size, len(matches), unique_ids, potential, digest))
        for path, fileid in matches:
            records.append((i, name, size, digest, len(matches), unique_ids, potential, path))
    write_csv(dest/'confirmed-duplicates.csv', ['Group','FileName','SizeBytes','SHA256','Copies','DistinctPhysicalFiles','PotentialSavingsBytes','FullPath'], records)
    write_csv(dest/'confirmed-groups.csv', ['Group','FileName','SizeBytes','Copies','DistinctPhysicalFiles','PotentialSavingsBytes','SHA256'], totals)
    write_csv(dest/'verification-errors.csv', ['FullPath','FileName','ExpectedSizeBytes','Reason'], errors)
    summary = [
        'FULL SHA-256 DUPLICATE REPORT (same name + same size + same SHA-256)',
        f'EFU: {efu}',
        f'Excluded prefixes: {prefixes}',
        f'Minimum file size: {args.min_mb:g} MiB',
        f'EFU rows: {total:,}',
        f'Candidate groups after name+size matching: {len(candidates):,}',
        f'Candidate files successfully hashed: {hashed:,}',
        f'Confirmed duplicate groups: {len(verified):,}',
        f'Potential savings from distinct file IDs: {savings/1073741824:,.2f} GiB',
        f'Files that could not be verified: {len(errors):,}',
        'Read-only report. NEVER delete files automatically.',
        'Savings are estimates; Windows hardlinks are excluded when file IDs match, but compression/sparse files may alter space saved.',
        '', 'TOP CONFIRMED DUPLICATES:',
    ]
    for i, (name, size, digest, matches, unique_ids) in enumerate(verified[:args.top], 1):
        saving = size*max(0,unique_ids-1)
        summary.append(f'{i}. {name}: {len(matches)} copies, each {size/1048576:,.1f} MiB; potential saving {saving/1073741824:.2f} GiB; SHA256 {digest}')
        summary.extend('   ' + path for path, _ in matches)
    (dest/'summary.txt').write_text('\n'.join(summary)+'\n', encoding='utf-8')
    print('\n'.join(summary), flush=True)
    print('\nReports:', dest, flush=True)
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\nInterrupted; no files changed.', file=sys.stderr)
        sys.exit(130)

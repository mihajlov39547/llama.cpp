#!/usr/bin/env python3
"""Line-aligned Serbian Latin revision using refined English + existing Serbian draft.
Standard library only. Checkpoints per physical line. Does not overwrite source or draft.
"""
import argparse
import csv
import hashlib
import json
import os
import re
import time
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

VERSION = 'serbian-reference-edit-v1'
SYSTEM = '''You are a Serbian literary editor and translator. You receive ONE refined English source line and ONE existing Serbian draft translation of that SAME line. Produce a polished, natural, grammatically correct SERBIAN LATIN translation of the English line, using the draft as a starting suggestion, not as authoritative text. Repair poor draft grammar, missing words, OCR errors, mistranslations and awkward phrasing; freely rewrite when necessary. The result should read clearly and preserve the same scene, events and main information as the English source. Do not borrow text from neighboring lines. Retain names and numbers. Do not add plot events. Do not use Cyrillic. Produce exactly ONE physical line, even if it contains multiple sentences. Do not add explanations, markdown or literal newline characters. If the draft is already a clear, adequate translation, retain it. Return ONLY JSON object: {"corrected":"single Serbian Latin line","needs_review":false,"reason":"brief reason"}. If English/draft alignment is uncertain or impossible, set needs_review true.'''
CYR = re.compile(r'[\u0400-\u052f]')

def read_lines(path):
    raw = path.read_bytes()
    if raw.startswith(b'\xff\xfe'):
        text = raw[2:].decode('utf-16-le')
    elif raw.startswith(b'\xfe\xff'):
        text = raw[2:].decode('utf-16-be')
    else:
        text = raw.decode('utf-8-sig')
    if '\x00' in text:
        raise ValueError(f'NUL / unsupported encoding: {path}')
    result=[]
    for l in text.splitlines(keepends=True):
        if l.endswith('\r\n'): result.append((l[:-2], '\r\n'))
        elif l.endswith(('\r','\n')): result.append((l[:-1], l[-1]))
        else: result.append((l,''))
    return result, hashlib.sha256(raw).hexdigest()

def atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp=path.with_name(path.name+'.tmp')
    tmp.write_bytes(content)
    os.replace(tmp,path)

def json_response(output):
    value=output.strip()
    if value.startswith('```'):
        value=re.sub(r'^```(?:json)?\s*','',value,flags=re.I)
        value=re.sub(r'\s*```$','',value)
    try: obj=json.loads(value)
    except json.JSONDecodeError:
        start=value.find('{'); end=value.rfind('}')
        if start<0 or end<=start: raise ValueError('No JSON object')
        obj=json.loads(value[start:end+1])
    if not isinstance(obj,dict) or not isinstance(obj.get('corrected'),str) or type(obj.get('needs_review')) is not bool:
        raise ValueError('Invalid JSON response structure')
    return obj

def call_llm(args, english, draft):
    body=json.dumps({'model':args.model,'temperature':0.1,'max_tokens':args.max_tokens,
        'stream':False,'cache_prompt':True,'messages':[{'role':'system','content':SYSTEM},
        {'role':'user','content':json.dumps({'REFINED_ENGLISH':english,'EXISTING_SERBIAN_DRAFT':draft},ensure_ascii=False)}]},ensure_ascii=False).encode('utf-8')
    for attempt in range(args.retries+1):
        try:
            req=Request(args.url.rstrip('/')+'/v1/chat/completions',data=body,headers={'Content-Type':'application/json'},method='POST')
            with urlopen(req,timeout=args.timeout) as r: reply=json.load(r)
            choice=reply['choices'][0]
            if choice.get('finish_reason')=='length':raise ValueError('truncated response')
            result=json_response(choice['message']['content'])
            return result,reply.get('usage',{})
        except (HTTPError,URLError,TimeoutError,ValueError,KeyError,IndexError) as exc:
            if attempt==args.retries:raise RuntimeError(str(exc)) from exc
            time.sleep(min(2**attempt,6))

def classify(english,draft,proposed,uncertain):
    if not english.strip():
        return ('','unchanged','empty_english') if not draft.strip() else (draft,'review','nonempty_draft_for_blank_english')
    if not proposed.strip():return draft,'review','empty_response'
    if any(c in proposed for c in ('\n','\r','\x00')):return draft,'review','embedded_newline_or_nul'
    if CYR.search(proposed):return draft,'review','cyrillic_output'
    if uncertain:return draft,'review','model_uncertain'
    # A lenient length bound to detect lost chapters, hallucinated paragraphs, etc.
    if len(proposed)>max(200,4*max(len(draft),len(english))):return draft,'review','implausibly_long'
    if len(proposed)<max(4,int(0.18*len(english))):return draft,'review','implausibly_short'
    # Numerals are hard alignment anchors, but can legitimately differ in words; flag instead of discarding.
    nums=lambda s:re.findall(r'(?<!\w)\d+(?!\w)',s)
    if nums(english) and nums(english)!=nums(proposed):return draft,'review','numeric_anchors_changed'
    if proposed==draft:return draft,'unchanged','same_as_draft'
    return proposed,'accepted','edited'

def match_draft(directory,english_filename):
    stem=Path(english_filename).stem
    candidates=[directory/(stem+'.txt'), directory/(stem+'.sr-latn.txt'), directory/(stem+'.sr.txt')]
    found=[p for p in candidates if p.is_file()]
    if len(found)!=1:raise ValueError(f'Expected exactly one Serbian draft for {english_filename}; found {found}. Checked: {candidates}')
    return found[0]

def load_progress(path):
    rows={}
    if path.exists():
        for line in path.read_text(encoding='utf-8').splitlines():
            try:
                v=json.loads(line);rows[int(v['line'])]=v
            except (ValueError,KeyError,TypeError):continue
    return rows

def process(args):
    en_dir=Path(args.english_dir); sr_dir=Path(args.draft_dir)
    out_dir=Path(args.output_dir); state_dir=Path(args.state_dir)
    if not en_dir.is_dir():raise ValueError(f'Refined English folder missing: {en_dir}')
    if not sr_dir.is_dir():raise ValueError(f'Existing Serbian translation folder missing: {sr_dir}')
    if len({x.resolve() for x in (en_dir,sr_dir,out_dir,state_dir)})!=4:
        raise ValueError('Input, draft, output and state folders must differ')
    all_books=sorted(en_dir.glob('*.txt'))
    if args.book:all_books=[en_dir/args.book]
    if not all_books or any(not x.is_file() for x in all_books):raise ValueError('English book(s) not found')
    out_dir.mkdir(parents=True,exist_ok=True);state_dir.mkdir(parents=True,exist_ok=True)
    print(f'Books: {len(all_books)} | Model: {args.model} | Destination: {out_dir}',flush=True)
    for book in all_books:
        english,en_hash=read_lines(book)
        draft_path=match_draft(sr_dir,book.name)
        draft,sr_hash=read_lines(draft_path)
        if len(english)!=len(draft):
            raise ValueError(f'Line count mismatch {book.name}: English={len(english)}, Serbian={len(draft)}. No automatic re-alignment attempted.')
        fingerprint={'english_hash':en_hash,'draft_hash':sr_hash,'prompt':VERSION,'model':args.model,
            'max_tokens':args.max_tokens,'template_tag':args.template_tag,'max_lines':args.max_lines}
        run_id=hashlib.sha256(json.dumps(fingerprint,sort_keys=True).encode()).hexdigest()[:16]
        run=state_dir/book.stem/run_id;run.mkdir(parents=True,exist_ok=True)
        manifest=run/'manifest.json'
        if not manifest.exists():atomic(manifest,json.dumps({'book':book.name,'draft':draft_path.name,'total_lines':len(english),'settings':fingerprint},indent=2).encode('utf-8'))
        progress_path=run/'progress.jsonl';records=load_progress(progress_path)
        count=min(len(english),args.max_lines) if args.max_lines else len(english)
        print(f'\n{book.name}: {count}/{len(english)} lines; resumed {len(records)}',flush=True)
        for i in range(count):
            n=i+1
            if n in records:continue
            en=english[i][0];sr=draft[i][0]
            if not en.strip() and not sr.strip():row={'line':n,'original':sr,'proposed':sr,'applied':sr,'status':'unchanged','why':'blank_line'}
            else:
                try:
                    response,usage=call_llm(args,en,sr)
                    proposal=response['corrected'];applied,status,why=classify(en,sr,proposal,response['needs_review'])
                    row={'line':n,'original':sr,'english':en,'proposed':proposal,'applied':applied,'status':status,'why':why,
                        'model_reason':str(response.get('reason',''))[:500],'usage':usage}
                except Exception as exc:
                    row={'line':n,'original':sr,'english':en,'proposed':sr,'applied':sr,'status':'error','why':str(exc)[:500]}
            with progress_path.open('a',encoding='utf-8',newline='\n') as f:
                f.write(json.dumps(row,ensure_ascii=False)+'\n');f.flush();os.fsync(f.fileno())
            records[n]=row
            if n%20==0 or n==count:print(f'  completed {n}/{count}',flush=True)
        # For previews preserve rest of existing Serbian draft, matching physical line endings.
        output=''.join((records.get(i+1,{}).get('applied',d[0])+d[1]) for i,d in enumerate(draft)).encode('utf-8')
        verify=output.decode('utf-8').splitlines(keepends=True)
        if len(verify)!=len(draft):raise ValueError(f'Output line count differs for {book.name}')
        target=run/'preview'/book.name if args.max_lines else out_dir/book.name
        if not args.max_lines and len(records)!=len(english):raise ValueError('Incomplete run; refusing final output')
        atomic(target,output)
        review=run/'review.csv'
        with review.open('w',encoding='utf-8-sig',newline='') as f:
            w=csv.writer(f);w.writerow(['line','status','why','english','serbian_draft','proposal','applied','model_reason'])
            for i in sorted(records):
                x=records[i]
                if x['status'] in ('review','error'):w.writerow([i,x['status'],x['why'],x.get('english',english[i-1][0]),x['original'],x['proposed'],x['applied'],x.get('model_reason','')])
        stats={s:sum(r['status']==s for r in records.values()) for s in ['accepted','unchanged','review','error']}
        print(f'  output: {target}\n  review: {review}\n  results: {stats}',flush=True)
    print('Finished. Review flagged entries before model training.',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--english-dir',default=r'C:\llama.cpp\books\refined-en')
    p.add_argument('--draft-dir',default=r'C:\llama.cpp\books\translated')
    p.add_argument('--output-dir',default=r'C:\llama.cpp\books\refined-sr-latn')
    p.add_argument('--state-dir',default=r'C:\llama.cpp\books\translation-refinement-runs')
    p.add_argument('--url',default='http://127.0.0.1:8080')
    p.add_argument('--model',default='gemma-4-local')
    p.add_argument('--template-tag',default='single')
    p.add_argument('--book')
    p.add_argument('--max-lines',type=int,default=0)
    p.add_argument('--max-tokens',type=int,default=1500)
    p.add_argument('--timeout',type=int,default=180)
    p.add_argument('--retries',type=int,default=2)
    args=p.parse_args()
    try:process(args)
    except (ValueError,OSError) as exc:p.exit(1,f'ERROR: {exc}\n')

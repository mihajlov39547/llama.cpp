#!/usr/bin/env python3
"""Gemma 4 / llama.cpp: prompt-prefix cache and coding/tool-calling readiness (fixed v2).
Python 3.10+, standard library only. Runs an isolated server. Never modifies a project.
"""
import argparse, csv, datetime as dt, json, pathlib, re, socket, statistics, subprocess, sys, time, urllib.error, urllib.request

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--root',default=str(pathlib.Path(__file__).resolve().parent))
p.add_argument('--model',default='google_gemma-4-E2B-it-Q4_K_M.gguf')
p.add_argument('--context',type=int,default=49152)
p.add_argument('--prompt-tokens',type=int,default=16000,help='target total input tokens for caching experiment')
p.add_argument('--port',type=int,default=18084)
p.add_argument('--timeout',type=int,default=480)
p.add_argument('--minutes',type=int,default=75)
p.add_argument('--skip-cache',action='store_true')
p.add_argument('--skip-tools',action='store_true')
p.add_argument('--cache-mode',choices=['on','off','both'],default='both',help='independent server sessions for A/B comparison')
p.add_argument('--max-output',type=int,default=512)
a=p.parse_args()
root=pathlib.Path(a.root);exe=root/'bin'/'llama-server.exe';model=root/'models'/a.model
if not exe.is_file() or not model.is_file():sys.exit(f'Missing {exe} or {model}')
if a.context<4096 or a.prompt_tokens<1000 or a.prompt_tokens>a.context-a.max_output-512:sys.exit('Invalid context / prompt target: reserve output and chat-template room.')
run=root/'benchmark-results'/('opencode-readiness-'+dt.datetime.now().strftime('%Y%m%d-%H%M%S'));run.mkdir(parents=True,exist_ok=True)
log_run=root/'logs'/'benchmark-results'/run.name;log_run.mkdir(parents=True,exist_ok=True)
results=run/'requests.csv';events=log_run/'study.log';deadline=time.monotonic()+a.minutes*60
cols='timestamp,mode,scenario,round,request_tokens_est,prompt_tokens_reported,completion_tokens_reported,cached_tokens_reported,ttfe_s,ttfc_s,total_s,prefill_tps,decode_tps,finish_reason,correct,tool_calls,server_gpu_mib,server_gpu_temp_c,answer,error'.split(',')
with results.open('w',newline='',encoding='utf-8-sig') as f:csv.DictWriter(f,fieldnames=cols).writeheader()

def log(s):
 s=f'[{dt.datetime.now():%Y-%m-%d %H:%M:%S}] {s}';print(s,flush=True)
 with events.open('a',encoding='utf-8') as f:f.write(s+'\n')
def request(path,data=None,timeout=60):
 payload=None if data is None else json.dumps(data,ensure_ascii=False).encode('utf-8')
 r=urllib.request.Request(f'http://127.0.0.1:{a.port}{path}',data=payload,headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(r,timeout=timeout) as f:return json.load(f)
def available():
 try:
  with socket.create_connection(('127.0.0.1',a.port),timeout=1):return False
 except OSError:return True

def gpu():
 try:
  x=subprocess.run(['nvidia-smi','--query-gpu=memory.used,temperature.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=4)
  m,t=x.stdout.strip().splitlines()[0].split(',')[:2];return int(m),int(t)
 except Exception:return None,None

def count_tokens(s):return len(request('/tokenize',{'content':s},timeout=120)['tokens'])

def send(messages,mid,cache,tools=None,tool_choice=None,output=None,timeout=None):
 data={'model':mid,'messages':messages,'temperature':0,'seed':42,'stream':True,'max_tokens':output or a.max_output,'cache_prompt':bool(cache)}
 if tools is not None:data['tools']=tools;data['tool_choice']=tool_choice or 'auto'
 q=urllib.request.Request(f'http://127.0.0.1:{a.port}/v1/chat/completions',data=json.dumps(data,ensure_ascii=False).encode('utf-8'),headers={'Content-Type':'application/json','Accept':'text/event-stream'})
 start=time.perf_counter();first=None;visible=None;parts=[];funcs={};finish='';timings={};usage={};err='';done=False
 try:
  with urllib.request.urlopen(q,timeout=timeout or a.timeout) as r:
   for raw in r:
    elapsed=time.perf_counter()-start
    if elapsed>(timeout or a.timeout):raise TimeoutError('request wall-clock timeout')
    line=raw.decode('utf-8','replace').strip()
    if not line.startswith('data:'):continue
    d=line[5:].strip()
    if d=='[DONE]':done=True;break
    try:o=json.loads(d)
    except ValueError:continue
    if first is None:first=elapsed
    timings=o.get('timings') or timings;usage=o.get('usage') or usage
    for c in o.get('choices',[]):
     finish=c.get('finish_reason') or finish
     delta=c.get('delta') or {}
     v=delta.get('content') or ''
     if v:
      if visible is None:visible=elapsed
      parts.append(v)
     for tc in delta.get('tool_calls') or []:
      idx=tc.get('index',0)
      f=funcs.setdefault(idx,{'id':'','type':'function','function':{'name':'','arguments':''}})
      if tc.get('id'):f['id']=tc['id']
      fn=tc.get('function') or {}
      f['function']['name']+=fn.get('name') or ''
      f['function']['arguments']+=fn.get('arguments') or ''
 except Exception as e:err=f'{type(e).__name__}: {e}'
 total=time.perf_counter()-start
 details=usage.get('prompt_tokens_details') or {}
 return {'ttfe_s':round(first,3) if first is not None else '', 'ttfc_s':round(visible,3) if visible is not None else '',
   'total_s':round(total,3),'prefill_tps':timings.get('prompt_per_second',''),'decode_tps':timings.get('predicted_per_second',''),
   'prompt_tokens_reported':usage.get('prompt_tokens',timings.get('prompt_n','')),
   'completion_tokens_reported':usage.get('completion_tokens',timings.get('predicted_n','')),
   'cached_tokens_reported':details.get('cached_tokens',''),'finish_reason':finish,'answer':''.join(parts),
   'tool_calls':list(funcs.values()),'error':err,'done':done}

def save(mode,scenario,num,estimate,r,correct):
 mem,temp=gpu()
 row={'timestamp':dt.datetime.now().isoformat(),'mode':mode,'scenario':scenario,'round':num,'request_tokens_est':estimate,
  'correct':correct,'tool_calls':json.dumps(r['tool_calls'],ensure_ascii=False)[:1000],
  'server_gpu_mib':mem,'server_gpu_temp_c':temp,**{k:r[k] for k in ('prompt_tokens_reported','completion_tokens_reported','cached_tokens_reported','ttfe_s','ttfc_s','total_s','prefill_tps','decode_tps','finish_reason','error')},
  'answer':r['answer'][:1200].replace('\n','\\n')}
 with results.open('a',newline='',encoding='utf-8-sig') as f:csv.DictWriter(f,fieldnames=cols).writerow(row)
 log(f'{mode:4} {scenario:23} pass={correct!s:5} input={estimate:6} TTFC={r["ttfc_s"]}s total={r["total_s"]}s prefill={r["prefill_tps"]} cache={r["cached_tokens_reported"]} err={r["error"][:90]}')

def filler(target):
 paragraph='Technical repository note: validation must run before encryption; retry only transient network failures; paths are resolved relative to the repository root; log measurements separately from results. '
 # Avoid /tokenize with excessively large JSON responses.
 lo,hi=0,int(target*5)
 for _ in range(13):
  n=(lo+hi)//2
  s=(paragraph*((n//len(paragraph))+1))[:n]
  c=count_tokens(s)
  if c<target:lo=n+1
  else:hi=n
 s=(paragraph*((lo//len(paragraph))+1))[:lo]
 return s,count_tokens(s)

def start_server(cache):
 outf=(log_run/f'server-cache-{int(cache)}.stdout.log').open('w',encoding='utf-8')
 errf=(log_run/f'server-cache-{int(cache)}.stderr.log').open('w',encoding='utf-8')
 cmd=[str(exe),'-m',str(model),'--host','127.0.0.1','--port',str(a.port),'--no-webui','--gpu-layers','auto','--fit','on','--parallel','1','-t','4','-c',str(a.context),'-b','512','-ub','128','--cache-type-k','f16','--cache-type-v','f16','--reasoning','off','--reasoning-budget','0']
 proc=subprocess.Popen(cmd,cwd=str(exe.parent),stdout=outf,stderr=errf,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
 try:
  start=time.perf_counter()
  while time.perf_counter()-start<105:
   if proc.poll() is not None:raise RuntimeError('Server exited; inspect stderr log')
   try:
    h=request('/health',timeout=3)
    if h.get('status')=='ok':
     ctx=request('/props')['default_generation_settings']['n_ctx']
     if int(ctx)!=a.context:raise RuntimeError(f'Context mismatch {ctx}')
     mid=request('/v1/models')['data'][0]['id']
     log(f'Server ready cache={cache} context={ctx} startup={time.perf_counter()-start:.1f}s GPU={gpu()}')
     return proc,outf,errf,mid
   except (urllib.error.URLError,TimeoutError):pass
   time.sleep(1.5)
  raise TimeoutError('server startup timeout')
 except BaseException:
  proc.terminate();proc.wait(timeout=20);outf.close();errf.close();raise

def stop_server(proc,outf,errf):
 if proc.poll() is None:
  proc.terminate()
  try:proc.wait(timeout=15)
  except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=10)
 outf.close();errf.close();time.sleep(3)

TOOL=[{'type':'function','function':{'name':'read_file','description':'Read an allowed project file by its exact relative path','parameters':{'type':'object','properties':{'path':{'type':'string'}},'required':['path']}}}]
FILES={
 'src/discount.ps1':'function Get-Discount { param([decimal]$Total) if ($Total -gt 100) { return 0.10 } return 0 }',
 'tests/discount.tests.ps1':'It "applies at boundary" { (Get-Discount -Total 100) | Should -Be 0.10 }'
}

def check_tool(r,name,path):
 for t in r['tool_calls']:
  if t.get('function',{}).get('name')!=name:continue
  try:
   arg=json.loads(t['function']['arguments'])
   if arg.get('path')==path:return t
  except ValueError:pass
 return None

def tools_study(mid,mode,cache):
 msgs=[{'role':'system','content':'You are a coding assistant. Use read_file when asked to examine repository files. Never invent file content. Do not modify files.'},
       {'role':'user','content':'Read src/discount.ps1 using the read_file tool, then inspect the threshold comparison.'}]
 r=send(msgs,mid,cache,tools=TOOL,output=128)
 t=check_tool(r,'read_file','src/discount.ps1')
 save(mode,'tool-call-file-read',1,count_tokens(msgs[-1]['content']),r,bool(t))
 if not t:return
 msgs.append({'role':'assistant','tool_calls':[t]})
 msgs.append({'role':'tool','tool_call_id':t['id'],'name':'read_file','content':FILES['src/discount.ps1']})
 msgs.append({'role':'user','content':'Read tests/discount.tests.ps1 using read_file before proposing any fix.'})
 r2=send(msgs,mid,cache,tools=TOOL,output=128)
 t2=check_tool(r2,'read_file','tests/discount.tests.ps1')
 save(mode,'tool-call-test-read',1,sum(count_tokens(m.get('content','')) for m in msgs),r2,bool(t2))
 if not t2:return
 msgs.append({'role':'assistant','tool_calls':[t2]})
 msgs.append({'role':'tool','tool_call_id':t2['id'],'name':'read_file','content':FILES['tests/discount.tests.ps1']})
 msgs.append({'role':'user','content':'Answer in ONE LINE: what exact PowerShell operator should replace -gt to pass the boundary test? No tool needed.'})
 r3=send(msgs,mid,cache,tools=TOOL,output=100)
 save(mode,'tool-reason-correct-fix',1,sum(count_tokens(m.get('content','')) for m in msgs),r3,bool(re.search(r'(?<!\w)-ge(?!\w)',r3['answer'])))

def cache_study(mid,mode,cache):
 # Shared stable prefix with four scenarios; compare independent cache-enabled/disabled servers.
 static,n=filler(a.prompt_tokens-500)
 system='You are a software engineering auditor. Answer with the exact requested label and nothing else.'
 mark='\nAUDIT ENTRY: validated key is ORBIT-7321.\n'
 base=static+mark
 tests=[('cold','Question: What is the validated key?',base),
        ('exact-repeat','Question: What is the validated key?',base),
        ('append-new-question','Question: Repeat the validated key exactly.',base),
        ('change-middle','Question: What is the validated key?',base[:len(base)//2]+' EDITED CHECKPOINT '+base[len(base)//2:]),
        ('change-early','Question: What is the validated key?', 'EARLY EDIT '+base),
        ('return-baseline','Question: What is the validated key?',base)]
 for i,(scenario,question,document) in enumerate(tests,1):
  if time.monotonic()>deadline:break
  msgs=[{'role':'system','content':system},{'role':'user','content':document+'\n'+question}]
  r=send(msgs,mid,cache,output=48)
  save(mode,scenario,i,n+count_tokens(question),r,('ORBIT-7321' in r['answer']))

if not available():sys.exit(f'Port {a.port} already occupied. Choose another --port.')
log(f'Output: {run}; context={a.context}; cache mode={a.cache_mode}; requested prompt~{a.prompt_tokens}')
modes=[('off',False),('on',True)] if a.cache_mode=='both' else [(a.cache_mode,a.cache_mode=='on')]
for mode,cache in modes:
 if time.monotonic()>deadline:break
 proc=outf=errf=None
 try:
  proc,outf,errf,mid=start_server(cache)
  warm=send([{'role':'user','content':'Reply exactly READY.'}],mid,cache,output=24,timeout=60)
  save(mode,'warmup',0,8,warm,'READY' in warm['answer'])
  if not a.skip_cache and time.monotonic()<deadline:cache_study(mid,mode,cache)
  if not a.skip_tools and time.monotonic()<deadline:tools_study(mid,mode,cache)
 except Exception as e:log(f'FAILED {mode}: {type(e).__name__}: {e}')
 finally:
  if proc is not None:stop_server(proc,outf,errf)
with results.open(encoding='utf-8-sig') as f:rows=list(csv.DictReader(f))
summary=run/'summary.csv'
with summary.open('w',encoding='utf-8-sig',newline='') as f:
 cols2=['mode','scenario','count','success','median_ttfc_s','median_total_s','median_prefill_tps']
 w=csv.DictWriter(f,fieldnames=cols2);w.writeheader()
 for mode in dict.fromkeys(x['mode'] for x in rows):
  for scenario in dict.fromkeys(x['scenario'] for x in rows if x['mode']==mode):
   subset=[x for x in rows if x['mode']==mode and x['scenario']==scenario]
   def med(key):
    vals=[float(x[key]) for x in subset if x[key] not in ('',None)]
    return round(statistics.median(vals),3) if vals else ''
   w.writerow({'mode':mode,'scenario':scenario,'count':len(subset),'success':sum(x['correct']=='True' for x in subset),'median_ttfc_s':med('ttfc_s'),'median_total_s':med('total_s'),'median_prefill_tps':med('prefill_tps')})
log(f'Finished. Results: {results} and {summary}')

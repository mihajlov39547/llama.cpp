#!/usr/bin/env python3
"""Reproducible Gemma 4 llama.cpp long-context study. Python standard library only.
Windows: python llama-context-study.py --minutes 90
"""
import argparse,csv,json,os,subprocess,sys,time,datetime,urllib.request,urllib.error,threading,statistics,random,pathlib,signal

P=argparse.ArgumentParser(description='llama.cpp long-context: streaming TTFT, prefill, memory and recall')
P.add_argument('--root',default=str(pathlib.Path(__file__).resolve().parent))
P.add_argument('--model',default='google_gemma-4-E2B-it-Q4_K_M.gguf')
P.add_argument('--contexts',default='4096,8192,16384,32768',help='Comma separated contexts; optionally add 65536')
P.add_argument('--port',type=int,default=18083)
P.add_argument('--minutes',type=int,default=90)
P.add_argument('--repeats',type=int,default=1)
P.add_argument('--timeout',type=int,default=540,help='Per HTTP request limit in seconds')
P.add_argument('--temp-limit',type=int,default=85)
P.add_argument('--output-tokens',type=int,default=256)
args=P.parse_args()
root=pathlib.Path(args.root); executable=root/'bin'/'llama-server.exe'; model=root/'models'/args.model
if not executable.exists() or not model.exists():sys.exit(f'Missing executable or GGUF: {executable} | {model}')
contexts=sorted(set(int(x.strip()) for x in args.contexts.split(',') if x.strip()))
if not contexts or min(contexts)<512 or max(contexts)>131072:sys.exit('Invalid contexts; use 512..131072')
if args.repeats<1 or args.minutes<1:sys.exit('repeats and minutes must be positive')
base=f'http://127.0.0.1:{args.port}'
try:
 urllib.request.urlopen(base+'/health',timeout=1)
 sys.exit(f'Port {args.port} already has an HTTP service. Choose another port.')
except urllib.error.HTTPError:sys.exit(f'Port {args.port} already serves HTTP. Choose another port.')
except urllib.error.URLError:pass
run=root/'benchmark-results'/('context-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'));run.mkdir(parents=True)
log_file=run/'study.log';csv_file=run/'measurements.csv';summary_file=run/'summary.csv';deadline=time.monotonic()+args.minutes*60
fields=['timestamp','context_requested','context_effective','target_tokens','actual_prompt_tokens','input_fill_ratio','task','position','round','startup_s','http_ok','answer_correct','finish_reason','ttfe_s','ttfc_s','total_s','prefill_tps','decode_tps','prompt_tokens_reported','completion_tokens_reported','gpu_before_mib','gpu_peak_mib','gpu_temp_peak_c','error','answer']
with csv_file.open('w',newline='',encoding='utf-8-sig') as f:csv.DictWriter(f,fieldnames=fields).writeheader()

def log(x):
 s=f'[{datetime.datetime.now():%Y-%m-%d %H:%M:%S}] {x}';print(s,flush=True)
 with log_file.open('a',encoding='utf-8') as f:f.write(s+'\n')
def call(url,data=None,timeout=30):
 req=urllib.request.Request(base+url,data=None if data is None else json.dumps(data,ensure_ascii=False).encode('utf-8'),headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=timeout) as r:return json.load(r)
def gpu():
 try:
  x=subprocess.run(['nvidia-smi','--query-gpu=memory.used,temperature.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=5)
  a=x.stdout.strip().splitlines()[0].split(',');return int(a[0]),int(a[1])
 except Exception:return None,None
class Sampler:
 def __init__(self):self.stop_event=threading.Event();self.maxmem=None;self.maxtemp=None
 def start(self):
  def work():
   while not self.stop_event.is_set():
    mem,temp=gpu()
    if mem is not None:self.maxmem=max(self.maxmem or 0,mem)
    if temp is not None:self.maxtemp=max(self.maxtemp or 0,temp)
    self.stop_event.wait(1.0)
  self.t=threading.Thread(target=work,daemon=True);self.t.start()
 def stop(self):self.stop_event.set();self.t.join(timeout=3)

def tokenize(text):return len(call('/tokenize',{'content':text},timeout=120)['tokens'])
# Stable filler paragraphs. A unique marker can be placed in the beginning/middle/end.
fragments=[
 'Notebook entry on profiling local inference: measure preprocessing, token generation, and peak allocated memory independently. Benchmark only one request at a time, and record exact hardware and software versions. ',
 'Engineering memo: the data pipeline applies input validation, model tokenization, scheduler admission, prefill, then autoregressive decoding. Warm up kernels before measuring the model. ',
 'Quality checklist: compare matched requests, preserve raw timings, monitor GPU memory and temperatures, and never confuse the maximum configured context with a verified useful context. ',
 'Technical note: CPU RAM and GPU VRAM are distinct resources. A model can offload transformer blocks while retaining selected tensors mapped in system memory. '
]
# Chunks vary to reduce risk of artificially easy identical repeated blocks.
rng=random.Random(97314)
filler='\n'.join((f'Entry {i:05d}: '+fragments[(i*3+rng.randrange(4))%4]) for i in range(1400))

def make_prompt(ctx,position):
 # target ~85% of window leaves room for chat template and output
 target=int(ctx*0.85)
 code=f'{(ctx*7919+sum(map(ord,position))*131)%90000000+10000000:08d}'
 needle=f'IMPORTANT AUDIT RECORD: The secret verification code for this document is {code}. This is the only audit record.\n'
 ending='\nQUESTION: What is the exact eight-digit secret verification code in the audit record? Reply with ONLY the eight digits, no explanation.'
 # A calibrated base filler size then binary search on character length; exact count comes from /tokenize.
 low,high=0,min(len(filler),max(2000,target*9))
 for _ in range(11):
  size=(low+high)//2
  part=filler[:size]
  cut=int(len(part)*({'begin':0.0,'middle':0.50,'end':1.0}[position]))
  prompt=part[:cut]+'\n'+needle+part[cut:]+ending
  count=tokenize(prompt)
  if count<=target:low=size
  else:high=size
 size=low;part=filler[:size];cut=int(len(part)*({'begin':0.0,'middle':0.5,'end':1.0}[position]));prompt=part[:cut]+'\n'+needle+part[cut:]+ending
 return prompt,code,tokenize(prompt),target

# Coding task: a real PowerShell boundary-condition bug, buried in a large document.
# The model must inspect code, not merely repeat a numeric marker.
def make_coding_prompt(ctx):
 target=int(ctx*0.80)
 snippet = """
### PowerShell review target: Get-BulkDiscount
```powershell
function Get-BulkDiscount {
    param([decimal]$Total, [decimal]$Threshold = 100)
    if ($Total -gt $Threshold) {
        return [decimal]0.10
    }
    return [decimal]0
}
```
Business requirement: a 10% discount applies WHEN Total IS GREATER THAN OR EQUAL TO Threshold.
The script incorrectly rejects the exact-boundary case. The comparison operator is the bug.
"""
 ending='\nREVIEW TASK: For Get-BulkDiscount, what PowerShell comparison operator must replace the incorrect operator to fix the exact-threshold bug? Reply with ONLY the replacement operator (including the hyphen), nothing else.'
 low,high=0,min(len(filler),max(2000,target*9))
 for _ in range(12):
  size=(low+high)//2; part=filler[:size]; cut=len(part)//2
  prompt=part[:cut]+snippet+part[cut:]+ending
  count=tokenize(prompt)
  if count<=target:low=size
  else:high=size
 part=filler[:low];cut=len(part)//2
 prompt=part[:cut]+snippet+part[cut:]+ending
 return prompt,'-ge',tokenize(prompt),target

def stream_chat(prompt,model_id,expected,timeout):
 payload={'model':model_id,'messages':[{'role':'user','content':prompt}],'temperature':0,'seed':42,'stream':True,'cache_prompt':False,'max_tokens':args.output_tokens}
 req=urllib.request.Request(base+'/v1/chat/completions',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json','Accept':'text/event-stream'})
 start=time.perf_counter();first_event=None;first_visible=None;answer=[];finish='';timings={};usage={};error='';ok=False
 try:
  with urllib.request.urlopen(req,timeout=timeout) as resp:
   for raw in resp:
    if time.perf_counter()-start>timeout:raise TimeoutError('overall request timeout')
    line=raw.decode('utf-8',errors='replace').strip()
    if not line.startswith('data:'):continue
    event=line[5:].strip()
    if event=='[DONE]':ok=True;break
    try:obj=json.loads(event)
    except Exception:continue
    if first_event is None:first_event=time.perf_counter()-start
    timings=obj.get('timings',timings) or timings;usage=obj.get('usage',usage) or usage
    for c in obj.get('choices',[]):
     if c.get('finish_reason'):finish=c['finish_reason']
     delta=c.get('delta') or {};piece=delta.get('content') or ''
     if piece:
      if first_visible is None:first_visible=time.perf_counter()-start
      answer.append(piece)
  total=time.perf_counter()-start
 except Exception as e:
  total=time.perf_counter()-start;error=str(e)
 text=''.join(answer).strip();correct=(text==expected)
 return dict(http_ok=ok,answer_correct=correct,finish_reason=finish,ttfe_s=first_event,ttfc_s=first_visible,total_s=total,prefill_tps=timings.get('prompt_per_second'),decode_tps=timings.get('predicted_per_second'),prompt_tokens_reported=usage.get('prompt_tokens') or timings.get('prompt_n'),completion_tokens_reported=usage.get('completion_tokens') or timings.get('predicted_n'),error=error,answer=text[:160])

def save(row):
 with csv_file.open('a',newline='',encoding='utf-8-sig') as f:csv.DictWriter(f,fieldnames=fields).writerow(row)

def summarize():
 with csv_file.open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
 groups={}
 for r in rows:
  if r['position']=='warmup':continue
  key=r['context_requested'];groups.setdefault(key,[]).append(r)
 fields2=['context','tests','valid_responses','correct','median_fill_ratio','median_ttfc_s','median_total_s','median_prefill_tps','median_decode_tps','max_gpu_peak_mib','max_temp_c']
 def med(rs,k):
  vals=[float(r[k]) for r in rs if r[k] not in ('',None)]
  return round(statistics.median(vals),3) if vals else ''
 with summary_file.open('w',newline='',encoding='utf-8-sig') as f:
  w=csv.DictWriter(f,fieldnames=fields2);w.writeheader()
  for context,rs in sorted(groups.items(),key=lambda p:int(p[0])):
   w.writerow(dict(context=context,tests=len(rs),valid_responses=sum(r['http_ok']=='True' and r['finish_reason']=='stop' for r in rs),correct=sum(r['answer_correct']=='True' for r in rs),median_fill_ratio=med(rs,'input_fill_ratio'),median_ttfc_s=med(rs,'ttfc_s'),median_total_s=med(rs,'total_s'),median_prefill_tps=med(rs,'prefill_tps'),median_decode_tps=med(rs,'decode_tps'),max_gpu_peak_mib=max((int(r['gpu_peak_mib']) for r in rs if r['gpu_peak_mib']),default=''),max_temp_c=max((int(r['gpu_temp_peak_c']) for r in rs if r['gpu_temp_peak_c']),default='')))

log(f'Study output: {run} | contexts={contexts} | minutes={args.minutes}')
for ctx in contexts:
 if time.monotonic()>deadline:break
 proc=None;start=time.perf_counter();startup=None
 out=(run/f'server-{ctx}.stdout.log').open('w',encoding='utf-8');err=(run/f'server-{ctx}.stderr.log').open('w',encoding='utf-8')
 command=[str(executable),'-m',str(model),'--host','127.0.0.1','--port',str(args.port),'--no-webui','--gpu-layers','auto','--fit','on','--parallel','1','-t','4','-c',str(ctx),'-b','512','-ub','128','--cache-type-k','f16','--cache-type-v','f16','--reasoning','off','--reasoning-budget','0']
 try:
  current_mem,current_temp=gpu()
  if current_temp is not None and current_temp>=args.temp_limit:raise RuntimeError('GPU too hot before starting next context')
  log(f'Starting context={ctx}')
  proc=subprocess.Popen(command,cwd=str(root/'bin'),stdout=out,stderr=err,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
  ready=False
  for _ in range(90):
   if proc.poll() is not None:break
   if time.monotonic()>deadline:break
   try:
    status=call('/health',timeout=2)
    if status.get('status')=='ok':ready=True;break
   except Exception:pass
   time.sleep(2)
  startup=round(time.perf_counter()-start,3)
  if not ready:
   log(f'FAILED start context={ctx}; examine server-{ctx}.stderr.log');continue
  props=call('/props');effective=props.get('default_generation_settings',{}).get('n_ctx')
  models=call('/v1/models');model_id=models['data'][0]['id']
  log(f'Ready ctx={ctx}, actual={effective}, startup={startup}s, gpu={gpu()}')
  if int(effective)!=ctx:log(f'WARNING actual context differs: {effective} != {ctx}')
  # One short warmup; then real long context retrieval from three placements.
  tests=[('warmup','Reply with the exact word READY.','READY',0,0,'warmup')]
  for pos in ('begin','middle','end'):
   if time.monotonic()>deadline:break
   prompt,code,count,target=make_prompt(ctx,pos)
   tests.append((pos,prompt,code,count,target,'recall'))
  if time.monotonic() < deadline:
   code_prompt,fix,count,target=make_coding_prompt(ctx)
   tests.append(('code-middle',code_prompt,fix,count,target,'code-review'))
  for r in range(1,args.repeats+1):
   for pos,prompt,expected,count,target,task in tests:
    if time.monotonic()>deadline:break
    before,_=gpu();sampler=Sampler();sampler.start()
    try:result=stream_chat(prompt,model_id,expected,args.timeout)
    finally:sampler.stop()
    row={**dict(timestamp=datetime.datetime.now().isoformat(),context_requested=ctx,context_effective=effective,target_tokens=target,actual_prompt_tokens=count,input_fill_ratio=float(f"{count/ctx:.4f}"),task=task,position=pos,round=r,startup_s=startup,gpu_before_mib=before,gpu_peak_mib=sampler.maxmem,gpu_temp_peak_c=sampler.maxtemp),**result}
    save(row)
    if pos != 'warmup' and count < ctx*0.70: log(f'WARNING underfilled context: requested={ctx}, actual prompt={count} tokens ({count/ctx:.1%})')
    log(f'{ctx:>6} {pos:<12} tokens={count:>6} fill={count/ctx:.1%} correct={result["answer_correct"]} TTFC={result["ttfc_s"]}s total={result["total_s"]:.1f}s prefill={result["prefill_tps"]}t/s VRAM={sampler.maxmem}MiB temp={sampler.maxtemp}C finish={result["finish_reason"]}')
    if sampler.maxtemp is not None and sampler.maxtemp>=args.temp_limit:raise RuntimeError('GPU temperature limit reached')
    summarize()
 finally:
  if proc and proc.poll() is None:
   proc.terminate()
   try:proc.wait(timeout=10)
   except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=5)
  out.close();err.close()
  time.sleep(2)
summarize()
log(f'Complete. CSV: {csv_file} | summary: {summary_file}')

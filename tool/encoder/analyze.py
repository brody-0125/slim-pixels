from pathlib import Path
import collections,statistics as st,json,sys,hashlib
root=Path(__file__).resolve().parent
results=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root/'results'
def header(path):
 b=path.read_bytes();assert b[:2]==b'\xff\xd8'
 pos=2;out=dict(dqt={},dht={},markers=[])
 while pos<len(b):
  assert b[pos]==255
  while b[pos]==255:pos+=1
  mark=b[pos];pos+=1
  if mark==0xda:break
  n=int.from_bytes(b[pos:pos+2],'big');d=b[pos+2:pos+n];pos+=n
  out['markers'].append(hex(mark))
  if mark in (0xc0,0xc1,0xc2):out['sof']=dict(marker=mark,precision=d[0],height=int.from_bytes(d[1:3],'big'),width=int.from_bytes(d[3:5],'big'),components=[list(d[i:i+3]) for i in range(6,len(d),3)])
  elif mark==0xdb:
   i=0
   while i<len(d):
    tag=d[i];size=64*(2 if tag>>4 else 1);out['dqt'][str(tag)]=d[i+1:i+1+size].hex();i+=1+size
  elif mark==0xc4:
   i=0
   while i<len(d):
    tag=d[i];counts=d[i+1:i+17];size=sum(counts);out['dht'][str(tag)]=d[i+1:i+17+size].hex();i+=17+size
 return out

summaries=[]
for p in sorted(results.glob('trial-*.jsonl')):
 rows=[json.loads(s) for s in p.read_text().splitlines()]
 assert len(rows)==4620,len(rows)
 groups=collections.defaultdict(list)
 for r in rows:
  if r['type']=='time':groups[(r['stage'],r['bound'],r['quality'],r['file'],r['mode'])].append(r['ms'])
 assert all(len(v)==7 for v in groups.values())
 comparisons=[]
 for stage,bound,q in [('encode',b,q) for b in [512,1600] for q in [75,90,95]]+[('pipeline',1600,90)]:
  for mode in ['aa','turbo','turbo_opt']:
   cases=[]
   for(s,b,quality,f,m),v in groups.items():
    if(s,b,quality,m)==(stage,bound,q,mode):
     base=st.median(groups[(s,b,quality,f,'baseline')]);candidate=st.median(v)
     cases.append(dict(file=f,baseline_ms=base,candidate_ms=candidate,speedup=base/candidate))
   comparisons.append(dict(stage=stage,bound=bound,quality=q,mode=mode,median_speedup=st.median(c['speedup'] for c in cases),cases=cases))
 quality=[];lookup={(r['file'],r['bound'],r['quality'],r['mode']):r for r in rows if r['type']=='quality'}
 for(f,b,q,m),r in lookup.items():
  if m=='aa':assert r['encoded_exact']
  if m not in ['turbo','turbo_opt']:continue
  base=lookup[(f,b,q,'baseline')];assert(base['width'],base['height'])==(r['width'],r['height'])
  delta=r['raw_error']['psnr']-base['raw_error']['psnr'] if r['raw_error']['psnr'] is not None and base['raw_error']['psnr'] is not None else None
  ratio=r['bytes']/base['bytes'];size_pass=ratio<=1.02
  psnr_pass=(r['raw_error']['psnr'] is None) if base['raw_error']['psnr'] is None else (delta is None or delta>=-.2)
  quality.append(dict(mode=m,file=f,bound=b,quality=q,bytes_ratio=ratio,baseline_psnr=base['raw_error']['psnr'],turbo_psnr=r['raw_error']['psnr'],psnr_delta=delta,screen_pass=size_pass and psnr_pass,exact=r['encoded_exact'],baseline_decoded_error=r['baseline_error']))
 summaries.append(dict(trial=p.name,comparisons=comparisons,quality=quality))
assert len(summaries)==3
headers=[]
for r in summaries[0]['quality']:
 f,b,q=r['file'],r['bound'],r['quality'];prefix=f'{f}__{b}__q{q}__'
 a=header(root/'encoded'/(prefix+'baseline.jpg'));t=header(root/'encoded'/(prefix+r['mode']+'.jpg'))
 valid=a['sof']==t['sof'] and a['dqt']==t['dqt'] and (r['mode']=='turbo_opt' or a['dht']==t['dht'])
 assert a['sof']['marker']==192 and a['sof']['precision']==8
 assert all(c[1]==17 for c in a['sof']['components'])
 headers.append(dict(mode=r["mode"],file=f,bound=b,quality=q,matched=valid,baseline=a,turbo=t))
(results/'headers.json').write_text(json.dumps(headers,indent=2),encoding='utf8')
(results/'summary.json').write_text(json.dumps(summaries,indent=2),encoding='utf8')
print('Header gates',sum(r['matched'] for r in headers),'/',len(headers))
for s in summaries:
 print(s['trial'])
 for c in s['comparisons']:print(c['stage'],c['bound'],c['quality'],c['mode'],round(c['median_speedup'],3))
 print('quality pass',sum(r['screen_pass'] for r in s['quality']),'/',len(s['quality']))
 print('size ratio median',st.median(r['bytes_ratio'] for r in s['quality']))
 print('PSNR delta range',min(r['psnr_delta'] for r in s['quality'] if r['psnr_delta'] is not None),max(r['psnr_delta'] for r in s['quality'] if r['psnr_delta'] is not None))

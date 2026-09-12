"""Encoder screening; timing is reported and never used as a merge threshold."""
from pathlib import Path
import json,hashlib,subprocess,shutil,os,platform,datetime
root=Path(__file__).resolve().parent.parent
source=root/'tool/encoder';out=root/'build/quality'
out.mkdir(parents=True,exist_ok=True)
if (out/'results').exists():raise RuntimeError('Refusing to overwrite a previous quality run')
for name in ['corpus','manifest.json','analyze.py']:
    src=source/name
    if src.is_dir():shutil.copytree(src,out/name)
    else:shutil.copyfile(src,out/name)
(out/'results').mkdir()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for row in json.loads((source/'manifest.json').read_text()):
    assert sha(out/'corpus'/row['file'])==row['sha256']
for name,expected in json.loads((root/'test/golden/SHA256SUMS.json').read_text()).items():
    assert sha(root/'test/golden'/name)==expected, name
lib=root/'native/bin/linux-x64'
os.environ['LD_LIBRARY_PATH']=str(lib)
os.environ['LIBRARY_PATH']=str(lib)
(lib/'libturbojpeg.so').symlink_to('libturbojpeg.so.0') if not (lib/'libturbojpeg.so').exists() else None
target=root/'build/encoder-target'
subprocess.run(['cargo','+1.97.1','build','--release','--locked','--manifest-path',str(source/'Cargo.toml'),'--target-dir',str(target)],check=True)
os.environ['RAYON_NUM_THREADS']='1';os.environ.pop('JSIMD_FORCENONE',None)
if hasattr(os,'sched_setaffinity'):os.sched_setaffinity(0,{min(os.sched_getaffinity(0))})
meta={'started':datetime.datetime.now(datetime.timezone.utc).isoformat(),'platform':platform.platform(),'cpu':Path('/proc/cpuinfo').read_text(),'affinity':list(os.sched_getaffinity(0)),'performance_policy':'report-only','binary_sha256':sha(target/'release/encoder_validation')}
for trial in range(1,4):
    subprocess.run([str(target/'release/encoder_validation'),str(out),str(out/f'results/trial-{trial}.jsonl'),str(trial)],check=True)
subprocess.run(['python3',str(out/'analyze.py')],check=True)
ref=json.loads((source/'reference.json').read_text())
assert len(ref['raw_checks'])==42 and len(ref['cross_checks'])==378
for row in ref['raw_checks']:assert sha(out/'raw'/row['file'])==row['sha256'],row['file']
for row in ref['cross_checks']:assert sha(out/'encoded'/row['file'])==row['windows_sha256'],row['file']
summaries=json.loads((out/'results/summary.json').read_text())
assert len(summaries)==3
for trial in summaries:
    q90=[q for q in trial['quality'] if q['quality']==90 and q['mode']=='turbo_opt']
    assert len(q90)==42 and all(q['screen_pass'] for q in q90),'Q90 quality/size gate failed'
headers=json.loads((out/'results/headers.json').read_text())
assert len(headers)==252 and all(row['matched'] for row in headers)
meta['completed']=datetime.datetime.now(datetime.timezone.utc).isoformat()
(out/'results/environment.json').write_text(json.dumps(meta,indent=2))
print('PASS: corpus hashes, 42 raw / 378 JPEG reference hashes, 3 x 42 Q90 quality gates, header gates. Timings report-only.')

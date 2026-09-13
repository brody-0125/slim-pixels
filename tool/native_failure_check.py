"""Linux-only fault injection through isolated, hash-verified native bundles."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile

if sys.platform != 'linux':
    raise SystemExit('Run on Linux with gcc and a Dart SDK')
root = Path(__file__).resolve().parents[1]
dart = sys.argv[1] if len(sys.argv) > 1 else 'dart'
common = """#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
static int live;
void slim_free(uint8_t *p, size_t n) { if(p) {live--;free(p);} }
"""
run = """int32_t slim_transform(const uint8_t *p,size_t n,const uint8_t *j,size_t k,
 uint8_t **out,size_t *len,uint32_t *w,uint32_t *h,uint32_t *fmt,int32_t *op) {
 *out=NULL;*len=0;*w=1;*h=1;*fmt=2;*op=-1;
 if(live) return 10;
 BODY
}
"""
cases = {
 'old_abi': ('incompatibleNative', common + 'uint32_t slim_abi_version(void){return 1;}'),
 'missing_symbol': ('nativeUnavailable', common + 'uint32_t slim_abi_version(void){return 2;}'),
 'bad_metadata': ('internalFailure', common + 'uint32_t slim_abi_version(void){return 2;}' + run.replace('BODY', '*out=malloc(1);live++;*len=1;*fmt=99;return 0;')),
 'bad_index': ('internalFailure', common + 'uint32_t slim_abi_version(void){return 2;}' + run.replace('BODY', '*op=99;return 6;')),
 'encode_failure': ('encodeFailed', common + 'uint32_t slim_abi_version(void){return 2;}' + run.replace('BODY', 'return 10;')),
 'invalid_binary': ('nativeUnavailable', None),
}
with tempfile.TemporaryDirectory(prefix='slim-fault-') as temp:
    workspace = Path(temp)
    package = workspace / 'package'
    package.mkdir()
    for name in ['lib', 'hook']:
        shutil.copytree(root / name, package / name)
    shutil.copy2(root / 'pubspec.yaml', package / 'pubspec.yaml')
    bundle = package / 'native/bin/linux-x64'
    bundle.mkdir(parents=True)
    shutil.copy2(root / 'native/bin/linux-x64/libturbojpeg.so.0', bundle)
    app = workspace / 'app'
    app.mkdir()
    (app / 'pubspec.yaml').write_text("name: fault_consumer\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\ndependencies:\n  slim_pixels:\n    path: ../package\n")
    (app / 'main.dart').write_text("""import 'dart:typed_data';
import 'package:slim_pixels/slim_pixels.dart';
void main(List<String> args) {
  for (var i = 0; i < 2; i++) {
    try {
      SlimPixels().transformSync(Uint8List.fromList([1]), encoding: const PngEncoding());
      throw StateError('Expected a typed failure');
    } on SlimPixelsException catch (e) {
      if (e.code.name != args.single || e.operationIndex != null) {
        throw StateError('Unexpected public failure: $e');
      }
    }
  }
  print('PASS: ${args.single}');
}
""")
    subprocess.run([dart, 'pub', 'get'], cwd=app, check=True)
    library = bundle / 'libslim_pixels.so'
    for label, (expected, code) in cases.items():
        if code is None:
            library.write_bytes(b'invalid native binary')
        else:
            source = workspace / 'fake.c'
            source.write_text(code)
            subprocess.run(['gcc', '-shared', '-fPIC', str(source), '-o', str(library)], check=True)
        hashes = {name: hashlib.sha256((bundle / name).read_bytes()).hexdigest()
                  for name in ['libslim_pixels.so', 'libturbojpeg.so.0']}
        (bundle / 'SHA256SUMS.json').write_text(json.dumps(hashes))
        subprocess.run([dart, 'run', 'main.dart', expected], cwd=app, check=True)
        print('Verified ' + label, flush=True)
print('PASS: six isolated native failure scenarios; malformed-result buffer released')

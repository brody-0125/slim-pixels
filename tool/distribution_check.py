"""Exercise a separate consumer and run only its relocated native app bundle."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
dart = shutil.which(sys.argv[1] if len(sys.argv) > 1 else 'dart')
if not dart:
    raise SystemExit('Dart executable not found')

def run(args, cwd, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)

with tempfile.TemporaryDirectory(prefix='slim consumer ') as temporary:
    workspace = Path(temporary)
    package = workspace / 'package'
    package.mkdir()
    for name in ('lib', 'hook', 'native/bin', 'third_party'):
        shutil.copytree(root / name, package / name)
    for name in ('pubspec.yaml', 'LICENSE', 'THIRD_PARTY_NOTICES.md'):
        shutil.copy2(root / name, package / name)
    app = workspace / 'app'
    (app / 'bin').mkdir(parents=True)
    (app / 'pubspec.yaml').write_text(
        "name: distribution_consumer\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\n"
        "dependencies:\n  slim_pixels:\n    path: ../package\n", encoding='utf-8')
    shutil.copy2(root / 'test/fixtures/rgb.png', app / 'input.png')
    shutil.copy2(root / 'test/fixtures/rgb-q90.jpg', app / 'expected.jpg')
    (app / 'bin/main.dart').write_text("""
import 'dart:io';
import 'package:slim_pixels/slim_pixels.dart';
void main() {
  final result = SlimPixels().transformSync(File('input.png').readAsBytesSync(),
    encoding: JpegEncoding()).bytes;
  final expected = File('expected.jpg').readAsBytesSync();
  if (result.length != expected.length) throw StateError('JPEG size differs');
  for (var i = 0; i < result.length; i++) {
    if (result[i] != expected[i]) throw StateError('JPEG byte differs at $i');
  }
  print('Bundled JPEG golden passed');
}
""", encoding='utf-8')
    run([dart, 'pub', 'get'], app)
    run([dart, 'run', 'bin/main.dart'], app)
    # Changing either the manifest or library must invalidate the hook cache.
    platform = 'windows-x64' if os.name == 'nt' else 'linux-x64'
    manifest = package / 'native/bin' / platform / 'SHA256SUMS.json'
    saved = manifest.read_bytes()
    manifest.write_text('{}', encoding='utf-8')
    rejected = subprocess.run([dart, 'run', 'bin/main.dart'], cwd=app,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if rejected.returncode == 0 or 'hash mismatch' not in rejected.stdout:
        raise RuntimeError('Corrupt manifest was not rejected: ' + rejected.stdout)
    manifest.write_bytes(saved)
    run([dart, 'build', 'cli', '--target=bin/main.dart', '--output=dist'], app)
    moved = workspace / 'relocated'
    shutil.move(str(app / 'dist/bundle'), moved)
    shutil.copy2(app / 'input.png', moved / 'input.png')
    shutil.copy2(app / 'expected.jpg', moved / 'expected.jpg')
    # Remove all source and hook caches: the executable must use its own bundle.
    shutil.rmtree(app)
    shutil.rmtree(package)
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    env.pop('LIBRARY_PATH', None)
    env['PATH'] = str(Path(os.environ.get('SystemRoot', 'C:/Windows')) / 'System32') if os.name == 'nt' else '/usr/bin:/bin'
    executables = list((moved / 'bin').iterdir())
    if len(executables) != 1:
        raise RuntimeError(f'Unexpected bundle executables: {executables}')
    run([str(executables[0])], moved, env)
print('Consumer JIT and relocated AOT bundle passed')

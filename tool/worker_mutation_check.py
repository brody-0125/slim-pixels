"""Require two selected worker regressions to fail their intended assertions."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
dart = sys.argv[1] if len(sys.argv) > 1 else 'dart'
with tempfile.TemporaryDirectory(prefix='slim-worker-mutations-') as temporary:
    package = Path(temporary)
    for name in ('lib', 'hook', 'native/bin', 'test'):
        shutil.copytree(root / name, package / name)
    for name in ('pubspec.yaml', 'pubspec.lock'):
        shutil.copy2(root / name, package / name)
    subprocess.run([dart, 'pub', 'get', '--enforce-lockfile'], cwd=package, check=True)
    source = package / 'lib/src/worker.dart'
    original = source.read_text(encoding='utf-8')
    cases = [
        ('control', None, None, None),
        ('count', '_queue.length + (_active == null ? 0 : 1) >= _maxRequests ||',
         'false ||', 'C1 request count limit not enforced'),
        ('fifo', '_queue.removeFirst()', '_queue.removeLast()', 'Q1 FIFO completion order differs'),
    ]
    for name, before, after, expected in cases:
        if before is not None and original.count(before) != 1:
            raise RuntimeError(f'{name}: mutation anchor must occur exactly once')
        source.write_text(original if before is None else original.replace(before, after), encoding='utf-8')
        result = subprocess.run([dart, 'run', 'test/worker.dart'], cwd=package,
                                capture_output=True, text=True, timeout=120)
        output = result.stdout + result.stderr
        if expected is None:
            if result.returncode != 0 or 'PASS:' not in output:
                raise RuntimeError('Control failed: ' + output)
        elif result.returncode == 0 or f'Bad state: {expected}' not in output:
            raise RuntimeError(f'{name}: did not fail the intended assertion: {output}')
        print(f'PASS: {name}' + (f' rejected by {expected}' if expected else ''), flush=True)

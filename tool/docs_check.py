"""Check repository documentation links and fail on dartdoc diagnostics."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
for doc in [*root.glob('*.md'), *root.glob('doc/*.md')]:
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', doc.read_text(encoding='utf-8')):
        if '://' in target or target.startswith('#'):
            continue
        relative = target.split('#', 1)[0]
        if not (doc.parent / relative).exists():
            raise RuntimeError(f'Broken local link in {doc.name}: {target}')
dart = sys.argv[1] if len(sys.argv) > 1 else 'dart'
result = subprocess.run([dart, 'doc', '--validate-links', '--output', 'build/api-doc'],
                        cwd=root, capture_output=True, text=True)
print(result.stdout)
print(result.stderr)
if result.returncode or not re.search(r'Found 0 warnings and 0 errors', result.stdout + result.stderr):
    raise RuntimeError('dartdoc did not report zero warnings and errors')
print('PASS: local documentation links and warning-free dartdoc')

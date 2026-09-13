"""Build and run an existing validation entry point with its code assets."""
from pathlib import Path
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
if source.is_absolute() or '..' in source.parts or not (root / source).is_file():
    raise SystemExit('Expected an existing package-relative Dart entry point')
wrapper = root / 'bin/slim_validation.dart'
if wrapper.exists():
    raise SystemExit('Temporary validation entry point already exists')
wrapper.parent.mkdir(exist_ok=True)
try:
    wrapper.write_text("import '../" + source.as_posix() + "' as validation;\n"
                       "Future<void> main(List<String> args) async { await Future<void>.sync(() => validation.main(args)); }\n", encoding='utf-8')
    output = root / 'build/aot' / source.stem
    subprocess.run(['dart', 'build', 'cli', '--target=bin/slim_validation.dart',
                    '--output=' + str(output)], cwd=root, check=True)
    exe = output / 'bundle/bin' / ('slim_validation.exe' if os.name == 'nt' else 'slim_validation')
    subprocess.run([str(exe), *sys.argv[2:]], cwd=root, check=True)
finally:
    wrapper.unlink(missing_ok=True)

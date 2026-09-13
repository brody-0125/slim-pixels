"""Assemble verified native release archives from the already-tested artifacts."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
version = re.search(r'^version: (.+)$', (root / 'pubspec.yaml').read_text(), re.M)[1]
if len(sys.argv) > 1 and sys.argv[1] != 'v' + version:
    raise SystemExit('Release tag must match pubspec version v' + version)
output = root / 'build/release'
output.mkdir(parents=True, exist_ok=True)
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
for platform in ('windows-x64', 'linux-x64'):
    bundle = root / 'native/bin' / platform
    hashes = json.loads((bundle / 'SHA256SUMS.json').read_text(encoding='utf-8-sig'))
    expected = {'slim_pixels.dll', 'turbojpeg.dll'} if platform == 'windows-x64' else {'libslim_pixels.so', 'libturbojpeg.so.0'}
    if set(hashes) != expected:
        raise SystemExit('Unexpected bundle files for ' + platform)
    for name, digest in hashes.items():
        if hashlib.sha256((bundle / name).read_bytes()).hexdigest() != digest:
            raise SystemExit('Native hash mismatch: ' + name)
    files = [bundle / name for name in sorted(expected)] + [bundle / 'SHA256SUMS.json', root / 'LICENSE', root / 'THIRD_PARTY_NOTICES.md']
    files += sorted(f for f in (root / 'third_party').rglob('*') if f.is_file())
    metadata = {'package_version': version, 'abi': 2, 'source_commit': commit,
                'platform': platform, 'sha256': hashes,
                'windows_codec_provenance': 'See THIRD_PARTY_NOTICES.md; original compiler flags are not recorded.'}
    archive = output / f'slim-pixels-{version}-{platform}.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for f in files:
            name = f.name if f.parent == bundle else f.relative_to(root).as_posix()
            z.write(f, name)
        z.writestr('BUILD.json', json.dumps(metadata, indent=2) + '\n')
    print(archive)
archives = sorted(output.glob(f'slim-pixels-{version}-*.zip'))
(output / 'SHA256SUMS').write_text(''.join(
    hashlib.sha256(f.read_bytes()).hexdigest() + '  ' + f.name + '\n' for f in archives), encoding='utf-8')

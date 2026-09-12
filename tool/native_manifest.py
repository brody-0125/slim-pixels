"""Record native bundle integrity after a successful source build."""
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
files = ('slim_pixels.dll', 'turbojpeg.dll') if root.name == 'windows-x64' else ('libslim_pixels.so', 'libturbojpeg.so.0')
hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files}
(root / 'SHA256SUMS.json').write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')

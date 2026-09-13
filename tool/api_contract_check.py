"""Analyze public consumer contracts, including intentionally invalid calls."""
from collections import Counter
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
dart = sys.argv[1] if len(sys.argv) > 1 else 'dart'
(root / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='api-contract-', dir=root / 'build') as temp:
    path = Path(temp)
    good = path / 'good.dart'
    good.write_text("""import 'dart:typed_data';
import 'package:slim_pixels/slim_pixels.dart';
ImageResult convert(Uint8List input) => SlimPixels().transformSync(input,
    operations: [Resize.cover(width: 2, height: 3), Rotate.clockwise90],
    encoding: const PngEncoding());
Future<ImageResult> convertAsync(Uint8List input) async {
  final worker = await SlimPixelsWorker.start(maxPendingRequests: 2);
  try { return await worker.transform(input, encoding: const PngEncoding()); }
  finally { await worker.close(); }
}
String name(ImageFormat format) => switch (format) {
  ImageFormat.png => 'png', _ => 'other',
};
""", encoding='utf-8')
    bad = path / 'bad.dart'
    bad.write_text("""import 'dart:typed_data';
import 'package:slim_pixels/slim_pixels.dart';
class CustomOperation implements ImageOperation {}
class CustomEncoding implements ImageEncoding {}
void invalid(Uint8List input) {
  SlimPixels().transformSync(input);
  SlimPixels().transformSync(input, operations: ['resize'], encoding: const PngEncoding());
  PngEncoding(quality: 90);
  Resize.exact(width: '2', height: 3);
  ImageResult(input, 1, 1, ImageFormat.png);
  SlimPixels('library');
  SlimPixels().transform(input, {});
}
String name(ImageFormat format) => switch (format) {
  ImageFormat.jpeg => 'jpeg', ImageFormat.png => 'png', ImageFormat.webp => 'webp',
};
""", encoding='utf-8')
    subprocess.run([dart, 'analyze', '--fatal-infos', str(good)], cwd=root, check=True)
    for readme in ('README.md', 'README.ko.md'):
        for index, snippet in enumerate(re.findall(r'```dart\n(.*?)```',
                (root / readme).read_text(encoding='utf-8'), re.S)):
            example = path / f'{Path(readme).stem.lower().replace('.', '_')}_{index}.dart'
            example.write_text(snippet, encoding='utf-8')
            subprocess.run([dart, 'analyze', '--fatal-infos', str(example)], cwd=root, check=True)

    result = subprocess.run([dart, 'analyze', '--format', 'machine', str(bad)], cwd=root,
                            capture_output=True, text=True)
    codes = Counter(line.split('|')[2] for line in (result.stdout + result.stderr).splitlines()
                    if line.startswith('ERROR|'))
    expected = Counter({'INVALID_USE_OF_TYPE_OUTSIDE_LIBRARY': 2,
        'MISSING_REQUIRED_ARGUMENT': 1, 'LIST_ELEMENT_TYPE_NOT_ASSIGNABLE': 1,
        'UNDEFINED_NAMED_PARAMETER': 1, 'ARGUMENT_TYPE_NOT_ASSIGNABLE': 1,
        'NEW_WITH_UNDEFINED_CONSTRUCTOR_DEFAULT': 1,
        'EXTRA_POSITIONAL_ARGUMENTS': 1, 'UNDEFINED_METHOD': 1,
        'NON_EXHAUSTIVE_SWITCH_EXPRESSION': 1})
    if result.returncode == 0 or codes != expected:
        raise RuntimeError(f'Unexpected diagnostics: {codes}\n{result.stdout}{result.stderr}')
print('PASS: public consumer, README examples, 10 intentional API contract errors')

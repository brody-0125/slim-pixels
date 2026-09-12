import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    if (code.targetArchitecture != Architecture.x64 ||
        (code.targetOS != OS.windows && code.targetOS != OS.linux)) {
      throw UnsupportedError('slim_pixels supports Windows/Linux x64 only.');
    }
    final windows = code.targetOS == OS.windows;
    final platform = windows ? 'windows-x64' : 'linux-x64';
    final directory =
        input.userDefines.path('native_directory') ??
        input.packageRoot.resolve('native/bin/$platform/');
    final root = Directory.fromUri(directory).uri;
    final manifest = File.fromUri(root.resolve('SHA256SUMS.json'));
    if (!manifest.existsSync()) {
      throw StateError(
        'Missing native bundle: ${manifest.path}. '
        'Build with tool/build.ps1 or tool/build-linux.sh first, '
        'or set hooks.user_defines.slim_pixels.native_directory.',
      );
    }
    output.dependencies.add(manifest.uri);
    final hashes =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final files = {
      'src/native_bindings.dart': windows
          ? 'slim_pixels.dll'
          : 'libslim_pixels.so',
      'src/codec_bindings.dart': windows
          ? 'turbojpeg.dll'
          : 'libturbojpeg.so.0',
    };
    for (final entry in files.entries) {
      final file = File.fromUri(root.resolve(entry.value));
      output.dependencies.add(file.uri);
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != hashes[entry.value]) {
        throw StateError('Native bundle hash mismatch: ${entry.value}');
      }
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: entry.key,
          linkMode: DynamicLoadingBundled(),
          file: file.uri,
        ),
      );
    }
  });
}

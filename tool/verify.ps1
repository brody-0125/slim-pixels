param([string]$Dart='dart')
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  & $Dart pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
  & $Dart format --output=none --set-exit-if-changed lib hook example test tool/validation
  if ($LASTEXITCODE -ne 0) { throw 'Dart formatting failed' }
  & $Dart analyze --fatal-infos
  if ($LASTEXITCODE -ne 0) { throw 'Dart analysis failed' }
  & $Dart run test/smoke.dart native/bin/windows-x64/slim_pixels.dll test/fixtures/rgb.png
  if ($LASTEXITCODE -ne 0) { throw 'FFI smoke test failed' }
  & $Dart run test/worker.dart
  if ($LASTEXITCODE -ne 0) { throw "Worker validation failed" }
} finally { Pop-Location }

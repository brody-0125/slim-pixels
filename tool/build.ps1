param([string]$Cargo='cargo', [string]$TargetDir='')
$ErrorActionPreference='Stop'
$packageRoot = Split-Path $PSScriptRoot -Parent
if (!$TargetDir) { $TargetDir = Join-Path $packageRoot 'native/target' }
$TargetDir = [IO.Path]::GetFullPath($TargetDir)
New-Item -ItemType Directory -Force "$TargetDir/release/deps" | Out-Null
$codec = Join-Path $packageRoot 'native/bin/windows-x64/turbojpeg.dll'
Copy-Item -LiteralPath $codec -Destination "$TargetDir/release/turbojpeg.dll"
Copy-Item -LiteralPath $codec -Destination "$TargetDir/release/deps/turbojpeg.dll"
& $Cargo +1.97.1 test --release --locked --lib --manifest-path "$packageRoot/native/Cargo.toml" --target-dir $TargetDir
if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed' }
& $Cargo +1.97.1 build --release --locked --lib --manifest-path "$packageRoot/native/Cargo.toml" --target-dir $TargetDir
if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
Copy-Item -LiteralPath "$TargetDir/release/slim_pixels.dll" -Destination "$packageRoot/native/bin/windows-x64/slim_pixels.dll"

$bundle = Join-Path $packageRoot 'native/bin/windows-x64'
$hashes = [ordered]@{}
foreach ($name in @('slim_pixels.dll', 'turbojpeg.dll')) {
  $hashes[$name] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bundle $name)).Hash.ToLowerInvariant()
}
$hashes | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $bundle 'SHA256SUMS.json')

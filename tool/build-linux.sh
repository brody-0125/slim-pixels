#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build/turbojpeg"
mkdir -p "$build"
if [ ! -d "$build/source" ]; then
  git clone --depth 1 --branch 3.2.0 https://github.com/libjpeg-turbo/libjpeg-turbo.git "$build/source"
fi
test "$(git -C "$build/source" rev-parse HEAD)" = c85e6b905bf237038faa936dab160ebfc5da0344
cmake -S "$build/source" -B "$build/target" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$build/install" -DENABLE_SHARED=ON -DENABLE_STATIC=OFF -DWITH_SIMD=ON
cmake --build "$build/target" --parallel 2
cmake --install "$build/target"
export LIBRARY_PATH="$build/install/lib:$build/install/lib64"
export LD_LIBRARY_PATH="$LIBRARY_PATH"
cargo +1.97.1 test --release --locked --lib --manifest-path "$root/native/Cargo.toml"
cargo +1.97.1 build --release --locked --lib --manifest-path "$root/native/Cargo.toml"
out="$root/native/bin/linux-x64"
mkdir -p "$out"
cp "$root/native/target/release/libslim_pixels.so" "$out/"
find "$build/install" -name 'libturbojpeg.so.0' -exec cp -L '{}' "$out/" \;

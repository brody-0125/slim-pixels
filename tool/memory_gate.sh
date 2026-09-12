#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/memory"
mkdir -p "$out"
export LD_LIBRARY_PATH="$root/native/bin/linux-x64"
gcc -g -O1 "$root/tool/memory_check.c" -L"$LD_LIBRARY_PATH" -lslim_pixels -o "$out/check"
valgrind --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=definite,indirect,possible --error-exitcode=99 --log-file="$out/valgrind.log" "$out/check" "$root/test/fixtures/rgb.png" | tee "$out/check.log"
grep -q 'in use at exit: 0 bytes in 0 blocks' "$out/valgrind.log"

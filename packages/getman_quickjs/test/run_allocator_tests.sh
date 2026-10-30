#!/usr/bin/env bash
# Compile the real allocator contract on POSIX hosts, including the MSVC layout.
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_build_dir="$(mktemp -d)"
trap 'rm -rf "$test_build_dir"' EXIT

for layout in native msvc; do
  flags=(-std=c11 -D_GNU_SOURCE)
  if [[ "$layout" == msvc ]]; then
    flags+=(-DGETMAN_TEST_MSVC_ALIGNMENT)
  fi
  "${CC:-cc}" "${flags[@]}" \
    -I "$package_dir/src" \
    "$package_dir/test/allocator_test.c" \
    "$package_dir/src/quickjs.c" \
    "$package_dir/src/libregexp.c" \
    "$package_dir/src/libunicode.c" \
    "$package_dir/src/dtoa.c" \
    -lm -o "$test_build_dir/allocator_$layout"
  "$test_build_dir/allocator_$layout"
  printf 'Allocator contract passed (%s layout)\n' "$layout"
done

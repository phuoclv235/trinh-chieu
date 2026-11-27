#!/usr/bin/env bash
# Chạy test TrinhChieuCore 3 lần (có đo độ phủ) rồi in độ phủ dòng của một thư mục nguồn.
#   scripts/coverage.sh [thư-mục-nguồn] [ngưỡng-phần-trăm]
# Mặc định: Sources/CoreModel/Show, ngưỡng 90. Dưới ngưỡng thì thoát mã 1.
set -euo pipefail

cd "$(dirname "$0")/.."

package="Packages/TrinhChieuCore"
target_dir="${1:-Sources/CoreModel/Show}"
threshold="${2:-90}"

for run in 1 2 3; do
  echo "=== Test lần $run/3 ==="
  swift test --package-path "$package" --enable-code-coverage
done

bin_path="$(swift build --package-path "$package" --show-bin-path)"
binary="$bin_path/TrinhChieuCorePackageTests.xctest"
if [[ -d "$binary" ]]; then
  # macOS: tệp chạy nằm trong gói .xctest
  binary="$binary/Contents/MacOS/TrinhChieuCorePackageTests"
fi
profile="$bin_path/codecov/default.profdata"

llvm_cov="llvm-cov"
if [[ "$(uname -s)" == "Darwin" ]]; then
  llvm_cov="xcrun llvm-cov"
fi

sources=("$PWD/$package/$target_dir"/*.swift)
echo
echo "=== Độ phủ $target_dir ==="
report="$($llvm_cov report "$binary" -instr-profile="$profile" "${sources[@]}")"
echo "$report"

line_cover="$(echo "$report" | awk '/^TOTAL/ {print $10}' | tr -d '%')"
echo
echo "Độ phủ dòng của $target_dir: ${line_cover}% (ngưỡng ${threshold}%)"
if awk -v value="$line_cover" -v limit="$threshold" 'BEGIN { exit !(value + 0 < limit + 0) }'; then
  echo "Dưới ngưỡng." >&2
  exit 1
fi

#!/usr/bin/env bash
# Kiểm cục bộ cho TrinhChieu.
#   scripts/check.sh --quick   mọi máy: định dạng, build và test gói TrinhChieuCore
#   scripts/check.sh --full    chỉ macOS: --quick + gói TrinhChieuMedia + XcodeGen + xcodebuild build test cho App
set -uo pipefail

cd "$(dirname "$0")/.."

mode="${1:-}"
if [[ "$mode" != "--quick" && "$mode" != "--full" ]]; then
  echo "Cách dùng: scripts/check.sh --quick | --full" >&2
  exit 64
fi

if [[ "$mode" == "--full" && "$(uname -s)" != "Darwin" ]]; then
  echo "--full chỉ chạy được trên macOS (cần Xcode). Trên máy này hãy dùng --quick; CI macOS sẽ chạy --full khi PR không còn nháp." >&2
  exit 2
fi

results=()
failed=0

step() {
  local name="$1"
  shift
  echo
  echo "=== $name ==="
  if "$@"; then
    results+=("ĐẠT   $name")
  else
    results+=("LỖI   $name")
    failed=1
  fi
}

lint_swift() {
  find Packages App -name '*.swift' -not -path '*/.build/*' -print0 | xargs -0 swift format lint --strict
}

step "Định dạng (swift format lint)" lint_swift
step "Build TrinhChieuCore" swift build --package-path Packages/TrinhChieuCore
step "Test TrinhChieuCore" swift test --package-path Packages/TrinhChieuCore

if [[ "$mode" == "--full" ]]; then
  step "Build TrinhChieuMedia" swift build --package-path Packages/TrinhChieuMedia
  step "Test TrinhChieuMedia" swift test --package-path Packages/TrinhChieuMedia
  step "XcodeGen" xcodegen generate --spec App/project.yml --project App
  step "Build và test App" xcodebuild \
    -project App/TrinhChieu.xcodeproj \
    -scheme TrinhChieu \
    -destination 'platform=macOS,arch=arm64' \
    build test
fi

echo
echo "=== Tóm tắt ($mode) ==="
printf '%s\n' "${results[@]}"
exit "$failed"

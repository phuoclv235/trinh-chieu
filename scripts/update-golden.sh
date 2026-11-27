#!/usr/bin/env bash
# Dựng lại ảnh chuẩn cho test ảnh của RenderEngine (chỉ macOS).
# Chỉ chạy khi thay đổi hình có chủ ý; nêu rõ trong PR kèm ảnh trước và sau.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "update-golden.sh chỉ chạy trên macOS (cần Metal)." >&2
  exit 2
fi

golden="Packages/TrinhChieuMedia/Tests/RenderEngineTests/Fixtures/golden"
before="$(mktemp -d)/anh-chuan-cu"
mkdir -p "$before"
cp "$golden"/*.png "$before"/ 2>/dev/null || true

TRINHCHIEU_UPDATE_GOLDEN=1 swift test --package-path Packages/TrinhChieuMedia --filter GoldenSceneTests

echo
echo "Ảnh chuẩn cũ (để so trước và sau): $before"
git status --short -- "$golden"

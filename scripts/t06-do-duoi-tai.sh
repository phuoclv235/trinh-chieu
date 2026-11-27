#!/usr/bin/env bash
# T0.6: đo bản thử dựng hình dưới tải thật. Đặc tả: plans/giai-doan-0-1/T0.6-ben-duoi-tai.md
#
# Cách dùng (trên Mac, từ thư mục gốc của repo, Mac mở khoá, hai màn đang cắm):
#   scripts/t06-do-duoi-tai.sh vong "<mô tả tải>"               L0..L5 (kèm L4m) hai vòng xen kẽ, mỗi lần 5 phút
#   scripts/t06-do-duoi-tai.sh gon "<mô tả tải>"                L0..L5 (kèm L4m) một vòng, mỗi lần 3 phút
#   scripts/t06-do-duoi-tai.sh mot <mã> "<mô tả tải>" [cờ...]    một lần chạy (L6, L7, L8...), cờ truyền thẳng ProbeApp
#
# Ví dụ:
#   scripts/t06-do-duoi-tai.sh vong "Zoom họp, camera, chia sẻ màn ngoài; Chrome phát video 1080p"
#   scripts/t06-do-duoi-tai.sh mot L6 "Zoom + Chrome" --duration 600 --on-demand --looper --decode-size output
#
# Kết quả ở $T06_OUT (mặc định ~/TrinhChieuDo/t06/<ngày>): mỗi lần chạy một báo cáo đầy đủ, và tom-tat.md gom
# một dòng cho mỗi màn của mỗi lần chạy. Không thoát ứng dụng nào của người dùng.
set -uo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Chỉ chạy trên macOS." >&2
  exit 2
fi

mode="${1:-}"
out="${T06_OUT:-$HOME/TrinhChieuDo/t06/$(date +%Y%m%d)}"
mkdir -p "$out"
summary="$out/tom-tat.md"

echo "=== Build ProbeApp (release) ==="
swift build -c release --package-path Packages/TrinhChieuMedia --product ProbeApp || exit 2
bin="$(swift build -c release --package-path Packages/TrinhChieuMedia --show-bin-path)/ProbeApp"

# Mặc định đã chốt: mỗi đầu ra một command queue.
base=(--queue-per-screen)

run_one() {
  local label="$1"
  local load="$2"
  shift 2
  local stamp
  stamp="$(date +%H%M%S)"
  echo
  echo "=== $label ($(date +%H:%M:%S)) cờ: ${base[*]} $* ==="
  echo "Tải máy: $(uptime | sed 's/.*load averages*: //')"
  pmset -g therm 2>/dev/null | grep -i -E "warning|limit" || true
  "$bin" "${base[@]}" "$@" --label "$label" --load "$load" \
    --report "$out/$label-$stamp.md" --summary "$summary" >"$out/$label-$stamp.log" 2>&1
  local code=$?
  echo "Mã thoát $code. Báo cáo: $out/$label-$stamp.md"
  tail -n 3 "$out/$label-$stamp.log"
  # Nghỉ giữa hai lần để máy về trạng thái ổn định.
  sleep 15
}

case "$mode" in
  vong)
    load="${2:?Thiếu mô tả tải}"
    for round in 1 2; do
      echo
      echo "##### Vòng $round #####"
      run_one L0 "$load" --duration 300
      run_one L1 "$load" --duration 300 --realtime
      run_one L2 "$load" --duration 300 --looper
      run_one L3 "$load" --duration 300 --looper --decode-size output
      # L4m: mốc của L4 (cảnh tĩnh, vẽ liên tục) để so CPU trước và sau B1.
      run_one L4m "$load" --duration 300 --no-video
      run_one L4 "$load" --duration 300 --no-video --on-demand
      run_one L5 "$load" --duration 300 --recover
    done
    ;;
  gon)
    load="${2:?Thiếu mô tả tải}"
    run_one L0 "$load" --duration 180
    run_one L1 "$load" --duration 180 --realtime
    run_one L2 "$load" --duration 180 --looper
    run_one L3 "$load" --duration 180 --looper --decode-size output
    run_one L4m "$load" --duration 180 --no-video
    run_one L4 "$load" --duration 180 --no-video --on-demand
    run_one L5 "$load" --duration 180 --recover
    ;;
  mot)
    label="${2:?Thiếu mã lần chạy}"
    load="${3:?Thiếu mô tả tải}"
    shift 3
    run_one "$label" "$load" "$@"
    ;;
  *)
    sed -n '2,15p' "$0" >&2
    exit 64
    ;;
esac

echo
echo "=== Tóm tắt: $summary ==="
cat "$summary"

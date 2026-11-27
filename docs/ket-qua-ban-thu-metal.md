# Kết quả bản thử Metal (T0.4)

Tài liệu này ghi số đo của bản thử `ProbeApp` (đặc tả: `plans/giai-doan-0-1/T0.4-ban-thu-metal.md`). Mỗi lần chạy thêm một mục "Lần chạy" ở cuối tệp, không xoá lần cũ. T1.6 cũng ghi số đo lặp lại vào đây.

## Cách chạy

Trên Mac (Apple Silicon, macOS 15+), từ thư mục gốc của repo, cắm sẵn hai màn (nếu chỉ có một màn rời, màn tích hợp là màn thứ hai):

```bash
# Xem danh sách tuỳ chọn
swift run -c release --package-path Packages/TrinhChieuMedia ProbeApp --help

# Lần đo chính: 10 phút, bản release
swift run -c release --package-path Packages/TrinhChieuMedia ProbeApp --report docs/lan-chay-release.md

# Thread Sanitizer: 2 phút, bản debug
swift run -c debug --sanitize=thread --package-path Packages/TrinhChieuMedia ProbeApp --duration 120 --report docs/lan-chay-tsan.md
```

- Lần đầu, bản thử tự tạo hai video mẫu trong `~/Library/Caches/TrinhChieuProbe`: nền 1080p H.264 30 khung/giây và khung phụ 4K HEVC 30 khung/giây, mỗi video 20 giây, lặp. Có video thật thì truyền `--video1` và `--video2`.
- Bố cục trên khung vẽ 1920x1080: video nền phủ kín, video khung phụ 480x270 góc trên phải, logo 120x120 góc dưới trái, lời 4 dòng cỡ 72 có viền đen ở giữa. Lời đổi mỗi 2 giây với hoà tan 0.35 giây, vòng qua 4 lời có dấu chồng ở dòng đầu ("Ẩn", "Ở", "Người", "Đấng").
- Có 5 giây khởi động trước khi đo (bỏ các khung giật lúc mở cửa sổ và nạp video). Bấm Esc trên màn đầu ra để dừng sớm; báo cáo vẫn được ghi.
- Mã thoát: 0 khi cả hai tiêu chí số đo đạt, 1 khi có tiêu chí không đạt, 2 khi lỗi hoặc lần chạy không hợp lệ (có màn không nhận khung nào, thường do màn hình đang khoá).
- Mac phải mở khoá và không tự khoá trong lúc đo: khi màn hình khoá, macOS không trình chiếu drawable nào.
- Từ lần chạy 4: display link mặc định chạy theo tần số gốc của từng màn (`--fps 60` để ép 60). Khoảng đổi chữ cộng thêm ngẫu nhiên 0 đến 1 chu kỳ khung để pha giữa lúc gửi cảnh và nhịp vẽ trải đều. Báo cáo có thêm bảng "Đường ống từng màn" (ba mốc mỗi khung: lúc gọi vẽ, `targetPresentationTimestamp`, `presentedTime`) và "Nhật ký khung rớt".
- `--native-fullscreen` đưa cửa sổ vào toàn màn hình gốc của macOS (`toggleFullScreen`), khác `--fullscreen` (`enterFullScreenMode` của view).

## Cách đo

| Số đo | Cách tính |
| --- | --- |
| Khung rớt | Mỗi khung gắn `addPresentedHandler`. Khung rớt là khung có `presentedTime` cách khung trước hơn 1.5 lần chu kỳ, cộng khung không được hiển thị (`presentedTime == 0`). Chu kỳ = 1 / min(tần số màn, 60) |
| Thời gian GPU | `gpuEndTime - gpuStartTime` của command buffer mỗi khung; báo trung bình và p99 |
| Độ trễ đổi cảnh | Từ lúc gửi cảnh vào `SceneMailbox` (`CACurrentMediaTime`) tới `presentedTime` của khung đầu tiên chứa cảnh mới; báo p50, p95, lớn nhất |
| CPU, RAM | Lấy mẫu mỗi giây: CPU từ `getrusage` (phần trăm một nhân), RAM là `phys_footprint` |

Chữ của cả 4 lời được dựng trước khi đo, nên độ trễ đo được là của vòng vẽ chứ không gồm thời gian Core Text dựng chữ. Display link đặt `preferredFrameLatency = 1` (đổi bằng `--frame-latency 2` để so sánh).

Từ lần chạy 4 có thêm: "gọi tới đích" (`targetPresentationTimestamp` trừ lúc display link gọi vẽ), "đích tới thật" (`presentedTime` trừ `targetPresentationTimestamp`), "đường ống" (`presentedTime` trừ lúc gọi vẽ), mỗi loại báo p50, p95, p99. Chu kỳ đo là trung vị khoảng cách giữa hai `presentedTime`.

## Tiêu chí (cổng giai đoạn 0)

1. Dưới 1 khung rớt mỗi phút mỗi màn trong 10 phút (tính trung bình; báo cáo ghi thêm phút tệ nhất).
2. Độ trễ đổi cảnh p95 dưới 2 khung (33 ms ở 60 Hz).
3. Dấu chồng không bị cắt ở dòng trên cùng: test `TextRasterizerTests` và kiểm bằng mắt trên màn.
4. Không có cảnh báo Thread Sanitizer khi chạy 2 phút.

Nếu tiêu chí 1 hoặc 2 không đạt: dừng, báo coordinator kèm số đo, không tự đổi kiến trúc.

## Các lần chạy

### Lần chạy 1 (2026-11-27, 00:5x UTC): không hợp lệ

Mac đang khoá màn hình (`CGSSessionScreenIsLocked = true`) nên 0 khung lên màn; GPU vẫn dựng khung khoảng 3 ms. Sau lần này bản thử tự báo "lần chạy không hợp lệ" khi có màn không nhận khung nào.

### Lần chạy 2 (2026-11-27 07:59 đến 08:12, giờ Việt Nam), commit e4ec7e1

| Mục | Giá trị |
| --- | --- |
| Model máy | MacBookPro18,1, Apple M1 Pro, 32 GB |
| macOS | 27.0.1 (26A434); chỉ có Command Line Tools (Swift 6.3.3), chưa cài Xcode |
| Màn 0 | Màn tích hợp Liquid Retina XDR, drawable 4112x2658, 120 Hz (ProMotion) |
| Màn 1 | LG ULTRAWIDE 2560x1080, 60 Hz |
| Cấu hình | Display link 60 khung/giây, trễ 1 khung; nền 1080p H.264 30 khung/giây; khung phụ 4K HEVC 30 khung/giây; chữ đổi mỗi 2 giây, hoà tan 0.35 giây; khởi động 5 giây; chạy dưới `caffeinate -dimsu` |

Cột: khung lên màn, khung rớt (không lên / trễ), rớt TB mỗi phút, phút tệ nhất, GPU TB, GPU p99, trễ đổi cảnh p50, p95, lớn nhất.

| Lần đo | Màn | Lên màn | Rớt | Rớt/phút | Phút tệ nhất | GPU TB | GPU p99 | Trễ p50 | Trễ p95 | Trễ max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Release 10 phút | 0 (120 Hz) | 35348 | 709 (0 / 709) | 70.90 | 170 | 0.88 ms | 1.09 ms | 18.64 ms | 31.53 ms | 54.77 ms |
| Release 10 phút | 1 (60 Hz) | 35984 | 16 (2 / 14) | 1.60 | 6 | 0.33 ms | 1.02 ms | 45.24 ms | 47.63 ms | 47.90 ms |
| Release 30 giây | 0 | 1742 | 53 (0 / 53) | 105.99 | 53 | 0.90 ms | 1.92 ms | 28.57 ms | 49.63 ms | 49.63 ms |
| Release 30 giây | 1 | 1797 | 3 (1 / 2) | 6.00 | 3 | 0.35 ms | 1.36 ms | 37.65 ms | 42.03 ms | 42.03 ms |
| Debug + TSan 2 phút | 0 | 7059 | 73 (0 / 73) | 36.50 | 69 | 0.89 ms | 1.21 ms | 20.12 ms | 31.04 ms | 54.62 ms |
| Debug + TSan 2 phút | 1 | 7180 | 20 (2 / 18) | 10.00 | 15 | 0.32 ms | 1.07 ms | 37.93 ms | 40.05 ms | 40.90 ms |

Tiến trình (release 10 phút): CPU TB 16.0%, lớn nhất 20.3% một nhân; RAM TB 264 MB, lớn nhất 274 MB. Bản TSan: CPU 23.2%, RAM 423 MB.

| Tiêu chí | Kết quả |
| --- | --- |
| 1. Dưới 1 khung rớt mỗi phút mỗi màn | **KHÔNG ĐẠT**: màn 0 70.90/phút, màn 1 1.60/phút |
| 2. Trễ đổi cảnh p95 dưới 33.33 ms | **KHÔNG ĐẠT** ở màn 1 (47.63 ms); màn 0 đạt sát (31.53 ms) |
| 3. Dấu chồng không bị cắt | Test `TextRasterizerTests` xanh trên CI macOS; chưa kiểm bằng mắt trên máy thật |
| 4. Không cảnh báo TSan 2 phút | **ĐẠT**: 0 cảnh báo, có khung lên màn cả hai màn |

Nhận xét (chưa kiểm chứng, cần đo thêm):

- GPU rất nhẹ (dưới 1 ms mỗi khung, p99 khoảng 1 ms trên ngân sách 16.7 ms), nên rớt khung không đến từ tải GPU.
- Màn 0 là màn ProMotion 120 Hz, không phải màn 1080p 60 Hz như đặc tả. Mọi khung rớt ở màn này là khung "trễ" (không có khung "không lên"). Có thể display link 60 khung/giây lệch nhịp với màn 120 Hz. Cần đo lại với màn tích hợp ghim 60 Hz (Cài đặt hệ thống, Màn hình, Tần số làm tươi) để tách lỗi đo khỏi lỗi thật.
- Màn 1 (60 Hz, gần với điều kiện đặc tả) rớt 1.60 khung/phút, gần ngưỡng. Độ trễ đổi cảnh ổn định quanh 45 ms (khoảng 2.7 khung), cao hơn hẳn màn 0 dù cùng `preferredFrameLatency = 1`. Có thể có thêm một khung trễ do bộ ghép hình của hệ thống trên màn ngoài.
- Theo tiêu chí 5: dừng, báo coordinator kèm số đo, không tự đổi kiến trúc.

### Lần chạy 3: vòng chẩn đoán (2026-11-27, commit 6aef6b9)

Cùng máy với lần 2. Lần này màn tích hợp đã ghim 60 Hz (ProbeApp đọc được 60 Hz ở cả hai màn). Mỗi cấu hình chạy 180 giây bản release dưới `caffeinate -dimsu`, kiểm màn không khoá trước mỗi lần. Cả 6 lần đều có mã thoát 1 (không đạt), không lần nào lỗi.

| Lần | Tuỳ chọn | Màn | Lên màn | Rớt (không lên / trễ) | Rớt/phút | Phút tệ nhất | GPU TB | GPU p99 | Trễ p50 | Trễ p95 | Trễ max | CPU TB | RAM TB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A | `--screens 1` | 1 | 10764 | 36 (11 / 25) | 12.00 | 18 | 0.30 ms | 0.66 ms | 42.06 ms | 43.57 ms | 48.40 ms | 9.8% | 79 MB |
| B | `--screens 1 --fullscreen` | 1 | 10779 | 29 (18 / 11) | 9.67 | 16 | 0.34 ms | 0.57 ms | 64.82 ms | 81.43 ms | 82.92 ms | 10.4% | 112 MB |
| C | `--screens 1 --frame-latency 2` | 1 | 10757 | 43 (27 / 16) | 14.33 | 20 | 0.30 ms | 0.39 ms | 45.31 ms | 47.46 ms | 47.80 ms | 10.2% | 79 MB |
| D | `--fps native` | 0 | 10797 | 3 (0 / 3) | 1.00 | 2 | 0.89 ms | 1.75 ms | 33.39 ms | 46.40 ms | 48.76 ms | 13.2% | 315 MB |
| D | `--fps native` | 1 | 10799 | 1 (1 / 0) | 0.33 | 1 | 0.59 ms | 1.50 ms | 34.51 ms | 46.31 ms | 48.21 ms | | |
| E | `--fps native --fullscreen` | 0 | 10790 | 15 (6 / 9) | 5.00 | 11 | 1.21 ms | 2.12 ms | 63.09 ms | 64.22 ms | 64.56 ms | 14.5% | 413 MB |
| E | `--fps native --fullscreen` | 1 | 10791 | 10 (5 / 5) | 3.33 | 8 | 0.58 ms | 1.55 ms | 65.34 ms | 66.40 ms | 66.44 ms | | |
| F | mặc định, 2 màn | 0 | 10799 | 1 (0 / 1) | 0.33 | 1 | 0.87 ms | 0.98 ms | 42.39 ms | 45.25 ms | 48.71 ms | 16.2% | 309 MB |
| F | mặc định, 2 màn | 1 | 10798 | 3 (3 / 0) | 1.00 | 2 | 0.29 ms | 0.35 ms | 46.05 ms | 48.62 ms | 48.88 ms | | |

Ghi chú: "1.00/phút" được chấm ĐẠT vì thời gian đo dài hơn 180 giây một chút (3 khung trong hơn 3 phút cho 0.99x, làm tròn thành 1.00). Phép so sánh vẫn là "dưới 1".

Kết luận chẩn đoán:

- **Rớt khung:** lỗi ở lần 2 chủ yếu do màn 120 Hz. Khi cả hai màn ở 60 Hz, chạy 2 màn (D, F) đạt hoặc sát ngưỡng: 0.33 đến 1.00 khung/phút. Chỉ là 3 phút nên chưa đủ để chốt đạt cho 10 phút.
- **Kỳ lạ:** chỉ chạy màn ngoài (A, B, C) lại rớt nhiều hơn hẳn (9.67 đến 14.33/phút, có cả khung "không lên"). Giả thuyết: khi màn tích hợp không có cửa sổ của bản thử, WindowServer ghép hình màn ngoài theo đường khác. Chưa kiểm chứng.
- **Toàn màn hình AppKit (B, E):** không giúp gì; trễ đổi cảnh tăng thêm 20 đến 35 ms và rớt nhiều hơn. Loại.
- **`--frame-latency 2` (C):** không cải thiện.
- **Trễ đổi cảnh:** p95 ở mọi cấu hình đều 43 đến 48 ms (khoảng 2.6 đến 2.9 khung), kể cả khi gần như không rớt khung. Phân rã ước lượng: chờ tới lần gọi display link kế tiếp (0 đến 1 khung, trung bình nửa khung) cộng khoảng cách từ lúc gọi tới `targetPresentationTimestamp` (khoảng 2 khung: một khung dựng, một khung bộ ghép hình của hệ thống). Như vậy trễ nằm ở cấu trúc đường trình chiếu qua bộ ghép hình, không phải ở tải vẽ. Với đường hiện tại, tiêu chí 2 (dưới 2 khung, 33 ms) gần như không thể đạt.
- Theo tiêu chí 5 và quyết định của coordinator: không đổi kiến trúc, không merge; chuyển tổng hợp để rà soát kiến trúc.

### Kiểm bằng mắt tiêu chí 3 (Phuoc, 2026-11-27)

Dấu tiếng Việt hiển thị đúng, không bị cắt. Nhưng viền "cắt nét" chữ: viền kiểu Core Text (`kCTStrokeWidthAttributeName` âm) nằm giữa đường bao nên ăn vào trong nét, làm nét chữ mảnh đi. Đã sửa trong bản thử: vẽ viền trước với độ dày gấp đôi rồi tô chữ đè lên, nên viền chỉ nằm ngoài nét; chừa thêm lề bằng độ dày viền. Có test `strokeOutsideGlyph`. Cần Phuoc kiểm lại bằng mắt ở lần chạy 4.

### Lần chạy 4 (2026-11-27, commit 0827322): phép đo đề xuất của rà soát kiến trúc

Cùng máy, cả hai màn 60 Hz, display link theo tần số gốc của từng màn (ra 60), trễ 1 khung, bản release dưới `caffeinate -dimsu`, kiểm màn không khoá trước mỗi lần. Cả 5 lần có mã thoát 1. Không chụp được HUD của Metal (Terminal không có quyền ghi màn hình).

| Lần | Cấu hình | Màn | Rớt (không lên / trễ) | Rớt/phút | Gọi tới đích p50 / p99 | Đích tới thật p99 | Đường ống p50 / p99 / max | Trễ đổi cảnh min / p50 / p95 / max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R1 | 2 màn, 10 phút | 0 | 147 (25 / 122) | 14.69 | 49.74 / 49.94 ms | 16.58 ms | 49.57 / 49.89 / 116.56 ms | 32.95 / 55.37 / 65.61 / 113.33 ms |
| R1 | 2 màn, 10 phút | 1 | 143 (28 / 115) | 14.30 | 49.75 / 49.94 ms | 0.00 ms | 49.57 / 49.89 / 116.56 ms | 32.72 / 55.11 / 65.61 / 113.33 ms |
| R2 | chỉ màn LG, màn tích hợp để yên, 10 phút | 1 | 86 (44 / 42) | 8.60 | 32.65 / 32.92 ms | 0.00 ms | 32.59 / 32.84 / 99.48 ms | 31.39 / 37.44 / 47.58 / 54.15 ms |
| R3 | như R2, QuickTime phát lặp video trên màn tích hợp, 5 phút | 1 | 45 (14 / 31) | 8.99 | 32.70 / 32.98 ms | 0.00 ms | 32.64 / 32.89 / 149.45 ms | 31.20 / 37.63 / 48.37 / 48.62 ms |
| R4 | như R2, chạy trong gói `.app` tối thiểu, 5 phút | 1 | 133 (78 / 55) | 26.60 | 32.62 / 32.94 ms | 0.00 ms | 32.56 / 32.86 / 131.61 ms | 31.07 / 38.90 / 48.33 / 59.66 ms |
| R5 | như R2, `--native-fullscreen`, 3 phút | 1 | 68 (32 / 36) | 22.65 | 32.62 / 32.92 ms | 0.00 ms | 32.56 / 32.85 / 115.92 ms | 25.12 / 38.12 / 47.16 / 48.70 ms |

Chu kỳ làm tươi đo được: 16.6665 ms (R1, cả hai màn) và 16.6667 ms (R2 đến R5). GPU dưới 1.3 ms mỗi khung (p99 dưới 2.4 ms). CPU 9 đến 14%; RAM 80 MB một màn, 353 MB hai màn.

| Tiêu chí | R1 màn 0 | R1 màn 1 | R2 | R3 | R4 | R5 |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Rớt dưới 1/phút | Không | Không | Không | Không | Không | Không |
| 2 (cũ). Trễ đổi cảnh p95 dưới 2 chu kỳ | Không | Không | Không | Không | Không | Không |
| 2a (đề xuất). Đường ống p99 ≤ 2 chu kỳ + 2 ms (35.33 ms) | Không (49.89) | Không (49.89) | Đạt (32.84) | Đạt (32.89) | Đạt (32.86) | Đạt (32.85) |
| 2b (đề xuất). Trễ đổi cảnh p95 ≤ 51 ms, max ≤ 66.67 ms | Không | Không | Đạt | Đạt | Đạt | Đạt |

Nhận xét:

- **Đường ống là số nguyên chu kỳ, do display link quyết định.** Chạy một màn: `targetPresentationTimestamp` luôn cách lúc gọi khoảng 2 chu kỳ (32.6 ms), và khung lên màn đúng hạn (đích tới thật p99 là 0.00 ms). Chạy hai màn: khoảng cách này thành 3 chu kỳ (49.7 ms) ở cả hai màn. Trễ đổi cảnh vì vậy bằng thời gian chờ lần gọi kế tiếp (0 đến 1 chu kỳ) cộng 2 hoặc 3 chu kỳ. Tiêu chí 2 cũ (dưới 2 chu kỳ) không thể đạt với đường này.
- **R1 có một lần khựng toàn hệ thống** ở giây 182 đến 184: cả hai màn bỏ 87 và 97 nhịp (1.5 đến 1.8 giây) cùng lúc. Các lần rớt khác của R1 (141.6, 187.7, 188.8, 208.5, 277.4, 311.9, 403.8 giây...) cũng trùng thời điểm giữa hai màn. Vì vậy nguyên nhân nằm ở phía hệ thống hoặc ở chỗ hai màn dùng chung (hàng đợi lệnh, luồng chính, giải mã video), không phải ở từng màn riêng. Màn 0 có một mẫu "gọi tới đích" âm (-666.58 ms) đúng lúc khựng. Lần F ở lần chạy 3 (cũng hai màn 60 Hz, 3 phút) chỉ rớt 0.33 đến 1.00 khung/phút, nên mức rớt giữa các lần chạy dao động mạnh.
- **Chạy một màn: rớt theo nhịp khoảng 4 giây.** Ở R2, R4 và R5, khoảng cách giữa hai lần rớt thường là 3.98 đến 4.05 giây. Các lần rớt hay đi thành cặp "không lên" rồi "trễ", cách nhau 16 đến 34 ms. Nhịp 4 giây gần bằng hai lần đổi chữ (2 giây cộng ngẫu nhiên tối đa 1 chu kỳ). Giả thuyết cần kiểm: mỗi lần đổi chữ có việc chặn luồng vẽ (ví dụ đổi texture, `mailbox.latest()` hoặc `textCache.texture(for:)` khoá), hoặc có tác vụ định kỳ khác. Chưa kiểm chứng.
- QuickTime phát video trên màn tích hợp (R3) không làm xấu hơn R2. Chạy trong gói `.app` (R4) và toàn màn hình gốc (R5) rớt nhiều hơn, chủ yếu do tăng khung "không lên".
- Theo chỉ dẫn của rà soát: không đổi kiến trúc, không merge. Số đo chuyển cho thread rà soát kiến trúc.

### Lần chạy 5 (2026-11-27, commit 1654052): vòng loại trừ

Cùng máy, cả hai màn 60 Hz, `CAMetalDisplayLink` theo tần số gốc, trễ 1 khung, bản release dưới `caffeinate -dimsu`. Lượt đầu (10:00 đến 10:15 giờ Việt Nam) bị bỏ vì máy quá tải: đang cài Xcode, chạy máy ảo, nhiều `headless_shell`, node và next-server, load 28 đến 46, đang swap. Phuoc đã tắt các việc nền đó. Lượt dưới đây chạy 10:53 đến 13:37 giờ Việt Nam. Trước mỗi lần, máy được chờ tới khi lặng: Spotlight dưới 10% CPU, load 1 phút dưới 6, không có `Runner.Worker` của GitHub Actions. Riêng E0-v1 đo khi máy chưa lặng hẳn (mds 59%, load 8.6). Trên màn tích hợp vẫn mở các ứng dụng thường ngày (Zalo, WhatsApp, Activity Monitor, Claude). Cả 13 lần có mã thoát 1.

| Lần | Cấu hình | Màn | Rớt/phút (không lên / trễ) | Đường ống p99 | Trễ đổi cảnh p95 | Lần gọi vẽ > 4 ms |
| --- | --- | --- | --- | --- | --- | --- |
| E0-v1 | chỉ màn LG, đủ nội dung (máy chưa lặng) | 1 | 6.66 (14 / 6) | 32.85 ms | 47.69 ms | 3 |
| E0-v2 | như trên | 1 | 26.66 (49 / 31) | 32.86 ms | 47.30 ms | 7 |
| E1-v1 | chỉ màn LG, chữ tĩnh | 1 | 33.64 (11 / 90) | 32.81 ms | không áp dụng | 61 |
| E1-v2 | như trên | 1 | 22.00 (41 / 25) | 32.84 ms | không áp dụng | 17 |
| E2-v1 | chỉ màn LG, không video | 1 | 17.00 (12 / 39) | 32.62 ms | 48.27 ms | 13 |
| E2-v2 | như trên | 1 | 22.99 (15 / 54) | 45.43 ms | 47.97 ms | 0 |
| E3-v1 | chỉ màn LG, không video, chữ tĩnh | 1 | 19.32 (20 / 38) | 32.75 ms | không áp dụng | 14 |
| E3-v2 | như trên | 1 | 19.32 (21 / 37) | 32.87 ms | không áp dụng | 0 |
| E4-v1 | chỉ màn LG, chỉ video nền | 1 | 44.97 (23 / 112) | 32.94 ms | 48.06 ms | 38 |
| E4-v2 | như trên | 1 | 7.00 (4 / 17) | 32.76 ms | 47.52 ms | 10 |
| E5 | 2 màn, không video, chữ tĩnh, 5 phút | 0 | 1.80 (3 / 6) | 32.91 ms | không áp dụng | 0 |
| E5 | | 1 | 0.80 (2 / 2) | 32.92 ms | không áp dụng | 0 |
| E6 | 2 màn, đủ nội dung, mỗi màn một command queue, 5 phút | 0 | **0.20** (0 / 1) | 32.90 ms | 47.67 ms | 1 |
| E6 | | 1 | **0.20** (0 / 1) | 32.80 ms | 46.90 ms | 27 |
| E7 | chỉ màn LG, như E3, `CADisplayLink` của NSView | 1 | 1.33 (0 / 4) | 49.20 ms | không áp dụng | (*) |

(*) Với `CADisplayLink` của view, lần gọi vẽ chờ `nextDrawable()` gần trọn một chu kỳ (p50 16.59 ms) trên luồng chính, nên gần như mọi lần gọi đều vượt 4 ms. Đó là thời gian chờ, không phải tải vẽ.

Kết luận:

- **Rớt khung không do việc dựng hình của bản thử.** E3-v2 (nền màu, chữ tĩnh, không video) không có lần gọi vẽ nào trên 4 ms; lần lâu nhất là 1.94 ms, đường ống đều 2 chu kỳ. Vậy mà vẫn rớt 19.32 khung/phút. Bỏ video hay bỏ đổi chữ không làm hết rớt.
- **Khi chạy một màn, rớt theo nhịp khoảng 2.0 đến 2.2 giây**, kể cả khi chữ tĩnh (E1-v2: các lần rớt cách nhau 2.000, 2.017, 2.033 giây). Nhịp này không gắn với lúc đổi chữ hay vị trí video. Nhịp 4 giây ở lần chạy 4 là cùng hiện tượng (bỏ sót một nhịp).
- **Khi chạy hai màn, cả hai màn gần như sạch**: E5 0.8 đến 1.8 khung/phút, E6 0.20 khung/phút cả hai màn, với đủ video và đổi chữ. Đây là kết quả tốt nhất từ đầu. Giả thuyết (chưa kiểm chứng): khi chỉ có màn ngoài chạy bản thử, màn tích hợp còn hiện các ứng dụng tự cập nhật (Zalo Helper GPU 55% CPU, WhatsApp, Activity Monitor). WindowServer phải ghép lại màn đó theo nhịp riêng và làm lỡ nhịp màn ngoài. Khi chạy hai màn, cửa sổ bản thử ở mức screenSaver che kín màn tích hợp nên không còn bị.
- **Mỗi màn một command queue (E6)** cho kết quả tốt nhất nhưng mới chạy một lần 5 phút; chưa tách được phần do hàng đợi riêng và phần do dao động giữa các lần.
- **Trễ:** đường ống p99 luôn khoảng 32.9 ms (2 chu kỳ); riêng E2-v2 có lúc lên 3 chu kỳ (45.4 ms). Trễ đổi cảnh p95 47 đến 48 ms. Tiêu chí 2a và 2b đạt ở mọi lần có đổi chữ, trừ những lúc đường ống lên 3 chu kỳ. Tiêu chí 2 cũ không thể đạt với kiến trúc này.
- **`CADisplayLink` của view (E7)** chỉ rớt 4 khung trong 3 phút (1.33/phút, 2 khung ở 3 giây đầu) dù chạy một màn với cùng ứng dụng trên màn tích hợp như E3 (19.32/phút). Nhưng đường ống 3 chu kỳ (49.2 ms): `targetTimestamp` chỉ cách lần gọi 1 chu kỳ, còn khung thật lên màn sau đó 2 chu kỳ nữa. Lần gọi chờ `nextDrawable()` gần trọn chu kỳ trên luồng chính. Khác biệt rớt khung giữa E3 và E7 là manh mối đáng xem: có thể một khung đệm thêm trong đường ống che được nhịp lỡ của WindowServer.
- E5 có một cụm rớt ở giây 16.5 đến 17.5, cùng lúc trên cả hai màn: có lẽ do một sự kiện hệ thống.
- Đã sửa báo cáo: khi chữ tĩnh, tiêu chí trễ đổi cảnh ghi "không áp dụng" thay vì chấm không đạt.

### Lần chạy 6 (2026-11-27, commit 71d6c41): vòng xác nhận cổng

Chạy từ 13:42 đến 14:38 giờ Việt Nam. Máy lặng trước mỗi lần (load 1 phút 2.5 đến 5.3), không có `Runner.Worker`, và màn không khoá lần nào. Màn tích hợp có cửa sổ của Cloudflare WARP, Dock, Finder, Google Chrome, Passwords, Safari, Screenshot và TextEdit. Zalo đang chạy nhưng không có cửa sổ hiện. Không đóng ứng dụng nào. Cả 8 lần có mã thoát 1. TSan: 0 cảnh báo.

| Lần | Cấu hình | Màn | Rớt/phút (không lên / trễ) | Đường ống p99 | Trễ đổi cảnh p95 / lớn nhất | Lần gọi vẽ > 4 ms |
| --- | --- | --- | --- | --- | --- | --- |
| G1a | 2 màn, mỗi màn một command queue, 10 phút | 0 | 111.28 (110 / 1003) | 47.27 ms | 47.72 / 68.30 ms | 723 |
| G1a | | 1 | 96.38 (99 / 865) | 33.06 ms | 47.67 / 71.39 ms | 316 |
| G1b | như G1a | 0 | 58.78 (66 / 522) | 33.16 ms | 47.94 / 56.17 ms | 194 |
| G1b | | 1 | 85.36 (76 / 778) | 33.13 ms | 47.39 / 59.88 ms | 406 |
| TSan | như G1a, bản debug, 2 phút | 0 | 47.98 (18 / 78) | 32.91 ms | 47.04 / 52.69 ms | 35 |
| TSan | | 1 | 89.47 (25 / 154) | 33.09 ms | 53.33 / 63.53 ms | 316 |
| G2 | chỉ màn LG, phủ đen màn tích hợp, 5 phút | 1 | 70.78 (40 / 314) | 33.12 ms | 46.75 / 48.07 ms | 156 |
| G3 | 2 màn, một command queue chung, 10 phút | 0 | 95.10 (116 / 835) | 33.22 ms | 48.08 / 62.94 ms | 689 |
| G3 | | 1 | 93.00 (116 / 814) | 33.06 ms | 47.33 / 67.22 ms | 415 |
| G5a | chỉ màn LG, cửa sổ giữ nhịp 320x180 theo tần số gốc trên màn tích hợp, 5 phút | 1 | 6.20 (4 / 27) | 32.93 ms | 47.99 / 48.97 ms | 18 |
| G5b | như G5a | 1 | 2.00 (2 / 8) | 32.94 ms | 48.11 / 48.73 ms | 90 |
| G6 | như G5a, cửa sổ giữ nhịp 15 khung/giây | 1 | 1.40 (2 / 5) | 32.86 ms | 45.87 / 48.16 ms | 51 |

G4 (thoát Zalo, WhatsApp và Activity Monitor) chưa chạy: cần Phuoc đồng ý thoát ứng dụng.

Nhận xét:

- **Cổng chưa đạt.** G1 trượt tiêu chí 1 ở cả hai lần (59 đến 111 khung/phút). Tiêu chí 2b cũng trượt ở vài màn vì có mẫu trễ lớn nhất trên 66.67 ms.
- **Hai màn tệ đi hẳn so với lần chạy 5 chỉ 1.5 giờ trước** (E6 0.20/phút, E5 0.8 đến 1.8/phút). Đường mặc định của bản thử không đổi giữa hai lần: từ 1654052 tới 71d6c41 chỉ thêm `--blank-other-screens` và `--keeper`. Vậy nhiều khả năng nguyên nhân là môi trường máy.
- Ở các lần tệ (G1a, G1b, TSan, G2, G3), 30 đến 50 giây đầu gần như sạch, sau đó rớt liên tục, cùng thời điểm trên cả hai màn. Khoảng cách giữa hai lần gọi vẽ có lúc lên tới khoảng 300 ms, và số lần gọi vẽ trên 4 ms lên hàng trăm. Luồng vẽ bị chậm vì cả máy bận, không phải vì tải vẽ.
- **Tương quan với Zalo:** mẫu `top` sau khi đo ở cả 5 lần tệ đều có "Zalo Helper (GPU)" 54 đến 58% CPU và `kernel_task` 26 đến 39%. Ở 3 lần tốt (G5a, G5b, G6), Zalo không có trong `top` và `kernel_task` chỉ khoảng 10%. Điểm chung của 5 lần tệ là màn tích hợp bị che kín bởi cửa sổ toàn màn hình (đầu ra hoặc tấm phủ đen). Có thể Zalo phản ứng với việc đó, nhưng E5 và E6 trước đây cũng có Zalo GPU khoảng 55% mà vẫn sạch. Vì vậy đây mới là tương quan, chưa phải nguyên nhân.
- **Cửa sổ giữ nhịp giúp rõ khi chỉ chạy màn ngoài:** G5 và G6 rớt 1.4 đến 6.2 khung/phút, so với 7 đến 45 khung/phút ở E0 đến E4. Cửa sổ chỉ cập nhật 15 khung/giây (G6, giống PreviewPublisher của T1.6) cho kết quả tốt nhất, nhưng vẫn chưa dưới 1 khung/phút. Phủ đen tĩnh (G2) không giúp.
- Trễ đổi cảnh p95 vẫn khoảng 46 đến 48 ms ở mọi lần. Đường ống p99 khoảng 33 ms, trừ G1a màn 0 lên 3 chu kỳ.
- **Kết luận cho rà soát:** số đo rớt khung trên chiếc Mac dùng hằng ngày này dao động từ 0.2 lên tới 111 khung/phút giữa các lần chạy cùng cấu hình, tuỳ các ứng dụng đang chạy nền. Muốn chấm cổng đáng tin cần một môi trường đo cố định: thoát các ứng dụng nền (Zalo, trình duyệt, WARP), hoặc dùng một tài khoản người dùng sạch, hoặc đo trên máy dùng cho buổi nhóm thật.

### Lần chạy 7 (2026-11-27, commit 0980b31 và c02f767): T0.6 đo dưới tải thật

Đặc tả: `plans/giai-doan-0-1/T0.6-ben-duoi-tai.md`. Kịch bản: `scripts/t06-do-duoi-tai.sh`. Chạy từ 19:18 đến 20:19 giờ Việt Nam trên MacBook Pro M1 Pro 32 GB, macOS 27.0.1.

**Lệch so với đặc tả (Phuoc chọn ngày 2026-11-27):** bản gọn, mỗi cấu hình một lần 3 phút (đặc tả: hai vòng xen kẽ 5 phút); L6 một lần 10 phút (đặc tả: hai lần); L7 5 phút; **chỉ màn MacBook** (không cắm màn ngoài), nên bỏ L8. Ép 60 khung/giây (`--fps 60`) như đầu ra HDMI tới LED; màn MacBook là màn 120 Hz. Một vòng đầu ở tần số gốc 120 Hz (commit 18b6bb1) bị bỏ vì chu kỳ 8.33 ms không so được với đầu ra thật và vì lỗi đếm của B1 (đã sửa ở 0980b31).

Tải chuẩn: Zoom đang họp, bật camera, chia sẻ màn hình; ứng dụng web trong Chrome. Không thoát ứng dụng nào khác (Outlook, Activity Monitor, Claude vẫn chạy). Máy lặng (L7): Phuoc rời cuộc họp và đóng cửa sổ Chrome; tiến trình zoom.us và Chrome vẫn còn nhưng gần như không dùng CPU. Nhiệt "bình thường" ở mọi lần. WindowServer 47 đến 52% CPU khi có tải (122% một lần ở L4k).

| Lần | Biện pháp | Rớt/phút | Khựng ≥3 | Đường ống p50 / p99 | Đổi cảnh p95 / lớn nhất | CPU TB | GPU TB | RAM lớn nhất |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L0 | không | 1.00 | 0 | 33.17 / 33.28 ms | 49.23 / 49.56 ms | 14.6% | 1.13 ms | 266 MB |
| L1 | B2 | 0.33 | 0 | 33.18 / 41.56 ms | 49.66 / 56.77 ms | 13.9% | 1.18 ms | 266 MB |
| L2 | B3 | 2.66 | 0 | 33.14 / 37.24 ms | 49.17 / 57.22 ms | 14.6% | 1.26 ms | 269 MB |
| L3 | B3 + B4 | 0.00 | 0 | 33.14 / 33.27 ms | 49.32 / 49.65 ms | 14.5% | 1.31 ms | 268 MB |
| L4m | cảnh tĩnh, vẽ liên tục (mốc của L4) | 3.67 | 0 | 33.16 / 41.57 ms | 57.52 / 57.88 ms | 8.9% | 0.91 ms | 261 MB |
| L4 | B1, display link nghỉ | 0.00 | 0 | 41.48 / 41.59 ms | 107.89 / 8977 ms (*) | 2.5% | 1.10 ms | 260 MB |
| L4s | B1, link không nghỉ, chỉ bỏ nhịp | 89.21 (**) | 89 | 41.47 / 41.59 ms | 108.02 / 9001 ms (*) | 4.7% | 1.11 ms | 260 MB |
| L4k | B1 giữ ấm: cảnh đứng yên thì present lại mỗi 4 nhịp | 0.67 | 0 | 41.50 / 41.59 ms | 58.09 / 58.16 ms | 5.6% | 0.94 ms | 261 MB |
| L5 | B5 | 1.66 | 0 | 33.14 / 33.28 ms | 49.25 / 49.60 ms | 14.9% | 1.29 ms | 266 MB |
| L0b | không (lặp mốc cuối vòng) | 0.00 | 0 | 33.15 / 33.27 ms | 49.10 / 49.68 ms | 14.5% | 1.26 ms | 266 MB |
| **L6** | B3 + B4, 10 phút | **0.00** | **0** | 41.47 / 41.60 ms | 57.65 / 58.08 ms | **16.3%** | **1.26 ms** | **271 MB** |
| **L7** | B3 + B4, máy lặng, 5 phút | **0.00** | **0** | 32.52 / 32.81 ms | 47.29 / 48.08 ms | 14.7% | 1.34 ms | 269 MB |
| L7k | B1 giữ ấm, máy lặng | 0.67 | 0 | 33.18 / 33.38 ms | 49.81 / 66.53 ms | 4.3% | 1.05 ms | 260 MB |

(*) Lần lớn nhất khoảng 9 giây là lỗi đo đã sửa ở c02f767 (cảnh khởi động chưa từng lên màn bị gán cho khung lên màn sau đó); p95 không bị ảnh hưởng.
(**) Ở L4 và L4s, mỗi lần đổi cảnh sau lúc đứng yên có khoảng 3 khung không lên màn (266 và 267 khung trên 89 lần đổi). L4 đếm chúng là "không lên ngay sau nghỉ", L4s đếm là khựng. Hệ quả chung: chữ mới hiện trễ khoảng 100 ms thay vì 49 ms.

Nhận xét:

- **Ở 60 khung/giây, chỉ màn MacBook, đường mặc định đã đạt mức dưới tải.** Mọi lần vẽ liên tục rớt 0 đến 3.7 khung/phút, không lần khựng nào. L0 đầu vòng và L0b cuối vòng (1.00 và 0.00) cho thấy máy ổn định suốt vòng. Chênh lệch giữa các biện pháp nhỏ hơn độ nhiễu của một lần 3 phút.
- **Đường ống có hai mức ổn định: 2 chu kỳ (33 ms) hoặc 2.5 chu kỳ (41.5 ms).** "Đích tới thật" nhảy giữa 8.34 ms và 16.67 ms theo từng lần chạy, kể cả cùng cấu hình (L3 33 ms, L6 41.5 ms). Màn 120 Hz chạy nội dung 60 khung/giây có hai pha nửa chu kỳ, nên nhiều khả năng đây là đặc tính của màn MacBook, không phải của bản thử. Ở máy lặng (L7), "đích tới thật" gần 0 ms và đường ống đúng 2 chu kỳ. Tiêu chí 2a, 2b phải chấm lại trên đầu ra 60 Hz thật (Mac mini, T1.11).
- **B1 dạng nghỉ link hoặc bỏ nhịp không dùng được:** sau mỗi khoảng đứng yên, khoảng 3 khung đầu không lên màn, nên chữ mới hiện trễ khoảng 100 ms. Đây là hành vi của đường trình chiếu macOS khi lớp không nhận present một lúc, không phụ thuộc display link có nghỉ hay không.
- **B1 dạng giữ ấm (present lại mỗi 4 nhịp, tức 15 khung/giây, khi cảnh đứng yên) hết lỗi trên:** 0 khung "không lên", trễ đổi cảnh như vẽ liên tục, CPU giảm từ 8.9% (L4m) xuống 5.6% dưới tải và 4.3% ở máy lặng. Chưa đạt ngân sách 3% của cảnh tĩnh.
- B2 không giảm rớt rõ rệt và làm đuôi đường ống p99 xấu đi (41.56 ms so với 33.28 ms). B5 không lần nào kích hoạt ở 60 khung/giây (ở vòng 120 Hz nó kích hoạt nhầm mỗi lần đổi cảnh vì ngưỡng tính theo chu kỳ 8.33 ms).

#### Đối chiếu tiêu chí T0.6

| Tiêu chí | Kết quả |
| --- | --- |
| 1. L6 dưới tải: không khựng ≥3, dưới 6 khung/phút | **ĐẠT** (0 khựng, 0.00/phút trong 10 phút; một lần thay vì hai, một màn) |
| 2. L7 máy lặng: dưới 1 khung/phút | **ĐẠT** (0.00/phút) |
| 3. 2a, 2b ở L6 và L7 | L7 **ĐẠT** (p99 32.81 ms ≤ 35.33; p95 47.29 ms ≤ 51.00, lớn nhất 48.08 ≤ 66.67). L6 **KHÔNG ĐẠT** (p99 41.60 ms; p95 57.65 ms) vì đường ống ở mức 2.5 chu kỳ, xem nhận xét về màn 120 Hz. B1 giữ ấm: không có lần nghỉ link nên tiêu chí khung đầu sau nghỉ không áp dụng; trễ đổi cảnh lớn nhất 58.16 ms dưới tải, 66.53 ms ở máy lặng (≤ 4 chu kỳ) |
| 4. Ngân sách ở L6: CPU < 25%, GPU < 3 ms, RAM < 500 MB | **ĐẠT** (16.3%, 1.26 ms, 271 MB) |
| 4. Cảnh tĩnh (L4): CPU < 3% | **KHÔNG ĐẠT** với dạng giữ được chất lượng (L4k 5.6%). Dạng nghỉ link đạt 2.5% nhưng làm chữ hiện trễ 100 ms |
| 5. Bảng kết luận | Bên dưới |
| 6. Dừng nếu tiêu chí 1 không đạt | Không cần: tiêu chí 1 đạt |

#### Kết luận: biện pháp nào vào `RenderEngine` ở T1.6 PR 2

| Biện pháp | Quyết định | Số đo trước → sau | Lý do |
| --- | --- | --- | --- |
| B1 vẽ theo nhu cầu, dạng giữ ấm | **Giữ** | CPU cảnh tĩnh 8.9% → 5.6% (máy lặng 4.3%); trễ đổi cảnh p95 57.5 → 58.1 ms; rớt 3.67 → 0.67/phút | Nhẹ máy hơn mà không mất chất lượng. Bắt buộc: khung cuối của mỗi lần chuyển cảnh phải được xác nhận đã lên màn (`presentedTime > 0`), nếu không thì dựng lại, để màn không dừng ở khung giữa hoà tan |
| B1 dạng nghỉ link hoặc bỏ nhịp | **Bỏ** | Trễ đổi cảnh p95 57.5 → 108 ms | Mất khoảng 3 khung đầu sau mỗi lần đứng yên |
| B2 luồng vẽ thời gian thực | **Bỏ** | Rớt 1.00 → 0.33/phút (trong độ nhiễu); đường ống p99 33.28 → 41.56 ms | Không cải thiện đo được, đuôi trễ xấu hơn, thêm rủi ro bị hệ thống hạ ưu tiên khi vượt ngân sách tính toán |
| B3 lặp video bằng `AVPlayerLooper` | **Giữ** | Rớt 1.00 → 2.66/phút một mình (trong độ nhiễu); cùng B4 → 0.00 | Không còn `seek` trên luồng chính ở điểm lặp, không tốn thêm CPU |
| B4 giải mã video ở cỡ đầu ra | **Giữ** | Cùng B3: rớt 0.00/phút ở L3, L6, L7; CPU 14.5 đến 16.3% (không đổi) | Bộ nhớ khung nhỏ hơn khi đầu ra nhỏ hơn video; T1.6 cần tính lại cỡ khi đầu ra đổi độ phân giải |
| B5 hồi phục sau khựng | **Bỏ** (giữ ý tưởng cho chẩn đoán) | 0 lần kích hoạt ở 60 khung/giây | Đường ống không dài ra lần nào; ngưỡng tính theo chu kỳ dễ kích hoạt nhầm trên màn 120 Hz |
| Đầu ra 60 khung/giây | **Giữ làm mặc định** | Vòng 120 Hz: đường ống 4 đến 5 chu kỳ, rớt 0.3 đến 145/phút | Khớp HDMI tới LED và máy chiếu, nửa tải GPU và CPU |

**Còn treo cho lần chấm trên Mac mini (T1.11):** rớt khung khi đầu ra ở màn ngoài (lỗi của lần chạy 5, 6), hai đầu ra cùng lúc (LED và màn nhắc), tiêu chí 2a, 2b trên đầu ra 60 Hz thật, và ngân sách CPU 3% cho cảnh tĩnh.

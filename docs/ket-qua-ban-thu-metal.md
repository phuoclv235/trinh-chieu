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

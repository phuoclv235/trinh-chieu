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
- Màn 120 Hz (ProMotion) vẫn đo theo chu kỳ 16.67 ms vì display link đặt 60 khung/giây.

## Cách đo

| Số đo | Cách tính |
| --- | --- |
| Khung rớt | Mỗi khung gắn `addPresentedHandler`. Khung rớt là khung có `presentedTime` cách khung trước hơn 1.5 lần chu kỳ, cộng khung không được hiển thị (`presentedTime == 0`). Chu kỳ = 1 / min(tần số màn, 60) |
| Thời gian GPU | `gpuEndTime - gpuStartTime` của command buffer mỗi khung; báo trung bình và p99 |
| Độ trễ đổi cảnh | Từ lúc gửi cảnh vào `SceneMailbox` (`CACurrentMediaTime`) tới `presentedTime` của khung đầu tiên chứa cảnh mới; báo p50, p95, lớn nhất |
| CPU, RAM | Lấy mẫu mỗi giây: CPU từ `getrusage` (phần trăm một nhân), RAM là `phys_footprint` |

Chữ của cả 4 lời được dựng trước khi đo, nên độ trễ đo được là của vòng vẽ chứ không gồm thời gian Core Text dựng chữ. Display link đặt `preferredFrameLatency = 1` (đổi bằng `--frame-latency 2` để so sánh).

## Tiêu chí (cổng giai đoạn 0)

1. Dưới 1 khung rớt mỗi phút mỗi màn trong 10 phút (tính trung bình; báo cáo ghi thêm phút tệ nhất).
2. Độ trễ đổi cảnh p95 dưới 2 khung (33 ms ở 60 Hz).
3. Dấu chồng không bị cắt ở dòng trên cùng: test `TextRasterizerTests` và kiểm bằng mắt trên màn.
4. Không có cảnh báo Thread Sanitizer khi chạy 2 phút.

Nếu tiêu chí 1 hoặc 2 không đạt: dừng, báo coordinator kèm số đo, không tự đổi kiến trúc.

## Các lần chạy

Chưa có lần chạy nào trên máy thật.

# TrinhChieu: phần mềm trình chiếu chuyên nghiệp cho macOS

Đọc tệp này trước mọi việc. Quy chuẩn đầy đủ của chủ dự án nằm ở `docs/huong-dan-chung.md` và **bắt buộc đọc** các mục đánh dấu [LÕI] trước khi làm. Lời Phuoc nói trong cuộc trò chuyện > tệp này > `docs/huong-dan-chung.md` > thói quen mặc định.

## 1. Những điều không được quên

- Giao tiếp tiếng Việt, gọi chủ dự án là "bạn". Chữ trên giao diện tiếng Việt, xưng "Hệ thống" và "bạn".
- Phuoc là người Tin Lành: dùng thuật ngữ Tin Lành (Hội Thánh, buổi nhóm, Chúa Nhật, Mục sư, thánh ca). Không dùng Giáo hội, Thánh lễ, Linh mục.
- Chỉ code khi task đã được duyệt. Kế hoạch tổng và đặc tả task nằm ở `plans/`. Không tự suy luận lại kiến trúc: nếu đặc tả thiếu hoặc mâu thuẫn, dừng và hỏi coordinator.
- Không thêm thư viện ngoài danh sách đã duyệt ở `docs/kien-truc.md` mục "Thư viện ngoài".
- Thuật ngữ theo `docs/thuat-ngu.md`. Một khái niệm một tên, trong code (tên kiểu tiếng Anh theo cột "Tên trong code") và trên giao diện.
- Giao diện chỉ được code sau khi mẫu HTML ở `design/` đã được Phuoc duyệt.

## 2. Phân vai model

| Việc | Model |
| --- | --- |
| Lập kế hoạch, thiết kế kiến trúc, đặc tả task, rà soát kiến trúc | Fable 5.2 |
| Viết code (mọi task trong `plans/`), CI, bảo mật | Opus 5.5 |
| Việc lặt vặt: đổi tên, tài liệu, bài hướng dẫn, chỉnh nhỏ | Sonnet 5.5 |

Tối đa 2 chuỗi code song song (xem `plans/giai-doan-0-1/README.md`).

## 3. Điều chỉnh quy chuẩn chung cho ứng dụng máy Mac (đã được Phuoc duyệt 2026-11-26)

- **Cỡ kiểm giao diện ứng dụng Mac:** cửa sổ 1280, 1512, 1920 px, chỉ giao diện tối (Phuoc bỏ giao diện sáng 2026-11-28). Bộ 390 / 820 / 1280 px chỉ áp cho remote web và trang tương tác (giai đoạn 4, 5).
- **Deploy = phát hành bản build đã ký và notarize.** Vẫn chỉ chạy khi Phuoc gõ "Deploy". Không có container hay cơ sở dữ liệu production.
- **Sao lưu:** mọi thay đổi định dạng tệp phải có bước chuyển đổi tự động (migration) và giữ bản sao tệp cũ (`.bak`) trước khi ghi đè.

## 4. Môi trường build

- Container đám mây là Linux: **không build được ứng dụng macOS**. Gói `Packages/TrinhChieuCore` là Swift thuần, build và test được trên Linux.
- Build, chạy và kiểm hình thật trên Mac của Phuoc qua Remote Control (thư mục dự án trên máy Phuoc: `/Volumes/DATA/Projects/Claude/TrinhChieu`), hoặc CI macOS khi PR chuyển Ready.
- Mỗi PR đụng phần macOS phải kèm **danh sách thử tay** ngắn (5 đến 10 bước) để Phuoc kiểm trên máy thật.

## Phụ lục A. Thông tin riêng của dự án

| Mục | Giá trị |
| --- | --- |
| Tên dự án, tên hiển thị | Tên mã `TrinhChieu`; giao diện xưng "Hệ thống". Tên thương mại chưa chốt |
| Kho mã và nhánh chính | `phuoclv235/trinh-chieu`, nhánh `main` |
| Ngăn xếp công nghệ | Swift 6 (strict concurrency), SwiftUI + AppKit, Metal, AVFoundation, Core Text, SQLite (FTS5). macOS 15+, chỉ Apple Silicon |
| Production | Không có máy chủ. Phân phối ngoài App Store, ký Developer ID, notarize |
| Lệnh kiểm cục bộ | `scripts/check.sh --quick` (Linux hoặc Mac, phần lõi); `scripts/check.sh --full` (chỉ Mac: thêm build app và test media) |
| Lệnh phát hành | Chưa có (giai đoạn 8) |
| CI | GitHub Actions: `core.yml` chạy Ubuntu mỗi lần đẩy; `macos.yml` chạy macOS chỉ khi PR không còn nháp. Sổ cách ly test: `docs/so-cach-ly-test.md` |
| Màu chủ đạo, font, quy tắc giao diện | Chốt sau khi Phuoc duyệt mẫu ở task T0.3; ghi vào `docs/ui-rules.md` |
| Thiết bị Phuoc dùng để thử | Phát triển và đo: MacBook Pro M1 Pro 32 GB (tối đa 2 màn ngoài). Buổi nhóm thật: Mac mini M4 base, 3 màn (màn điều khiển, LED qua bộ xử lý nhận HDMI, màn hình nhắc); máy chiếu phụ lặp màn LED bằng bộ chia HDMI |
| Bản đồ mã nguồn | `docs/kien-truc.md` mục "Bản đồ module"; Graphify khi repo đã được lập chỉ mục |
| Tệp nguy hiểm | `Packages/TrinhChieuCore/Sources/CoreModel/ShowCommand.swift`, `ShowState.swift`, `Packages/TrinhChieuCore/Sources/CoreModel/Document/*` (định dạng tệp), `Packages/TrinhChieuCore/Sources/CoreModel/RenderScene.swift` (hợp đồng giữa lõi và lõi dựng hình), `docs/thuat-ngu.md` |
| Nơi lưu kế hoạch, mẫu, hàng đợi góp ý | `plans/`, `design/`, `plans/feedback-queue.md` |
| Quy ước ghi chú thay đổi | Mỗi PR thêm một tệp `.changes/<chủ-đề>.md` có dòng đầu `minor` hoặc `patch` và mô tả tiếng Việt. Không sửa `CHANGELOG.md` hay số phiên bản trong PR |
| Danh sách đề xuất chưa làm | `docs/de-xuat.md` |

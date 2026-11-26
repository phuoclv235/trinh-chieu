# Bàn giao giai đoạn 0 và 1

Phuoc duyệt kế hoạch ngày 2026-11-26 và giữ nguyên các giả định tạm cho 7 câu hỏi nền (xem mục "Giả định đang dùng"). Thư mục này là đặc tả để thread code (Opus 5.5) làm **không cần suy luận lại kiến trúc**. Đọc theo thứ tự: `CLAUDE.md`, `docs/kien-truc.md`, `docs/dinh-dang-tep.md`, `docs/thuat-ngu.md`, rồi tệp task của mình.

## Mục tiêu

- **Giai đoạn 0 (Nền móng, 2 đến 3 tuần):** khung repo, CI, mẫu giao diện được duyệt, bản thử Metal đạt 60 khung mỗi giây trên 2 màn, lõi lệnh và trạng thái.
- **Giai đoạn 1 (MVP, 7 đến 9 tuần):** chiếu trọn một buổi nhóm thật bằng Hệ thống: thư viện bài hát và media, Kinh Thánh gõ là ra, chương trình buổi nhóm, trình soạn cơ bản, lưới trực tiếp, một đầu ra chính và một màn hình nhắc.

## Danh sách task

| Mã | Tên | Chuỗi | Phụ thuộc | Model | Chạy được trên Linux | Ước lượng |
| --- | --- | --- | --- | --- | --- | --- |
| [T0.1](T0.1-khung-repo.md) | Khung repo, gói Swift, dự án Xcode, CI | A | Không | Opus 5.5 | Một phần | 2 ngày |
| [T0.3](T0.3-mau-giao-dien.md) | Mẫu giao diện HTML cho 4 màn chính | B | Không | Opus 5.5 | Có | 3 ngày + chờ duyệt |
| [T0.4](T0.4-ban-thu-metal.md) | Bản thử Metal: chữ và video ra 2 màn | B | T0.1 | Opus 5.5 | Không | 3 ngày |
| [T0.5](T0.5-loi-lenh-trang-thai.md) | `CoreModel`: mô hình, lệnh, trạng thái, `RenderScene` | A | T0.1 | Opus 5.5 | Có | 4 ngày |
| [T1.1](T1.1-viettext-chi-muc.md) | `VietText` và `LibraryIndex` | A | T0.5 | Opus 5.5 | Có | 3 ngày |
| [T1.2](T1.2-kinh-thanh.md) | `Scripture`: địa chỉ câu, kho bản dịch, chia trang | A | T1.1 | Opus 5.5 | Có | 4 ngày |
| [T1.3](T1.3-luu-tru-thu-vien.md) | `LibraryStore`: đọc ghi, theo dõi, thùng rác, gói mang đi | A | T1.1 | Opus 5.5 | Có | 4 ngày |
| [T1.4](T1.4-bo-nhap.md) | `Importers` và `MediaImport` | A | T1.2, T1.3 | Opus 5.5 | Phần lớn | 4 ngày |
| [T1.5](T1.5-scene-resolver.md) | `SceneResolver`, mẫu trình bày mặc định, màn hình nhắc | A | T1.2, T1.3 | Opus 5.5 | Có | 3 ngày |
| [T1.6](T1.6-loi-dung-hinh.md) | `RenderEngine` hoàn chỉnh cho MVP | B | T0.4, T0.5 | Opus 5.5 | Không | 8 ngày |
| [T1.7](T1.7-khung-ung-dung.md) | Khung ứng dụng, cài đặt, nối lõi | B | T0.3 duyệt, T1.3, T1.6 | Opus 5.5 | Không | 4 ngày |
| [T1.8](T1.8-dieu-khien-truc-tiep.md) | Điều khiển trực tiếp và chương trình buổi nhóm | B | T1.7 | Opus 5.5 | Không | 6 ngày |
| [T1.9](T1.9-trinh-soan.md) | Trình soạn trang chiếu và lời bài hát | B | T1.8 | Opus 5.5 | Không | 7 ngày |
| [T1.10](T1.10-bang-lenh.md) | Bảng lệnh ⌘K | A | T1.2, T1.7 | Opus 5.5 | Không | 2 ngày |
| [T1.11](T1.11-tro-giup-nghiem-thu.md) | Trợ giúp trong ứng dụng, nghiệm thu MVP | B | Tất cả | Sonnet 5.5 (bài viết), Opus 5.5 (sửa lỗi) | Không | 3 ngày |

T0.2 (tài liệu nền) đã xong trong PR bàn giao này: `CLAUDE.md`, `docs/kien-truc.md`, `docs/dinh-dang-tep.md`, `docs/thuat-ngu.md`, `docs/de-xuat.md`.

Tổng cộng khoảng 60 ngày công. Với 2 chuỗi song song, dự kiến 9 đến 12 tuần lịch, tuỳ tốc độ duyệt mẫu và thử trên máy thật.

## Hai chuỗi song song

```
Chuỗi A (lõi, phần lớn test trên Linux):
  T0.1 ─► T0.5 ─► T1.1 ─┬─► T1.2 ─┬─► T1.5 ─► T1.4 ─► T1.10
                        └─► T1.3 ─┘

Chuỗi B (hình và giao diện, cần Mac):
  T0.3 (mẫu, chờ duyệt) ─────────────────────┐
  T0.1 ─► T0.4 ─► T1.6 (cần T0.5) ───────────┴─► T1.7 ─► T1.8 ─► T1.9 ─► T1.11

T1.7 cần thêm T1.3 và T1.5 từ chuỗi A; T1.6 test bằng cảnh dựng tay, nối với T1.5 ở T1.7.
```

Quy tắc điều phối:

1. T0.1 làm trước tiên và một mình, vì mọi task khác thêm tệp vào khung của nó.
2. T0.3 bắt đầu ngay song song với T0.1 (chỉ đụng `design/`). Gửi Phuoc duyệt sớm nhất có thể, vì T1.7 trở đi bị chặn bởi việc duyệt.
3. Hai task cùng sửa một tệp nguy hiểm (xem `CLAUDE.md` Phụ lục A) không chạy song song.
4. Mỗi task là một PR. Task ước lượng trên 5 ngày (T1.6, T1.8, T1.9) được chia thành 2 PR theo mục "Chia PR" trong tệp task.

## Quy ước chung cho mọi task

- Tên kiểu, hàm theo cột "Tên trong code" ở `docs/thuat-ngu.md`. Chữ trên giao diện lấy từ một bảng chuỗi duy nhất `App/Resources/Localizable.xcstrings` (khoá tiếng Anh, giá trị tiếng Việt).
- Mọi kiểu công khai trong `TrinhChieuCore` là `Sendable`. Mô hình dữ liệu là `struct`, `Codable`, `Equatable`, `Hashable`.
- Test viết bằng Swift Testing (`import Testing`), không dùng XCTest cho test mới. Test chạy lặp 3 lần trước khi báo xong (`swift test --repeat 3` hoặc tương đương).
- Không `print`; dùng `Logger` của `os` (phía Mac) hoặc giao thức `LogSink` của `CoreModel` (phía Linux).
- Mỗi PR có: tệp `.changes/<mã-task>.md`, bảng đối chiếu tiêu chí nghiệm thu với tệp và test, danh sách thử tay nếu đụng macOS.
- Hết task: cập nhật bảng "Trạng thái" bên dưới trong cùng PR.

## Giả định đang dùng (7 câu hỏi nền)

| # | Giả định |
| --- | --- |
| 1 | Dùng nội bộ Hội Thánh trước, thiết kế sẵn đường thương mại hoá |
| 2 | Phân phối ngoài App Store; Phuoc sẽ có tài khoản Apple Developer (cần trước giai đoạn 4) |
| 3 | macOS 15 trở lên, chỉ Apple Silicon |
| 4 | Mac Apple Silicon 16 GB, 3 đầu ra (LED, máy chiếu phụ, màn hình nhắc), LED qua bộ xử lý nhận HDMI |
| 5 | Tương tác 2 chiều gồm cả Zoom hai chiều và hội chúng gửi câu hỏi, bình chọn |
| 6 | Phuoc chốt (2026-11-26): cần **Bản Truyền Thống 1925** và **Bản Hiệu Đính 2010**. 1925 đóng gói sẵn nếu xác minh là phạm vi công cộng. 2010 còn bản quyền: chỉ đóng gói khi có giấy phép bằng văn bản của chủ sở hữu; trong lúc chờ, Phuoc tự nhập tệp cho dùng nội bộ. Giao diện tiếng Việt |
| 7 | Tên mã `TrinhChieu`, giao diện xưng "Hệ thống" |

## Trạng thái

| Mã | Trạng thái | PR |
| --- | --- | --- |
| T0.1 | Xong, chờ Phuoc duyệt PR | #2 |
| T0.3 | Chưa bắt đầu | |
| T0.4 | Mã xong, chờ số đo trên Mac của Phuoc | |
| T0.5 | Chưa bắt đầu | |
| T1.1 đến T1.11 | Chưa bắt đầu | |

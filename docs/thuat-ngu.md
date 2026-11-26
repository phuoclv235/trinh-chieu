# Bảng thuật ngữ

Đã chốt cùng bản kế hoạch kiến trúc (Phuoc duyệt 2026-11-26). Một khái niệm một tên. Đổi tên một khái niệm thì đổi ở mọi nơi (code, giao diện, tài liệu) trong cùng một PR.

## Khái niệm sản phẩm

| Khái niệm | Tên trên giao diện | Tên trong code | Không dùng |
| --- | --- | --- | --- |
| Tệp nội dung gồm nhiều trang (một bài hát, một bài giảng) | Bộ trình chiếu | `Presentation` | Bài trình chiếu, deck, slideshow |
| Một trang trong bộ | Trang chiếu | `Slide` | Slide, khung |
| Nhóm trang có nhãn (Câu 1, Điệp khúc) | Đoạn | `SlideGroup` | Group, phân đoạn |
| Thứ tự trình bày các đoạn | Thứ tự hát | `Arrangement` | Arrangement, sắp xếp |
| Danh sách các mục của một buổi | Chương trình buổi nhóm | `ServicePlan` | Playlist, danh sách phát |
| Một mục trong chương trình | Mục | `ServicePlanItem` | Cue |
| Hình thức áp cho nội dung | Mẫu trình bày | `Theme` | Theme, chủ đề, template |
| Ô chữ có vai trò trong mẫu (thân, tiêu đề, địa chỉ câu) | Ô mẫu | `ThemeSlot` | Placeholder |
| Đích nhận hình (màn hình, NDI, camera ảo) | Đầu ra | `Output` | Màn hình (khi nói chung) |
| Mặt phẳng điểm ảnh để dàn nội dung | Khung vẽ | `Canvas` | Canvas |
| Bộ thiết lập lớp nào ra đầu ra nào | Cảnh đầu ra | `OutputLook` | Look |
| Màn cho người trên bục | Màn hình nhắc | `StageDisplay` | Stage display |
| Camera, NDI, cửa sổ chụp | Nguồn vào | `InputSource` | Input |
| Tầng hình trong bộ trộn | Lớp | `Layer` | Layer |
| Hình đè lên trên (logo, đồng hồ, tên diễn giả) | Lớp phủ | `Overlay` | Overlay, prop |
| Chuỗi lệnh gộp một nút | Thao tác nhanh | `Macro` | Macro |
| Đưa nội dung ra đầu ra | Lên màn | `goLive` | Go live, phát |
| Bỏ nội dung khỏi một lớp | Xoá lớp | `clearLayer` | Clear |
| Giữ nguyên hình đang chiếu, không nhận thay đổi | Đóng băng | `freeze` | Freeze |
| Chạy thật nhưng không đưa ra đầu ra chính | Tập dượt | `rehearsal` | Rehearsal |
| Ảnh, video, âm thanh trong thư viện | Media | `MediaAsset` | Tài nguyên, asset |
| Toàn bộ dữ liệu người dùng trên đĩa | Thư viện | `Library` | Kho, database |
| Một bản Kinh Thánh | Bản dịch | `BibleTranslation` | Phiên bản (dễ nhầm) |
| Địa chỉ câu Kinh Thánh (Giăng 3:16) | Địa chỉ câu | `ScriptureReference` | Tham chiếu |
| Ô tìm mọi thứ bằng ⌘K | Bảng lệnh | `CommandPalette` | Spotlight |
| Gói xuất kèm media để mang sang máy khác | Gói mang đi | `PortableBundle` | Export, archive |
| Ghi mốc giờ từng mục, từng lần lên màn | Nhật ký buổi nhóm | `ServiceLog` | Log |

## Phân biệt các từ dễ nhầm

- **Phiên bản phần mềm** (1.2.0) khác **phiên bản định dạng tệp** (`schemaVersion`) khác **bản dịch** Kinh Thánh. Không gọi bản dịch là "phiên bản".
- **Đầu ra** là đích (một màn hình cụ thể). **Màn hình nhắc** là một loại nội dung có thể gửi tới một đầu ra.
- **Mẫu trình bày** là hình thức. **Bộ trình chiếu** là nội dung. Đổi mẫu không sửa nội dung.

## Thuật ngữ tôn giáo (Tin Lành)

| Dùng | Không dùng |
| --- | --- |
| Hội Thánh | Giáo hội |
| Buổi nhóm, nhóm thờ phượng | Thánh lễ |
| Mục sư, Truyền đạo | Linh mục, Cha |
| Chúa Nhật | Chủ nhật (trong ngữ cảnh Hội Thánh) |
| Thánh ca, Thi thiên | Thánh vịnh |
| Kinh Thánh | Thánh Kinh (trừ khi trích tên riêng) |
| Lời cầu nguyện | Kinh nguyện |

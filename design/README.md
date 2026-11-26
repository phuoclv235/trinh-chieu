# Mẫu giao diện TrinhChieu (T0.3)

Hướng thẩm mỹ: **Hướng 5 · Bàn trộn**. Phuoc tạm chọn ngày 2026-11-27 ("Tạm dùng") và cho tự duyệt khi xong ("Xong thì tự duyệt làm tiếp"). Quy tắc rút ra ở `docs/ui-rules.md`.

## Cách mở

Mở trực tiếp bằng trình duyệt, không cần máy chủ, không tải tài nguyên ngoài. Thanh nhỏ ở góc dưới trái (chỉ có trong mẫu) dùng để chuyển màn, đổi sáng tối, đổi phông A/B và xem các trạng thái (Tập dượt, Đóng băng, Bảng lệnh, hộp xoá, thư viện rỗng…). Thêm `?theme=light`, `?font=b`, `?state=rehearsal` vào địa chỉ để mở thẳng một trạng thái.

| Tệp | Màn |
| --- | --- |
| `components.html` | Bảng thành phần dùng chung |
| `live.html` | Trực tiếp. Bấm thẻ để lên màn; `→ ← Space`, `F1` đến `F3`, `⌘K`, `⌘R`, `⌘⇧F` chạy được |
| `editor.html` | Soạn thảo |
| `library.html` | Thư viện (cửa sổ riêng, quản lý) |
| `settings-outputs.html` | Cài đặt đầu ra, âm thanh media, thư mục thư viện |
| `stage.html` | Màn hình nhắc (hình ra đầu ra, luôn nền đen) |
| `tokens.css`, `ui.css`, `ui.js`, `data.js` | Biến thiết kế, thành phần, biểu tượng và thanh duyệt, dữ liệu mẫu |
| `huong/` | Năm hướng thẩm mỹ đã đưa Phuoc chọn ở bước 1 (lưu để tham khảo) |
| `tools/screenshots.cjs`, `tools/contrast.cjs` | Chụp 30 ảnh và kiểm tràn, lỗi console, chữ bị cắt; kiểm tương phản |
| `screenshots/` | `<màn>-<rộng>-<sang|toi>.png`, 1280×800, 1512×945, 1920×1080, `deviceScaleFactor: 2` |

Chạy lại: `node design/tools/screenshots.cjs` và `node design/tools/contrast.cjs` (cần Playwright, có sẵn trong container).

## Hướng 5 · Bàn trộn

- Tối chuyên nghiệp, nút là khối rõ ràng, viền mọi điều khiển 1 px cùng một màu, bo 6 px.
- Cam đất là màu duy nhất mang nghĩa "đang hoạt động, đang lên màn". Tập dượt hồng sen, Đóng băng xanh băng, trễ giờ vàng chanh, đúng giờ xanh lá.
- Đèn trạng thái thở nhẹ (nhịp 2,6 giây) chỉ ở chỗ đang hoạt động: trang đang lên màn, mục đang chiếu, lớp đang có nội dung, đầu ra đang nhận hình. Tắt khi bật "Giảm chuyển động".
- Khối **Luồng tín hiệu** ở cột phải màn Trực tiếp: mỗi lớp là một nút nối dây tới đầu ra đang nhận nó; bấm nút lớp là xoá lớp đó (cùng phím F2, F3, F4). Đây là nền cho nhiều đầu ra, camera, NDI ở giai đoạn sau.
- Giờ, phím tắt, bộ đếm dùng chữ số đều cột (SF Mono trên Mac).

## Quyết định

| # | Quyết định | Trạng thái |
| --- | --- | --- |
| 1 | Phông giao diện: (A) San Francisco của hệ thống hoặc (B) Inter đóng gói | **Theo khuyến nghị A** (tự duyệt). A đúng chất Mac, dấu tiếng Việt chuẩn, không phải đóng gói. Bật B trên thanh mẫu để so; Inter rút gọn ở `fonts/` (OFL) chỉ dùng cho mẫu |
| 2 | Màu chủ đạo | **Cam đất** `#F0814A` (tối), `#9E4317` (sáng), theo ảnh tham khảo Phuoc gửi. Khác hẳn hồng sen của Tập dượt |
| 3 | Chế độ mặc định | **Tối**. Bản sáng đầy đủ cho soạn bài ban ngày |

## Số thao tác

| Tình huống | Mục tiêu | Trong mẫu |
| --- | --- | --- |
| Chiếu một câu Kinh Thánh | 3 | **3**: `⌘K`, gõ "gi 3 16", `Enter` |
| Chuyển trang kế | 1 | **1**: `→` (hoặc `Space`, `↓`, `PageDown`) |
| Đưa một bài hát từ thư viện vào chương trình rồi lên màn | 4 | **4**: `⌘F` vào ô tìm thư viện, gõ tên, bấm đúp bài (thêm vào cuối chương trình **và chọn luôn mục mới**), bấm thẻ trang |
| Xoá chữ khỏi màn khẩn cấp | 1 | **1**: `F2` (hoặc bấm nút Chữ trong Luồng tín hiệu; `F1` xoá tất cả) |

## Tương phản WCAG AA

Tính từ `tokens.css` bằng `tools/contrast.cjs`. Chữ thường cần 4,5:1. Dòng cuối là mục tiêu riêng cho viền điều khiển.

| Cặp | Tối | Sáng | Tối thiểu | Kết quả |
| --- | --- | --- | --- | --- |
| `--text` trên `--bg-panel` | 15.57 | 16.82 | 4.5 | Đạt |
| `--text-2` trên `--bg-panel` | 7.67 | 7.66 | 4.5 | Đạt |
| `--text-3` trên `--bg-panel` | 5.71 | 5.67 | 4.5 | Đạt |
| `--text-3` trên `--bg-window` | 5.90 | 5.19 | 4.5 | Đạt |
| `--text-3` trên `--bg-stage` | 6.13 | 4.70 | 4.5 | Đạt |
| `--text-3` trên `--bg-raised` | 5.24 | 6.07 | 4.5 | Đạt |
| `--text-2` trên `--bg-raised` | 7.04 | 8.20 | 4.5 | Đạt |
| `--accent` trên `--bg-panel` | 7.02 | 6.00 | 4.5 | Đạt |
| `--accent` trên `--bg-stage` | 7.54 | 4.98 | 4.5 | Đạt |
| `--on-accent` trên `--accent-fill` | 7.13 | 6.42 | 4.5 | Đạt |
| `--warn` trên `--bg-panel` | 6.07 | 5.47 | 4.5 | Đạt |
| `--late` trên `--bg-panel` | 11.91 | 4.60 | 4.5 | Đạt |
| `--late-ink` trên `--late` | 11.64 | 4.92 | 4.5 | Đạt |
| `--freeze` trên `--bg-panel` | 11.39 | 4.60 | 4.5 | Đạt |
| `--ok` trên `--bg-panel` | 9.67 | 4.70 | 4.5 | Đạt |
| `--danger` trên `--bg-overlay` | 6.28 | 5.61 | 4.5 | Đạt |
| `--on-danger` trên `--danger-fill` | 5.06 | 5.61 | 4.5 | Đạt |
| `--line-strong` trên `--bg-panel` | 1.61 | 1.62 | 1.5 | Đạt |

Chữ của điều khiển bị tắt (`--text-disabled`) không tính, theo miễn trừ của WCAG.

## Điểm lệch so với đặc tả T0.3

1. Làm hai bước theo yêu cầu của Phuoc: bước 1 đưa 5 hướng thẩm mỹ (`huong/`), bước 2 làm chi tiết hướng được chọn.
2. Khối "Lớp: Chữ, Nền, Âm thanh" ở cột phải thành sơ đồ Luồng tín hiệu dạng nút (theo tiêu chí "kết hợp node và layer" của Phuoc). Phím F1 đến F4 giữ nguyên.
3. Tập dượt dùng hồng sen thay hổ phách, vì hổ phách gần cam đất. Viền cửa sổ 2 px khi tập dượt giữ nguyên.
4. Bảng thuộc tính của Soạn thảo có 4 tab theo T1.9 (Chữ, Bố cục, Nền trang, Bộ trình chiếu), không phải 3.
5. Trang Cài đặt đầu ra gộp cả mục Âm thanh media và Thư mục thư viện vì đặc tả T0.3 yêu cầu trên cùng trang; ứng dụng thật vẫn chia 4 tab như T1.7.
6. Đề xuất cho T1.8: bấm đúp bài trong thư viện thì thêm vào cuối chương trình **và chọn mục mới**, để đạt 4 bước.
7. Tên trong `docs/thuat-ngu.md` được giữ nguyên trên mọi màn.

## Ghi chú về nội dung mẫu

- Ảnh chụp trên Linux nên phông A hiện thành Inter; trên Mac là San Francisco.
- Ảnh chụp là khung tĩnh (tắt hiệu ứng); mở tệp HTML để thấy đèn thở và dòng chảy trên dây.
- Lời "Đấng Chăn Giữ Tôi" là văn bản mẫu phỏng theo Thi Thiên 23, không trích sách Thánh Ca. Câu Kinh Thánh trích Bản Truyền Thống 1925. Số thánh ca là số mẫu, chưa đối chiếu sách Thánh Ca. Bản Hiệu Đính 2010 chỉ xuất hiện tên, không có chữ.

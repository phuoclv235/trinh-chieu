# Quy tắc giao diện

Chốt theo mẫu T0.3, hướng **Bàn trộn** (Phuoc tạm chọn 2026-11-27, cho tự duyệt khi xong). Nguồn sự thật cho màu, cỡ, bo góc: `design/tokens.css`; thành phần: `design/ui.css` và `design/components.html`. Ứng dụng Swift đọc lại các giá trị này (Asset Catalog, hằng số), không tự đặt giá trị mới.

## Màu và nghĩa

| Nghĩa | Biến | Tối | Sáng |
| --- | --- | --- | --- |
| Đang hoạt động, đang lên màn (màu chủ đạo) | `--accent` | #F0814A | #9E4317 |
| Tập dượt | `--warn` | #E6699D | #B3326B |
| Đóng băng | `--freeze` | #8FD4F4 | #1B78A3 |
| Trễ giờ, mục thiếu tệp | `--late` | #E8CF55 | #8A6D00 |
| Đúng giờ, khung hình đều | `--ok` | #6FCF86 | #1D7F45 |
| Xoá | `--danger-fill` | #C93A3A | #C22F2F |

- Một màu một nghĩa. Không dùng cam đất cho trang trí hay nút không liên quan tới trạng thái "đang hoạt động", trừ nút chính duy nhất của một màn.
- Chỉ có giao diện tối (Phuoc chốt 2026-11-28): không có tuỳ chọn sáng, không theo chế độ sáng của macOS.
- Nền than chì ngả xanh đêm, bốn tầng: `--bg-stage` (lưới, khung vẽ) < `--bg-window` < `--bg-panel` < `--bg-raised`.
- Không quầng tím, gradient hào nhoáng, kính mờ, biểu tượng hoạt hình. Chỉ nền mẫu trình bày trên trang chiếu được có ánh ấm.

## Hình khối

- Viền mọi điều khiển: 1 px `--line-strong`. Chia vùng: 1 px `--line`.
- Bo góc: 6 px cho điều khiển, thẻ trang chiếu, nút lớp; 8 px cho phiến chọn và nhóm biểu mẫu; 10 px cho hộp thoại, bảng lệnh.
- Phiến chọn trong danh sách: nền `--accent-soft` và vạch trái 2 px cam đất. Vòng focus 2 px cam đất vẽ vào trong.
- Thẻ trang chiếu: vạch màu đoạn ở đáy thẻ; rê chuột viền mảnh `--accent-line`; kế tiếp viền 1 px cam đất; đang lên màn viền 2 px và quầng thở.
- Bóng chỉ cho lớp nổi (hộp thoại, bảng lệnh, chú giải, thanh chọn).

## Chữ

- Phông hệ thống (SF Pro Text, SF Pro Display); số, giờ, phím tắt dùng SF Mono.
- Cỡ: 11, 12, 12.5 cho chữ nhỏ; 13 chữ thân; 15 tiêu đề khối; 16 tiêu đề cột; 26 tiêu đề nguồn; 40 đồng hồ. Không chữ in hoa nhỏ; không biểu tượng ⓘ đứng riêng.

## Đèn trạng thái và chuyển động

- Đèn 7 px. Thở nhịp 2,6 giây chỉ ở chỗ đang hoạt động: trang đang lên màn, mục đang chiếu, lớp đang có nội dung, đầu ra đang nhận hình, đồng hồ khung hình. Không thở ở khối lớn hay nút thường.
- Hiệu ứng giao diện 120 đến 200 ms, đường cong `cubic-bezier(0.2, 0.8, 0.2, 1)`. Tôn trọng "Giảm chuyển động": tắt thở và dòng chảy, giữ quầng tĩnh.

## Điều khiển

- Nút chính dùng động từ ("Lên màn", "Lưu thay đổi", "Chuyển vào Thùng rác"); không "OK".
- Nút biểu tượng luôn có chú giải kèm phím tắt và nhãn trợ năng.
- Xoá luôn hỏi xác nhận nêu tên đối tượng, có Hoàn tác (⌘Z). Riêng xoá mục khỏi chương trình không hỏi, có Hoàn tác.
- Khối Luồng tín hiệu: lớp là nút bên trái, đầu ra là nút bên phải, dây cam đất có dòng chảy khi lớp đang ra đầu ra; bấm nút lớp là xoá lớp.

## Kiểm bắt buộc cho mọi màn

Cửa sổ 1280, 1512, 1920 px, giao diện tối; không tràn ngang; chữ bị cắt phải có chú giải; tương phản chữ đạt WCAG AA (`node design/tools/contrast.cjs`).

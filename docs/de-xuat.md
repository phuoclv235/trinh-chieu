# Đề xuất đang theo dõi

Đề xuất chưa làm hoặc làm dở. Mỗi đề xuất có ưu, khuyết, khuyến nghị và trạng thái. Cập nhật khi đề xuất được làm hoặc bị bỏ.

| # | Đề xuất | Ưu | Khuyết | Khuyến nghị | Trạng thái |
| --- | --- | --- | --- | --- | --- |
| 1 | Gói mang đi: xuất chương trình kèm media thành một tệp | Soạn ở nhà, chiếu ở Hội Thánh | Tệp lớn khi có video | Làm trong MVP | Xong ở T1.3 |
| 2 | Nhật ký buổi nhóm: ghi mốc giờ từng mục, từng lần lên màn | Xem lại lệch giờ, báo cáo bài hát đã dùng, đánh dấu chương cho bản ghi hình | Thêm một màn xem lại | Ghi dữ liệu từ MVP, màn xem lại ở giai đoạn 2 | Phần ghi xong ở T1.3; màn xem lại chưa làm |
| 3 | Thư viện dùng chung nhiều máy qua thư mục đồng bộ | Không cần máy chủ | Hai người sửa cùng bài cùng lúc gây xung đột | Sau MVP; định dạng mỗi bài một tệp ngay từ đầu | Định dạng đã sẵn; phát hiện và giữ bản xung đột xong ở T1.3; màn xử lý xem đề xuất 8 |
| 4 | Kéo phần "khung vẽ kích thước tuỳ ý" vào MVP nếu màn LED cần bố cục riêng từ buổi đầu | LED dùng được ngay | Thêm khoảng 1 tuần | Chỉ làm khi Phuoc xác nhận LED cần | Chờ Phuoc |
| 5 | Camera ảo cho Zoom (chỉ hình) làm sớm ngay sau MVP | Lên Zoom sớm | Cần tài khoản Apple Developer | Làm nếu Zoom gấp | Chờ Phuoc |
| 6 | Trình chiếu đồng bộ nhiều máy: máy chủ điều khiển, các nút trình chiếu tự dựng hình ra đầu ra của mình (Phuoc yêu cầu 2026-11-26) | Linh động vị trí, vượt giới hạn cổng ra của một máy, chất lượng gốc ở mỗi nút | Thêm một chế độ ứng dụng, đồng bộ media và đồng hồ, cần máy chuyển tiếp nếu qua Internet | Giai đoạn mới sau giai đoạn 2; hợp đồng lõi đã chuẩn bị từ giai đoạn 0 | Phuoc chốt cùng mạng nội bộ, media từ NAS qua direct link của Slate, tải qua LAN bằng header `x-slate-net: lan` (2026-11-26); giai đoạn 2b. Phuoc duyệt hướng A, dùng link trực tiếp (2026-11-26). Về sau có thể thêm "Chọn từ Slate" (đề xuất 7) |
| 7 | Tích hợp Slate sâu: nút "Chọn từ Slate" duyệt thư mục và chèn media không cần tạo link chia sẻ từng tệp | Không lo link hết hạn hay bị thu hồi, chọn nhanh nhiều tệp, đồng bộ khi tệp đổi | Cần API và tài khoản dịch vụ phía Slate (sửa cả hai dự án), thêm phần đăng nhập và bảo mật | Sau giai đoạn 2b, khi dùng link trực tiếp thấy vướng | Chưa duyệt |
| 8 | Màn "Xử lý xung đột": so hai bản của cùng bộ trình chiếu cạnh nhau (bản của bạn và tệp `.conflict-` từ máy khác), chọn từng đoạn giữ bản nào | Không mất lời bài hát khi hai máy cùng sửa qua iCloud Drive hay Dropbox; T1.3 đã giữ đủ hai bản | Thêm một màn và phần so khác biệt theo đoạn | Làm cùng hoặc ngay sau T1.9 (trình soạn) | Chưa duyệt |
| 9 | Dọn media không còn dùng: liệt kê media không bộ trình chiếu, mẫu hay chương trình nào tham chiếu, chuyển vào thùng rác | Thư viện gọn, nhất là khi có nhiều video | Phải quét mọi tham chiếu; dễ xoá nhầm media chỉ dùng trong chương trình cũ | Giai đoạn 2, có bước xem trước và thùng rác 30 ngày | Chưa duyệt |
| 10 | Tự xuất gói mang đi của chương trình Chúa Nhật kế tiếp vào thư mục sao lưu (ổ ngoài, NAS) mỗi tối thứ Bảy | Có bản dự phòng đủ media nếu máy chiếu hỏng sáng Chúa Nhật | Tốn chỗ khi có video | Giai đoạn 2, cho bật tắt trong Cài đặt | Chưa duyệt |

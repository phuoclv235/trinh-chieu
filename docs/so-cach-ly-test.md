# Sổ cách ly test

Test chập chờn (lúc xanh lúc đỏ) **không được** tắt hay bỏ qua lặng lẽ để CI xanh. Mỗi test bị cách ly phải ghi vào bảng dưới đây cùng lý do, người xử lý và hạn sửa. Test nằm trong sổ vẫn phải chạy, chỉ được đánh dấu không chặn (ví dụ `.disabled("Xem docs/so-cach-ly-test.md #n")` kèm mục tương ứng).

| # | Test | Từ ngày | Triệu chứng | Nguyên nhân nghi ngờ | Người xử lý | Hạn |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

Quy tắc:

1. Chỉ cách ly khi đã chạy lặp (`swift test --repeat 3`) và thấy kết quả không ổn định.
2. Quá hạn mà chưa sửa thì nêu trong PR kế tiếp để Phuoc quyết định.
3. Khi test được sửa, xoá hàng khỏi bảng trong cùng PR.

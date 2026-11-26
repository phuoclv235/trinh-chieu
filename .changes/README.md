# Ghi chú thay đổi

Mỗi PR thêm đúng một tệp `.changes/<mã-task-hoặc-chủ-đề>.md`.

- **Dòng 1:** `minor` (tính năng mới hoặc đổi hành vi người dùng thấy được) hoặc `patch` (sửa lỗi, chỉnh nhỏ, hạ tầng).
- **Các dòng sau:** mô tả tiếng Việt cho người dùng cuối, ngắn gọn, nói điều gì thay đổi với họ.

Ví dụ:

```
minor
Hệ thống có thể tìm câu Kinh Thánh bằng cách gõ không dấu.
```

Không sửa `CHANGELOG.md` hay số phiên bản trong PR. Việc gộp các tệp ở đây vào `CHANGELOG.md` và nâng phiên bản làm khi phát hành (giai đoạn 8).

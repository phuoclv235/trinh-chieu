# Ảnh chuẩn của test ảnh `RenderEngine`

Mỗi tệp `<tên>.png` là ảnh 960x540 mà `RenderEngine.renderOffscreen` phải dựng ra cho cảnh cùng tên trong `GoldenSceneTests.swift`. Test so ảnh dựng với ảnh chuẩn: sai số trung bình dưới 1% và không điểm ảnh nào lệch quá 8% trên một kênh.

- Dựng lại: `scripts/update-golden.sh` (chỉ trên Mac). Chỉ chạy khi thay đổi hình có chủ ý, và nêu rõ trong PR kèm ảnh trước và sau.
- Khi thư mục này chưa có ảnh nào, test chỉ kiểm tính chất (màu điểm ảnh, vị trí chữ) và bỏ qua bước so. Có ít nhất một ảnh thì mọi cảnh đều phải có ảnh chuẩn.
- Ảnh lệch hoặc thiếu được ghi ra `TRINHCHIEU_GOLDEN_OUTPUT` (CI macOS tải lên thành artifact `anh-test-render`).

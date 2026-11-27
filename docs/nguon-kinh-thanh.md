# Nguồn bản dịch Kinh Thánh

Ghi nguồn, giấy phép và mã băm của mọi tệp Kinh Thánh trước khi nhập hoặc đóng gói. **Chỉ đóng gói vào ứng dụng khi Phuoc đã duyệt dòng tương ứng.** Không đưa tệp bản dịch vào repo, kể cả thư mục test (test dùng dữ liệu tự tạo trong `Tests/ImportersTests/Fixtures/Bible/`, không phải chữ của bản dịch thật nào).

| Mã | Bản dịch | Nguồn đề xuất | Định dạng | Giấy phép | SHA-256 tệp | Trạng thái |
| --- | --- | --- | --- | --- | --- | --- |
| `vi1925` | Bản Truyền Thống 1925 (eBible.org ghi là "Vietnamese 1934", mã `vie1934`) | eBible.org: trang chi tiết `https://ebible.org/details.php?id=vie1934`, trang bản quyền `https://ebible.org/vie1934/copyright.htm`; tệp USFM `vie1934_usfm.zip` | USFM, mỗi sách một tệp (bộ nhập `USFMImporter` gộp nhiều tệp) | eBible.org ghi là phạm vi công cộng; **chưa xác minh** vì container đám mây bị chặn truy cập eBible.org (2026-11-27) | Chưa có (tính khi tải trên Mac của Phuoc) | Chờ xác minh giấy phép, rồi chờ Phuoc duyệt đóng gói |
| `vi2010` | Bản Hiệu Đính 2010 | Tệp Phuoc tự có | Chờ Phuoc cho biết | Còn bản quyền: `meta.license` = "Chỉ dùng nội bộ, chưa có giấy phép phân phối" (`BibleLicense.internalUseOnly`). Không đóng gói, không đưa vào repo | Không ghi | Chờ Phuoc gửi định dạng tệp |

## Cách xác minh và nhập Bản Truyền Thống 1925 (làm trên Mac của Phuoc)

1. Mở trang bản quyền ở trên, chụp hoặc chép nguyên văn dòng giấy phép vào cột "Giấy phép".
2. Tải `vie1934_usfm.zip`, ghi `shasum -a 256 vie1934_usfm.zip` vào cột SHA-256.
3. Nhập bằng `BibleImportRegistry.standard.importBible(files:)` với mọi tệp `.usfm` trong gói, rồi gọi `bookNameDifferences()` để đối chiếu tên 66 sách với danh mục `books-vi.json` (việc T1.2 để lại). Sửa `books-vi.json` nếu tên trong tệp đúng chính tả 1925 hơn.
4. Dừng, gửi Phuoc kết quả trước khi đóng gói vào ứng dụng.

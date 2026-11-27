# Ảnh chụp giá trị của cảnh (T1.5)

Mỗi tệp JSON là một `ScenePublication` (đầu ra chính và màn hình nhắc, `revision` đặt 0) mà `SceneSnapshotTests`
mong đợi từ thư viện mẫu ở `ShowLibraryFixture.swift`. Test so giá trị sau khi giải mã, không so từng ký tự.

Khi cố ý đổi cách dựng cảnh: chạy `UPDATE_SNAPSHOTS=1 swift test --filter SceneSnapshotTests` để ghi lại tệp, rồi xem
kỹ phần khác trong diff trước khi commit. Test hỏng cũng in JSON thật ra log lỗi chuẩn (giữa hai dòng
`SNAPSHOT <tên> BẮT ĐẦU` và `SNAPSHOT <tên> KẾT THÚC`).

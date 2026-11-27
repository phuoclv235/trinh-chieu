import CoreModel
import Foundation
import Synchronization

@testable import LibraryStore

/// Thư mục tạm riêng cho từng test, xoá khi xong.
struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Thư mục con (thư viện, nơi xuất gói), tạo nếu chưa có.
    func child(_ name: String) throws -> URL {
        let child = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        return child
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Đồng hồ giả: trả mốc giờ cố định, test tự đẩy tới.
final class FakeClock: Sendable {
    private let current: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_795_000_000)) {
        current = Mutex(start)
    }

    var now: Date {
        current.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

/// Thiết lập cho test: đồng hồ giả, ghi hoãn rất lâu (test tự gọi `flush`), nhật ký buổi nhóm ghi khi `flush`.
func testConfiguration(clock: FakeClock, writeDelay: Duration = .seconds(3_600)) -> LibraryStoreConfiguration {
    LibraryStoreConfiguration(
        writeDelay: writeDelay, serviceLogInterval: .seconds(3_600), now: { clock.now },
        timeZone: TimeZone(secondsFromGMT: 7 * 3_600)!)
}

/// Bài hát có một đoạn, hai trang chữ.
func makeSong(
    _ number: Int, title: String? = nil, lyrics: String? = nil, date: Date = Date(timeIntervalSince1970: 1_790_000_000)
) -> Presentation {
    let first = TextElement(slot: .body, text: lyrics ?? "Lời bài số \(number)\nCa ngợi Chúa")
    let second = TextElement(slot: .body, text: "Điệp khúc bài \(number)")
    let group = SlideGroup(
        label: GroupLabel(kind: .verse, number: 1),
        slides: [Slide(elements: [.text(first)]), Slide(notes: "Ghi chú \(number)", elements: [.text(second)])])
    let arrangement = Arrangement(name: "Mặc định", groupIDs: [group.id])
    return Presentation(
        kind: .song, title: title ?? "Thánh ca \(number)", createdAt: date, modifiedAt: date, tags: ["thánh ca"],
        song: SongInfo(number: String(number), hymnal: "Thánh Ca", authors: ["Tác giả \(number)"]), groups: [group],
        arrangements: [arrangement], activeArrangementID: arrangement.id)
}

/// Ghi thẳng một tài liệu xuống thư mục thư viện (giả lập tệp có sẵn hoặc chương trình khác ghi).
func writeDocument<T: Encodable>(_ value: T, to root: URL, path: String) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try DocumentCoding.encode(value).write(to: url)
}

/// Ghi số đo ra luồng lỗi chuẩn để thấy trong log CI (test không dùng `print`).
func reportMeasurement(_ line: String) {
    FileHandle.standardError.write(Data("ĐO HIỆU NĂNG: \(line)\n".utf8))
}

func fileExists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

import Foundation

@testable import LibraryIndex

/// Thư mục tạm riêng cho từng test, xoá khi xong.
struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var indexURL: URL {
        url.appendingPathComponent(".cache/index.sqlite")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func song(_ id: String, _ title: String, number: String? = nil, lyrics: String? = nil) -> IndexEntry {
    IndexEntry(id: id, kind: .presentation, title: title, subtitle: number, body: lyrics)
}

func verse(_ id: String, reference: String, text: String) -> IndexEntry {
    IndexEntry(id: id, kind: .verse, title: reference, subtitle: reference, body: text)
}

/// Bộ sinh số giả ngẫu nhiên có hạt giống, để dữ liệu thử lần nào cũng như nhau.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Ghi số đo ra luồng lỗi chuẩn để thấy trong log CI (test không dùng `print`).
func reportMeasurement(_ line: String) {
    FileHandle.standardError.write(Data("ĐO HIỆU NĂNG: \(line)\n".utf8))
}

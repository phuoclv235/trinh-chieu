import Foundation

@testable import Scripture

/// Thư mục tạm riêng cho từng test, xoá khi xong.
struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var biblesURL: URL {
        url.appendingPathComponent("bibles", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Bản dịch giả 3 sách để thử, không dùng chữ của bản dịch thật nào.
///
/// - Sáng-thế Ký: 2 chương, mỗi chương 10 câu.
/// - Thi-thiên: khai báo 150 chương, chỉ có chữ cho chương 23 (6 câu) và 117 (2 câu).
/// - Giăng: 21 chương, mỗi chương 5 câu, riêng chương 3 có 36 câu.
enum FakeBible {
    static let code = "thu3"

    static let info = TranslationInfo(
        code: code, name: "Bản thử ba sách", abbreviation: "THU", language: "vi", license: "Dữ liệu thử",
        source: "TestSupport.swift", importedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    static let books = [
        BookInfo(osis: "Gen", ordinal: 1, name: "Sáng-thế Ký", chapters: 2),
        BookInfo(osis: "Ps", ordinal: 19, name: "Thi-thiên", chapters: 150),
        BookInfo(osis: "John", ordinal: 43, name: "Giăng", chapters: 21),
    ]

    static let verses: [Verse] = {
        var result: [Verse] = []
        for chapter in 1...2 {
            for verse in 1...10 {
                result.append(Verse(book: "Gen", chapter: chapter, verse: verse, text: text("Gen", chapter, verse)))
            }
        }
        for (chapter, count) in [(23, 6), (117, 2)] {
            for verse in 1...count {
                result.append(Verse(book: "Ps", chapter: chapter, verse: verse, text: text("Ps", chapter, verse)))
            }
        }
        for chapter in 1...21 {
            for verse in 1...(chapter == 3 ? 36 : 5) {
                result.append(Verse(book: "John", chapter: chapter, verse: verse, text: text("John", chapter, verse)))
            }
        }
        // Ghi lộn thứ tự để chắc kho tự sắp lại khi đọc.
        return result.reversed()
    }()

    static func text(_ book: String, _ chapter: Int, _ verse: Int) -> String {
        "Lời thử \(book) \(chapter):\(verse), Đấng Christ yêu thương Hội Thánh."
    }

    static func makeStore(_ dir: borrowing TemporaryDirectory) async throws -> BibleStore {
        let store = BibleStore(directory: dir.biblesURL)
        try await store.write(code: code, info: info, books: books, verses: verses)
        return store
    }
}

/// Phân tích địa chỉ bằng danh mục chuẩn; ca thử luôn hợp lệ.
func reference(_ text: String) -> ScriptureReference {
    guard case .reference(let reference) = ReferenceParser().parse(text) else {
        preconditionFailure("Địa chỉ thử không hợp lệ: \(text)")
    }
    return reference
}

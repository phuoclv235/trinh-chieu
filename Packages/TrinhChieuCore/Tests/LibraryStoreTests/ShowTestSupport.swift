import CoreModel
import Foundation
import Scripture

@testable import LibraryStore

/// Đồng hồ trình chiếu giả: thời gian do test đặt, nhịp do test gọi.
@MainActor final class ManualShowClock: ShowClock {
    var now: Date
    private var handler: (@MainActor () -> Void)?

    init(now: Date) {
        self.now = now
    }

    func startTicking(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func stopTicking() {
        handler = nil
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    func fire() {
        handler?()
    }
}

/// Nơi nhận cảnh ghi lại lần giao cuối.
@MainActor final class LastSceneSink: SceneSink {
    var outputs: [ScenePublication] = []
    var previews: [ScenePublication] = []

    func publishToOutputs(_ publication: ScenePublication) {
        outputs.append(publication)
    }

    func publishToPreview(_ publication: ScenePublication) {
        previews.append(publication)
    }
}

/// UUID cố định dễ đọc cho test.
func fixedID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", number))!
}

/// Bản dịch giả một sách (Giăng, 3 chương, mỗi chương 18 câu), không dùng chữ của bản dịch thật nào.
enum SampleBible {
    static let code = "thu1"

    static let info = TranslationInfo(
        code: code, name: "Bản thử một sách", abbreviation: "THU", language: "vi", license: "Dữ liệu thử",
        source: "ShowTestSupport.swift", importedAt: Date(timeIntervalSince1970: 1_800_000_000))

    static func verses() -> [Verse] {
        (1...3).flatMap { chapter in
            (1...18).map { verse in
                Verse(
                    book: "John", chapter: chapter, verse: verse,
                    text: "Lời thử Giăng \(chapter):\(verse). Đức Chúa Trời yêu thương thế gian, ban Con một của Ngài.")
            }
        }
    }

    /// Ghi bản dịch vào `directory` rồi mở ra.
    static func open(in directory: URL) async throws -> BibleTranslation {
        let store = BibleStore(directory: directory)
        let books = [BookInfo(osis: "John", ordinal: 43, name: "Giăng", chapters: 3)]
        try await store.write(code: code, info: info, books: books, verses: verses())
        return try await store.open(code)
    }
}

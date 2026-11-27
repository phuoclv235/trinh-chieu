import Foundation
import Testing

@testable import Scripture

@Suite("BibleStore: kho bản dịch")
struct BibleStoreTests {
    @Test("Ghi bản dịch giả 3 sách rồi liệt kê, mở, đọc thông tin")
    func writeAndList() async throws {
        let dir = try TemporaryDirectory()
        let store = try await FakeBible.makeStore(dir)
        let list = try await store.translations()
        #expect(list.map { $0.code } == [FakeBible.code])
        #expect(list.first == FakeBible.info)
        #expect(list.first?.displayAbbreviation == "THU")

        let bible = try await store.open(FakeBible.code)
        #expect(bible.books().map { $0.osis } == ["Gen", "Ps", "John"])
        #expect(bible.verseCount(book: "John", chapter: 3) == 36)
        #expect(bible.verseCount(book: "John", chapter: 4) == 5)
        #expect(bible.verseCount(book: "John", chapter: 22) == 0)
        #expect(bible.verseCount(book: "Rev", chapter: 1) == 0)
        #expect(try await store.open(FakeBible.code) === bible)
    }

    @Test("Tra đoạn câu: một chương, vắt chương, cả chương, nhiều đoạn theo thứ tự gõ")
    func lookup() async throws {
        let dir = try TemporaryDirectory()
        let bible = try await FakeBible.makeStore(dir).open(FakeBible.code)

        let three = try bible.verses(reference("gi 3:16-18"))
        #expect(three.map { $0.verse } == [16, 17, 18])
        #expect(three.first == Verse(book: "John", chapter: 3, verse: 16, text: FakeBible.text("John", 3, 16)))

        let across = try bible.verses(reference("gi 3:35-4:2"))
        #expect(across.map { "\($0.chapter):\($0.verse)" } == ["3:35", "3:36", "4:1", "4:2"])

        #expect(try bible.verses(reference("thi 23")).count == 6)
        #expect(try bible.verses(reference("gi 2-3")).count == 41)

        let mixed = try bible.verses(reference("gi 3:16; sa 1:1-2; gi 1:1"))
        let places = mixed.map { "\($0.book) \($0.chapter):\($0.verse)" }
        #expect(places == ["John 3:16", "Gen 1:1", "Gen 1:2", "John 1:1"])
    }

    @Test("Ngoài phạm vi báo lỗi tiếng Việt")
    func outOfRange() async throws {
        let dir = try TemporaryDirectory()
        let bible = try await FakeBible.makeStore(dir).open(FakeBible.code)

        #expect(throws: ScriptureError.chapterOutOfRange(book: "Giăng", chapter: 22, chapterCount: 21)) {
            try bible.verses(reference("gi 22"))
        }
        let chapterError = ScriptureError.chapterOutOfRange(book: "Giăng", chapter: 22, chapterCount: 21)
        #expect(chapterError.message == "Giăng chỉ có 21 chương.")
        #expect(throws: ScriptureError.verseOutOfRange(book: "Giăng", chapter: 3, verse: 40, verseCount: 36)) {
            try bible.verses(reference("gi 3:16-40"))
        }
        let verseError = ScriptureError.verseOutOfRange(book: "Giăng", chapter: 3, verse: 40, verseCount: 36)
        #expect(verseError.message == "Giăng 3 chỉ có 36 câu.")
        #expect(throws: ScriptureError.bookNotInTranslation(book: "Rô-ma", translation: "Bản thử ba sách")) {
            try bible.verses(reference("ro 8:28"))
        }
        #expect(throws: ScriptureError.chapterOutOfRange(book: "Sáng-thế Ký", chapter: 3, chapterCount: 2)) {
            try bible.verses(reference("sa 1:1-3:1"))
        }
    }

    @Test("Mở bản dịch không có hoặc mã sai")
    func openErrors() async throws {
        let dir = try TemporaryDirectory()
        let store = try await FakeBible.makeStore(dir)
        await #expect(throws: ScriptureError.translationNotFound(code: "vi1925")) {
            try await store.open("vi1925")
        }
        await #expect(throws: ScriptureError.invalidTranslationCode(code: "../thu3")) {
            try await store.open("../thu3")
        }
        #expect(ScriptureError.translationNotFound(code: "vi1925").message.contains("không tìm thấy bản dịch"))
        #expect(try await BibleStore(directory: dir.url.appendingPathComponent("khong-co")).translations().isEmpty)
    }

    @Test("Mọi câu theo thứ tự quy điển, cho lập chỉ mục")
    func allVersesInCanonicalOrder() async throws {
        let dir = try TemporaryDirectory()
        let bible = try await FakeBible.makeStore(dir).open(FakeBible.code)
        let all = Array(bible.allVerses())
        #expect(all.count == FakeBible.verses.count)
        #expect(all.first.map { "\($0.book) \($0.chapter):\($0.verse)" } == "Gen 1:1")
        #expect(all.last.map { "\($0.book) \($0.chapter):\($0.verse)" } == "John 21:5")
        let psalms = all.firstIndex(where: { $0.book == "Ps" }) ?? -1
        let john = all.firstIndex(where: { $0.book == "John" }) ?? -1
        #expect(psalms >= 0 && psalms < john)
    }

    @Test("Ghi đè thay tệp cũ; ghi lỗi giữ nguyên tệp cũ, không để lại tệp tạm")
    func overwriteIsAtomic() async throws {
        let dir = try TemporaryDirectory()
        let store = try await FakeBible.makeStore(dir)
        _ = try await store.open(FakeBible.code)

        var renamed = FakeBible.info
        renamed.name = "Bản thử đã sửa"
        let genesisOnly = FakeBible.verses.filter { $0.book == "Gen" }
        try await store.write(code: FakeBible.code, info: renamed, books: [FakeBible.books[0]], verses: genesisOnly)
        let reopened = try await store.open(FakeBible.code)
        #expect(reopened.info.name == "Bản thử đã sửa")
        #expect(reopened.books().map { $0.osis } == ["Gen"])

        let stray = [Verse(book: "Rev", chapter: 1, verse: 1, text: "Không khai báo")]
        await #expect(throws: ScriptureError.self) {
            try await store.write(code: FakeBible.code, info: renamed, books: [FakeBible.books[0]], verses: stray)
        }
        let duplicate = Array(genesisOnly.prefix(1)) + Array(genesisOnly.prefix(1))
        await #expect(throws: ScriptureError.self) {
            try await store.write(code: FakeBible.code, info: renamed, books: [FakeBible.books[0]], verses: duplicate)
        }
        #expect(try await store.open(FakeBible.code).info.name == "Bản thử đã sửa")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.biblesURL.path)
        #expect(files == ["\(FakeBible.code).sqlite"])
    }

    @Test("Chữ câu được chuẩn hoá NFC khi ghi")
    func textIsNormalized() async throws {
        let dir = try TemporaryDirectory()
        let store = BibleStore(directory: dir.biblesURL)
        let decomposed = "Đức Chúa Trời".decomposedStringWithCanonicalMapping
        try await store.write(
            code: "nfc", info: FakeBible.info, books: [FakeBible.books[0]],
            verses: [Verse(book: "Gen", chapter: 1, verse: 1, text: decomposed)]
        )
        let verse = try await store.open("nfc").verses(reference("sa 1:1")).first
        let expected = Array("Đức Chúa Trời".precomposedStringWithCanonicalMapping.unicodeScalars)
        #expect(verse.map { Array($0.text.unicodeScalars) } == expected)
        #expect(try await store.open("nfc").info.code == "nfc")
    }

    @Test("Đọc song song từ nhiều tác vụ")
    func concurrentReads() async throws {
        let dir = try TemporaryDirectory()
        let bible = try await FakeBible.makeStore(dir).open(FakeBible.code)
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for chapter in 1...21 {
                group.addTask { try bible.verses(reference("gi \(chapter)")).count }
            }
            var total = 0
            for try await count in group { total += count }
            return total
        }
        #expect(counts == 20 * 5 + 36)
    }

    @Test("Tra một đoạn 10 câu dưới 1 ms")
    func lookupIsFast() async throws {
        let dir = try TemporaryDirectory()
        let bible = try await FakeBible.makeStore(dir).open(FakeBible.code)
        let ref = reference("gi 3:16-25")
        #expect(try bible.verses(ref).count == 10)
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<200 {
            let elapsed = try clock.measure { _ = try bible.verses(ref) }
            samples.append(elapsed)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        #expect(median < .milliseconds(1), "trung vị \(median)")
    }
}

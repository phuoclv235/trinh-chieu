import Foundation
import Scripture
import Testing

@testable import Importers

/// Câu dạng "Gen 1:1 chữ" để so gọn.
func verseLines(_ outcome: BibleImportOutcome) -> [String] {
    outcome.verses.map { "\($0.book) \($0.chapter):\($0.verse) \($0.text)" }
}

func importBible(_ path: String) throws -> BibleImportOutcome {
    let url = try fixtureURL(path)
    return try BibleImportRegistry.standard.importBible(files: [(try Data(contentsOf: url), url.lastPathComponent)])
}

@Suite("Kinh Thánh: OSIS, USFM, Zefania")
struct BibleImportTests {
    @Test("Chọn đúng bộ nhập theo nội dung")
    func detectsFormats() throws {
        let osis = try fixtureData("Bible/mau.osis.xml")
        let usfm = try fixtureData("Bible/mau.usfm")
        let zefania = try fixtureData("Bible/mau.zefania.xml")
        let registry = BibleImportRegistry.standard
        #expect(registry.importer(for: osis, filename: "a.xml") is OSISImporter)
        #expect(registry.importer(for: usfm, filename: "a.txt") is USFMImporter)
        #expect(registry.importer(for: zefania, filename: "a.xml") is ZefaniaImporter)
        #expect(registry.importer(for: Data("Lời bài hát".utf8), filename: "a.txt") == nil)
        #expect(!OSISImporter.canImport(zefania, filename: "a.xml"))
        #expect(!ZefaniaImporter.canImport(osis, filename: "a.xml"))
    }

    @Test("OSIS: câu bọc và câu mốc, bỏ chú thích, tiêu đề, Strong; thơ nối dòng")
    func osis() throws {
        let outcome = try importBible("Bible/mau.osis.xml")
        #expect(
            verseLines(outcome) == [
                "Gen 1:1 Ban đầu là câu thử một.",
                "Gen 1:2 Câu thử hai có hai dòng.",
                "Gen 1:3 Câu thử ba dòng thơ một, dòng thơ hai.",
                "John 3:16 Câu thử Giăng ba mười sáu, có ngắt dòng.",
                "John 3:17 Câu gộp mười bảy và mười tám.",
            ])
        #expect(outcome.name == "Bản thử OSIS")
        #expect(outcome.language == "vi")
        #expect(
            outcome.books == [
                BookInfo(osis: "Gen", ordinal: 1, name: "Sáng-thế Ký (tệp)", chapters: 1),
                BookInfo(osis: "John", ordinal: 43, name: "Giăng", chapters: 3),
            ])
        let messages = outcome.warnings.map(\.message)
        #expect(messages.contains { $0.contains("ngoài 66 sách") && $0.contains("Tob") })
        #expect(messages.contains { $0.hasPrefix("1 câu không có chữ") && $0.contains("John 3:19") })
        #expect(messages.contains { $0.hasPrefix("1 chỗ gộp nhiều câu") })
        #expect(messages.contains { $0.hasPrefix("Bản dịch thiếu 64 sách") })
        #expect(outcome.warnings.allSatisfy { $0.filename == "mau.osis.xml" })
    }

    @Test("USFM: bỏ \\f, \\x, \\s, \\r, thuộc tính \\w; nối \\q; câu gộp; sách ngoài quy điển")
    func usfm() throws {
        let outcome = try importBible("Bible/mau.usfm")
        #expect(
            verseLines(outcome) == [
                "Gen 1:1 Ban đầu là câu thử một.",
                "Gen 1:2 Câu thử hai có hai dòng thơ.",
                "Gen 1:3 Câu gộp ba và bốn.",
                "Gen 2:1 Chương hai câu một với CHÚA.",
                "John 3:16 Câu thử Giăng ba mười sáu.",
            ])
        #expect(
            outcome.books == [
                BookInfo(osis: "Gen", ordinal: 1, name: "Sáng-thế", chapters: 2),
                BookInfo(osis: "John", ordinal: 43, name: "Giăng", chapters: 3),
            ])
        #expect(outcome.name == nil)
        let messages = outcome.warnings.map(\.message)
        #expect(messages.contains { $0.contains("ngoài 66 sách") && $0.contains("TOB") })
        #expect(messages.contains { $0.hasPrefix("1 câu không có chữ") && $0.contains("Gen 2:2") })
        #expect(messages.contains { $0.hasPrefix("1 chỗ gộp nhiều câu") && $0.contains("Gen 1:3-4") })
    }

    @Test("Zefania: sách theo số thứ tự, bỏ NOTE, CAPTION; giữ gr, STYLE; tên trong INFORMATION")
    func zefania() throws {
        let outcome = try importBible("Bible/mau.zefania.xml")
        #expect(
            verseLines(outcome) == [
                "Gen 1:1 Ban đầu là câu thử một.",
                "Gen 1:2 Câu thử hai có chữ nghiêng.",
                "John 3:16 Câu thử Giăng ba mười sáu.",
                "John 3:17 Câu gộp mười bảy và mười tám.",
            ])
        #expect(outcome.name == "Bản thử Zefania")
        #expect(outcome.books.map(\.name) == ["Sáng Thế Ký", "Giăng"])
        let info = outcome.translationInfo(code: "thu-zef", license: BibleLicense.internalUseOnly, now: fixedDate)
        #expect(info.language == "vi")
        #expect(info.name == "Bản thử Zefania")
        #expect(info.license == "Chỉ dùng nội bộ, chưa có giấy phép phân phối")
        #expect(info.source == "mau.zefania.xml")
        let messages = outcome.warnings.map(\.message)
        #expect(messages.contains { $0.contains("ngoài 66 sách") && $0.contains("Sách lạ") })
    }

    @Test("Ghi vào BibleStore rồi đọc lại được câu và tên viết tắt")
    func writesToBibleStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportersTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcome = try importBible("Bible/mau.usfm")
        let store = BibleStore(directory: directory)
        try await outcome.write(
            to: store, code: "thu-usfm", name: "Bản thử USFM", abbreviation: "THU", license: BibleLicense.publicDomain,
            now: fixedDate)
        let translation = try await store.open("thu-usfm")
        #expect(translation.info.name == "Bản thử USFM")
        #expect(translation.info.displayAbbreviation == "THU")
        #expect(translation.info.license == "Phạm vi công cộng")
        #expect(translation.books().map(\.osis) == ["Gen", "John"])
        let range = VerseRange(book: "John", startChapter: 3, startVerse: 16, endChapter: 3, endVerse: 16)
        let reference = ScriptureReference(ranges: [range])
        #expect(try translation.verses(reference).map(\.text) == ["Câu thử Giăng ba mười sáu."])
    }

    @Test("Gộp nhiều tệp USFM (mỗi sách một tệp); câu trùng giữa các tệp bị bỏ, có cảnh báo")
    func mergesFiles() throws {
        let genesis = Data("\\id GEN\n\\h Sáng-thế Ký\n\\c 1\n\\p\n\\v 1 Một.\n\\v 2 Hai.\n".utf8)
        let john = Data("\\id JHN\n\\c 1\n\\p\n\\v 1 Giăng một.\n".utf8)
        let again = Data("\\id GEN\n\\c 1\n\\v 1 Trùng.\n".utf8)
        let files = [(genesis, "01-GEN.usfm"), (john, "02-JHN.usfm"), (again, "03-GEN.usfm")]
        let outcome = try BibleImportRegistry.standard.importBible(files: files)
        #expect(verseLines(outcome) == ["Gen 1:1 Một.", "Gen 1:2 Hai.", "John 1:1 Giăng một."])
        #expect(outcome.source == "01-GEN.usfm, 02-JHN.usfm, 03-GEN.usfm")
        #expect(outcome.books.map(\.name) == ["Sáng-thế Ký", "Giăng"])
        let missing = outcome.warnings.filter { $0.message.hasPrefix("Bản dịch thiếu") }
        #expect(missing.count == 1)
        #expect(missing.first?.message.hasPrefix("Bản dịch thiếu 64 sách") == true)
        #expect(outcome.warnings.contains { $0.message.hasPrefix("1 câu bị lặp") && $0.message.contains("Gen 1:1") })
    }

    @Test("Mã sách USFM và Zefania sang OSIS đủ 66 sách")
    func bookCodes() {
        #expect(BibleBookCodes.usfmCodes.count == 66)
        #expect(Set(BibleBookCodes.usfmCodes).count == 66)
        #expect(BibleBookCodes.osis(usfm: "GEN") == "Gen")
        #expect(BibleBookCodes.osis(usfm: "jhn") == "John")
        #expect(BibleBookCodes.osis(usfm: "PSA") == "Ps")
        #expect(BibleBookCodes.osis(usfm: "REV") == "Rev")
        #expect(BibleBookCodes.osis(usfm: "TOB") == nil)
        #expect(BibleBookCodes.osis(ordinal: 1) == "Gen")
        #expect(BibleBookCodes.osis(ordinal: 43) == "John")
        #expect(BibleBookCodes.osis(ordinal: 66) == "Rev")
        #expect(BibleBookCodes.osis(ordinal: 67) == nil)
        #expect(BibleBookCodes.osis(osisID: "JOHN") == "John")
    }

    @Test("Đối chiếu tên sách trong tệp với danh mục chuẩn")
    func bookNameDifferences() throws {
        let outcome = try importBible("Bible/mau.usfm")
        let differences = outcome.bookNameDifferences()
        #expect(differences.map(\.osis) == ["Gen"])
        #expect(differences.first?.catalogName == "Sáng-thế Ký")
        #expect(differences.first?.fileName == "Sáng-thế")
        #expect(differences.first?.sameWhenFolded == false)
    }

    @Test("Tệp không có câu nào: lỗi tiếng Việt có tên tệp")
    func emptyBible() {
        let data = Data("\\id GEN\n\\h Sáng-thế Ký\n".utf8)
        #expect(throws: ImportError.empty(filename: "rong.usfm")) {
            try USFMImporter().importBible(from: data, filename: "rong.usfm")
        }
        let broken = Data("<?xml version=\"1.0\"?><osis><osisText><div type=\"book\" osisID=\"Gen\">".utf8)
        #expect(throws: ImportError.self) {
            try OSISImporter().importBible(from: broken, filename: "hong.osis")
        }
    }
}

import Foundation
import Scripture
import VietText

/// Bộ nhập một định dạng tệp Kinh Thánh (OSIS, USFM, Zefania) thành dữ liệu cho `BibleStore.write`.
public protocol BibleImporter: Sendable {
    /// Tên định dạng hiện trên giao diện.
    static var displayName: String { get }
    /// Đuôi tệp thường gặp, chữ thường, không có dấu chấm.
    static var fileExtensions: [String] { get }
    /// Dò nội dung, không chỉ dựa vào đuôi tệp.
    static func canImport(_ data: Data, filename: String) -> Bool
    /// Đọc một tệp. Tệp hỏng thì ném ``ImportError`` có tên tệp.
    func importBible(from data: Data, filename: String) throws -> BibleImportOutcome
}

/// Ghi chú giấy phép ghi vào khoá `license` của bảng `meta`.
public enum BibleLicense {
    /// Bản dịch còn bản quyền mà Hội Thánh tự nhập (Bản Hiệu Đính 2010): không đóng gói, không phân phối.
    public static let internalUseOnly = "Chỉ dùng nội bộ, chưa có giấy phép phân phối"
    /// Bản dịch thuộc phạm vi công cộng đã xác minh nguồn.
    public static let publicDomain = "Phạm vi công cộng"
}

/// Dữ liệu một bản dịch đọc từ tệp, chưa ghi vào thư viện.
public struct BibleImportOutcome: Sendable {
    /// Tên bản dịch ghi trong tệp (nếu có).
    public var name: String?
    /// Mã ngôn ngữ ghi trong tệp (nếu có): `vi`, `en`.
    public var language: String?
    /// Các sách có câu, theo thứ tự quy điển. Tên sách lấy từ tệp; tệp không ghi thì lấy từ danh mục chuẩn.
    public var books: [BookInfo]
    /// Các câu theo thứ tự quy điển, chương, câu. Chữ đã chuẩn hoá NFC, đã bỏ chú thích và thẻ.
    public var verses: [Verse]
    /// Tên sách đúng như tệp ghi (mã OSIS → tên), để đối chiếu với danh mục chuẩn.
    public var fileBookNames: [String: String]
    /// Tên tệp nguồn, nối bằng dấu phẩy khi nhập nhiều tệp.
    public var source: String
    public var warnings: [ImportWarning]

    public init(
        name: String?, language: String?, books: [BookInfo], verses: [Verse], fileBookNames: [String: String],
        source: String, warnings: [ImportWarning]
    ) {
        self.name = name
        self.language = language
        self.books = books
        self.verses = verses
        self.fileBookNames = fileBookNames
        self.source = source
        self.warnings = warnings
    }

    /// Thông tin bản dịch để ghi. `name` để trống thì dùng tên trong tệp, không có nữa thì dùng mã.
    public func translationInfo(
        code: String, name: String? = nil, abbreviation: String? = nil, license: String, now: Date = Date()
    ) -> TranslationInfo {
        let chosenName = [name, self.name].compactMap { $0 }.first { !$0.isEmpty } ?? code
        return TranslationInfo(
            code: code, name: chosenName, abbreviation: abbreviation, language: Self.languageCode(language),
            license: license, source: source, importedAt: now
        )
    }

    /// Mã ngôn ngữ hai chữ: "VIE", "vie", "Vietnamese" → "vi"; không rõ thì "vi".
    static func languageCode(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "", "vi", "vie", "vietnamese", "tiếng việt":
            return "vi"
        case "en", "eng", "english":
            return "en"
        default:
            return value
        }
    }

    /// Ghi bản dịch vào `bibles/<code>.sqlite` của thư viện.
    public func write(
        to store: BibleStore, code: String, name: String? = nil, abbreviation: String? = nil, license: String,
        now: Date = Date()
    ) async throws {
        let info = translationInfo(code: code, name: name, abbreviation: abbreviation, license: license, now: now)
        try await store.write(code: code, info: info, books: books, verses: verses)
    }
}

/// Một tên sách trong tệp khác tên trong danh mục chuẩn (Bản Truyền Thống 1925).
public struct BookNameDifference: Sendable, Hashable {
    public var osis: String
    public var catalogName: String
    public var fileName: String
    /// Hai tên giống nhau khi bỏ dấu, viết thường, bỏ gạch nối: chỉ khác cách viết hoa hoặc gạch nối.
    public var sameWhenFolded: Bool

    public init(osis: String, catalogName: String, fileName: String, sameWhenFolded: Bool) {
        self.osis = osis
        self.catalogName = catalogName
        self.fileName = fileName
        self.sameWhenFolded = sameWhenFolded
    }
}

extension BibleImportOutcome {
    /// Đối chiếu tên sách ghi trong tệp với tên đầy đủ của danh mục chuẩn. Chỉ trả các sách khác tên.
    public func bookNameDifferences(catalog: BookCatalog = .standard) -> [BookNameDifference] {
        catalog.books.compactMap { book -> BookNameDifference? in
            guard let fileName = fileBookNames[book.osis], fileName != book.nameVi else { return nil }
            let same = VietText.foldLoose(fileName) == VietText.foldLoose(book.nameVi)
            return BookNameDifference(
                osis: book.osis, catalogName: book.nameVi, fileName: fileName, sameWhenFolded: same
            )
        }
    }
}

/// Danh sách bộ nhập Kinh Thánh.
public struct BibleImportRegistry: Sendable {
    public var importers: [any BibleImporter]

    public init(importers: [any BibleImporter]) {
        self.importers = importers
    }

    public static let standard = BibleImportRegistry(importers: [
        OSISImporter(), ZefaniaImporter(), USFMImporter(),
    ])

    public func importer(for data: Data, filename: String) -> (any BibleImporter)? {
        importers.first { type(of: $0).canImport(data, filename: filename) }
    }

    /// Đọc một hoặc nhiều tệp của cùng một bản dịch (USFM thường mỗi sách một tệp) và gộp lại.
    public func importBible(files: [(data: Data, filename: String)]) throws -> BibleImportOutcome {
        var outcomes: [BibleImportOutcome] = []
        for file in files {
            guard let importer = importer(for: file.data, filename: file.filename) else {
                throw ImportError.unsupportedFormat(filename: file.filename)
            }
            outcomes.append(try importer.importBible(from: file.data, filename: file.filename))
        }
        guard let first = outcomes.first else { throw ImportError.empty(filename: "") }
        if outcomes.count == 1 { return first }
        return try BibleCollector.merge(outcomes)
    }
}

/// Mã sách của các định dạng → mã OSIS.
public enum BibleBookCodes {
    /// Mã 3 chữ của USFM (Paratext) theo thứ tự quy điển Tin Lành.
    public static let usfmCodes = [
        "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR",
        "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO",
        "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM",
        "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
        "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
    ]

    /// Mã OSIS từ mã USFM (`JHN` → `John`), `nil` với sách ngoài 66 sách.
    public static func osis(usfm code: String, catalog: BookCatalog = .standard) -> String? {
        guard let index = usfmCodes.firstIndex(of: code.uppercased()), index < catalog.books.count else { return nil }
        return catalog.books[index].osis
    }

    /// Mã OSIS từ số thứ tự 1 đến 66 (Zefania), `nil` ngoài khoảng.
    public static func osis(ordinal: Int, catalog: BookCatalog = .standard) -> String? {
        catalog.books.first { $0.ordinal == ordinal }?.osis
    }

    /// Mã OSIS có trong danh mục (so không phân biệt hoa thường: `JOHN` → `John`).
    public static func osis(osisID code: String, catalog: BookCatalog = .standard) -> String? {
        if let book = catalog.book(osis: code) { return book.osis }
        return catalog.books.first { $0.osis.lowercased() == code.lowercased() }?.osis
    }
}

/// Gom câu từ bộ phân tích: chuẩn hoá chữ, bỏ câu rỗng và câu trùng, dựng danh sách sách, ghi cảnh báo.
struct BibleCollector {
    struct Key: Hashable {
        var book: String
        var chapter: Int
        var verse: Int
    }

    let filename: String
    let catalog: BookCatalog
    var name: String?
    var language: String?
    private(set) var verses: [Verse] = []
    private var seen: Set<Key> = []
    var bookNames: [String: String] = [:]
    private var emptyVerses: [String] = []
    private var duplicateVerses: [String] = []
    private var unknownBooks: [String] = []
    private var bridgedVerses: [String] = []
    var warnings: [ImportWarning] = []

    init(filename: String, catalog: BookCatalog = .standard) {
        self.filename = filename
        self.catalog = catalog
    }

    /// Ghi nhận một sách không thuộc 66 sách (bỏ qua câu của nó).
    mutating func noteUnknownBook(_ code: String) {
        if !unknownBooks.contains(code) { unknownBooks.append(code) }
    }

    /// Ghi nhận một câu gộp ("1-2"): chữ được gán cho câu đầu.
    mutating func noteBridge(_ place: String) {
        bridgedVerses.append(place)
    }

    /// Đặt tên sách theo tệp (lần đầu thắng).
    mutating func setBookName(_ name: String, for osis: String) {
        let cleaned = XMLText.collapseWhitespace(VietText.normalize(name))
        if !cleaned.isEmpty, bookNames[osis] == nil { bookNames[osis] = cleaned }
    }

    mutating func add(book: String, chapter: Int, verse: Int, text rawText: String) {
        let place = "\(book) \(chapter):\(verse)"
        guard chapter > 0, verse > 0 else { return }
        let text = XMLText.collapseWhitespace(VietText.normalize(rawText))
        guard !text.isEmpty else {
            emptyVerses.append(place)
            return
        }
        let key = Key(book: book, chapter: chapter, verse: verse)
        guard seen.insert(key).inserted else {
            duplicateVerses.append(place)
            return
        }
        verses.append(Verse(book: book, chapter: chapter, verse: verse, text: text))
    }

    /// Kết quả cuối. Không có câu nào thì ném ``ImportError/empty(filename:)``.
    func finish() throws -> BibleImportOutcome {
        guard !verses.isEmpty else { throw ImportError.empty(filename: filename) }
        var outcomeWarnings = warnings
        func warn(_ message: String) {
            outcomeWarnings.append(ImportWarning(filename: filename, message: message))
        }
        if !unknownBooks.isEmpty {
            warn("Bỏ qua sách ngoài 66 sách của quy điển Tin Lành: \(unknownBooks.joined(separator: ", ")).")
        }
        if !emptyVerses.isEmpty {
            warn("\(emptyVerses.count) câu không có chữ, Hệ thống bỏ qua: \(Self.sample(emptyVerses)).")
        }
        if !duplicateVerses.isEmpty {
            warn("\(duplicateVerses.count) câu bị lặp, Hệ thống giữ lần đầu: \(Self.sample(duplicateVerses)).")
        }
        if !bridgedVerses.isEmpty {
            let places = Self.sample(bridgedVerses)
            warn("\(bridgedVerses.count) chỗ gộp nhiều câu làm một, chữ được gán cho câu đầu: \(places).")
        }

        var chapters: [String: Int] = [:]
        for verse in verses {
            chapters[verse.book] = max(chapters[verse.book] ?? 0, verse.chapter)
        }
        var books: [BookInfo] = []
        var missing: [String] = []
        for book in catalog.books {
            guard let count = chapters[book.osis] else {
                missing.append(book.nameVi)
                continue
            }
            let fallback = (language ?? "vi").hasPrefix("vi") ? book.nameVi : book.nameEn
            let name = bookNames[book.osis] ?? fallback
            books.append(BookInfo(osis: book.osis, ordinal: book.ordinal, name: name, chapters: count))
        }
        if !missing.isEmpty {
            let names = Self.sample(missing, limit: 10)
            warn("Bản dịch thiếu \(missing.count) sách: \(names). Hệ thống vẫn nhập các sách có.")
        }

        let ordinals = Dictionary(uniqueKeysWithValues: catalog.books.map { ($0.osis, $0.ordinal) })
        let sorted = verses.sorted { lhs, rhs in
            let left = (ordinals[lhs.book] ?? 0, lhs.chapter, lhs.verse)
            let right = (ordinals[rhs.book] ?? 0, rhs.chapter, rhs.verse)
            return left < right
        }
        return BibleImportOutcome(
            name: name, language: language, books: books, verses: sorted, fileBookNames: bookNames,
            source: filename, warnings: outcomeWarnings
        )
    }

    /// Gộp kết quả của nhiều tệp cùng một bản dịch.
    static func merge(_ outcomes: [BibleImportOutcome]) throws -> BibleImportOutcome {
        let source = outcomes.map(\.source).joined(separator: ", ")
        var collector = BibleCollector(filename: source)
        collector.name = outcomes.compactMap(\.name).first
        collector.language = outcomes.compactMap(\.language).first
        for outcome in outcomes {
            collector.warnings += outcome.warnings.filter { !$0.message.hasPrefix("Bản dịch thiếu") }
            for (osis, name) in outcome.fileBookNames {
                collector.setBookName(name, for: osis)
            }
            for verse in outcome.verses {
                collector.add(book: verse.book, chapter: verse.chapter, verse: verse.verse, text: verse.text)
            }
        }
        return try collector.finish()
    }

    /// Vài mục đầu, thêm "…" khi còn nữa.
    static func sample(_ items: [String], limit: Int = 5) -> String {
        let head = items.prefix(limit).joined(separator: ", ")
        return items.count > limit ? head + ", …" : head
    }

    /// Phân tích mã câu OSIS `Gen.1.1` (lấy phần đầu nếu có nhiều mã cách nhau bởi dấu cách).
    static func parseOSISRef(_ text: String) -> (book: String, chapter: Int, verse: Int?, isRange: Bool)? {
        let tokens = text.split(separator: " ")
        guard let first = tokens.first else { return nil }
        let parts = first.split(separator: ".")
        guard parts.count >= 2, let chapter = Int(parts[1]) else { return nil }
        let verse = parts.count >= 3 ? Int(parts[2]) : nil
        return (String(parts[0]), chapter, verse, tokens.count > 1 || first.contains("-"))
    }
}

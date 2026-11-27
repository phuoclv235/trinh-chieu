import Foundation
import GRDB

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Thông tin một bản dịch, đọc từ bảng `meta` của tệp `bibles/<code>.sqlite`.
public struct TranslationInfo: Sendable, Hashable, Codable {
    /// Mã bản dịch, cũng là tên tệp: `vi1925`.
    public var code: String
    /// Tên đầy đủ: "Bản Truyền Thống 1925".
    public var name: String
    /// Tên viết tắt hiện trên trang chiếu: "TT1925". Khoá `abbreviation` trong `meta`, không bắt buộc.
    public var abbreviation: String?
    /// Mã ngôn ngữ: `vi`, `en`.
    public var language: String
    /// Giấy phép hoặc ghi chú bản quyền.
    public var license: String
    /// Nguồn tệp đã nhập (tên tệp OSIS, USFM, Zefania).
    public var source: String?
    public var importedAt: Date?

    public init(
        code: String, name: String, abbreviation: String? = nil, language: String, license: String,
        source: String? = nil, importedAt: Date? = nil
    ) {
        self.code = code
        self.name = name
        self.abbreviation = abbreviation
        self.language = language
        self.license = license
        self.source = source
        self.importedAt = importedAt
    }

    /// Tên ngắn để ghi kèm địa chỉ câu trên trang: `abbreviation`, không có thì mã viết hoa.
    public var displayAbbreviation: String {
        if let abbreviation, !abbreviation.isEmpty { return abbreviation }
        return code.uppercased()
    }
}

/// Một sách có trong bản dịch.
public struct BookInfo: Sendable, Hashable, Codable {
    /// Mã sách OSIS.
    public var osis: String
    public var ordinal: Int
    /// Tên sách theo bản dịch.
    public var name: String
    /// Số chương.
    public var chapters: Int

    public init(osis: String, ordinal: Int, name: String, chapters: Int) {
        self.osis = osis
        self.ordinal = ordinal
        self.name = name
        self.chapters = chapters
    }
}

/// Một câu Kinh Thánh.
public struct Verse: Sendable, Hashable, Codable {
    /// Mã sách OSIS.
    public var book: String
    public var chapter: Int
    public var verse: Int
    public var text: String

    public init(book: String, chapter: Int, verse: Int, text: String) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.text = text
    }
}

/// Lỗi của kho bản dịch, có thông điệp tiếng Việt cho người dùng.
public enum ScriptureError: Error, Sendable, Equatable, LocalizedError, CustomStringConvertible {
    case translationNotFound(code: String)
    case invalidTranslationCode(code: String)
    case unsupportedSchema(code: String, found: Int, supported: Int)
    case bookNotInTranslation(book: String, translation: String)
    case chapterOutOfRange(book: String, chapter: Int, chapterCount: Int)
    case verseOutOfRange(book: String, chapter: Int, verse: Int, verseCount: Int)
    case invalidData(String)
    /// Địa chỉ tự dựng (không qua ``ReferenceParser``) có số 0, số âm hoặc đoạn ngược.
    case invalidReference(reason: String)

    /// Thông điệp tiếng Việt.
    public var message: String {
        switch self {
        case .translationNotFound(let code):
            return "Hệ thống không tìm thấy bản dịch “\(code)”."
        case .invalidTranslationCode(let code):
            return "Mã bản dịch “\(code)” không hợp lệ: chỉ dùng chữ thường không dấu, số, gạch nối và gạch dưới."
        case .unsupportedSchema(let code, let found, let supported):
            return "Tệp bản dịch “\(code)” dùng định dạng \(found); Hệ thống mới đọc tới \(supported). Hãy cập nhật."
        case .bookNotInTranslation(let book, let translation):
            return "Bản dịch \(translation) không có sách \(book)."
        case .chapterOutOfRange(let book, _, let chapterCount):
            return "\(book) chỉ có \(chapterCount) chương."
        case .verseOutOfRange(let book, let chapter, _, let verseCount):
            return "\(book) \(chapter) chỉ có \(verseCount) câu."
        case .invalidData(let detail):
            return "Dữ liệu bản dịch không hợp lệ: \(detail)"
        case .invalidReference(let reason):
            return reason
        }
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}

/// Kho bản dịch Kinh Thánh: thư mục `bibles/`, mỗi bản dịch một tệp SQLite chỉ đọc (`docs/dinh-dang-tep.md` mục 5).
public actor BibleStore {
    /// Phiên bản lược đồ tệp bản dịch mà Hệ thống ghi và đọc được.
    public static let schemaVersion = 1

    public let directory: URL
    private var opened: [String: BibleTranslation] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    /// Các bản dịch có trong thư mục, theo tên. Tệp hỏng hoặc không đọc được thì bỏ qua.
    public func translations() throws -> [TranslationInfo] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var result: [TranslationInfo] = []
        for file in files where file.pathExtension == "sqlite" && !file.lastPathComponent.hasPrefix(".") {
            let code = file.deletingPathExtension().lastPathComponent
            guard Self.isValidCode(code), let translation = try? open(code) else { continue }
            result.append(translation.info)
        }
        return result.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.code < rhs.code : lhs.name < rhs.name
        }
    }

    /// Mở bản dịch theo mã. Bản dịch đã mở được giữ lại cho lần sau.
    public func open(_ code: String) throws -> BibleTranslation {
        guard Self.isValidCode(code) else { throw ScriptureError.invalidTranslationCode(code: code) }
        if let translation = opened[code] { return translation }
        let url = fileURL(for: code)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScriptureError.translationNotFound(code: code)
        }
        let translation = try BibleTranslation(url: url, fallbackCode: code)
        opened[code] = translation
        return translation
    }

    /// Tạo (hoặc thay) tệp bản dịch `code`: ghi vào tệp tạm trong cùng thư mục rồi đổi tên, nên tệp cũ còn
    /// nguyên nếu ghi lỗi giữa chừng. Dùng cho bộ nhập (T1.4).
    ///
    /// `info.code` bị thay bằng `code`. Chữ của câu được chuẩn hoá NFC. Câu thuộc sách không có trong `books`,
    /// hoặc trùng (sách, chương, câu), làm hàm ném lỗi.
    public func write(code: String, info: TranslationInfo, books: [BookInfo], verses: [Verse]) throws {
        guard Self.isValidCode(code) else { throw ScriptureError.invalidTranslationCode(code: code) }
        let bookCodes = Set(books.map(\.osis))
        if let stray = verses.first(where: { !bookCodes.contains($0.book) }) {
            let place = "\(stray.book) \(stray.chapter):\(stray.verse)"
            throw ScriptureError.invalidData("câu \(place) thuộc sách không khai báo trong danh sách sách.")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(code).\(UUID().uuidString).sqlite")
        defer { try? fileManager.removeItem(at: temporary) }

        var meta = info
        meta.code = code
        do {
            let queue = try DatabaseQueue(path: temporary.path)
            try queue.write { db in
                try Self.createSchema(db)
                try Self.insert(meta: meta, books: books, verses: verses, into: db)
            }
            try queue.close()
        } catch let error as DatabaseError {
            throw ScriptureError.invalidData(error.message ?? "\(error)")
        }

        let destination = fileURL(for: code)
        guard rename(temporary.path, destination.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
        opened[code] = nil
    }

    // MARK: - Nội bộ

    func fileURL(for code: String) -> URL {
        directory.appendingPathComponent(code + ".sqlite")
    }

    /// Mã bản dịch hợp lệ: 1 đến 32 ký tự `a-z`, `0-9`, `-`, `_`, không bắt đầu bằng dấu.
    static func isValidCode(_ code: String) -> Bool {
        guard (1...32).contains(code.count), let first = code.unicodeScalars.first else { return false }
        let allowed = code.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-" || scalar == "_"
        }
        return allowed && first != "-" && first != "_"
    }

    private static func createSchema(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE verses(
                  book TEXT NOT NULL,
                  chapter INTEGER NOT NULL,
                  verse INTEGER NOT NULL,
                  text TEXT NOT NULL,
                  PRIMARY KEY(book, chapter, verse)
                ) WITHOUT ROWID;
                CREATE TABLE books(
                  osis TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, name TEXT NOT NULL, chapters INTEGER NOT NULL
                );
                """
        )
    }

    private static func insert(meta: TranslationInfo, books: [BookInfo], verses: [Verse], into db: Database) throws {
        var pairs: [(String, String)] = [
            ("code", meta.code), ("name", meta.name), ("language", meta.language), ("license", meta.license),
            ("schemaVersion", "\(schemaVersion)"),
            ("importedAt", (meta.importedAt ?? Date()).ISO8601Format()),
        ]
        if let abbreviation = meta.abbreviation { pairs.append(("abbreviation", abbreviation)) }
        if let source = meta.source { pairs.append(("source", source)) }
        let insertMeta = try db.makeStatement(sql: "INSERT INTO meta(key, value) VALUES (?, ?)")
        for (key, value) in pairs {
            try insertMeta.execute(arguments: [key, value])
        }
        let insertBook = try db.makeStatement(sql: "INSERT INTO books VALUES (?, ?, ?, ?)")
        for book in books {
            try insertBook.execute(arguments: [book.osis, book.ordinal, book.name, book.chapters])
        }
        let insertVerse = try db.makeStatement(sql: "INSERT INTO verses VALUES (?, ?, ?, ?)")
        for verse in verses {
            let text = verse.text.precomposedStringWithCanonicalMapping
            try insertVerse.execute(arguments: [verse.book, verse.chapter, verse.verse, text])
        }
    }
}

/// Một bản dịch đã mở, chỉ đọc. An toàn đa luồng: mọi lần đọc đi qua một hàng đợi nối tiếp của GRDB; danh sách
/// sách và số câu mỗi chương nạp sẵn vào bộ nhớ khi mở.
public final class BibleTranslation: Sendable {
    public let info: TranslationInfo
    private let dbQueue: DatabaseQueue
    private let bookList: [BookInfo]
    private let booksByOSIS: [String: BookInfo]
    /// "John.3" → số câu cuối của chương.
    private let lastVerses: [String: Int]

    init(url: URL, fallbackCode: String) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        let loaded = try queue.read { db -> (TranslationInfo, [BookInfo], [String: Int]) in
            let metaRows = try Row.fetchAll(db, sql: "SELECT key, value FROM meta")
            var meta: [String: String] = [:]
            for row in metaRows {
                let key: String = row[0]
                let value: String = row[1]
                meta[key] = value
            }
            let found = meta["schemaVersion"].flatMap(Int.init) ?? 1
            guard found <= BibleStore.schemaVersion else {
                throw ScriptureError.unsupportedSchema(
                    code: fallbackCode, found: found, supported: BibleStore.schemaVersion
                )
            }
            let info = TranslationInfo(
                code: meta["code"] ?? fallbackCode,
                name: meta["name"] ?? fallbackCode,
                abbreviation: meta["abbreviation"],
                language: meta["language"] ?? "vi",
                license: meta["license"] ?? "",
                source: meta["source"],
                importedAt: meta["importedAt"].flatMap { ISO8601DateFormatter().date(from: $0) }
            )
            let bookRows = try Row.fetchAll(db, sql: "SELECT osis, ordinal, name, chapters FROM books ORDER BY ordinal")
            let books = bookRows.map { row in
                BookInfo(osis: row[0], ordinal: row[1], name: row[2], chapters: row[3])
            }
            var lastVerses: [String: Int] = [:]
            let counts = try Row.fetchAll(db, sql: "SELECT book, chapter, max(verse) FROM verses GROUP BY 1, 2")
            for row in counts {
                let book: String = row[0]
                let chapter: Int = row[1]
                let last: Int = row[2]
                lastVerses["\(book).\(chapter)"] = last
            }
            return (info, books, lastVerses)
        }
        info = loaded.0
        bookList = loaded.1
        booksByOSIS = Dictionary(loaded.1.map { ($0.osis, $0) }, uniquingKeysWith: { first, _ in first })
        lastVerses = loaded.2
        dbQueue = queue
    }

    /// Các sách có trong bản dịch, theo thứ tự quy điển.
    public func books() -> [BookInfo] {
        bookList
    }

    /// Số câu của chương (số thứ tự câu cuối); 0 nếu không có chương này.
    public func verseCount(book: String, chapter: Int) -> Int {
        lastVerses["\(book).\(chapter)"] ?? 0
    }

    /// Các câu của địa chỉ, theo thứ tự các đoạn. Ném ``ScriptureError`` với thông điệp tiếng Việt khi sách, chương
    /// hoặc câu nằm ngoài bản dịch ("Giăng chỉ có 21 chương.").
    public func verses(_ ref: ScriptureReference) throws -> [Verse] {
        var bounds: [Bound] = []
        for range in ref.ranges {
            if let failure = NumberParser.validate(range) {
                throw ScriptureError.invalidReference(reason: failure.reason)
            }
            guard let book = booksByOSIS[range.book] else {
                let name = BookCatalog.standard.book(osis: range.book)?.nameVi ?? range.book
                throw ScriptureError.bookNotInTranslation(book: name, translation: info.name)
            }
            for chapter in [range.startChapter, range.endChapter] where chapter > book.chapters {
                throw ScriptureError.chapterOutOfRange(book: book.name, chapter: chapter, chapterCount: book.chapters)
            }
            let startVerse = range.startVerse ?? 1
            let endVerse = range.endVerse ?? verseCount(book: range.book, chapter: range.endChapter)
            for (chapter, verse) in [(range.startChapter, startVerse), (range.endChapter, endVerse)] {
                let count = verseCount(book: range.book, chapter: chapter)
                if verse > count {
                    throw ScriptureError.verseOutOfRange(
                        book: book.name, chapter: chapter, verse: verse, verseCount: count
                    )
                }
            }
            bounds.append(
                Bound(
                    book: range.book, startChapter: range.startChapter, startVerse: startVerse,
                    endChapter: range.endChapter, endVerse: endVerse
                )
            )
        }
        return try dbQueue.read { db in
            let statement = try db.cachedStatement(
                sql: """
                    SELECT book, chapter, verse, text FROM verses
                    WHERE book = ? AND chapter BETWEEN ? AND ?
                      AND (chapter > ? OR verse >= ?) AND (chapter < ? OR verse <= ?)
                    ORDER BY chapter, verse
                    """
            )
            var result: [Verse] = []
            for bound in bounds {
                let arguments: StatementArguments = [
                    bound.book, bound.startChapter, bound.endChapter, bound.startChapter, bound.startVerse,
                    bound.endChapter, bound.endVerse,
                ]
                let rows = try Row.fetchAll(statement, arguments: arguments)
                result += rows.map { row in
                    Verse(book: row[0], chapter: row[1], verse: row[2], text: row[3])
                }
            }
            return result
        }
    }

    /// Mọi câu theo thứ tự quy điển, cho lập chỉ mục. Đọc lỗi thì trả dãy rỗng.
    public func allVerses() -> AnySequence<Verse> {
        do {
            let verses = try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: Self.allVersesSQL)
                return rows.map { row in
                    Verse(book: row[0], chapter: row[1], verse: row[2], text: row[3])
                }
            }
            return AnySequence(verses)
        } catch {
            return AnySequence([])
        }
    }

    private static let allVersesSQL = """
        SELECT v.book, v.chapter, v.verse, v.text FROM verses v
        LEFT JOIN books b ON b.osis = v.book
        ORDER BY b.ordinal, v.chapter, v.verse
        """

    /// Giới hạn đã kiểm của một đoạn, dùng để truy vấn.
    private struct Bound {
        var book: String
        var startChapter: Int
        var startVerse: Int
        var endChapter: Int
        var endVerse: Int
    }
}

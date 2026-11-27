import Foundation
import VietText

/// Một sách trong quy điển Tin Lành (66 sách).
public struct Book: Sendable, Hashable, Codable, Identifiable {
    /// Mã sách OSIS: `Gen`, `John`, `1Cor`.
    public var osis: String
    /// Thứ tự trong quy điển, từ 1 (Sáng-thế Ký) tới 66 (Khải-huyền).
    public var ordinal: Int
    /// Tên đầy đủ theo Bản Truyền Thống 1925: "Giăng", "I Cô-rinh-tô".
    public var nameVi: String
    /// Viết tắt hiển thị: "Gi", "1 Cô".
    public var shortVi: String
    /// Các cách gõ tiếng Việt khác: "gi", "giang".
    public var aliases: [String]
    public var nameEn: String
    public var aliasesEn: [String]
    /// Ưu tiên khi tên gõ khớp nhiều sách: nhỏ là ưu tiên.
    public var priority: Int

    public var id: String { osis }

    public init(
        osis: String, ordinal: Int, nameVi: String, shortVi: String, aliases: [String] = [], nameEn: String,
        aliasesEn: [String] = [], priority: Int
    ) {
        self.osis = osis
        self.ordinal = ordinal
        self.nameVi = nameVi
        self.shortVi = shortVi
        self.aliases = aliases
        self.nameEn = nameEn
        self.aliasesEn = aliasesEn
        self.priority = priority
    }

    /// Số thứ tự đứng đầu mã OSIS (`1Cor` → 1), `nil` với sách không đánh số.
    public var numberPrefix: Int? {
        guard let first = osis.first, let value = first.wholeNumberValue else { return nil }
        return value
    }
}

/// Danh mục sách: tra theo mã OSIS và theo khoá gõ đã gộp dấu.
public struct BookCatalog: Sendable, Hashable {
    /// Các sách theo thứ tự quy điển.
    public let books: [Book]
    private let byOSIS: [String: Int]
    /// Khoá gõ tiếng Việt (tên đầy đủ, viết tắt, alias) → chỉ số sách.
    let vietnameseKeys: [String: [Int]]
    /// Khoá gõ tiếng Anh (tên, alias, mã OSIS) → chỉ số sách.
    let englishKeys: [String: [Int]]

    public init(books: [Book]) {
        let sorted = books.sorted { $0.ordinal < $1.ordinal }
        self.books = sorted
        var byOSIS: [String: Int] = [:]
        var vietnamese: [String: [Int]] = [:]
        var english: [String: [Int]] = [:]
        for (index, book) in sorted.enumerated() {
            byOSIS[book.osis] = index
            for (offset, name) in ([book.nameVi, book.shortVi] + book.aliases).enumerated() {
                for key in Self.keys(forName: name, includesRoman: offset == 0) {
                    Self.add(index, to: &vietnamese[key, default: []])
                }
            }
            for (offset, name) in ([book.nameEn, book.osis] + book.aliasesEn).enumerated() {
                for key in Self.keys(forName: name, includesRoman: offset == 0) {
                    Self.add(index, to: &english[key, default: []])
                }
            }
        }
        self.byOSIS = byOSIS
        self.vietnameseKeys = vietnamese
        self.englishKeys = english
    }

    /// Danh mục chuẩn đọc từ `books-vi.json` trong gói.
    public static let standard: BookCatalog = {
        do {
            return try BookCatalog.loadBundled()
        } catch {
            preconditionFailure("Không đọc được danh mục sách books-vi.json: \(error)")
        }
    }()

    /// Đọc danh mục từ dữ liệu JSON dạng `{"version": 1, "books": [...]}`.
    public static func decode(_ data: Data) throws -> BookCatalog {
        struct File: Decodable {
            var books: [Book]
        }
        return BookCatalog(books: try JSONDecoder().decode(File.self, from: data).books)
    }

    static func loadBundled() throws -> BookCatalog {
        guard let url = Bundle.module.url(forResource: "books-vi", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    /// Sách theo mã OSIS.
    public func book(osis: String) -> Book? {
        byOSIS[osis].map { books[$0] }
    }

    public static func == (lhs: BookCatalog, rhs: BookCatalog) -> Bool {
        lhs.books == rhs.books
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(books)
    }

    // MARK: - Khoá gõ

    /// Khoá so khớp của một tên: gộp dấu lỏng, bỏ khoảng trắng. Tên có số thứ tự đứng đầu ("I Cô-rinh-tô",
    /// "1 Cô") cho khoá dạng số Ả Rập ("1corinhto", "1co").
    ///
    /// `includesRoman` thêm khoá dạng số La Mã viết liền ("icorinhto"), chỉ dùng cho tên đầy đủ: với tên viết tắt
    /// khoá này dễ trùng tên sách khác ("I Sa" thành "isa", trùng mã tiếng Anh của Ê-sai).
    static func keys(forName name: String, includesRoman: Bool) -> [String] {
        let tokens = VietText.foldLoose(name).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        if tokens.count > 1, let number = ordinalValue(tokens[0]) {
            let stem = tokens.dropFirst().joined()
            let arabic = "\(number)" + stem
            return includesRoman ? [arabic, romanNumerals[number - 1] + stem] : [arabic]
        }
        return [tokens.joined()]
    }

    /// Khoá so khớp của phần tên sách người dùng gõ: như ``keys(forName:)`` nhưng số thứ tự đứng riêng
    /// ("ii co", "2 co") luôn đổi về số Ả Rập ("2co").
    static func inputKey(_ text: String) -> String {
        let tokens = VietText.foldLoose(text).split(separator: " ").map(String.init)
        if tokens.count > 1, let number = ordinalValue(tokens[0]) {
            return "\(number)" + tokens.dropFirst().joined()
        }
        return tokens.joined()
    }

    static let romanNumerals = ["i", "ii", "iii"]

    /// "1", "2", "3", "i", "ii", "iii" → 1...3.
    static func ordinalValue(_ token: String) -> Int? {
        switch token {
        case "1", "i":
            return 1
        case "2", "ii":
            return 2
        case "3", "iii":
            return 3
        default:
            return nil
        }
    }

    private static func add(_ index: Int, to list: inout [Int]) {
        if !list.contains(index) { list.append(index) }
    }
}

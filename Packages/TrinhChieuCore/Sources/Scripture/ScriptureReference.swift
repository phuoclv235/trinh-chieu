import Foundation

/// Một đoạn liên tục trong một sách: một câu, nhiều câu, một hay nhiều chương.
///
/// Quy ước: `startVerse` và `endVerse` cùng `nil` nghĩa là trọn các chương từ `startChapter` tới `endChapter`;
/// cùng có giá trị nghĩa là từ câu `startChapter:startVerse` tới câu `endChapter:endVerse`.
public struct VerseRange: Sendable, Hashable, Codable {
    /// Mã sách OSIS.
    public var book: String
    public var startChapter: Int
    /// `nil` = cả chương.
    public var startVerse: Int?
    public var endChapter: Int
    public var endVerse: Int?

    public init(book: String, startChapter: Int, startVerse: Int?, endChapter: Int, endVerse: Int?) {
        self.book = book
        self.startChapter = startChapter
        self.startVerse = startVerse
        self.endChapter = endChapter
        self.endVerse = endVerse
    }

    /// Một câu.
    public static func verse(_ book: String, _ chapter: Int, _ verse: Int) -> VerseRange {
        VerseRange(book: book, startChapter: chapter, startVerse: verse, endChapter: chapter, endVerse: verse)
    }

    /// Các câu `from...to` trong một chương.
    public static func verses(_ book: String, _ chapter: Int, _ from: Int, _ to: Int) -> VerseRange {
        VerseRange(book: book, startChapter: chapter, startVerse: from, endChapter: chapter, endVerse: to)
    }

    /// Trọn các chương `from...to`.
    public static func chapters(_ book: String, _ from: Int, _ to: Int) -> VerseRange {
        VerseRange(book: book, startChapter: from, startVerse: nil, endChapter: to, endVerse: nil)
    }

    /// Đoạn nằm gọn trong một chương và có số câu.
    var isWithinOneChapterWithVerses: Bool {
        startChapter == endChapter && startVerse != nil && endVerse != nil
    }
}

/// Địa chỉ câu Kinh Thánh đã phân tích: "Giăng 3:16-18", "Rô-ma 8:28; 12:1-2".
public struct ScriptureReference: Sendable, Hashable, Codable {
    /// Các đoạn theo thứ tự người dùng gõ.
    public var ranges: [VerseRange]
    /// Chuỗi chuẩn hoá, phân tích lại ra đúng `ranges`: "Giăng 3:16-18".
    public var canonical: String

    public init(ranges: [VerseRange], canonical: String) {
        self.ranges = ranges
        self.canonical = canonical
    }

    /// Tạo địa chỉ và sinh `canonical` từ tên sách trong danh mục.
    public init(ranges: [VerseRange], catalog: BookCatalog = .standard) {
        self.ranges = ranges
        self.canonical = ReferenceFormatter.format(ranges, catalog: catalog, dash: "-")
    }
}

/// Viết địa chỉ câu thành chữ.
public enum ReferenceFormatter {
    /// Viết các đoạn thành chuỗi: cùng sách nối bằng "; ", cùng chương nối câu bằng ", ".
    ///
    /// - Parameter dash: "-" cho chuỗi chuẩn hoá (gõ lại được), "–" (gạch ngang vừa) cho chữ trên trang chiếu.
    public static func format(_ ranges: [VerseRange], catalog: BookCatalog, dash: String) -> String {
        var out = ""
        var previous: VerseRange?
        for range in ranges {
            if let previous, previous.book == range.book {
                let sameChapterVerses = range.isWithinOneChapterWithVerses && range.startChapter == previous.endChapter
                if previous.endVerse != nil && sameChapterVerses {
                    out += ", " + versePart(range, dash: dash)
                } else {
                    out += "; " + chapterVersePart(range, dash: dash)
                }
            } else {
                if !out.isEmpty { out += "; " }
                let name = catalog.book(osis: range.book)?.nameVi ?? range.book
                out += name + " " + chapterVersePart(range, dash: dash)
            }
            previous = range
        }
        return out
    }

    /// "16" hoặc "16-18" (chỉ phần câu, cho đoạn nằm gọn trong một chương).
    static func versePart(_ range: VerseRange, dash: String) -> String {
        let start = range.startVerse ?? 1
        let end = range.endVerse ?? start
        return start == end ? "\(start)" : "\(start)\(dash)\(end)"
    }

    /// "3", "3-4", "3:16", "3:16-18", "3:16-4:2".
    static func chapterVersePart(_ range: VerseRange, dash: String) -> String {
        guard let startVerse = range.startVerse else {
            if range.startChapter == range.endChapter {
                return "\(range.startChapter)"
            }
            if let endVerse = range.endVerse {
                return "\(range.startChapter):1\(dash)\(range.endChapter):\(endVerse)"
            }
            return "\(range.startChapter)\(dash)\(range.endChapter)"
        }
        let start = "\(range.startChapter):\(startVerse)"
        guard let endVerse = range.endVerse else {
            return start
        }
        if range.startChapter == range.endChapter {
            return endVerse == startVerse ? start : "\(start)\(dash)\(endVerse)"
        }
        return "\(start)\(dash)\(range.endChapter):\(endVerse)"
    }
}

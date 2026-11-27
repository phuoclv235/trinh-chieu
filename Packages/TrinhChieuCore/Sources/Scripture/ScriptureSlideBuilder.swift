import CoreModel
import Foundation

/// Tuỳ chọn chia câu thành trang.
public struct ScriptureLayoutOptions: Sendable, Hashable {
    /// Số ký tự tối đa của phần thân một trang, kể cả số câu.
    public var maxCharactersPerSlide: Int
    /// Có phần tử chữ ghi địa chỉ câu (`slot = reference`) hay không.
    public var showReference: Bool
    public var verseNumbers: VerseNumberStyle

    public init(
        maxCharactersPerSlide: Int = 220, showReference: Bool = true, verseNumbers: VerseNumberStyle = .superscript
    ) {
        self.maxCharactersPerSlide = maxCharactersPerSlide
        self.showReference = showReference
        self.verseNumbers = verseNumbers
    }

    /// Lấy từ thiết lập Kinh Thánh của mẫu trình bày.
    public init(settings: ScriptureSettings) {
        self.init(
            maxCharactersPerSlide: settings.maxCharactersPerSlide, showReference: settings.showReference,
            verseNumbers: settings.verseNumbers
        )
    }
}

/// Chia các câu Kinh Thánh thành trang chiếu.
///
/// Quy tắc:
/// 1. Gom câu liên tiếp vào một trang khi tổng ký tự (kể cả số câu) không vượt `maxCharactersPerSlide`. Sang sách
///    khác, hoặc nhảy sang chương không liền kề, thì sang trang mới.
/// 2. Câu dài hơn giới hạn được tách tại ranh giới câu văn (". ", "? ", "! ", "; ", ": ", ", ") gần điểm chia đều
///    nhất mà mỗi phần không vượt giới hạn; không có thì tách tại khoảng trắng gần nhất. Không cắt giữa một từ (trừ
///    khi một từ dài hơn cả giới hạn).
/// 3. Trang có phần tử chữ `slot = body` và, nếu `showReference`, phần tử chữ `slot = reference` ghi địa chỉ các câu
///    trên trang cùng tên viết tắt bản dịch: "Giăng 3:16–17 (TT1925)".
/// 4. `id` của trang (và của phần tử) sinh tất định từ mã bản dịch, sách, chương, câu đầu và phần tách.
public struct ScriptureSlideBuilder: Sendable {
    public let catalog: BookCatalog

    /// Khoảng cách giữa số câu chỉ số trên và chữ: khoảng trắng hẹp không ngắt dòng (U+202F).
    static let verseNumberSeparator = "\u{202F}"

    public init(catalog: BookCatalog = .standard) {
        self.catalog = catalog
    }

    /// Chia trang cho một bản dịch đã mở: lấy mã và tên viết tắt từ `translation`.
    public func slides(
        for ref: ScriptureReference, verses: [Verse], translation: TranslationInfo, options: ScriptureLayoutOptions
    ) -> [Slide] {
        slides(
            for: ref, verses: verses, translationCode: translation.code,
            translationName: translation.displayAbbreviation, options: options
        )
    }

    /// Chia trang.
    ///
    /// - Parameters:
    ///   - ref: địa chỉ đã phân tích; `verses` là kết quả tra địa chỉ này, theo đúng thứ tự.
    ///   - translationCode: mã bản dịch, dùng sinh `id` tất định.
    ///   - translationName: tên viết tắt ghi trong ngoặc sau địa chỉ ("TT1925"); rỗng thì không ghi ngoặc.
    public func slides(
        for ref: ScriptureReference, verses: [Verse], translationCode: String, translationName: String,
        options: ScriptureLayoutOptions
    ) -> [Slide] {
        let limit = max(1, options.maxCharactersPerSlide)
        var pages: [[Piece]] = []
        var current: [Piece] = []
        var currentLength = 0
        var previous: Verse?

        for verse in verses {
            if let previous, !Self.continues(previous, with: verse), !current.isEmpty {
                pages.append(current)
                current = []
                currentLength = 0
            }
            previous = verse
            let text = Self.numberPrefix(verse.verse, style: options.verseNumbers) + Self.clean(verse.text)
            let parts = TextSplitter.split(text, limit: limit)
            for (index, part) in parts.enumerated() {
                let piece = Piece(verse: verse, part: index, text: part)
                let added = current.isEmpty ? part.count : part.count + 1
                if !current.isEmpty, currentLength + added > limit {
                    pages.append(current)
                    current = []
                    currentLength = 0
                }
                currentLength += current.isEmpty ? part.count : part.count + 1
                current.append(piece)
            }
        }
        if !current.isEmpty { pages.append(current) }

        return pages.map { makeSlide($0, translationCode: translationCode, translationName: translationName, options) }
    }

    // MARK: - Nội bộ

    /// Một câu, hoặc một phần của câu dài đã tách.
    struct Piece {
        var verse: Verse
        var part: Int
        var text: String
    }

    private func makeSlide(
        _ pieces: [Piece], translationCode: String, translationName: String, _ options: ScriptureLayoutOptions
    ) -> Slide {
        let first = pieces[0]
        let place = "\(first.verse.book).\(first.verse.chapter).\(first.verse.verse)"
        let key = "scripture:\(translationCode):\(place):\(first.part)"
        let reference = ReferenceFormatter.format(Self.ranges(of: pieces.map(\.verse)), catalog: catalog, dash: "–")
        let body = pieces.map(\.text).joined(separator: " ")
        var elements: [Element] = [.text(TextElement(id: UUID(hashing: key + ":body"), slot: .body, text: body))]
        if options.showReference {
            let label = translationName.isEmpty ? reference : "\(reference) (\(translationName))"
            elements.append(.text(TextElement(id: UUID(hashing: key + ":reference"), slot: .reference, text: label)))
        }
        return Slide(id: UUID(hashing: key), label: reference, elements: elements)
    }

    /// Câu `next` có nối tiếp được trên cùng trang với `previous` không: cùng sách, và cùng chương hoặc sang đầu
    /// chương kế.
    static func continues(_ previous: Verse, with next: Verse) -> Bool {
        guard previous.book == next.book else { return false }
        if previous.chapter == next.chapter { return true }
        return next.chapter == previous.chapter + 1 && next.verse == 1
    }

    /// Gom các câu (đã bỏ trùng phần tách) thành đoạn để ghi địa chỉ: câu liền nhau thành một đoạn.
    static func ranges(of verses: [Verse]) -> [VerseRange] {
        var ranges: [VerseRange] = []
        for verse in verses {
            if var last = ranges.last, last.book == verse.book, let endVerse = last.endVerse {
                if last.endChapter == verse.chapter && endVerse == verse.verse {
                    continue
                }
                let sameChapterNext = last.endChapter == verse.chapter && verse.verse == endVerse + 1
                let nextChapterStart = verse.chapter == last.endChapter + 1 && verse.verse == 1
                if sameChapterNext || nextChapterStart {
                    last.endChapter = verse.chapter
                    last.endVerse = verse.verse
                    ranges[ranges.count - 1] = last
                    continue
                }
            }
            ranges.append(.verse(verse.book, verse.chapter, verse.verse))
        }
        return ranges
    }

    /// Bỏ khoảng trắng thừa: xuống dòng và khoảng trắng liên tiếp thành một khoảng trắng.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func numberPrefix(_ verse: Int, style: VerseNumberStyle) -> String {
        switch style {
        case .none:
            return ""
        case .superscript:
            return superscript(verse) + verseNumberSeparator
        }
    }

    /// 16 → "¹⁶".
    static func superscript(_ number: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return String(String(number).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}

/// Tách chữ dài thành các phần không vượt giới hạn ký tự.
enum TextSplitter {
    /// Dấu kết thúc vế câu, tách ngay sau dấu (và sau ngoặc kép, ngoặc đơn đóng nếu có).
    static let clauseMarks: Set<Character> = [".", "?", "!", ";", ":", ","]
    static let closingMarks: Set<Character> = ["”", "’", "\"", "'", ")", "»"]

    /// Chia `text` thành ít phần nhất có thể; mỗi lần cắt chọn điểm gần chỗ chia đều nhất, ưu tiên ranh giới vế câu
    /// rồi mới tới khoảng trắng.
    static func split(_ text: String, limit: Int) -> [String] {
        var remaining = Array(text)
        guard remaining.count > limit else { return [text] }
        var parts: [String] = []
        var partsLeft = Int((Double(remaining.count) / Double(limit)).rounded(.up))
        while remaining.count > limit {
            partsLeft = max(partsLeft, Int((Double(remaining.count) / Double(limit)).rounded(.up)))
            guard let cut = bestCut(remaining, limit: limit, partsLeft: partsLeft) else {
                partsLeft += 1
                if partsLeft > remaining.count {
                    // Một từ dài hơn cả giới hạn: đành cắt cứng.
                    parts.append(String(remaining[..<limit]))
                    remaining = Array(remaining[limit...])
                    partsLeft = 1
                }
                continue
            }
            parts.append(String(remaining[..<cut.end]).trimmingCharacters(in: .whitespaces))
            remaining = Array(remaining[cut.next...])
            partsLeft -= 1
        }
        let tail = String(remaining).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }

    /// Điểm cắt: phần đầu là `[0, end)`, phần sau bắt đầu từ `next` (bỏ khoảng trắng ở giữa).
    struct Cut {
        var end: Int
        var next: Int
    }

    /// Chọn điểm cắt sao cho phần đầu không vượt `limit` và phần còn lại vừa `partsLeft - 1` trang.
    static func bestCut(_ characters: [Character], limit: Int, partsLeft: Int) -> Cut? {
        guard partsLeft >= 2 else { return nil }
        let total = characters.count
        let ideal = Double(total) / Double(partsLeft)
        let restCapacity = limit * (partsLeft - 1)
        var bestClause: (cut: Cut, distance: Double)?
        var bestSpace: (cut: Cut, distance: Double)?

        for index in characters.indices where characters[index] == " " {
            var next = index
            while next < total && characters[next] == " " { next += 1 }
            let end = index
            guard end > 0, end <= limit, total - next <= restCapacity, next < total else { continue }
            let distance = abs(Double(end) - ideal)
            let cut = Cut(end: end, next: next)
            var last = end - 1
            while last > 0 && closingMarks.contains(characters[last]) { last -= 1 }
            if clauseMarks.contains(characters[last]), bestClause.map({ distance < $0.distance }) ?? true {
                bestClause = (cut, distance)
            }
            if bestSpace.map({ distance < $0.distance }) ?? true {
                bestSpace = (cut, distance)
            }
        }
        return bestClause?.cut ?? bestSpace?.cut
    }
}

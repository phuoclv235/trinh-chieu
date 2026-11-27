import Foundation

/// Kết quả phân tích chuỗi người dùng gõ.
public enum ParseResult: Sendable, Equatable {
    case reference(ScriptureReference)
    /// Tên sách khớp nhiều sách ngang nhau. `rest` là phần chương câu đã gõ sau tên sách.
    case ambiguousBook(candidates: [Book], rest: String)
    /// Mới gõ tên sách, chưa có chương.
    case incomplete(book: Book)
    /// Không hiểu được; `reason` là thông điệp tiếng Việt cho người dùng.
    case invalid(reason: String)
}

/// Phân tích địa chỉ câu: "gi 3 16", "I Cô-rinh-tô 13:4-7", "ro 8:28; 12:1-2", "mat 5:3,5,7".
///
/// Tên sách so khớp trên chuỗi đã gộp dấu lỏng và bỏ khoảng trắng, theo bốn bậc: khớp đúng khoá tiếng Việt,
/// khớp đúng khoá tiếng Anh, khớp tiền tố khoá tiếng Việt, khớp tiền tố khoá tiếng Anh (từ 3 ký tự). Nhiều sách
/// cùng khớp thì chọn sách có `priority` tốt hơn hẳn (chênh từ 5), không thì trả ``ParseResult/ambiguousBook``.
///
/// Bộ phân tích không biết số chương, số câu của bản dịch; kiểm phạm vi nằm ở ``BibleTranslation``.
public struct ReferenceParser: Sendable {
    public let catalog: BookCatalog

    /// Chênh lệch ưu tiên tối thiểu để chọn luôn ứng viên đầu.
    public static let decisivePriorityGap = 5

    public init(catalog: BookCatalog = .standard) {
        self.catalog = catalog
    }

    // MARK: - Phân tích

    public func parse(_ input: String) -> ParseResult {
        var segments = input.split(separator: ";", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while let last = segments.last, last.isEmpty {
            segments.removeLast()
        }
        guard !segments.isEmpty else {
            return .invalid(reason: Messages.missingBook)
        }
        if segments.contains(where: \.isEmpty) {
            return .invalid(reason: Messages.unreadable(input))
        }

        var ranges: [VerseRange] = []
        var currentBook: Book?
        for (index, segment) in segments.enumerated() {
            let numbers: String
            if segment.contains(where: \.isLetter) {
                guard let split = Self.splitBook(segment) else {
                    return .invalid(reason: Messages.unreadable(segment))
                }
                switch resolveBook(split.book) {
                case .found(let book):
                    currentBook = book
                case .ambiguous(let candidates):
                    if index == 0 {
                        let rest = ([split.numbers] + segments.dropFirst()).filter { !$0.isEmpty }
                        return .ambiguousBook(candidates: candidates, rest: rest.joined(separator: "; "))
                    }
                    return .invalid(reason: Messages.ambiguous(split.book, candidates: candidates))
                case .notFound:
                    return .invalid(reason: Messages.unknownBook(split.book))
                }
                numbers = split.numbers
                if numbers.isEmpty, let book = currentBook {
                    if segments.count == 1 { return .incomplete(book: book) }
                    return .invalid(reason: Messages.missingChapter(book.nameVi))
                }
            } else {
                guard currentBook != nil else {
                    return .invalid(reason: Messages.missingBook)
                }
                numbers = segment
            }
            guard let book = currentBook else { return .invalid(reason: Messages.missingBook) }
            switch NumberParser.parse(numbers, book: book.osis) {
            case .success(let parsed):
                ranges += parsed
            case .failure(let failure):
                return .invalid(reason: failure.reason)
            }
        }
        return .reference(ScriptureReference(ranges: ranges, catalog: catalog))
    }

    /// Các sách khớp phần tên đang gõ, tốt nhất trước: khớp đúng trước, khớp tiền tố sau, mỗi nhóm theo `priority`.
    public func bookCandidates(_ prefix: String, limit: Int = 5) -> [Book] {
        let key = BookCatalog.inputKey(prefix)
        guard !key.isEmpty, limit > 0 else { return [] }
        var seen = Set<Int>()
        var result: [Int] = []
        let groups = [
            sortedByPriority(exactMatches(key, in: catalog.vietnameseKeys)),
            sortedByPriority(exactMatches(key, in: catalog.englishKeys)),
            sortedByPriority(prefixMatches(key, in: catalog.vietnameseKeys)),
            sortedByPriority(prefixMatches(key, in: catalog.englishKeys)),
        ]
        for group in groups {
            for index in group where seen.insert(index).inserted {
                result.append(index)
            }
        }
        return result.prefix(limit).map { catalog.books[$0] }
    }

    // MARK: - Tên sách

    enum BookResolution: Equatable {
        case found(Book)
        case ambiguous([Book])
        case notFound
    }

    func resolveBook(_ text: String) -> BookResolution {
        let key = BookCatalog.inputKey(text)
        guard !key.isEmpty else { return .notFound }
        let tiers: [() -> [Int]] = [
            { exactMatches(key, in: catalog.vietnameseKeys) },
            { exactMatches(key, in: catalog.englishKeys) },
            { prefixMatches(key, in: catalog.vietnameseKeys) },
            { key.count >= 3 ? prefixMatches(key, in: catalog.englishKeys) : [] },
        ]
        for tier in tiers {
            let matches = sortedByPriority(tier())
            guard let first = matches.first else { continue }
            if matches.count == 1 {
                return .found(catalog.books[first])
            }
            let gap = catalog.books[matches[1]].priority - catalog.books[first].priority
            if gap >= Self.decisivePriorityGap {
                return .found(catalog.books[first])
            }
            return .ambiguous(matches.map { catalog.books[$0] })
        }
        return .notFound
    }

    private func exactMatches(_ key: String, in keys: [String: [Int]]) -> [Int] {
        keys[key] ?? []
    }

    private func prefixMatches(_ key: String, in keys: [String: [Int]]) -> [Int] {
        var result = Set<Int>()
        for (candidate, indices) in keys where candidate.hasPrefix(key) {
            result.formUnion(indices)
        }
        return Array(result)
    }

    private func sortedByPriority(_ indices: [Int]) -> [Int] {
        Array(Set(indices)).sorted { lhs, rhs in
            let left = catalog.books[lhs]
            let right = catalog.books[rhs]
            if left.priority != right.priority { return left.priority < right.priority }
            return left.ordinal < right.ordinal
        }
    }

    /// Tách "1 co 13:4" thành tên sách "1 co" và phần số "13:4". Trước chữ cái đầu tiên chỉ được có số thứ tự
    /// (chữ số, khoảng trắng, dấu chấm); sau phần số không được còn chữ cái.
    static func splitBook(_ segment: String) -> (book: String, numbers: String)? {
        let characters = Array(segment)
        guard let firstLetter = characters.firstIndex(where: \.isLetter) else { return nil }
        let prefixIsOrdinal = characters[..<firstLetter].allSatisfy { character in
            character.isWhitespace || character == "." || isASCIIDigit(character)
        }
        guard prefixIsOrdinal else { return nil }
        let numbersStart = characters[firstLetter...].firstIndex(where: { isASCIIDigit($0) }) ?? characters.endIndex
        let book = String(characters[..<numbersStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = String(characters[numbersStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if numbers.contains(where: \.isLetter) { return nil }
        return (book, numbers)
    }

    static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

// MARK: - Phần chương câu

/// Lỗi phân tích phần chương câu.
struct NumberParseFailure: Error, Equatable {
    var reason: String
}

/// Phân tích phần chương câu của một đoạn (giữa hai dấu `;`): "3:16", "3 16", "3.16", "3,16", "3:16-18",
/// "3:16-4:2", "3", "3-4", "3:16,18".
enum NumberParser {
    enum Token: Equatable {
        case number(Int)
        case colon
        case dash
        case comma
        case space
    }

    /// Số lớn nhất chấp nhận cho chương hoặc câu (Thi-thiên 119 có 176 câu).
    static let maxValue = 999

    static func parse(_ text: String, book: String) -> Result<[VerseRange], NumberParseFailure> {
        let unreadable = NumberParseFailure(reason: Messages.unreadable(text))
        guard var tokens = tokenize(text) else { return .failure(unreadable) }
        tokens = collapseSpaces(tokens)
        guard let normalized = chooseChapterVerseSeparator(tokens) else { return .failure(unreadable) }
        tokens = normalized

        var position = 0
        var ranges: [VerseRange] = []
        var currentChapter = 0
        var verseContext = false

        func readReference() -> (Int, Int?)? {
            guard position < tokens.count, case .number(let first) = tokens[position] else { return nil }
            position += 1
            guard position < tokens.count, tokens[position] == .colon else { return (first, nil) }
            position += 1
            guard position < tokens.count, case .number(let second) = tokens[position] else { return nil }
            position += 1
            return (first, second)
        }

        while true {
            guard let start = readReference() else { return .failure(unreadable) }
            var range: VerseRange
            if let verse = start.1 {
                range = .verse(book, start.0, verse)
            } else if verseContext {
                range = .verse(book, currentChapter, start.0)
            } else {
                range = .chapters(book, start.0, start.0)
            }
            if position < tokens.count, tokens[position] == .dash {
                position += 1
                guard let end = readReference() else { return .failure(unreadable) }
                if range.startVerse != nil {
                    if let endVerse = end.1 {
                        range.endChapter = end.0
                        range.endVerse = endVerse
                    } else {
                        range.endVerse = end.0
                    }
                } else if let endVerse = end.1 {
                    range.startVerse = 1
                    range.endChapter = end.0
                    range.endVerse = endVerse
                } else {
                    range.endChapter = end.0
                }
            }
            if let failure = validate(range) { return .failure(failure) }
            ranges.append(range)
            currentChapter = range.endChapter
            verseContext = range.endVerse != nil

            if position == tokens.count { break }
            guard tokens[position] == .comma else { return .failure(unreadable) }
            position += 1
        }
        return .success(ranges)
    }

    static func validate(_ range: VerseRange) -> NumberParseFailure? {
        let values = [range.startChapter, range.endChapter] + [range.startVerse, range.endVerse].compactMap { $0 }
        if values.contains(where: { $0 < 1 }) {
            return NumberParseFailure(reason: Messages.zeroNumber)
        }
        if range.endChapter < range.startChapter {
            return NumberParseFailure(
                reason: Messages.endChapterBeforeStart(end: range.endChapter, start: range.startChapter)
            )
        }
        if range.endChapter == range.startChapter, let start = range.startVerse, let end = range.endVerse, end < start {
            return NumberParseFailure(reason: Messages.endVerseBeforeStart(end: end, start: start))
        }
        return nil
    }

    static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var digits = ""
        func flushDigits() -> Bool {
            guard !digits.isEmpty else { return true }
            defer { digits = "" }
            guard digits.count <= 3, let value = Int(digits), value <= maxValue else { return false }
            tokens.append(.number(value))
            return true
        }
        for character in text {
            if ReferenceParser.isASCIIDigit(character) {
                digits.append(character)
                continue
            }
            guard flushDigits() else { return nil }
            switch character {
            case ":", ".":
                tokens.append(.colon)
            case "-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}":
                tokens.append(.dash)
            case ",":
                tokens.append(.comma)
            default:
                guard character.isWhitespace else { return nil }
                if tokens.last != .space { tokens.append(.space) }
            }
        }
        guard flushDigits() else { return nil }
        return tokens
    }

    /// Bỏ khoảng trắng, trừ khoảng trắng đứng giữa hai số ("3 16").
    static func collapseSpaces(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        for (index, token) in tokens.enumerated() {
            guard token == .space else {
                result.append(token)
                continue
            }
            let previousIsNumber = index > 0 && isNumber(tokens[index - 1])
            let nextIsNumber = index + 1 < tokens.count && isNumber(tokens[index + 1])
            if previousIsNumber && nextIsNumber { result.append(.space) }
        }
        return result
    }

    /// Chọn dấu tách chương và câu. Có ":" hoặc "." thì dùng nó và không cho khoảng trắng giữa hai số. Không có thì
    /// khoảng trắng đầu tiên giữa hai số ("3 16") là dấu tách; không có nữa thì dấu phẩy ngay sau số đầu ("3,16").
    static func chooseChapterVerseSeparator(_ tokens: [Token]) -> [Token]? {
        var tokens = tokens
        let spaces = tokens.indices.filter { tokens[$0] == .space }
        if tokens.contains(.colon) {
            return spaces.isEmpty ? tokens : nil
        }
        if let first = spaces.first {
            guard spaces.count == 1 else { return nil }
            tokens[first] = .colon
            return tokens
        }
        if tokens.count >= 3, isNumber(tokens[0]), tokens[1] == .comma, isNumber(tokens[2]) {
            tokens[1] = .colon
        }
        return tokens
    }

    static func isNumber(_ token: Token) -> Bool {
        if case .number = token { return true }
        return false
    }
}

// MARK: - Thông điệp

enum Messages {
    static let missingBook = "Hãy gõ tên sách trước, ví dụ “Giăng 3:16”."
    static let zeroNumber = "Số chương và số câu bắt đầu từ 1."

    static func unreadable(_ text: String) -> String {
        "Hệ thống chưa hiểu “\(text)”. Hãy gõ theo dạng “Giăng 3:16-18”."
    }

    static func unknownBook(_ text: String) -> String {
        "Hệ thống không tìm thấy sách “\(text)”."
    }

    static func ambiguous(_ text: String, candidates: [Book]) -> String {
        let names = candidates.prefix(5).map(\.nameVi).joined(separator: ", ")
        return "“\(text)” có thể là nhiều sách: \(names). Hãy gõ rõ hơn."
    }

    static func missingChapter(_ bookName: String) -> String {
        "Thiếu số chương sau “\(bookName)”."
    }

    static func endChapterBeforeStart(end: Int, start: Int) -> String {
        "Chương cuối (\(end)) nhỏ hơn chương đầu (\(start))."
    }

    static func endVerseBeforeStart(end: Int, start: Int) -> String {
        "Câu cuối (\(end)) nhỏ hơn câu đầu (\(start))."
    }
}

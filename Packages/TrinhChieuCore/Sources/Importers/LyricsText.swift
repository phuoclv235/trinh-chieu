import CoreModel
import Foundation
import VietText

/// Lời bài hát đã phân tích từ văn bản, trước khi thành bộ trình chiếu.
public struct ParsedLyrics: Sendable, Hashable {
    /// Một đoạn: nhãn và các trang (mỗi trang là các dòng nối bằng `\n`).
    public struct Section: Sendable, Hashable {
        public var label: GroupLabel
        public var slides: [String]
        /// Dòng (đếm từ 1) của nhãn, hoặc của dòng nội dung đầu tiên khi đoạn không có nhãn.
        public var line: Int

        public init(label: GroupLabel, slides: [String], line: Int) {
            self.label = label
            self.slides = slides
            self.line = line
        }
    }

    public var title: String?
    public var number: String?
    public var authors: [String]
    public var copyright: String?
    public var key: String?
    public var sections: [Section]
    /// Thứ tự hát, là chỉ số vào `sections`. Không có dòng "Thứ tự:" thì là thứ tự xuất hiện trong văn bản (đoạn
    /// lặp lại nguyên văn được tính là cùng một đoạn hát lại).
    public var order: [Int]
    /// Văn bản có dòng "Thứ tự:" dùng được.
    public var hasExplicitOrder: Bool
    /// Chỗ cần báo cho bạn: trang quá dài, thứ tự hát nhắc tới đoạn không có.
    public var issues: [Issue]

    public struct Issue: Sendable, Hashable {
        /// Dòng (đếm từ 1), `nil` khi áp cho cả bài.
        public var line: Int?
        public var message: String

        public init(line: Int?, message: String) {
            self.line = line
            self.message = message
        }
    }

    public init(
        title: String? = nil, number: String? = nil, authors: [String] = [], copyright: String? = nil,
        key: String? = nil, sections: [Section] = [], order: [Int] = [], hasExplicitOrder: Bool = false,
        issues: [Issue] = []
    ) {
        self.title = title
        self.number = number
        self.authors = authors
        self.copyright = copyright
        self.key = key
        self.sections = sections
        self.order = order
        self.hasExplicitOrder = hasExplicitOrder
        self.issues = issues
    }

    /// Bộ trình chiếu bài hát: mỗi đoạn một `SlideGroup`, mỗi trang một phần tử chữ ở ô `body`, một thứ tự hát
    /// "Mặc định". Đoạn không có trang nào được một trang trống, để trình soạn có chỗ gõ.
    public func makePresentation(fallbackTitle: String, now: Date = Date()) -> Presentation {
        let groups = sections.map { section -> SlideGroup in
            let texts = section.slides.isEmpty ? [""] : section.slides
            let slides = texts.map { Slide(elements: [.text(TextElement(slot: .body, text: $0))]) }
            return SlideGroup(label: section.label, slides: slides)
        }
        let arrangement = Arrangement(name: "Mặc định", groupIDs: order.map { groups[$0].id })
        let song = SongInfo(number: number, authors: authors, copyright: copyright, key: key)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespaces) ?? ""
        return Presentation(
            kind: .song, title: trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle, createdAt: now, modifiedAt: now,
            song: song, groups: groups, arrangements: [arrangement], activeArrangementID: arrangement.id
        )
    }
}

/// Phân tích và dựng lại lời bài hát dạng văn bản. Dùng cho bộ nhập tệp `.txt` và ô soạn lời dạng văn bản (T1.9).
///
/// Nhãn không có ngoặc vuông ("Câu 1", "ĐK:", "1. lời") chỉ được nhận khi văn bản không có nhãn ngoặc vuông nào.
///
/// Cú pháp:
///
/// ```
/// Tiêu đề: Chúa Là Đá Muôn Đời
/// Số: 123
/// Tác giả: A, B
/// Thứ tự: Câu 1, ĐK, Câu 2, ĐK
///
/// [Câu 1]
/// dòng một
/// dòng hai
///
/// trang thứ hai của câu 1
///
/// [Điệp khúc]
/// ...
/// ```
public enum LyricsText {
    /// Số dòng tối đa một trang của mẫu mặc định (`Theme.fallback().lyrics.maxLinesPerSlide`). Trang dài hơn chỉ bị
    /// cảnh báo, không bị chia khi nhập.
    public static let defaultMaxLinesPerSlide = 4

    /// Phân tích văn bản (đã giải mã). Không ném lỗi: văn bản lạ vẫn cho kết quả, có thể rỗng.
    public static func parse(_ text: String, maxLinesPerSlide: Int = defaultMaxLinesPerSlide) -> ParsedLyrics {
        var parser = LyricsParser(lines: VietText.normalize(text).components(separatedBy: "\n"))
        return parser.run(maxLinesPerSlide: maxLinesPerSlide)
    }

    /// Dựng văn bản từ bộ trình chiếu, ổn định: `parse(render(p))` giữ nguyên tiêu đề, thông tin bài hát, nhãn và chữ
    /// các trang, thứ tự hát đang chọn. Dòng trống trong một trang bị bỏ (dòng trống là dấu tách trang).
    public static func render(_ presentation: Presentation) -> String {
        var lines = ["Tiêu đề: \(oneLine(presentation.title))"]
        if let song = presentation.song {
            if let number = song.number, !number.isEmpty {
                lines.append("Số: \(oneLine(number))")
            }
            if !song.authors.isEmpty {
                lines.append("Tác giả: " + song.authors.map(oneLine).joined(separator: ", "))
            }
            if let copyright = song.copyright, !copyright.isEmpty {
                lines.append("Bản quyền: \(oneLine(copyright))")
            }
            if let key = song.key, !key.isEmpty {
                lines.append("Tông: \(oneLine(key))")
            }
        }
        let ordered = presentation.orderedGroups()
        if ordered.map(\.id) != presentation.groups.map(\.id) {
            lines.append("Thứ tự: " + ordered.map { labelName($0.label) }.joined(separator: ", "))
        }
        for group in presentation.groups {
            lines.append("")
            lines.append("[\(labelName(group.label))]")
            let texts = group.slides.map(slideText).filter { !$0.isEmpty }
            for (index, text) in texts.enumerated() {
                if index > 0 { lines.append("") }
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Tên nhãn hiện cho bạn và ghi trong văn bản: "Câu 1", "Điệp khúc", "Cầu nối 2".
    public static func labelName(_ label: GroupLabel) -> String {
        let base: String
        switch label.kind {
        case .verse:
            base = "Câu"
        case .chorus:
            base = "Điệp khúc"
        case .prechorus:
            base = "Tiền điệp khúc"
        case .bridge:
            base = "Cầu nối"
        case .tag:
            base = "Tag"
        case .intro:
            base = "Dạo"
        case .ending:
            base = "Kết"
        case .custom:
            let custom = oneLine(label.custom ?? "")
            return custom.isEmpty ? "Đoạn" : custom
        }
        if let number = label.number { return "\(base) \(number)" }
        return base
    }

    /// Chữ của một trang: các phần tử chữ nối bằng `\n`, mỗi dòng bỏ khoảng trắng đầu cuối, bỏ dòng trống.
    public static func slideText(_ slide: Slide) -> String {
        let texts = slide.elements.compactMap { element -> String? in
            if case .text(let text) = element { return text.text }
            return nil
        }
        return cleanLines(texts.joined(separator: "\n")).joined(separator: "\n")
    }

    // MARK: - Nhận dạng nhãn

    /// Tên nhãn đã gộp dấu → loại.
    private static let labelNameList: [(name: String, kind: GroupLabelKind)] = [
        ("tien diep khuc", .prechorus), ("pre-chorus", .prechorus), ("pre chorus", .prechorus),
        ("prechorus", .prechorus), ("tien dk", .prechorus),
        ("diep khuc", .chorus), ("dk", .chorus), ("chorus", .chorus), ("refrain", .chorus),
        ("cau noi", .bridge), ("bridge", .bridge),
        ("cau", .verse), ("verse", .verse),
        ("tag", .tag),
        ("dao", .intro), ("intro", .intro),
        ("ket", .ending), ("ending", .ending), ("outro", .ending),
    ]

    /// Như `labelNameList`, tên dài xếp trước để "cau noi" không bị nhận là "cau".
    static let labelNames = labelNameList.sorted { $0.name.count > $1.name.count }

    /// Nhận dạng chữ của một nhãn (không có ngoặc vuông): "Câu 1", "ĐK", "Điệp khúc 2:", "Chorus", "3".
    /// `nil` là không phải nhãn đã biết.
    static func knownLabel(_ raw: String) -> GroupLabel? {
        var folded = VietText.fold(raw)
        while let last = folded.last, last == ":" || last == "." || last == " " {
            folded.removeLast()
        }
        guard !folded.isEmpty else { return nil }
        if let number = smallNumber(folded) {
            return GroupLabel(kind: .verse, number: number)
        }
        for (name, kind) in labelNames where folded.hasPrefix(name) {
            let rest = folded.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return GroupLabel(kind: kind) }
            if let number = smallNumber(rest) { return GroupLabel(kind: kind, number: number) }
        }
        return nil
    }

    /// Số nguyên dương tối đa 3 chữ số.
    static func smallNumber(_ text: some StringProtocol) -> Int? {
        guard (1...3).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        guard let value = Int(text), value > 0 else { return nil }
        return value
    }

    /// Mỗi dòng bỏ khoảng trắng đầu cuối, bỏ dòng trống.
    static func cleanLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Bỏ xuống dòng trong giá trị một dòng (tiêu đề, tác giả).
    static func oneLine(_ text: String) -> String {
        cleanLines(text).joined(separator: " ")
    }
}

/// Trạng thái phân tích một văn bản lời bài hát.
private struct LyricsParser {
    /// Một dòng đã phân loại.
    enum LineKind {
        case blank
        /// Nhãn đứng riêng một dòng.
        case label(GroupLabel)
        /// Nhãn và dòng lời đầu tiên trên cùng một dòng: "ĐK: Hát lên...", "1. Lời câu một".
        case labelWithText(GroupLabel, String)
        case text(String)
    }

    /// Khoá siêu dữ liệu đã gộp dấu.
    enum MetadataKey {
        case title, number, authors, copyright, key, order
    }

    static let metadataKeys: [String: MetadataKey] = [
        "tieu de": .title, "title": .title,
        "so": .number, "so bai": .number, "number": .number,
        "tac gia": .authors, "author": .authors, "authors": .authors,
        "ban quyen": .copyright, "copyright": .copyright,
        "tong": .key, "key": .key,
        "thu tu": .order, "order": .order,
    ]

    let lines: [String]
    var result = ParsedLyrics()
    var orderNames: [String]?
    var orderLine: Int?

    init(lines: [String]) {
        self.lines = lines
    }

    mutating func run(maxLinesPerSlide: Int) -> ParsedLyrics {
        let bodyStart = readHeader()
        // Văn bản đã dùng nhãn trong ngoặc vuông (như `render` ghi) thì dòng không có ngoặc luôn là lời: một dòng lời
        // đúng bằng "Điệp khúc" hay "Kết" không bị nhận nhầm là nhãn.
        let allowsBareLabels = !(bodyStart..<lines.count).contains { Self.isBracketLabel(lines[$0]) }
        let kinds = (bodyStart..<lines.count).map { index in
            (index: index, kind: Self.classify(lines[index], allowsBareLabels: allowsBareLabels))
        }
        let hasLabels = kinds.contains { item in
            switch item.kind {
            case .label, .labelWithText:
                return true
            case .blank, .text:
                return false
            }
        }
        if hasLabels {
            readLabeledBody(kinds)
        } else {
            readBlocks(kinds)
        }
        applyOrder()
        checkSlideLengths(maxLinesPerSlide: maxLinesPerSlide)
        return result
    }

    // MARK: Đầu bài

    /// Đọc các dòng siêu dữ liệu ở đầu văn bản (bỏ qua dòng trống), trả chỉ số dòng đầu của phần lời.
    mutating func readHeader() -> Int {
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                index += 1
                continue
            }
            guard let colon = line.firstIndex(of: ":"),
                let key = Self.metadataKeys[VietText.fold(String(line[..<colon]))]
            else { break }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case .title:
                result.title = value
            case .number:
                result.number = value.isEmpty ? nil : value
            case .authors:
                result.authors = value.split(whereSeparator: { $0 == "," || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case .copyright:
                result.copyright = value.isEmpty ? nil : value
            case .key:
                result.key = value.isEmpty ? nil : value
            case .order:
                orderNames = value.split(whereSeparator: { $0 == "," || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                orderLine = index + 1
            }
            index += 1
        }
        return index
    }

    // MARK: Phân loại dòng

    static func isBracketLabel(_ raw: String) -> Bool {
        let line = raw.trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("[") && line.hasSuffix("]") && line.count > 2
    }

    static func classify(_ raw: String, allowsBareLabels: Bool) -> LineKind {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return .blank }
        if isBracketLabel(line) {
            let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if let label = LyricsText.knownLabel(inner) { return .label(label) }
            return .label(GroupLabel(kind: .custom, custom: inner))
        }
        guard allowsBareLabels else { return .text(line) }
        if let label = wholeLineLabel(line) { return .label(label) }
        if let (label, text) = inlineLabel(line) { return .labelWithText(label, text) }
        return .text(line)
    }

    /// Cả dòng là nhãn không có ngoặc vuông: "Câu 1", "1.", "ĐK:", "Điệp khúc:", "Chorus". Số đứng một mình phải có
    /// dấu chấm hoặc hai chấm theo sau, để dòng lời chỉ có một con số không bị nhận nhầm.
    static func wholeLineLabel(_ line: String) -> GroupLabel? {
        if LyricsText.smallNumber(line) != nil { return nil }
        return LyricsText.knownLabel(line)
    }

    /// Nhãn đứng đầu dòng lời: "ĐK: Hát lên", "Điệp khúc: ...", "1. Lời câu một", "2: Lời câu hai".
    static func inlineLabel(_ line: String) -> (GroupLabel, String)? {
        guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "." }) else { return nil }
        // Sau dấu phải có khoảng trắng: "1.5" hay "3:16" không phải nhãn.
        let afterSeparator = line.index(after: separator)
        guard afterSeparator < line.endIndex, line[afterSeparator].isWhitespace else { return nil }
        let head = String(line[..<separator])
        let text = line[afterSeparator...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        // Dấu chấm chỉ đi sau số câu ("1. Lời"), không đi sau tên đoạn.
        if line[separator] == "." && LyricsText.smallNumber(head) == nil { return nil }
        guard let label = LyricsText.knownLabel(head) else { return nil }
        // "Câu: ..." không số là dòng lời có dấu hai chấm, không phải nhãn.
        if label.kind == .verse && label.number == nil { return nil }
        return (label, text)
    }

    // MARK: Phần lời có nhãn

    mutating func readLabeledBody(_ kinds: [(index: Int, kind: LineKind)]) {
        var label: GroupLabel?
        var labelLine = 0
        var slides: [[String]] = []
        var slide: [String] = []
        var occurrences: [Int] = []

        func flushSlide() {
            if !slide.isEmpty { slides.append(slide) }
            slide = []
        }

        func flushSection(_ parser: inout LyricsParser) {
            flushSlide()
            defer {
                slides = []
                label = nil
            }
            guard let current = label else { return }
            let texts = slides.map { $0.joined(separator: "\n") }
            occurrences.append(parser.addSection(label: current, slides: texts, line: labelLine))
        }

        for (index, kind) in kinds {
            switch kind {
            case .blank:
                flushSlide()
            case .label(let newLabel):
                flushSection(&self)
                label = newLabel
                labelLine = index + 1
            case .labelWithText(let newLabel, let text):
                flushSection(&self)
                label = newLabel
                labelLine = index + 1
                slide.append(text)
            case .text(let text):
                if label == nil {
                    // Lời đứng trước nhãn đầu tiên: một đoạn "Câu" không số.
                    label = GroupLabel(kind: .verse)
                    labelLine = index + 1
                }
                slide.append(text)
            }
        }
        flushSection(&self)
        result.order = occurrences
    }

    /// Thêm một đoạn, hoặc trả đoạn đã có khi cùng nhãn và cùng chữ (đoạn hát lại được chép lại trong văn bản).
    mutating func addSection(label: GroupLabel, slides: [String], line: Int) -> Int {
        if let existing = result.sections.firstIndex(where: { $0.label == label && $0.slides == slides }) {
            return existing
        }
        result.sections.append(ParsedLyrics.Section(label: label, slides: slides, line: line))
        return result.sections.count - 1
    }

    // MARK: Văn bản không có nhãn

    /// Mỗi khối cách nhau bởi dòng trống là một đoạn. Khối trùng chữ với khối trước là cùng đoạn hát lại, và đoạn đó
    /// được coi là điệp khúc. Các khối khác là "Câu 1", "Câu 2"... theo thứ tự.
    mutating func readBlocks(_ kinds: [(index: Int, kind: LineKind)]) {
        var blocks: [(line: Int, text: String)] = []
        var current: [String] = []
        var currentLine = 0
        for (index, kind) in kinds {
            switch kind {
            case .text(let text):
                if current.isEmpty { currentLine = index + 1 }
                current.append(text)
            case .blank, .label, .labelWithText:
                if !current.isEmpty { blocks.append((currentLine, current.joined(separator: "\n"))) }
                current = []
            }
        }
        if !current.isEmpty { blocks.append((currentLine, current.joined(separator: "\n"))) }

        var counts: [String: Int] = [:]
        for block in blocks {
            counts[VietText.fold(block.text), default: 0] += 1
        }
        var repeatedKeys: [String] = []
        for block in blocks {
            let key = VietText.fold(block.text)
            if counts[key, default: 0] > 1, !repeatedKeys.contains(key) { repeatedKeys.append(key) }
        }

        var sectionByKey: [String: Int] = [:]
        var verseNumber = 0
        for block in blocks {
            let key = VietText.fold(block.text)
            if let existing = sectionByKey[key] {
                result.order.append(existing)
                continue
            }
            let label: GroupLabel
            if let chorusIndex = repeatedKeys.firstIndex(of: key) {
                label = GroupLabel(kind: .chorus, number: repeatedKeys.count > 1 ? chorusIndex + 1 : nil)
            } else {
                verseNumber += 1
                label = GroupLabel(kind: .verse, number: verseNumber)
            }
            result.sections.append(ParsedLyrics.Section(label: label, slides: [block.text], line: block.line))
            sectionByKey[key] = result.sections.count - 1
            result.order.append(result.sections.count - 1)
        }
    }

    // MARK: Thứ tự hát, độ dài trang

    mutating func applyOrder() {
        guard let names = orderNames, !names.isEmpty else { return }
        var order: [Int] = []
        for name in names {
            if let index = sectionIndex(named: name) {
                order.append(index)
            } else {
                let message = "Thứ tự hát nhắc tới đoạn “\(name)” không có trong bài; Hệ thống bỏ qua tên này."
                result.issues.append(ParsedLyrics.Issue(line: orderLine, message: message))
            }
        }
        if order.isEmpty { return }
        result.order = order
        result.hasExplicitOrder = true
    }

    /// Đoạn ứng với một tên trong dòng "Thứ tự:". Khớp đúng nhãn trước; "ĐK" khớp "Điệp khúc 1" khi bài chỉ có một
    /// điệp khúc; nhãn tự đặt khớp theo chữ đã gộp dấu.
    func sectionIndex(named name: String) -> Int? {
        let bracketless = name.hasPrefix("[") && name.hasSuffix("]") ? String(name.dropFirst().dropLast()) : name
        if let label = LyricsText.knownLabel(bracketless) {
            if let exact = result.sections.firstIndex(where: { $0.label == label }) { return exact }
            let sameKind = result.sections.indices.filter { result.sections[$0].label.kind == label.kind }
            if label.number == nil, sameKind.count == 1 { return sameKind[0] }
            if label.number == 1, sameKind.count == 1, result.sections[sameKind[0]].label.number == nil {
                return sameKind[0]
            }
            return nil
        }
        let folded = VietText.fold(bracketless)
        return result.sections.firstIndex { section in
            section.label.kind == .custom && VietText.fold(section.label.custom ?? "") == folded
        }
    }

    mutating func checkSlideLengths(maxLinesPerSlide: Int) {
        for section in result.sections {
            for (index, slide) in section.slides.enumerated() {
                let count = slide.components(separatedBy: "\n").count
                guard count > maxLinesPerSlide else { continue }
                let place = "Trang \(index + 1) của \(LyricsText.labelName(section.label))"
                let limit = "nhiều hơn \(maxLinesPerSlide) dòng của mẫu mặc định"
                let message = "\(place) có \(count) dòng, \(limit). Hệ thống không tự chia; bạn chia trong trình soạn."
                result.issues.append(ParsedLyrics.Issue(line: section.line, message: message))
            }
        }
    }
}

import Foundation
import Scripture

/// Bộ nhập Kinh Thánh dạng USFM (Paratext). Một tệp có thể chứa một hoặc nhiều sách (mỗi sách bắt đầu bằng `\id`).
///
/// Giữ chữ của câu trong `\v`; bỏ chú thích (`\f ... \f*`, `\fe`), tham chiếu chéo (`\x ... \x*`), tiêu đề đoạn
/// (`\s`, `\ms`, `\mr`, `\r`, `\d`, `\sp`), phần giới thiệu sách, thuộc tính sau dấu `|` (`\w chữ|strong="H1"\w*`).
public struct USFMImporter: BibleImporter {
    public static let displayName = "USFM"
    public static let fileExtensions = ["usfm", "sfm", "ptx"]

    public init() {}

    /// Văn bản có dòng `\id` hoặc có cả `\c` và `\v`.
    public static func canImport(_ data: Data, filename: String) -> Bool {
        guard !data.isEmpty, !TextDecoding.looksBinary(data), !TextDecoding.looksLikeXML(data) else { return false }
        let head = TextDecoding.decode(data.prefix(65_536)).text
        let firstMarker = head.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return firstMarker == "\\id" || (head.contains("\\c ") && head.contains("\\v "))
    }

    public func importBible(from data: Data, filename: String) throws -> BibleImportOutcome {
        let text = TextDecoding.decode(data).text
        var parser = USFMParser(collector: BibleCollector(filename: filename))
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            parser.process(line: line, number: index + 1)
        }
        return try parser.finish()
    }
}

/// Trạng thái phân tích USFM theo từng dòng.
struct USFMParser {
    var collector: BibleCollector
    private var book: String?
    private var chapter = 0
    private var verse: Int?
    private var buffer = ""
    /// Dấu đang mở của chú thích, tham chiếu chéo... mà nội dung bị bỏ (`f`, `x`). Đóng khi gặp `\f*`.
    private var skipping: String?
    /// Đang trong dấu ký tự (`\w`): phần sau `|` là thuộc tính, bỏ.
    private var cutsAttributes = false
    /// Mức ưu tiên của tên sách đang giữ: `toc2` (2) > `h` (1) > `toc1` (0).
    private var bookNamePriority: [String: Int] = [:]
    private var bookNamesFound: [String: String] = [:]

    init(collector: BibleCollector) {
        self.collector = collector
    }

    /// Dấu đầu dòng mà cả dòng không phải chữ của câu (tiêu đề, giới thiệu, ghi chú biên tập).
    static let lineSkipMarkers: Set<String> = [
        "s", "ms", "mr", "r", "d", "sp", "sr", "cl", "cd", "rem", "ide", "sts", "toc", "toca", "mt", "mte", "imt",
        "imte", "is", "ip", "ipi", "im", "imi", "ipq", "imq", "ipr", "iq", "ib", "ili", "iot", "io", "ior", "iex",
        "ie", "restore", "periph", "cp", "usfm", "lit",
    ]

    /// Dấu ký tự mà nội dung bên trong bị bỏ tới dấu đóng tương ứng.
    static let contentSkipMarkers: Set<String> = ["f", "fe", "ef", "x", "ex", "fig", "rq", "va", "vp", "ca", "cat"]

    /// Dấu đoạn văn, thơ, danh sách, bảng: chỉ là chỗ ngắt, thành một dấu cách.
    static let paragraphMarkers: Set<String> = [
        "p", "m", "po", "pr", "cls", "pmo", "pm", "pmc", "pmr", "pi", "mi", "nb", "pc", "ph", "b", "q", "qr", "qc",
        "qa", "qm", "qd", "lh", "li", "lf", "lim", "litl", "tr", "th", "thr", "tc", "tcr", "pb",
    ]

    /// Tên dấu bỏ số cuối (`s1` → `s`, `q2` → `q`, `toc2` → `toc`).
    static func baseName(_ marker: String) -> String {
        String(marker.reversed().drop(while: { $0.isNumber }).reversed())
    }

    mutating func process(line rawLine: String, number: Int) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("\\") else {
            // Dòng tiếp nối của câu đang đọc.
            appendInline(Array(line))
            return
        }
        let firstSpace = line.firstIndex(where: { $0 == " " }) ?? line.endIndex
        let marker = String(line[line.index(after: line.startIndex)..<firstSpace])
        let rest = line[firstSpace...].trimmingCharacters(in: .whitespaces)
        let base = Self.baseName(marker)
        switch marker {
        case "id":
            flushVerse()
            skipping = nil
            chapter = 0
            let code = String(rest.prefix { !$0.isWhitespace })
            book = BibleBookCodes.osis(usfm: code)
            if book == nil { collector.noteUnknownBook(code) }
            return
        case "c":
            flushVerse()
            skipping = nil
            chapter = Int(rest.prefix { $0.isNumber }) ?? 0
            return
        case "h", "toc1", "toc2":
            if let book {
                let priority = marker == "toc2" ? 2 : (marker == "h" ? 1 : 0)
                if priority > bookNamePriority[book, default: -1], !rest.isEmpty {
                    bookNamePriority[book] = priority
                    bookNamesFound[book] = rest
                }
            }
            return
        default:
            break
        }
        if Self.lineSkipMarkers.contains(base) {
            return
        }
        appendInline(Array(line))
    }

    /// Đọc phần trong dòng: dấu `\v`, dấu ký tự, chú thích, chữ.
    private mutating func appendInline(_ characters: [Character]) {
        guard !characters.isEmpty else { return }
        appendText(" ")
        var index = 0
        while index < characters.count {
            if characters[index] == "\\" {
                index = readMarker(characters, from: index + 1)
            } else {
                var end = index
                while end < characters.count, characters[end] != "\\" { end += 1 }
                appendText(String(characters[index..<end]))
                index = end
            }
        }
    }

    /// Đọc một dấu bắt đầu ở `start` (ngay sau dấu `\`), xử lý, trả vị trí đọc tiếp.
    private mutating func readMarker(_ characters: [Character], from start: Int) -> Int {
        var end = start
        while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "+" {
            end += 1
        }
        let isClosing = end < characters.count && characters[end] == "*"
        var name = String(characters[start..<end])
        if name.hasPrefix("+") { name.removeFirst() }
        var next = isClosing ? end + 1 : end
        // Một dấu cách sau dấu mở chỉ là dấu tách.
        if !isClosing, next < characters.count, characters[next] == " " { next += 1 }
        let base = Self.baseName(name)

        if let open = skipping {
            if isClosing && name == open { skipping = nil }
            return next
        }
        if isClosing {
            cutsAttributes = false
            return next
        }
        if name == "v" {
            flushVerse()
            var tokenEnd = next
            while tokenEnd < characters.count, !characters[tokenEnd].isWhitespace { tokenEnd += 1 }
            let token = String(characters[next..<tokenEnd])
            verse = Int(token.prefix { $0.isNumber })
            if token.contains("-") || token.contains(","), let book {
                collector.noteBridge("\(book) \(chapter):\(token)")
            }
            if tokenEnd < characters.count { tokenEnd += 1 }
            return tokenEnd
        }
        if name == "c" {
            flushVerse()
            var tokenEnd = next
            while tokenEnd < characters.count, characters[tokenEnd].isNumber { tokenEnd += 1 }
            chapter = Int(String(characters[next..<tokenEnd])) ?? chapter
            return tokenEnd
        }
        if Self.contentSkipMarkers.contains(name) {
            skipping = name
            return next
        }
        if Self.paragraphMarkers.contains(base) {
            appendText(" ")
            return next
        }
        // Dấu ký tự (\w, \nd, \wj, \add...): giữ chữ, bỏ thuộc tính sau `|`.
        cutsAttributes = true
        return next
    }

    private mutating func appendText(_ text: String) {
        guard skipping == nil, book != nil, verse != nil else { return }
        if cutsAttributes, let bar = text.firstIndex(of: "|") {
            buffer += text[..<bar]
        } else {
            buffer += text
        }
    }

    mutating func flushVerse() {
        if let book, let verse, chapter > 0 {
            collector.add(book: book, chapter: chapter, verse: verse, text: buffer)
        }
        buffer = ""
        verse = nil
    }

    /// Kết thúc tệp: ghi câu cuối và tên sách, trả kết quả.
    mutating func finish() throws -> BibleImportOutcome {
        flushVerse()
        for (osis, name) in bookNamesFound {
            collector.setBookName(name, for: osis)
        }
        return try collector.finish()
    }
}

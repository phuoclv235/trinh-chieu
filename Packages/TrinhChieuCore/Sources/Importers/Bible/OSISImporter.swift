import Foundation
import Scripture

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Bộ nhập Kinh Thánh dạng OSIS (XML). Đọc cả câu dạng phần tử bọc (`<verse osisID>chữ</verse>`) và dạng mốc
/// (`<verse sID/>chữ<verse eID/>`). Bỏ `note` (chú thích, tham chiếu chéo), `title` (tiêu đề đoạn, đề Thi-thiên),
/// thuộc tính Strong của `<w>` (giữ chữ).
public struct OSISImporter: BibleImporter {
    public static let displayName = "OSIS"
    public static let fileExtensions = ["osis", "xml"]

    public init() {}

    public static func canImport(_ data: Data, filename: String) -> Bool {
        guard !data.isEmpty, !TextDecoding.looksBinary(data), TextDecoding.looksLikeXML(data) else { return false }
        let head = TextDecoding.decode(data.prefix(4096)).text.lowercased()
        return head.contains("<osis") || head.contains(":osis")
    }

    public func importBible(from data: Data, filename: String) throws -> BibleImportOutcome {
        let handler = OSISHandler(collector: BibleCollector(filename: filename))
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        guard parser.parse() else { throw XMLText.parseError(parser, filename: filename) }
        handler.flushVerse()
        guard handler.sawOSISRoot else {
            throw ImportError.invalidContent(filename: filename, reason: "phần tử gốc không phải <osis>.")
        }
        return try handler.collector.finish()
    }
}

/// Xử lý sự kiện XML của tệp OSIS theo luồng, không dựng cây (cả bộ Kinh Thánh có hàng trăm nghìn phần tử).
private final class OSISHandler: NSObject, XMLParserDelegate {
    var collector: BibleCollector
    private(set) var sawOSISRoot = false

    private var depth = 0
    /// Mức lồng của phần tử bị bỏ nội dung (`note`, `title`); 0 là không bỏ.
    private var skipDepth = 0
    private var book: String?
    private var bookDepth = 0
    private var chapter = 0
    private var verse: (book: String, chapter: Int, verse: Int)?
    /// Mức lồng của câu dạng phần tử bọc; `nil` với câu dạng mốc.
    private var verseDepth: Int?
    private var buffer = ""

    /// Đang trong `<work>` ở phần đầu: đọc tên bản dịch và ngôn ngữ.
    private var workDepth: Int?
    private var headerField: String?
    private var headerText = ""
    /// Đang đọc tiêu đề chính của sách (trước chương đầu) làm tên sách.
    private var bookTitleDepth: Int?
    private var bookTitle = ""

    static let skippedElements: Set<String> = ["note", "title", "figure", "catchWord", "rdg", "index", "milestone"]
    static let breakElements: Set<String> = ["l", "lb", "lg", "p", "q", "list", "item", "div", "chapter"]

    init(collector: BibleCollector) {
        self.collector = collector
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        depth += 1
        let name = XMLText.localName(elementName)
        if name == "osis" { sawOSISRoot = true }
        if name == "osisText", let language = attributes["xml:lang"], collector.language == nil {
            collector.language = language
        }
        if skipDepth > 0 {
            skipDepth += 1
            return
        }
        if name == "work", workDepth == nil, collector.name == nil {
            workDepth = depth
            return
        }
        if workDepth != nil {
            if name == "title" || name == "language" {
                headerField = name
                headerText = ""
            }
            return
        }
        if Self.breakElements.contains(name) { append(" ") }
        switch name {
        case "div" where attributes["type"] == "book":
            flushVerse()
            let code = attributes["osisID"] ?? ""
            book = BibleBookCodes.osis(osisID: code)
            if book == nil { collector.noteUnknownBook(code) }
            bookDepth = depth
            chapter = 0
        case "chapter":
            if attributes["eID"] != nil { return }
            flushVerse()
            if let ref = BibleCollector.parseOSISRef(attributes["osisID"] ?? attributes["sID"] ?? "") {
                chapter = ref.chapter
            }
        case "verse":
            startVerse(attributes)
        case "title" where book != nil && chapter == 0 && bookTitleDepth == nil:
            bookTitleDepth = depth
            bookTitle = ""
            skipDepth = 1
        default:
            if Self.skippedElements.contains(name) { skipDepth = 1 }
        }
    }

    private func startVerse(_ attributes: [String: String]) {
        if attributes["eID"] != nil {
            flushVerse()
            return
        }
        guard let id = attributes["osisID"] ?? attributes["sID"] else { return }
        flushVerse()
        guard let ref = BibleCollector.parseOSISRef(id), let number = ref.verse else { return }
        guard let osis = BibleBookCodes.osis(osisID: ref.book) else {
            collector.noteUnknownBook(ref.book)
            return
        }
        if ref.isRange { collector.noteBridge(id) }
        verse = (osis, ref.chapter, number)
        verseDepth = attributes["sID"] == nil ? depth : nil
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        defer { depth -= 1 }
        let name = XMLText.localName(elementName)
        if let titleDepth = bookTitleDepth, titleDepth == depth {
            if let book { collector.setBookName(bookTitle, for: book) }
            bookTitleDepth = nil
        }
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }
        if let work = workDepth {
            if depth == work {
                workDepth = nil
            } else if name == headerField {
                let value = XMLText.collapseWhitespace(headerText)
                if name == "title", collector.name == nil, !value.isEmpty { collector.name = value }
                if name == "language", collector.language == nil, !value.isEmpty { collector.language = value }
                headerField = nil
            }
            return
        }
        if Self.breakElements.contains(name) { append(" ") }
        if let verseDepth, verseDepth == depth {
            flushVerse()
        }
        if name == "chapter" || (name == "div" && depth == bookDepth) {
            flushVerse()
        }
        if name == "div" && depth == bookDepth {
            book = nil
            bookDepth = 0
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if bookTitleDepth != nil {
            bookTitle += string
        }
        if workDepth != nil {
            if headerField != nil { headerText += string }
            return
        }
        guard skipDepth == 0 else { return }
        append(string)
    }

    private func append(_ text: String) {
        if verse != nil { buffer += text }
    }

    func flushVerse() {
        if let verse {
            collector.add(book: verse.book, chapter: verse.chapter, verse: verse.verse, text: buffer)
        }
        verse = nil
        verseDepth = nil
        buffer = ""
    }
}

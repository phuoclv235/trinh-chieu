import Foundation
import Scripture

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Bộ nhập Kinh Thánh dạng Zefania XML (`XMLBIBLE`). Sách đánh số 1 đến 66 theo `BIBLEBOOK@bnumber`. Bỏ `NOTE`,
/// `XREF`, `CAPTION` (tiêu đề đoạn), `MEDIA`, `REMARK`; giữ chữ trong `gr` (Strong), `STYLE`, `SUP`.
public struct ZefaniaImporter: BibleImporter {
    public static let displayName = "Zefania XML"
    public static let fileExtensions = ["xml"]

    public init() {}

    public static func canImport(_ data: Data, filename: String) -> Bool {
        guard !data.isEmpty, !TextDecoding.looksBinary(data), TextDecoding.looksLikeXML(data) else { return false }
        let head = TextDecoding.decode(data.prefix(4096)).text.lowercased()
        return head.contains("<xmlbible")
    }

    public func importBible(from data: Data, filename: String) throws -> BibleImportOutcome {
        let handler = ZefaniaHandler(collector: BibleCollector(filename: filename))
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        guard parser.parse() else { throw XMLText.parseError(parser, filename: filename) }
        guard handler.isComplete else { throw XMLText.truncatedError(parser, filename: filename) }
        handler.flushVerse()
        guard handler.sawRoot else {
            throw ImportError.invalidContent(filename: filename, reason: "phần tử gốc không phải <XMLBIBLE>.")
        }
        return try handler.collector.finish()
    }
}

/// Xử lý sự kiện XML của tệp Zefania theo luồng. Tên phần tử so không phân biệt hoa thường.
private final class ZefaniaHandler: NSObject, XMLParserDelegate {
    var collector: BibleCollector
    private(set) var sawRoot = false

    private var skipDepth = 0
    private var depth = 0
    /// Mọi phần tử đã mở đều đã đóng.
    var isComplete: Bool { depth == 0 }
    private var inInformation = false
    private var informationField: String?
    private var informationText = ""
    private var book: String?
    private var chapter = 0
    private var verse: Int?
    private var buffer = ""

    static let skippedElements: Set<String> = ["NOTE", "XREF", "CAPTION", "MEDIA", "REMARK", "PROLOG"]

    init(collector: BibleCollector) {
        self.collector = collector
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        let name = XMLText.localName(elementName).uppercased()
        depth += 1
        if skipDepth > 0 {
            skipDepth += 1
            return
        }
        switch name {
        case "XMLBIBLE":
            sawRoot = true
            if let title = attributes["biblename"], !title.isEmpty, collector.name == nil {
                collector.name = XMLText.collapseWhitespace(title)
            }
        case "INFORMATION":
            inInformation = true
        case "TITLE" where inInformation, "LANGUAGE" where inInformation:
            informationField = name
            informationText = ""
        case "BIBLEBOOK":
            flushVerse()
            chapter = 0
            let number = Int(attributes["bnumber"] ?? "") ?? 0
            book = BibleBookCodes.osis(ordinal: number)
            if let book {
                if let name = attributes["bname"] { collector.setBookName(name, for: book) }
            } else {
                collector.noteUnknownBook(attributes["bname"] ?? "số \(number)")
            }
        case "CHAPTER":
            flushVerse()
            chapter = Int(attributes["cnumber"] ?? "") ?? 0
        case "VERS":
            flushVerse()
            verse = Int((attributes["vnumber"] ?? "").prefix { $0.isNumber })
            if let book, let range = attributes["vnumber"], range.contains("-") {
                collector.noteBridge("\(book) \(chapter):\(range)")
            }
        case "BR":
            append(" ")
        default:
            if Self.skippedElements.contains(name) { skipDepth = 1 }
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        let name = XMLText.localName(elementName).uppercased()
        depth -= 1
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }
        switch name {
        case "INFORMATION":
            inInformation = false
        case "TITLE", "LANGUAGE":
            guard inInformation, informationField == name else { return }
            let value = XMLText.collapseWhitespace(informationText)
            if name == "TITLE", !value.isEmpty { collector.name = value }
            if name == "LANGUAGE", !value.isEmpty, collector.language == nil { collector.language = value }
            informationField = nil
        case "VERS", "CHAPTER", "BIBLEBOOK":
            flushVerse()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if informationField != nil {
            informationText += string
            return
        }
        guard skipDepth == 0 else { return }
        append(string)
    }

    private func append(_ text: String) {
        if verse != nil { buffer += text }
    }

    func flushVerse() {
        if let book, let verse {
            collector.add(book: book, chapter: chapter, verse: verse, text: buffer)
        }
        verse = nil
        buffer = ""
    }
}

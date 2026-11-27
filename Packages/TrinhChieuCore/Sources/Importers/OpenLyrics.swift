import CoreModel
import Foundation
import VietText

/// Bộ nhập bài hát OpenLyrics 0.9 (XML).
///
/// Ánh xạ: `title` đầu tiên → tiêu đề; `authors`; `copyright`; `ccliNo`; `key`; `tempo` (bpm);
/// `songbooks/songbook` đầu tiên: `@entry` → số bài, `@name` → tập thánh ca; mỗi `verse` một đoạn, nhãn theo
/// `@name` (`v1`, `c`, `b`, `p`, `e`, `i`, `t`, `o-<tên>`); mỗi `lines` một trang, `<br/>` là xuống dòng;
/// `verseOrder` → thứ tự hát. Hợp âm bị bỏ, có một cảnh báo mỗi tệp.
public struct OpenLyricsImporter: DocumentImporter {
    public static let displayName = "OpenLyrics"
    public static let fileExtensions = ["xml"]

    /// Ngày giờ gán cho bộ trình chiếu mới; test đặt cố định.
    public var now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// XML có phần tử `<song` và nhắc tới OpenLyrics (không gian tên hoặc thuộc tính `version`).
    public static func canImport(_ data: Data, filename: String) -> Bool {
        guard !data.isEmpty, !TextDecoding.looksBinary(data), TextDecoding.looksLikeXML(data) else { return false }
        let head = TextDecoding.decode(data.prefix(4096)).text.lowercased()
        return head.contains("<song") && (head.contains("openlyrics") || head.contains("<lyrics"))
    }

    public func importDocuments(from data: Data, filename: String) throws -> ImportOutcome {
        let root = try XMLTreeNode.parse(data, filename: filename)
        guard root.name == "song" else {
            let reason = "phần tử gốc không phải <song> của OpenLyrics."
            throw ImportError.invalidContent(filename: filename, reason: reason)
        }
        var warnings: [ImportWarning] = []
        func warn(_ message: String, at location: String? = nil) {
            warnings.append(ImportWarning(filename: filename, location: location, message: message))
        }

        let properties = root.first("properties")
        let song = Self.songInfo(from: properties)
        let title = properties?.first("titles")?.elements("title").first?.text ?? ""

        // Đoạn.
        var groups: [SlideGroup] = []
        var groupByName: [String: UUID] = [:]
        var sawChords = false
        var skippedLanguages = false
        for verse in root.first("lyrics")?.elements("verse") ?? [] {
            let rawName = verse.attributes["name"]?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = rawName.isEmpty ? "v\(groups.count + 1)" : rawName
            if groupByName[name.lowercased()] != nil {
                if verse.attributes["lang"] != nil {
                    skippedLanguages = true
                } else {
                    warn("Đoạn “\(name)” xuất hiện hai lần; Hệ thống giữ lần đầu.", at: "đoạn \(name)")
                }
                continue
            }
            var slides: [Slide] = []
            for lines in verse.elements("lines") {
                let text = Self.linesText(lines, sawChords: &sawChords)
                slides.append(Slide(elements: [.text(TextElement(slot: .body, text: text))]))
            }
            if slides.isEmpty {
                slides.append(Slide(elements: [.text(TextElement(slot: .body, text: ""))]))
            }
            let group = SlideGroup(label: Self.label(forVerseName: name), slides: slides)
            groups.append(group)
            groupByName[name.lowercased()] = group.id
        }
        guard !groups.isEmpty else { throw ImportError.empty(filename: filename) }
        if sawChords {
            warn("Tệp có hợp âm; Hệ thống bỏ qua hợp âm khi nhập.")
        }
        if skippedLanguages {
            warn("Tệp có lời nhiều ngôn ngữ; Hệ thống chỉ nhập lời của ngôn ngữ xuất hiện đầu tiên.")
        }

        // Thứ tự hát.
        var order: [UUID] = []
        let orderText = XMLText.collapseWhitespace(properties?.first("verseOrder")?.text ?? "")
        for name in orderText.split(separator: " ").map(String.init) {
            if let id = groupByName[name.lowercased()] {
                order.append(id)
            } else {
                let message = "Thứ tự hát nhắc tới đoạn “\(name)” không có trong bài; Hệ thống bỏ qua tên này."
                warn(message, at: "verseOrder")
            }
        }
        if order.isEmpty { order = groups.map(\.id) }
        let arrangement = Arrangement(name: "Mặc định", groupIDs: order)

        let date = now()
        let presentation = Presentation(
            kind: .song, title: title.isEmpty ? filename.deletingFileExtension : title, createdAt: date,
            modifiedAt: date, song: song, groups: groups, arrangements: [arrangement],
            activeArrangementID: arrangement.id
        )
        return ImportOutcome(presentations: [presentation], warnings: warnings)
    }

    // MARK: - Nội bộ

    static func songInfo(from properties: XMLTreeNode?) -> SongInfo {
        var info = SongInfo()
        guard let properties else { return info }
        var authors: [String] = []
        for author in properties.first("authors")?.elements("author") ?? [] {
            let name = author.text
            if !name.isEmpty, !authors.contains(name) { authors.append(name) }
        }
        info.authors = authors
        info.copyright = nonEmpty(properties.first("copyright")?.text)
        info.ccli = nonEmpty(properties.first("ccliNo")?.text)
        info.key = nonEmpty(properties.first("key")?.text)
        if let tempo = properties.first("tempo"), (tempo.attributes["type"] ?? "bpm") == "bpm" {
            info.tempo = Int(tempo.text)
        }
        if let songbook = properties.first("songbooks")?.elements("songbook").first {
            info.hymnal = nonEmpty(songbook.attributes["name"])
            info.number = nonEmpty(songbook.attributes["entry"])
        }
        return info
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = XMLText.collapseWhitespace(text)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Chữ của một `<lines>`: `<br/>` là xuống dòng, khoảng trắng khác gộp lại, bỏ hợp âm, chú thích.
    static func linesText(_ node: XMLTreeNode, sawChords: inout Bool) -> String {
        var raw = ""
        appendText(of: node, to: &raw, sawChords: &sawChords)
        let lines = raw.components(separatedBy: "\n").map(XMLText.collapseWhitespace).filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private static func appendText(of node: XMLTreeNode, to raw: inout String, sawChords: inout Bool) {
        for child in node.children {
            switch child {
            case .text(let text):
                // Xuống dòng trong tệp chỉ là định dạng XML; dòng thật đánh dấu bằng <br/>.
                raw += text.replacingOccurrences(of: "\n", with: " ")
            case .element(let element):
                switch element.name {
                case "br":
                    raw += "\n"
                case "comment":
                    continue
                case "chord":
                    sawChords = true
                    appendText(of: element, to: &raw, sawChords: &sawChords)
                default:
                    appendText(of: element, to: &raw, sawChords: &sawChords)
                }
            }
        }
    }

    /// Nhãn đoạn từ tên OpenLyrics: chữ cái đầu là loại (`v`, `c`, `p`, `b`, `e`, `i`, `t`), số liền sau chữ là số
    /// đoạn, phần đuôi (`v1a`) bị bỏ. `o-<tên>` là nhãn tự đặt (dấu gạch dưới thành dấu cách). Tên khác là nhãn tự
    /// đặt giữ nguyên.
    static func label(forVerseName name: String) -> GroupLabel {
        let lower = name.lowercased()
        if lower.hasPrefix("o-") {
            let custom = String(name.dropFirst(2)).replacingOccurrences(of: "_", with: " ")
            return GroupLabel(kind: .custom, custom: custom)
        }
        let letters = lower.prefix { $0.isLetter }
        let digits = lower.dropFirst(letters.count).prefix { $0.isASCII && $0.isNumber }
        let number = Int(digits)
        switch letters.first {
        case "v":
            return GroupLabel(kind: .verse, number: number)
        case "c":
            return GroupLabel(kind: .chorus, number: number)
        case "p":
            return GroupLabel(kind: .prechorus, number: number)
        case "b":
            return GroupLabel(kind: .bridge, number: number)
        case "e":
            return GroupLabel(kind: .ending, number: number)
        case "i":
            return GroupLabel(kind: .intro, number: number)
        case "t":
            return GroupLabel(kind: .tag, number: number)
        default:
            return GroupLabel(kind: .custom, custom: name)
        }
    }
}

/// Xuất bộ trình chiếu ra OpenLyrics 0.9. Nhập lại tệp vừa xuất bằng ``OpenLyricsImporter`` cho ra cùng tiêu đề,
/// thông tin bài hát, nhãn và chữ các trang, thứ tự hát đang chọn.
public enum OpenLyricsExporter {
    public static let namespace = "http://openlyrics.info/namespace/2009/song"

    /// Dữ liệu XML UTF-8.
    public static func export(_ presentation: Presentation, modifiedDate: Date = Date()) -> Data {
        Data(exportString(presentation, modifiedDate: modifiedDate).utf8)
    }

    public static func exportString(_ presentation: Presentation, modifiedDate: Date = Date()) -> String {
        let names = verseNames(for: presentation.groups)
        let song = presentation.song ?? SongInfo()
        let e = XMLText.escape
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<song xmlns=\"\(namespace)\" version=\"0.9\" createdIn=\"TrinhChieu\" modifiedIn=\"TrinhChieu\""
        xml += " modifiedDate=\"\(modifiedDate.ISO8601Format())\">\n"
        xml += "  <properties>\n"
        xml += "    <titles>\n      <title>\(e(presentation.title))</title>\n    </titles>\n"
        if !song.authors.isEmpty {
            xml += "    <authors>\n"
            for author in song.authors {
                xml += "      <author>\(e(author))</author>\n"
            }
            xml += "    </authors>\n"
        }
        if let copyright = song.copyright {
            xml += "    <copyright>\(e(copyright))</copyright>\n"
        }
        if let ccli = song.ccli {
            xml += "    <ccliNo>\(e(ccli))</ccliNo>\n"
        }
        if let tempo = song.tempo {
            xml += "    <tempo type=\"bpm\">\(tempo)</tempo>\n"
        }
        if let key = song.key {
            xml += "    <key>\(e(key))</key>\n"
        }
        let order = presentation.orderedGroups().compactMap { names[$0.id] }
        if !order.isEmpty {
            xml += "    <verseOrder>\(e(order.joined(separator: " ")))</verseOrder>\n"
        }
        if song.number != nil || song.hymnal != nil {
            var songbook = "<songbook name=\"\(e(song.hymnal ?? ""))\""
            if let number = song.number { songbook += " entry=\"\(e(number))\"" }
            xml += "    <songbooks>\n      \(songbook)/>\n    </songbooks>\n"
        }
        xml += "  </properties>\n  <lyrics>\n"
        for group in presentation.groups {
            xml += "    <verse name=\"\(e(names[group.id] ?? "v"))\">\n"
            for slide in group.slides {
                let lines = LyricsText.slideText(slide).components(separatedBy: "\n").map(e)
                xml += "      <lines>\(lines.joined(separator: "<br/>"))</lines>\n"
            }
            xml += "    </verse>\n"
        }
        xml += "  </lyrics>\n</song>\n"
        return xml
    }

    /// Tên OpenLyrics không trùng cho từng đoạn: `v1`, `c`, `b2`, `o-Lời_dẫn`. Đoạn trùng nhãn được thêm chữ
    /// `b`, `c`... vào cuối (`v1`, `v1b`), nhập lại vẫn ra cùng nhãn.
    public static func verseNames(for groups: [SlideGroup]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var used: Set<String> = []
        for group in groups {
            let base = baseName(for: group.label)
            var name = base
            var suffix = UnicodeScalar("b").value
            while used.contains(name.lowercased()), let scalar = UnicodeScalar(suffix) {
                name = base + String(Character(scalar))
                suffix += 1
            }
            used.insert(name.lowercased())
            result[group.id] = name
        }
        return result
    }

    static func baseName(for label: GroupLabel) -> String {
        let number = label.number.map(String.init) ?? ""
        switch label.kind {
        case .verse:
            return "v" + number
        case .chorus:
            return "c" + number
        case .prechorus:
            return "p" + number
        case .bridge:
            return "b" + number
        case .ending:
            return "e" + number
        case .intro:
            return "i" + number
        case .tag:
            return "t" + number
        case .custom:
            let custom = XMLText.collapseWhitespace(label.custom ?? "").replacingOccurrences(of: " ", with: "_")
            return custom.isEmpty ? "o" : "o-" + custom
        }
    }
}

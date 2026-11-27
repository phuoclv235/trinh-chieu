import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// Cây XML nhỏ cho tệp vừa phải (OpenLyrics). Tệp lớn như cả bộ Kinh Thánh dùng bộ phân tích theo luồng riêng.
final class XMLTreeNode {
    /// Tên phần tử bỏ tiền tố không gian tên: `song`, `lines`.
    let name: String
    let attributes: [String: String]
    private(set) var children: [Child] = []

    enum Child {
        case element(XMLTreeNode)
        case text(String)
    }

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func append(_ child: Child) {
        children.append(child)
    }

    /// Phần tử con trực tiếp có tên `name`.
    func elements(_ name: String) -> [XMLTreeNode] {
        children.compactMap { child in
            if case .element(let node) = child, node.name == name { return node }
            return nil
        }
    }

    /// Phần tử con trực tiếp đầu tiên có tên `name`.
    func first(_ name: String) -> XMLTreeNode? {
        for child in children {
            if case .element(let node) = child, node.name == name { return node }
        }
        return nil
    }

    /// Toàn bộ chữ bên trong, khoảng trắng liên tiếp gộp làm một, bỏ khoảng trắng đầu cuối.
    var text: String {
        var parts: [String] = []
        collectText(into: &parts)
        return XMLText.collapseWhitespace(parts.joined())
    }

    private func collectText(into parts: inout [String]) {
        for child in children {
            switch child {
            case .text(let text):
                parts.append(text)
            case .element(let node):
                node.collectText(into: &parts)
            }
        }
    }

    /// Đọc dữ liệu XML thành cây. Lỗi cú pháp thành ``ImportError/invalidXML(filename:line:reason:)``.
    static func parse(_ data: Data, filename: String) throws -> XMLTreeNode {
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw XMLText.parseError(parser, filename: filename)
        }
        guard builder.isComplete else { throw XMLText.truncatedError(parser, filename: filename) }
        return root
    }
}

/// Tiện ích chung cho các bộ phân tích XML.
enum XMLText {
    /// Gộp mọi chuỗi khoảng trắng (kể cả xuống dòng) thành một dấu cách, bỏ khoảng trắng đầu cuối.
    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Bỏ tiền tố không gian tên: `osis:verse` → `verse`.
    static func localName(_ name: String) -> String {
        guard let colon = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: colon)...])
    }

    /// Lỗi tiếng Việt cho lần phân tích thất bại.
    static func parseError(_ parser: XMLParser, filename: String) -> ImportError {
        let line = parser.lineNumber > 0 ? parser.lineNumber : nil
        if let error = parser.parserError {
            let code = (error as NSError).code
            return .invalidXML(filename: filename, line: line, reason: "cấu trúc XML không hợp lệ (mã lỗi \(code)).")
        }
        return .invalidXML(filename: filename, line: line, reason: "tệp không có phần tử gốc.")
    }

    /// Lỗi cho tệp bị cắt dở: bộ phân tích tới cuối tệp mà còn phần tử chưa đóng (Foundation trên Linux không tự
    /// báo lỗi này).
    static func truncatedError(_ parser: XMLParser, filename: String) -> ImportError {
        let line = parser.lineNumber > 0 ? parser.lineNumber : nil
        return .invalidXML(filename: filename, line: line, reason: "tệp bị cắt dở, còn phần tử chưa đóng.")
    }

    /// Thoát ký tự đặc biệt cho chữ và giá trị thuộc tính XML.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&":
                out += "&amp;"
            case "<":
                out += "&lt;"
            case ">":
                out += "&gt;"
            case "\"":
                out += "&quot;"
            default:
                out.append(character)
            }
        }
        return out
    }
}

/// Dựng ``XMLTreeNode`` từ sự kiện của `XMLParser`.
private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    private(set) var root: XMLTreeNode?
    private var stack: [XMLTreeNode] = []

    /// Mọi phần tử đã mở đều đã đóng.
    var isComplete: Bool { stack.isEmpty }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLTreeNode(name: XMLText.localName(elementName), attributes: attributeDict)
        if let parent = stack.last {
            parent.append(.element(node))
        } else if root == nil {
            root = node
        }
        stack.append(node)
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.append(.text(string))
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            stack.last?.append(.text(string))
        }
    }
}

import CoreModel
import Foundation

/// Bộ nhập tệp văn bản lời bài hát (`.txt`). Cú pháp xem ``LyricsText``.
public struct PlainLyricsImporter: DocumentImporter {
    public static let displayName = "Văn bản lời bài hát"
    public static let fileExtensions = ["txt", "text"]

    /// Ngày giờ gán cho bộ trình chiếu mới; test đặt cố định.
    public var now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Nhận mọi tệp văn bản không phải XML và không phải tệp nhị phân. Đứng cuối danh sách bộ nhập.
    public static func canImport(_ data: Data, filename: String) -> Bool {
        !data.isEmpty && !TextDecoding.looksBinary(data) && !TextDecoding.looksLikeXML(data)
    }

    public func importDocuments(from data: Data, filename: String) throws -> ImportOutcome {
        guard !TextDecoding.looksBinary(data) else { throw ImportError.unsupportedFormat(filename: filename) }
        let (text, encoding) = TextDecoding.decode(data)
        let parsed = LyricsText.parse(text)
        guard !parsed.sections.isEmpty else { throw ImportError.empty(filename: filename) }

        var warnings: [ImportWarning] = []
        if encoding == .windows1258 {
            let message = "Tệp không phải UTF-8 hay UTF-16; Hệ thống đọc theo bảng mã Windows-1258."
            warnings.append(ImportWarning(filename: filename, message: message))
        }
        for issue in parsed.issues {
            let location = issue.line.map { "dòng \($0)" }
            warnings.append(ImportWarning(filename: filename, location: location, message: issue.message))
        }
        let presentation = parsed.makePresentation(fallbackTitle: filename.deletingFileExtension, now: now())
        return ImportOutcome(presentations: [presentation], warnings: warnings)
    }
}

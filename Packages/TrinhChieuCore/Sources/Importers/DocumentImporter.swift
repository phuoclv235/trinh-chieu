import CoreModel
import Foundation

/// Bộ nhập một định dạng tài liệu (lời bài hát, OpenLyrics) thành bộ trình chiếu.
public protocol DocumentImporter: Sendable {
    /// Tên định dạng hiện trên giao diện: "OpenLyrics", "Văn bản lời bài hát".
    static var displayName: String { get }
    /// Đuôi tệp thường gặp, chữ thường, không có dấu chấm.
    static var fileExtensions: [String] { get }
    /// Dò nội dung, không chỉ dựa vào đuôi tệp.
    static func canImport(_ data: Data, filename: String) -> Bool
    /// Nhập một tệp. Tệp hỏng thì ném ``ImportError`` có tên tệp, không bao giờ làm ứng dụng dừng.
    func importDocuments(from data: Data, filename: String) throws -> ImportOutcome
}

/// Kết quả nhập một tệp.
public struct ImportOutcome: Sendable {
    public var presentations: [Presentation]
    /// Cảnh báo tiếng Việt, có tên tệp và vị trí.
    public var warnings: [ImportWarning]

    public init(presentations: [Presentation], warnings: [ImportWarning] = []) {
        self.presentations = presentations
        self.warnings = warnings
    }
}

/// Một cảnh báo khi nhập: tệp vẫn nhập được nhưng có chỗ Hệ thống phải bỏ qua hoặc đoán.
public struct ImportWarning: Sendable, Hashable, CustomStringConvertible {
    public var filename: String
    /// Vị trí trong tệp: "dòng 12", "đoạn v2", "Giăng 3:16". `nil` khi cảnh báo áp cho cả tệp.
    public var location: String?
    public var message: String

    public init(filename: String, location: String? = nil, message: String) {
        self.filename = filename
        self.location = location
        self.message = message
    }

    /// "bai-hat.txt, dòng 12: Trang 2 của Câu 1 có 6 dòng, ...".
    public var description: String {
        if let location { return "\(filename), \(location): \(message)" }
        return "\(filename): \(message)"
    }
}

/// Lỗi nhập một tệp. Thông báo tiếng Việt luôn có tên tệp.
public enum ImportError: Error, Sendable, Hashable, LocalizedError, CustomStringConvertible {
    /// Không đọc được tệp từ đĩa.
    case unreadable(filename: String, reason: String)
    /// Không có bộ nhập nào nhận nội dung này.
    case unsupportedFormat(filename: String)
    /// Tệp rỗng hoặc không có nội dung dùng được.
    case empty(filename: String)
    /// XML hỏng.
    case invalidXML(filename: String, line: Int?, reason: String)
    /// Đúng định dạng nhưng nội dung sai quy cách.
    case invalidContent(filename: String, reason: String)

    public var filename: String {
        switch self {
        case .unreadable(let filename, _), .unsupportedFormat(let filename), .empty(let filename),
            .invalidXML(let filename, _, _), .invalidContent(let filename, _):
            return filename
        }
    }

    public var message: String {
        switch self {
        case .unreadable(let filename, let reason):
            return "Hệ thống không đọc được tệp \(filename): \(reason)"
        case .unsupportedFormat(let filename):
            return "Hệ thống chưa nhận dạng được định dạng của tệp \(filename)."
        case .empty(let filename):
            return "Tệp \(filename) không có nội dung để nhập."
        case .invalidXML(let filename, let line, let reason):
            if let line { return "Tệp \(filename) bị hỏng ở dòng \(line): \(reason)" }
            return "Tệp \(filename) bị hỏng: \(reason)"
        case .invalidContent(let filename, let reason):
            return "Tệp \(filename) không đúng quy cách: \(reason)"
        }
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}

/// Danh sách bộ nhập tài liệu, chọn bộ nhập theo nội dung tệp.
public struct ImportRegistry: Sendable {
    /// Thứ tự là thứ tự ưu tiên: bộ nhập đứng trước được hỏi trước.
    public var importers: [any DocumentImporter]

    public init(importers: [any DocumentImporter]) {
        self.importers = importers
    }

    /// Bộ nhập mặc định: OpenLyrics trước (XML có dấu hiệu rõ), văn bản lời bài hát sau cùng.
    public static let standard = ImportRegistry(importers: [OpenLyricsImporter(), PlainLyricsImporter()])

    /// Bộ nhập đầu tiên nhận nội dung này, `nil` khi không bộ nào nhận.
    public func importer(for data: Data, filename: String) -> (any DocumentImporter)? {
        importers.first { type(of: $0).canImport(data, filename: filename) }
    }

    /// Nhập một tệp đã đọc vào bộ nhớ.
    public func importDocuments(from data: Data, filename: String) throws -> ImportOutcome {
        guard !data.isEmpty else { throw ImportError.empty(filename: filename) }
        guard let importer = importer(for: data, filename: filename) else {
            throw ImportError.unsupportedFormat(filename: filename)
        }
        return try importer.importDocuments(from: data, filename: filename)
    }

    /// Nhập nhiều tệp song song, mỗi tệp một kết quả theo đúng thứ tự `urls`; tệp lỗi không chặn tệp khác.
    public func importFiles(at urls: [URL]) async -> ImportReport {
        let registry = self
        let results = await withTaskGroup(of: (Int, ImportFileResult).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    (index, registry.importFile(at: url))
                }
            }
            var collected: [(Int, ImportFileResult)] = []
            for await item in group {
                collected.append(item)
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return ImportReport(files: results)
    }

    func importFile(at url: URL) -> ImportFileResult {
        let filename = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let reason = (error as NSError).localizedDescription
            let failure = ImportError.unreadable(filename: filename, reason: reason)
            return ImportFileResult(filename: filename, result: .failure(failure))
        }
        do {
            let outcome = try importDocuments(from: data, filename: filename)
            return ImportFileResult(filename: filename, result: .success(outcome))
        } catch let error as ImportError {
            return ImportFileResult(filename: filename, result: .failure(error))
        } catch {
            let wrapped = ImportError.invalidContent(filename: filename, reason: "\(error)")
            return ImportFileResult(filename: filename, result: .failure(wrapped))
        }
    }
}

/// Kết quả nhập một tệp trong một lần nhập nhiều tệp.
public struct ImportFileResult: Sendable {
    public var filename: String
    public var result: Result<ImportOutcome, ImportError>

    public init(filename: String, result: Result<ImportOutcome, ImportError>) {
        self.filename = filename
        self.result = result
    }

    public var isSuccess: Bool {
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

/// Báo cáo cuối của một lần nhập nhiều tệp.
public struct ImportReport: Sendable {
    /// Theo đúng thứ tự tệp đưa vào.
    public var files: [ImportFileResult]

    public init(files: [ImportFileResult]) {
        self.files = files
    }

    /// Mọi bộ trình chiếu nhập được, theo thứ tự tệp.
    public var presentations: [Presentation] {
        files.flatMap { file -> [Presentation] in
            if case .success(let outcome) = file.result { return outcome.presentations }
            return []
        }
    }

    /// Số tệp nhập thành công.
    public var successCount: Int {
        files.filter(\.isSuccess).count
    }

    /// Mọi cảnh báo của các tệp thành công.
    public var warnings: [ImportWarning] {
        files.flatMap { file -> [ImportWarning] in
            if case .success(let outcome) = file.result { return outcome.warnings }
            return []
        }
    }

    /// Lỗi theo tệp.
    public var failures: [ImportError] {
        files.compactMap { file -> ImportError? in
            if case .failure(let error) = file.result { return error }
            return nil
        }
    }

    /// Tóm tắt một dòng: "Đã nhập 8/10 tệp, 3 cảnh báo, 2 tệp lỗi."
    public var summary: String {
        var text = "Đã nhập \(successCount)/\(files.count) tệp"
        text += warnings.isEmpty ? ", không có cảnh báo" : ", \(warnings.count) cảnh báo"
        text += failures.isEmpty ? "." : ", \(failures.count) tệp lỗi."
        return text
    }
}

extension String {
    /// Tên tệp bỏ đuôi: "Chúa Là Đá.txt" → "Chúa Là Đá".
    var deletingFileExtension: String {
        guard let dot = lastIndex(of: "."), dot != startIndex else { return self }
        return String(self[..<dot])
    }

    /// Đuôi tệp chữ thường, không có dấu chấm.
    var lowercasedFileExtension: String {
        guard let dot = lastIndex(of: "."), dot != startIndex else { return "" }
        return String(self[index(after: dot)...]).lowercased()
    }
}

import CoreModel
import Foundation
import Synchronization

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Đường dẫn trong thư mục thư viện (`docs/dinh-dang-tep.md` mục 1). Mọi tên tệp chỉ dùng ASCII.
struct LibraryLayout: Sendable {
    static let libraryFileName = "library.json"
    static let mediaDirectory = "media"
    static let logsDirectory = "logs"
    static let biblesDirectory = "bibles"
    static let trashDirectory = ".trash"
    static let cacheDirectory = ".cache"
    static let cachedMediaDirectory = ".cache/media"
    static let indexPath = ".cache/index.sqlite"

    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    /// Thư mục tạo sẵn khi mở thư viện.
    var requiredDirectories: [String] {
        LibraryDocumentKind.allCases.map(\.directoryName) + [
            Self.mediaDirectory, Self.logsDirectory, Self.biblesDirectory, Self.trashDirectory, Self.cacheDirectory,
        ]
    }

    static func documentPath(_ kind: LibraryDocumentKind, _ id: UUID) -> String {
        "\(kind.directoryName)/\(id.uuidString).json"
    }

    static func mediaInfoPath(_ id: MediaID) -> String {
        "\(mediaDirectory)/\(id.rawValue).json"
    }

    static func mediaFilePath(_ id: MediaID, fileExtension: String) -> String {
        "\(mediaDirectory)/\(id.rawValue).\(fileExtension)"
    }

    static func cachedMediaPath(_ id: MediaID, fileExtension: String) -> String {
        "\(cachedMediaDirectory)/\(id.rawValue).\(fileExtension)"
    }

    static func biblePath(translation code: String) -> String {
        "\(biblesDirectory)/\(code).sqlite"
    }

    /// Mã UUID nếu tên tệp đúng dạng `<uuid>.json`.
    static func documentID(fileName: String) -> UUID? {
        guard fileName.hasSuffix(".json") else { return nil }
        return UUID(uuidString: String(fileName.dropLast(5)))
    }

    /// Mã media nếu tên tệp đúng dạng `<mã media>.json`.
    static func mediaID(infoFileName fileName: String) -> MediaID? {
        guard fileName.hasSuffix(".json") else { return nil }
        let raw = String(fileName.dropLast(5))
        return isValidMediaID(raw) ? MediaID(raw) : nil
    }

    /// Mã media hợp lệ: 12 ký tự hex thường (media chép), hoặc `l-` + 10 ký tự hex thường (media liên kết).
    static func isValidMediaID(_ raw: String) -> Bool {
        let hexDigits = Set("0123456789abcdef")
        if raw.hasPrefix("l-") {
            let rest = raw.dropFirst(2)
            return rest.count == 10 && rest.allSatisfy { hexDigits.contains($0) }
        }
        return raw.count == 12 && raw.allSatisfy { hexDigits.contains($0) }
    }

    /// Phần mở rộng an toàn để đặt tên tệp: chữ và số ASCII, tối đa 10 ký tự.
    static func isValidFileExtension(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 10 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Mã bản dịch an toàn để đặt tên tệp.
    static func isValidTranslationCode(_ code: String) -> Bool {
        !code.isEmpty && code.count <= 32
            && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// Mốc thời gian trong tên tệp (`.trash/`, `.conflict-`): `yyyyMMdd'T'HHmmss'Z'` theo UTC, chỉ ASCII.
enum FileTimestamp {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func string(from date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let datePart = pad(parts.year, 4) + pad(parts.month, 2) + pad(parts.day, 2)
        let timePart = pad(parts.hour, 2) + pad(parts.minute, 2) + pad(parts.second, 2)
        return datePart + "T" + timePart + "Z"
    }

    static func date(from string: String) -> Date? {
        let characters = Array(string)
        guard characters.count == 16, characters[8] == "T", characters[15] == "Z" else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            Int(String(characters[range]))
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8),
            let hour = number(9..<11), let minute = number(11..<13), let second = number(13..<15)
        else { return nil }
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: parts)
    }

    /// Ngày theo lịch ở múi giờ cho trước, dạng `yyyy-MM-dd`.
    static func day(from date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return pad(parts.year, 4) + "-" + pad(parts.month, 2) + "-" + pad(parts.day, 2)
    }

    private static func pad(_ value: Int?, _ width: Int) -> String {
        let text = String(value ?? 0)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

extension Date {
    /// Bỏ phần lẻ giây, để ngày ghi ra tệp rồi đọc lại so bằng nhau chính xác.
    var wholeSeconds: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}

/// Dấu vân tay nội dung tệp trong phiên chạy: phân biệt tệp do Hệ thống ghi với tệp đổi ngoài Hệ thống.
struct FileFingerprint: Sendable, Hashable {
    let byteCount: Int
    let hash: Int

    init(_ data: Data) {
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.combine(bytes: $0) }
        byteCount = data.count
        hash = hasher.finalize()
    }
}

/// Ghi tệp nguyên tử: ghi `<tên>.tmp`, đồng bộ xuống đĩa, rồi đổi tên đè lên tệp đích.
enum AtomicFile {
    static func temporaryURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".tmp")
    }

    static func write(_ data: Data, to url: URL) throws {
        let temporary = temporaryURL(for: url)
        let manager = FileManager.default
        try? manager.removeItem(at: temporary)
        guard manager.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
        do {
            try rename(temporary, to: url)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    /// Đổi tên bằng `rename(2)`: nguyên tử, đè tệp đích nếu có.
    static func rename(_ source: URL, to destination: URL) throws {
        guard posixRename(source.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

private func posixRename(_ source: String, _ destination: String) -> Int32 {
    rename(source, destination)
}

/// Khoá ghi theo đường dẫn. Mỗi lần ghi giữ một số thế hệ; lần ghi cũ hơn thế hệ hiện tại bị bỏ, nên thứ tự
/// ghi trên đĩa luôn theo thứ tự lưu trong bộ nhớ dù các lần ghi chạy song song ngoài luồng chính. Xoá và khôi
/// phục cũng đi qua khoá này để không có lần ghi nào dựng lại tệp vừa chuyển vào thùng rác.
final class WriteGate: Sendable {
    private let generations = Mutex<[String: UInt64]>([:])

    /// Cấp thế hệ mới cho đường dẫn; mọi lần ghi đã cấp trước đó trở thành cũ.
    func reserve(_ path: String) -> UInt64 {
        generations.withLock { state in
            let next = (state[path] ?? 0) &+ 1
            state[path] = next
            return next
        }
    }

    /// Chạy `body` trong khoá nếu `generation` còn là thế hệ mới nhất. Trả `false` nếu đã bị lần ghi mới hơn thay.
    func perform(_ path: String, generation: UInt64, _ body: () throws -> Void) throws -> Bool {
        try generations.withLock { state in
            guard state[path] == generation else { return false }
            try body()
            return true
        }
    }

    /// Làm cũ mọi lần ghi đang chờ của đường dẫn rồi chạy `body` trong khoá.
    func invalidate(_ path: String, _ body: () throws -> Void) throws {
        try generations.withLock { state in
            state[path] = (state[path] ?? 0) &+ 1
            try body()
        }
    }
}

/// Tài liệu có trường `schemaVersion`.
protocol VersionedDocument: Codable, Sendable {
    var schemaVersion: Int { get }
}

extension Presentation: VersionedDocument {}
extension Theme: VersionedDocument {}
extension ServicePlan: VersionedDocument {}
extension MediaAssetInfo: VersionedDocument {}
extension LibraryInfo: VersionedDocument {}
extension PortableBundleManifest: VersionedDocument {}

/// Kết quả giải mã một tệp tài liệu.
struct DecodedDocument<Value: VersionedDocument>: Sendable {
    var value: Value
    /// Dữ liệu ở định dạng hiện tại (khác dữ liệu gốc nếu đã chuyển đổi).
    var data: Data
    /// Phiên bản gốc nếu tệp vừa được chuyển đổi.
    var migratedFrom: Int?
}

enum DocumentDecoding {
    /// Giải mã nhanh: giải mã thẳng; chỉ khi `schemaVersion` khác phiên bản hiện tại hoặc giải mã lỗi mới chạy
    /// migration (phải phân tích JSON hai lần, chậm hơn).
    static func decode<Value: VersionedDocument>(
        _ type: Value.Type, from data: Data, kind: DocumentKind,
        migrate: @Sendable (Data, DocumentKind) throws -> (Data, migratedFrom: Int?)
    ) throws -> DecodedDocument<Value> {
        let decoder = DocumentCoding.makeDecoder()
        if let value = try? decoder.decode(type, from: data),
            value.schemaVersion == DocumentMigration.currentSchemaVersion
        {
            return DecodedDocument(value: value, data: data, migratedFrom: nil)
        }
        let (migrated, migratedFrom) = try migrate(data, kind)
        let value = try decoder.decode(type, from: migrated)
        return DecodedDocument(value: value, data: migrated, migratedFrom: migratedFrom)
    }

    /// Thông điệp tiếng Việt cho lỗi đọc tệp.
    static func problem(for error: any Error, relativePath: String, at date: Date) -> LoadProblem {
        if let documentError = error as? DocumentError {
            let kind: LoadProblem.Kind
            if case .newerSchema = documentError {
                kind = .newerSchema
            } else {
                kind = .unreadable
            }
            return LoadProblem(kind: kind, relativePath: relativePath, message: documentError.message, occurredAt: date)
        }
        let message = "Tệp \(relativePath) bị hỏng hoặc không đúng định dạng nên Hệ thống bỏ qua."
        return LoadProblem(kind: .unreadable, relativePath: relativePath, message: message, occurredAt: date)
    }
}

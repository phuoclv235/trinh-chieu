import Foundation

/// Loại tài liệu trong thư viện. Mỗi loại có chuỗi bước chuyển đổi riêng.
public enum DocumentKind: String, Sendable, Hashable, Codable, CaseIterable {
    case library
    case presentation
    case theme
    case plan
    case media
    case serviceLog
}

/// Chuyển đổi tài liệu từ định dạng cũ sang định dạng hiện tại.
public enum DocumentMigration {
    /// Phiên bản định dạng tệp hiện tại (`schemaVersion`).
    public static let currentSchemaVersion = 1

    /// Một bước chuyển đổi từ phiên bản `n` lên `n + 1`, làm việc trên cây JSON.
    typealias Step = @Sendable (inout [String: Any]) throws -> Void

    /// Các bước chuyển đổi theo loại tài liệu, khoá là phiên bản nguồn.
    /// Ví dụ khi có schema 2: `[.presentation: [1: { json in ... }]]`.
    static let steps: [DocumentKind: [Int: Step]] = [:]

    /// Kiểm và chuyển đổi dữ liệu JSON của một tài liệu.
    /// - Returns: dữ liệu ở định dạng hiện tại và phiên bản gốc nếu đã chuyển đổi (`nil` nếu không đổi gì).
    /// - Throws: `DocumentError.newerSchema` nếu tệp do phiên bản Hệ thống mới hơn tạo ra.
    public static func migrate(_ data: Data, kind: DocumentKind) throws -> (Data, migratedFrom: Int?) {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DocumentError.notAnObject
        }
        guard var object = json as? [String: Any] else {
            throw DocumentError.notAnObject
        }
        let version: Int
        if let raw = object["schemaVersion"] {
            guard let number = raw as? Int, number >= 1 else {
                throw DocumentError.invalidSchemaVersion
            }
            version = number
        } else {
            version = 1
        }
        if version > currentSchemaVersion {
            throw DocumentError.newerSchema(found: version, supported: currentSchemaVersion)
        }
        if version == currentSchemaVersion {
            return (data, migratedFrom: nil)
        }
        var current = version
        while current < currentSchemaVersion {
            if let step = steps[kind]?[current] {
                try step(&object)
            }
            current += 1
        }
        object["schemaVersion"] = currentSchemaVersion
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let migrated = try JSONSerialization.data(withJSONObject: object, options: options)
        return (migrated, migratedFrom: version)
    }
}

/// Kiểm và chuyển đổi dữ liệu JSON của một tài liệu lên định dạng hiện tại.
/// Xem `DocumentMigration.migrate(_:kind:)`.
public func migrate(_ data: Data, kind: DocumentKind) throws -> (Data, migratedFrom: Int?) {
    try DocumentMigration.migrate(data, kind: kind)
}

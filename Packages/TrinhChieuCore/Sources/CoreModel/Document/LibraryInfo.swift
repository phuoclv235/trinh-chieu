import Foundation

/// Thông tin thư viện (`library.json`).
public struct LibraryInfo: Sendable, Hashable, Codable, Identifiable {
    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    /// Mẫu mặc định cho bộ trình chiếu.
    public var defaultThemeID: UUID?
    /// Mẫu mặc định cho Kinh Thánh.
    public var defaultScriptureThemeID: UUID?

    public init(
        schemaVersion: Int = DocumentMigration.currentSchemaVersion, id: UUID = UUID(), createdAt: Date,
        defaultThemeID: UUID? = nil, defaultScriptureThemeID: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.defaultThemeID = defaultThemeID
        self.defaultScriptureThemeID = defaultScriptureThemeID
    }
}

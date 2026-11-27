import Foundation

/// Loại media.
public enum MediaKind: String, Sendable, Hashable, Codable, CaseIterable {
    case image
    case video
    case audio
}

/// Nguồn của media: chép vào thư viện hay liên kết tới NAS.
public enum MediaOriginKind: String, Sendable, Hashable, Codable, CaseIterable {
    case copied
    case linked
}

/// Nguồn của media. Với media liên kết, `url` là đường dẫn trực tiếp ổn định (với Slate là `/d/...`).
public struct MediaOrigin: Sendable, Hashable, Codable {
    public var kind: MediaOriginKind
    public var url: String?
    public var provider: String?
    public var etag: String?

    public init(kind: MediaOriginKind, url: String? = nil, provider: String? = nil, etag: String? = nil) {
        self.kind = kind
        self.url = url
        self.provider = provider
        self.etag = etag
    }

    public static let copied = MediaOrigin(kind: .copied)
}

/// Thông tin media (`media/<id>.json`).
public struct MediaAssetInfo: Sendable, Hashable, Codable, Identifiable {
    public var schemaVersion: Int
    public var id: MediaID
    public var kind: MediaKind
    /// Tên tệp gốc khi nhập.
    public var originalName: String
    /// Phần mở rộng của tệp trong `media/`, không có dấu chấm.
    public var fileExtension: String
    public var byteCount: Int?
    public var pixelSize: PixelSize?
    /// Thời lượng (giây) với video và âm thanh.
    public var duration: Double?
    public var tags: [String]
    public var importedAt: Date
    public var origin: MediaOrigin

    public init(
        schemaVersion: Int = DocumentMigration.currentSchemaVersion, id: MediaID, kind: MediaKind,
        originalName: String, fileExtension: String, byteCount: Int? = nil, pixelSize: PixelSize? = nil,
        duration: Double? = nil, tags: [String] = [], importedAt: Date, origin: MediaOrigin = .copied
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.originalName = originalName
        self.fileExtension = fileExtension
        self.byteCount = byteCount
        self.pixelSize = pixelSize
        self.duration = duration
        self.tags = tags
        self.importedAt = importedAt
        self.origin = origin
    }
}

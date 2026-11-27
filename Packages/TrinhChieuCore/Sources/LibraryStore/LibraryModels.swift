import CoreModel
import Foundation

/// Loại tài liệu có mã UUID, mỗi tài liệu một tệp JSON trong thư mục riêng.
public enum LibraryDocumentKind: String, Sendable, Hashable, Codable, CaseIterable {
    case presentation
    case theme
    case plan

    /// Thư mục chứa loại tài liệu này, tính từ gốc thư viện.
    public var directoryName: String {
        switch self {
        case .presentation:
            return "presentations"
        case .theme:
            return "themes"
        case .plan:
            return "plans"
        }
    }

    var documentKind: DocumentKind {
        switch self {
        case .presentation:
            return .presentation
        case .theme:
            return .theme
        case .plan:
            return .plan
        }
    }
}

/// Một vấn đề khi đọc hoặc ghi thư viện, hiện trên giao diện để bạn xử lý. Không chặn việc mở thư viện.
public struct LoadProblem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// Tệp hỏng hoặc không phải JSON của Hệ thống.
        case unreadable
        /// Tệp do phiên bản Hệ thống mới hơn tạo ra.
        case newerSchema
        /// Mã trong tệp không khớp tên tệp.
        case idMismatch
        /// Tệp đổi trên đĩa trong khi Hệ thống còn thay đổi chưa ghi; bản đĩa được giữ ở tệp `.conflict-...`.
        case syncConflict
        /// Hệ thống chưa ghi được tệp (đĩa đầy, không có quyền).
        case writeFailed
    }

    public var id: UUID
    public var kind: Kind
    /// Đường dẫn tính từ gốc thư viện, ví dụ `presentations/<uuid>.json`.
    public var relativePath: String
    /// Thông điệp tiếng Việt.
    public var message: String
    public var occurredAt: Date

    public init(id: UUID = UUID(), kind: Kind, relativePath: String, message: String, occurredAt: Date) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.message = message
        self.occurredAt = occurredAt
    }
}

/// Một thay đổi trong thư viện, phát qua ``LibraryStore/changes``.
public struct LibraryChange: Sendable, Hashable {
    public enum Reason: String, Sendable, Hashable, CaseIterable {
        /// Bạn lưu trong Hệ thống.
        case saved
        /// Chuyển vào thùng rác.
        case removed
        /// Khôi phục từ thùng rác.
        case restored
        /// Tệp đổi ngoài Hệ thống (iCloud Drive, Dropbox) và đã được nạp lại.
        case reloaded
        /// Tệp bị xoá ngoài Hệ thống.
        case removedExternally
        /// Nhập từ gói mang đi.
        case imported
        /// Thêm media.
        case mediaAdded
    }

    public var reason: Reason
    /// Mã các bộ trình chiếu, mẫu trình bày, chương trình bị ảnh hưởng.
    public var documentIDs: Set<UUID>
    public var mediaIDs: Set<MediaID>

    public init(reason: Reason, documentIDs: Set<UUID> = [], mediaIDs: Set<MediaID> = []) {
        self.reason = reason
        self.documentIDs = documentIDs
        self.mediaIDs = mediaIDs
    }
}

/// Phiếu xoá: đủ thông tin để ``LibraryStore/restore(_:)`` hoàn tác.
public struct TrashTicket: Sendable, Hashable {
    public struct Entry: Sendable, Hashable {
        public var id: UUID
        public var kind: LibraryDocumentKind
        /// Tên tệp trong `.trash/`.
        public var trashFileName: String
        public var deletedAt: Date
    }

    public var entries: [Entry]

    public var ids: [UUID] { entries.map(\.id) }
}

/// Cách xử lý khi tài liệu trong gói mang đi trùng mã với tài liệu trong thư viện mà nội dung khác.
public enum ConflictResolution: String, Sendable, Hashable, Codable, CaseIterable {
    /// Giữ cả hai: bản trong gói được nhập với mã mới, tên thêm "(bản sao)".
    case keepBoth
    /// Thay bản trong thư viện; bản cũ vào thùng rác.
    case replace
    /// Bỏ qua bản trong gói.
    case skip
}

/// Loại gói mang đi.
public enum PortableBundleKind: String, Sendable, Hashable, Codable, CaseIterable {
    case plan
    case presentation
}

/// `manifest.json` của gói mang đi (`docs/dinh-dang-tep.md` mục 7).
public struct PortableBundleManifest: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var kind: PortableBundleKind
    public var createdAt: Date
    /// Chương trình (gói `plan`) hoặc các bộ trình chiếu (gói `presentation`) được chọn khi xuất.
    public var rootIDs: [UUID]
    /// Đường dẫn các tệp trong gói, theo cấu trúc thư mục thư viện.
    public var files: [String]
    /// Mã các bản dịch Kinh Thánh chương trình dùng. Gói không chứa bản dịch.
    public var bibleTranslations: [String]

    public init(
        schemaVersion: Int = DocumentMigration.currentSchemaVersion, kind: PortableBundleKind, createdAt: Date,
        rootIDs: [UUID], files: [String], bibleTranslations: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.createdAt = createdAt
        self.rootIDs = rootIDs
        self.files = files
        self.bibleTranslations = bibleTranslations
    }
}

/// Tài liệu trùng mã giữa gói và thư viện, nội dung khác nhau. Cần chọn ``ConflictResolution``.
public struct BundleConflict: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: LibraryDocumentKind
    public var bundleTitle: String
    public var libraryTitle: String
}

/// Nội dung một gói mang đi, đối chiếu với thư viện hiện tại.
public struct BundleInspection: Sendable, Hashable {
    public var manifest: PortableBundleManifest
    public var plans: [ServicePlan]
    public var presentations: [Presentation]
    public var themes: [Theme]
    public var media: [MediaAssetInfo]
    /// Trùng mã, nội dung khác: cần chọn cách xử lý.
    public var conflicts: [BundleConflict]
    /// Trùng mã, nội dung giống hệt: bỏ qua khi nhập.
    public var unchangedIDs: Set<UUID>
    /// Media đã có trong thư viện (cùng SHA-256): bỏ qua khi nhập.
    public var existingMediaIDs: Set<MediaID>
    /// Bản dịch Kinh Thánh chương trình cần mà thư viện chưa có.
    public var missingTranslations: [String]
}

/// Lỗi của ``LibraryStore``, thông điệp tiếng Việt.
public enum LibraryStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case documentNotFound(UUID)
    case unsupportedMediaType(String)
    case mediaFileMissing(MediaID)
    case mediaNotFound(MediaID)
    case restoreConflict(UUID)
    case trashItemMissing(UUID)
    case invalidBundle(String)
    case newerBundle(found: Int, supported: Int)
    case unresolvedConflicts([UUID])
    case mediaChecksumMismatch(MediaID)
    case writeFailed(path: String, reason: String)

    public var message: String {
        switch self {
        case .documentNotFound(let id):
            return "Không tìm thấy tài liệu \(id.uuidString) trong thư viện."
        case .unsupportedMediaType(let fileExtension):
            return "Hệ thống chưa nhận loại tệp \".\(fileExtension)\" làm media."
        case .mediaFileMissing(let id):
            return "Tệp media \(id.rawValue) không còn trên đĩa."
        case .mediaNotFound(let id):
            return "Không tìm thấy media \(id.rawValue) trong thư viện."
        case .restoreConflict(let id):
            return "Không khôi phục được: thư viện đã có tài liệu cùng mã \(id.uuidString)."
        case .trashItemMissing(let id):
            return "Không khôi phục được: tài liệu \(id.uuidString) không còn trong thùng rác."
        case .invalidBundle(let detail):
            return "Gói mang đi không hợp lệ: \(detail)"
        case .newerBundle(let found, let supported):
            let detail = "định dạng \(found), Hệ thống hiện đọc tới \(supported)"
            return "Gói được tạo bởi phiên bản Hệ thống mới hơn (\(detail))."
        case .unresolvedConflicts(let ids):
            return "Còn \(ids.count) tài liệu trùng mã chưa chọn cách xử lý."
        case .mediaChecksumMismatch(let id):
            return "Media \(id.rawValue) trong gói bị hỏng (mã băm không khớp)."
        case .writeFailed(let path, let reason):
            return "Hệ thống chưa ghi được tệp \(path): \(reason)"
        }
    }

    public var description: String { message }
}

/// Thiết lập của ``LibraryStore``. Mặc định dùng cho ứng dụng; test thay đồng hồ và độ trễ.
public struct LibraryStoreConfiguration: Sendable {
    /// Thời gian hoãn ghi sau mỗi lần lưu, theo từng tài liệu.
    public var writeDelay: Duration
    /// Chu kỳ ghi nhật ký buổi nhóm theo lô.
    public var serviceLogInterval: Duration
    /// Tệp trong `.trash/` cũ hơn thời gian này bị xoá hẳn khi mở thư viện.
    public var trashRetention: TimeInterval
    /// Đồng hồ; test thay bằng đồng hồ giả.
    public var now: @Sendable () -> Date
    /// Múi giờ đặt tên tệp nhật ký buổi nhóm theo ngày.
    public var timeZone: TimeZone
    /// Mẫu trình bày tạo sẵn cho thư viện mới; mẫu đầu tiên là mẫu mặc định, mẫu có mã
    /// ``DefaultThemes/scriptureID`` (nếu có) là mẫu mặc định của Kinh Thánh.
    public var makeInitialThemes: @Sendable () -> [Theme]
    public var log: any LogSink
    /// Chuyển đổi định dạng tệp; test thay để thử đường migration.
    var migrate: @Sendable (Data, DocumentKind) throws -> (Data, migratedFrom: Int?)

    public init(
        writeDelay: Duration = .seconds(1), serviceLogInterval: Duration = .seconds(5),
        trashRetention: TimeInterval = 30 * 24 * 60 * 60, now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current, makeInitialThemes: @escaping @Sendable () -> [Theme] = { DefaultThemes.make() },
        log: any LogSink = NullLogSink()
    ) {
        self.writeDelay = writeDelay
        self.serviceLogInterval = serviceLogInterval
        self.trashRetention = trashRetention
        self.now = now
        self.timeZone = timeZone
        self.makeInitialThemes = makeInitialThemes
        self.log = log
        self.migrate = { data, kind in try DocumentMigration.migrate(data, kind: kind) }
    }
}

import Foundation

/// Loại mục trong chỉ mục tìm kiếm. Giá trị thô là chữ ghi vào cột `kind`.
public enum IndexKind: String, Sendable, CaseIterable {
    case presentation
    case theme
    case plan
    case media
    case verse
}

/// Một mục đưa vào chỉ mục. Chữ giữ nguyên dấu; `LibraryIndex` tự gộp dấu khi ghi.
public struct IndexEntry: Sendable, Equatable {
    /// UUID, mã media, hoặc "bible:<code>:<book>.<c>.<v>".
    public var id: String
    public var kind: IndexKind
    public var title: String
    /// Số thánh ca, tác giả, địa chỉ câu.
    public var subtitle: String?
    /// Lời bài hát, nội dung câu; chỉ dùng để tìm, không trả lại trong kết quả.
    public var body: String?
    public var path: String?
    public var modifiedAt: Date?

    public init(
        id: String,
        kind: IndexKind,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        path: String? = nil,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.path = path
        self.modifiedAt = modifiedAt
    }
}

/// Một kết quả tìm kiếm.
public struct SearchHit: Sendable, Equatable {
    public var id: String
    public var kind: IndexKind
    public var title: String
    public var subtitle: String?
    /// Độ liên quan, càng lớn càng khớp. Với kết quả toàn văn là `-bm25`; với kết quả khớp số thánh ca là
    /// ``LibraryIndex/exactNumberScore`` hoặc ``LibraryIndex/numberPrefixScore``, vượt xa mọi điểm toàn văn.
    public var score: Double

    public init(id: String, kind: IndexKind, title: String, subtitle: String?, score: Double) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.score = score
    }
}

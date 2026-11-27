import Foundation

/// Mục tiêu đề trong chương trình (không lên màn được).
public struct PlanHeaderItem: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var plannedDuration: Double?

    public init(id: UUID = UUID(), title: String, plannedDuration: Double? = nil) {
        self.id = id
        self.title = title
        self.plannedDuration = plannedDuration
    }
}

/// Mục bộ trình chiếu. `themeID` đè mẫu của bộ chỉ trong chương trình này.
public struct PlanPresentationItem: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var presentationID: UUID
    public var arrangementID: UUID?
    public var themeID: UUID?
    public var plannedDuration: Double?

    public init(
        id: UUID = UUID(), presentationID: UUID, arrangementID: UUID? = nil, themeID: UUID? = nil,
        plannedDuration: Double? = nil
    ) {
        self.id = id
        self.presentationID = presentationID
        self.arrangementID = arrangementID
        self.themeID = themeID
        self.plannedDuration = plannedDuration
    }
}

/// Mục Kinh Thánh.
public struct PlanScriptureItem: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    /// Địa chỉ câu, ví dụ "Giăng 3:16-18".
    public var reference: String
    /// Mã bản dịch, ví dụ "vi1925".
    public var translation: String
    public var themeID: UUID?
    public var plannedDuration: Double?

    public init(
        id: UUID = UUID(), reference: String, translation: String, themeID: UUID? = nil,
        plannedDuration: Double? = nil
    ) {
        self.id = id
        self.reference = reference
        self.translation = translation
        self.themeID = themeID
        self.plannedDuration = plannedDuration
    }
}

/// Mục media.
public struct PlanMediaItem: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var mediaID: MediaID
    public var plannedDuration: Double?

    public init(id: UUID = UUID(), mediaID: MediaID, plannedDuration: Double? = nil) {
        self.id = id
        self.mediaID = mediaID
        self.plannedDuration = plannedDuration
    }
}

/// Mục ghi chú cho người điều khiển (không lên màn được).
public struct PlanNoteItem: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var text: String
    public var plannedDuration: Double?

    public init(id: UUID = UUID(), text: String, plannedDuration: Double? = nil) {
        self.id = id
        self.text = text
        self.plannedDuration = plannedDuration
    }
}

/// Một mục trong chương trình buổi nhóm. Mã hoá JSON với khoá phân biệt `"type"`.
public enum ServicePlanItem: Sendable, Hashable, Codable, Identifiable {
    case header(PlanHeaderItem)
    case presentation(PlanPresentationItem)
    case scripture(PlanScriptureItem)
    case media(PlanMediaItem)
    case note(PlanNoteItem)

    public var id: UUID {
        switch self {
        case .header(let item):
            return item.id
        case .presentation(let item):
            return item.id
        case .scripture(let item):
            return item.id
        case .media(let item):
            return item.id
        case .note(let item):
            return item.id
        }
    }

    /// Thời lượng dự kiến, tính bằng giây.
    public var plannedDuration: Double? {
        switch self {
        case .header(let item):
            return item.plannedDuration
        case .presentation(let item):
            return item.plannedDuration
        case .scripture(let item):
            return item.plannedDuration
        case .media(let item):
            return item.plannedDuration
        case .note(let item):
            return item.plannedDuration
        }
    }

    /// `header` và `note` không lên màn được.
    public var isLiveable: Bool {
        switch self {
        case .header, .note:
            return false
        case .presentation, .scripture, .media:
            return true
        }
    }

    private enum TypeKey: String, CodingKey {
        case type
    }

    private enum Kind: String, Codable {
        case header
        case presentation
        case scripture
        case media
        case note
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .header:
            self = .header(try PlanHeaderItem(from: decoder))
        case .presentation:
            self = .presentation(try PlanPresentationItem(from: decoder))
        case .scripture:
            self = .scripture(try PlanScriptureItem(from: decoder))
        case .media:
            self = .media(try PlanMediaItem(from: decoder))
        case .note:
            self = .note(try PlanNoteItem(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .header(let item):
            try container.encode(Kind.header, forKey: .type)
            try item.encode(to: encoder)
        case .presentation(let item):
            try container.encode(Kind.presentation, forKey: .type)
            try item.encode(to: encoder)
        case .scripture(let item):
            try container.encode(Kind.scripture, forKey: .type)
            try item.encode(to: encoder)
        case .media(let item):
            try container.encode(Kind.media, forKey: .type)
            try item.encode(to: encoder)
        case .note(let item):
            try container.encode(Kind.note, forKey: .type)
            try item.encode(to: encoder)
        }
    }
}

/// Chương trình buổi nhóm.
public struct ServicePlan: Sendable, Hashable, Codable, Identifiable {
    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    /// Ngày nhóm dạng `yyyy-MM-dd`.
    public var date: String
    /// Giờ bắt đầu dự kiến dạng `HH:mm`.
    public var plannedStart: String?
    public var items: [ServicePlanItem]

    public init(
        schemaVersion: Int = DocumentMigration.currentSchemaVersion, id: UUID = UUID(), title: String, date: String,
        plannedStart: String? = nil, items: [ServicePlanItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.date = date
        self.plannedStart = plannedStart
        self.items = items
    }
}

import Foundation

/// Loại bộ trình chiếu.
public enum PresentationKind: String, Sendable, Hashable, Codable, CaseIterable {
    case song
    case generic
}

/// Loại nhãn đoạn.
public enum GroupLabelKind: String, Sendable, Hashable, Codable, CaseIterable {
    case verse
    case chorus
    case prechorus
    case bridge
    case tag
    case intro
    case ending
    case custom
}

/// Nhãn đoạn, ví dụ "Câu 1", "Điệp khúc".
public struct GroupLabel: Sendable, Hashable, Codable {
    public var kind: GroupLabelKind
    public var number: Int?
    public var custom: String?

    public init(kind: GroupLabelKind, number: Int? = nil, custom: String? = nil) {
        self.kind = kind
        self.number = number
        self.custom = custom
    }
}

/// Đoạn: nhóm trang có nhãn.
public struct SlideGroup: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var label: GroupLabel
    public var color: RGBA?
    public var slides: [Slide]

    public init(id: UUID = UUID(), label: GroupLabel, color: RGBA? = nil, slides: [Slide]) {
        self.id = id
        self.label = label
        self.color = color
        self.slides = slides
    }
}

/// Thứ tự hát: thứ tự trình bày các đoạn. Một đoạn có thể xuất hiện nhiều lần.
public struct Arrangement: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var groupIDs: [UUID]

    public init(id: UUID = UUID(), name: String, groupIDs: [UUID]) {
        self.id = id
        self.name = name
        self.groupIDs = groupIDs
    }
}

/// Thông tin bài hát.
public struct SongInfo: Sendable, Hashable, Codable {
    public var number: String?
    public var hymnal: String?
    public var authors: [String]
    public var copyright: String?
    public var ccli: String?
    public var key: String?
    public var tempo: Int?

    public init(
        number: String? = nil, hymnal: String? = nil, authors: [String] = [], copyright: String? = nil,
        ccli: String? = nil, key: String? = nil, tempo: Int? = nil
    ) {
        self.number = number
        self.hymnal = hymnal
        self.authors = authors
        self.copyright = copyright
        self.ccli = ccli
        self.key = key
        self.tempo = tempo
    }
}

/// Bộ trình chiếu: một bài hát, một bài giảng.
public struct Presentation: Sendable, Hashable, Codable, Identifiable {
    public var schemaVersion: Int
    public var id: UUID
    public var kind: PresentationKind
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var tags: [String]
    /// `nil` là mẫu mặc định của thư viện.
    public var themeID: UUID?
    /// `nil` khi `kind` là `generic`.
    public var song: SongInfo?
    public var groups: [SlideGroup]
    public var arrangements: [Arrangement]
    /// `nil` là thứ tự các đoạn như trong `groups`.
    public var activeArrangementID: UUID?

    public init(
        schemaVersion: Int = DocumentMigration.currentSchemaVersion, id: UUID = UUID(), kind: PresentationKind,
        title: String, createdAt: Date, modifiedAt: Date, tags: [String] = [], themeID: UUID? = nil,
        song: SongInfo? = nil, groups: [SlideGroup] = [], arrangements: [Arrangement] = [],
        activeArrangementID: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tags = tags
        self.themeID = themeID
        self.song = song
        self.groups = groups
        self.arrangements = arrangements
        self.activeArrangementID = activeArrangementID
    }

    /// Bài hát mới: một đoạn "verse 1" có một trang với một phần tử chữ ở ô `body`, một thứ tự hát "Mặc định".
    public static func newSong(title: String, now: Date = Date()) -> Presentation {
        let text = TextElement(slot: .body, text: "")
        let group = SlideGroup(label: GroupLabel(kind: .verse, number: 1), slides: [Slide(elements: [.text(text)])])
        let arrangement = Arrangement(name: "Mặc định", groupIDs: [group.id])
        return Presentation(
            kind: .song, title: title, createdAt: now, modifiedAt: now, song: SongInfo(), groups: [group],
            arrangements: [arrangement], activeArrangementID: arrangement.id
        )
    }

    /// Các đoạn theo thứ tự hát đang chọn, hoặc thứ tự gốc khi không có. Bỏ qua `groupIDs` không tồn tại.
    public func orderedGroups() -> [SlideGroup] {
        orderedGroups(arrangementID: nil)
    }

    /// Các đoạn theo thứ tự hát `arrangementID`; `nil` hoặc không tìm thấy thì dùng thứ tự hát đang chọn,
    /// rồi tới thứ tự gốc. Bỏ qua `groupIDs` không tồn tại.
    public func orderedGroups(arrangementID: UUID?) -> [SlideGroup] {
        let requested = arrangements.first(where: { $0.id == arrangementID })
        guard let arrangement = requested ?? arrangements.first(where: { $0.id == activeArrangementID }) else {
            return groups
        }
        var byID: [UUID: SlideGroup] = [:]
        for group in groups {
            byID[group.id] = group
        }
        return arrangement.groupIDs.compactMap { byID[$0] }
    }
}

import Foundation

/// Loại nền.
public enum BackgroundKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// Dùng nền của mẫu trình bày.
    case none
    case color
    case media
}

/// Nền của trang chiếu hoặc mẫu trình bày.
public struct SlideBackground: Sendable, Hashable, Codable {
    public var kind: BackgroundKind
    public var color: RGBA?
    public var mediaID: MediaID?
    public var loop: Bool?
    public var muted: Bool?

    public init(
        kind: BackgroundKind, color: RGBA? = nil, mediaID: MediaID? = nil, loop: Bool? = nil, muted: Bool? = nil
    ) {
        self.kind = kind
        self.color = color
        self.mediaID = mediaID
        self.loop = loop
        self.muted = muted
    }

    /// Không có nền riêng: dùng nền của mẫu.
    public static let none = SlideBackground(kind: .none)

    /// Nền một màu.
    public static func color(_ color: RGBA) -> SlideBackground {
        SlideBackground(kind: .color, color: color)
    }

    /// Nền là ảnh hoặc video trong thư viện.
    public static func media(_ id: MediaID, loop: Bool = true, muted: Bool = false) -> SlideBackground {
        SlideBackground(kind: .media, mediaID: id, loop: loop, muted: muted)
    }
}

/// Một trang chiếu.
public struct Slide: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var label: String?
    /// `false` thì bỏ qua khi bấm trang kế hoặc trang trước, nhưng vẫn lên màn được khi chọn trực tiếp.
    public var enabled: Bool
    /// Ghi chú cho màn hình nhắc.
    public var notes: String
    public var background: SlideBackground
    public var elements: [Element]

    public init(
        id: UUID = UUID(), label: String? = nil, enabled: Bool = true, notes: String = "",
        background: SlideBackground = .none, elements: [Element] = []
    ) {
        self.id = id
        self.label = label
        self.enabled = enabled
        self.notes = notes
        self.background = background
        self.elements = elements
    }
}

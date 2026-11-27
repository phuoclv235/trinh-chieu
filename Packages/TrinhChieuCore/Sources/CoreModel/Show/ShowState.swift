import Foundation

// Tệp nguy hiểm: trạng thái trình chiếu là thứ giao diện, remote và nút trình chiếu cùng đọc.

/// Ảnh chụp trạng thái trình chiếu. Giao diện chỉ đọc giá trị này.
public struct ShowState: Sendable, Equatable {
    public var activePlanID: UUID?
    public var selected: LiveSource?
    /// `nil` là lớp chữ trống.
    public var live: LivePosition?
    /// Chỉ chứa lớp có nội dung.
    public var layers: [LayerKind: LayerState]
    public var isFrozen: Bool
    public var isRehearsal: Bool
    public var settings: ShowSettings

    public init(
        activePlanID: UUID? = nil, selected: LiveSource? = nil, live: LivePosition? = nil,
        layers: [LayerKind: LayerState] = [:], isFrozen: Bool = false, isRehearsal: Bool = false,
        settings: ShowSettings = ShowSettings()
    ) {
        self.activePlanID = activePlanID
        self.selected = selected
        self.live = live
        self.layers = layers
        self.isFrozen = isFrozen
        self.isRehearsal = isRehearsal
        self.settings = settings
    }
}

/// Vị trí đang chiếu.
public struct LivePosition: Sendable, Equatable {
    public var source: LiveSource
    public var slideIndex: Int
    public var slideID: UUID
    public var wentLiveAt: Date

    public init(source: LiveSource, slideIndex: Int, slideID: UUID, wentLiveAt: Date) {
        self.source = source
        self.slideIndex = slideIndex
        self.slideID = slideID
        self.wentLiveAt = wentLiveAt
    }
}

/// Nội dung của một lớp.
public enum LayerState: Sendable, Equatable {
    /// `origin` là `slideID` hoặc `id` của mẫu, hoặc mã media băm thành UUID; dùng làm `contentID`.
    case background(SlideBackground, origin: UUID)
    case slide(slideID: UUID)
}

/// Thiết lập trình chiếu.
public struct ShowSettings: Sendable, Equatable, Codable {
    /// Trang cuối + trang kế thì sang mục kế của chương trình.
    public var advanceToNextItem: Bool = true

    public init(advanceToNextItem: Bool = true) {
        self.advanceToNextItem = advanceToNextItem
    }
}

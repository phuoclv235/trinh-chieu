import Foundation

// Hợp đồng giữa lõi và lõi dựng hình (tệp nguy hiểm, xem docs/kien-truc.md mục 5).
// Mọi kiểu ở đây Codable, không chứa đường dẫn tệp hay giá trị phụ thuộc máy, để gửi được sang máy khác.

/// Cảnh cần vẽ cho một đầu ra.
public struct RenderScene: Sendable, Equatable, Codable {
    /// Tăng dần mỗi lần xuất.
    public var revision: UInt64
    /// Kích thước khung vẽ của mẫu, ví dụ 1920x1080.
    public var canvasSize: PixelSize
    /// Các lớp theo thứ tự vẽ, dưới lên trên.
    public var layers: [RenderLayer]
    /// Cách chuyển từ cảnh trước sang cảnh này.
    public var transition: TransitionSpec

    public init(revision: UInt64 = 0, canvasSize: PixelSize, layers: [RenderLayer], transition: TransitionSpec = .cut) {
        self.revision = revision
        self.canvasSize = canvasSize
        self.layers = layers
        self.transition = transition
    }

    /// Mã nội dung cố định của lớp nền đen trong cảnh trống.
    public static let emptyContentID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Cảnh nền đen trống.
    public static func empty(canvas: PixelSize) -> RenderScene {
        let black = RenderItem.color(.black, frame: PixelRect(size: canvas))
        let layer = RenderLayer(kind: .background, contentID: emptyContentID, items: [black])
        return RenderScene(canvasSize: canvas, layers: [layer])
    }
}

/// Lớp trong bộ trộn. Giai đoạn 1 dùng `background` và `slide`.
public enum LayerKind: String, Sendable, Hashable, Codable, CaseIterable {
    case background
    case slide
    case overlay
    case message
    case mask
}

/// Một lớp của cảnh.
public struct RenderLayer: Sendable, Equatable, Codable {
    public var kind: LayerKind
    /// Đổi khi nội dung đổi; dùng để quyết định chuyển cảnh theo lớp.
    public var contentID: UUID
    public var items: [RenderItem]

    public init(kind: LayerKind, contentID: UUID, items: [RenderItem]) {
        self.kind = kind
        self.contentID = contentID
        self.items = items
    }
}

/// Một thứ cần vẽ trong lớp. Mã hoá JSON với khoá phân biệt `"type"`.
public enum RenderItem: Sendable, Equatable, Codable {
    case color(RGBA, frame: PixelRect)
    case image(MediaRef, frame: PixelRect, fit: ContentFit)
    case video(VideoRef, frame: PixelRect, fit: ContentFit)
    case text(TextBlock, frame: PixelRect)

    private enum CodingKeys: String, CodingKey {
        case type
        case color
        case media
        case video
        case text
        case frame
        case fit
    }

    private enum Kind: String, Codable {
        case color
        case image
        case video
        case text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let frame = try container.decode(PixelRect.self, forKey: .frame)
        switch try container.decode(Kind.self, forKey: .type) {
        case .color:
            self = .color(try container.decode(RGBA.self, forKey: .color), frame: frame)
        case .image:
            let media = try container.decode(MediaRef.self, forKey: .media)
            self = .image(media, frame: frame, fit: try container.decode(ContentFit.self, forKey: .fit))
        case .video:
            let video = try container.decode(VideoRef.self, forKey: .video)
            self = .video(video, frame: frame, fit: try container.decode(ContentFit.self, forKey: .fit))
        case .text:
            self = .text(try container.decode(TextBlock.self, forKey: .text), frame: frame)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let color, let frame):
            try container.encode(Kind.color, forKey: .type)
            try container.encode(color, forKey: .color)
            try container.encode(frame, forKey: .frame)
        case .image(let media, let frame, let fit):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(media, forKey: .media)
            try container.encode(frame, forKey: .frame)
            try container.encode(fit, forKey: .fit)
        case .video(let video, let frame, let fit):
            try container.encode(Kind.video, forKey: .type)
            try container.encode(video, forKey: .video)
            try container.encode(frame, forKey: .frame)
            try container.encode(fit, forKey: .fit)
        case .text(let text, let frame):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(frame, forKey: .frame)
        }
    }
}

/// Kiểu chữ đã giải xong (không còn tham chiếu tới mẫu), mọi trường bắt buộc.
public struct ResolvedTextStyle: Sendable, Hashable, Codable {
    public var fontFamily: String
    public var fontWeight: Int
    public var fontSize: Double
    public var color: RGBA
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment
    public var lineHeight: Double
    public var letterSpacing: Double
    public var stroke: TextStroke
    public var shadow: TextShadow
    public var box: TextBox

    public init(
        fontFamily: String, fontWeight: Int, fontSize: Double, color: RGBA, alignment: TextAlignment,
        verticalAlignment: VerticalAlignment, lineHeight: Double, letterSpacing: Double, stroke: TextStroke,
        shadow: TextShadow, box: TextBox
    ) {
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.stroke = stroke
        self.shadow = shadow
        self.box = box
    }

    /// Lấy các trường vẽ từ một `TextStyle` (bỏ `transform`, `autoFit`, `maxLines` vì `TextBlock` mang riêng).
    public init(_ style: TextStyle) {
        self.init(
            fontFamily: style.fontFamily, fontWeight: style.fontWeight, fontSize: style.fontSize, color: style.color,
            alignment: style.alignment, verticalAlignment: style.verticalAlignment, lineHeight: style.lineHeight,
            letterSpacing: style.letterSpacing, stroke: style.stroke, shadow: style.shadow, box: style.box
        )
    }
}

/// Khối chữ cần vẽ.
public struct TextBlock: Sendable, Equatable, Codable {
    /// Chuỗi NFC, đã áp `transform` (ví dụ chữ hoa).
    public var string: String
    public var style: ResolvedTextStyle
    public var autoFit: AutoFit
    public var maxLines: Int?

    public init(string: String, style: ResolvedTextStyle, autoFit: AutoFit, maxLines: Int? = nil) {
        self.string = string
        self.style = style
        self.autoFit = autoFit
        self.maxLines = maxLines
    }
}

/// Tham chiếu media. **Không** chứa đường dẫn: mỗi máy tự tìm tệp qua `MediaLocator`.
public struct MediaRef: Sendable, Hashable, Codable {
    public var id: MediaID

    public init(id: MediaID) {
        self.id = id
    }
}

/// Tham chiếu video cùng cách phát.
public struct VideoRef: Sendable, Hashable, Codable {
    public var media: MediaRef
    public var loop: Bool
    public var muted: Bool
    /// Mỗi lần lên màn một giá trị mới, để video phát lại từ đầu.
    public var playbackID: UUID
    /// Thời điểm (đồng hồ máy chủ) video bắt đầu phát; máy con dùng để khớp vị trí phát.
    public var startedAt: Date

    public init(media: MediaRef, loop: Bool, muted: Bool, playbackID: UUID, startedAt: Date) {
        self.media = media
        self.loop = loop
        self.muted = muted
        self.playbackID = playbackID
        self.startedAt = startedAt
    }
}

/// Tìm tệp của media trên máy đang chạy. `RenderEngine` nhận qua `init`.
public protocol MediaLocator: Sendable {
    func url(for id: MediaID) -> URL?
}

/// Cách chuyển cảnh.
public enum TransitionKind: String, Sendable, Hashable, Codable, CaseIterable {
    case cut
    case dissolve
}

/// Chuyển cảnh và thời lượng (giây).
public struct TransitionSpec: Sendable, Hashable, Codable {
    public var kind: TransitionKind
    public var duration: Double

    public init(kind: TransitionKind, duration: Double) {
        self.kind = kind
        self.duration = duration
    }

    /// Đổi tức thì.
    public static let cut = TransitionSpec(kind: .cut, duration: 0)
}

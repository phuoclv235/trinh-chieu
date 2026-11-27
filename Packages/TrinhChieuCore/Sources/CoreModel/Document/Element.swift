import Foundation

/// Vai trò của ô chữ trong mẫu trình bày.
public enum ThemeSlotKind: String, Sendable, Hashable, Codable, CaseIterable {
    case body
    case title
    case reference
}

/// Hình dạng của phần tử hình.
public enum ShapeKind: String, Sendable, Hashable, Codable, CaseIterable {
    case rect
}

/// Phần tử chữ. Có `slot` thì khung và kiểu lấy từ ô mẫu, `frame` bị bỏ qua, `style` chỉ đè các trường được ghi.
public struct TextElement: Sendable, Hashable, Codable {
    public var id: UUID
    public var frame: PixelRect
    public var slot: ThemeSlotKind?
    public var text: String
    public var style: TextStyleOverride?

    public init(
        id: UUID = UUID(), frame: PixelRect = .zero, slot: ThemeSlotKind? = nil, text: String,
        style: TextStyleOverride? = nil
    ) {
        self.id = id
        self.frame = frame
        self.slot = slot
        self.text = text
        self.style = style
    }
}

/// Phần tử ảnh.
public struct ImageElement: Sendable, Hashable, Codable {
    public var id: UUID
    public var frame: PixelRect
    public var mediaID: MediaID
    public var fit: ContentFit
    public var opacity: Double

    public init(id: UUID = UUID(), frame: PixelRect, mediaID: MediaID, fit: ContentFit = .fit, opacity: Double = 1) {
        self.id = id
        self.frame = frame
        self.mediaID = mediaID
        self.fit = fit
        self.opacity = opacity
    }
}

/// Phần tử video.
public struct VideoElement: Sendable, Hashable, Codable {
    public var id: UUID
    public var frame: PixelRect
    public var mediaID: MediaID
    public var fit: ContentFit
    public var loop: Bool
    public var muted: Bool

    public init(
        id: UUID = UUID(), frame: PixelRect, mediaID: MediaID, fit: ContentFit = .fit, loop: Bool = false,
        muted: Bool = false
    ) {
        self.id = id
        self.frame = frame
        self.mediaID = mediaID
        self.fit = fit
        self.loop = loop
        self.muted = muted
    }
}

/// Phần tử hình (khối màu).
public struct ShapeElement: Sendable, Hashable, Codable {
    public var id: UUID
    public var frame: PixelRect
    public var shape: ShapeKind
    public var fill: RGBA
    public var cornerRadius: Double

    public init(id: UUID = UUID(), frame: PixelRect, shape: ShapeKind = .rect, fill: RGBA, cornerRadius: Double = 0) {
        self.id = id
        self.frame = frame
        self.shape = shape
        self.fill = fill
        self.cornerRadius = cornerRadius
    }
}

/// Một phần tử trên trang chiếu. Mã hoá JSON với khoá phân biệt `"type"`.
public enum Element: Sendable, Hashable, Codable {
    case text(TextElement)
    case image(ImageElement)
    case video(VideoElement)
    case shape(ShapeElement)

    public var id: UUID {
        switch self {
        case .text(let element):
            return element.id
        case .image(let element):
            return element.id
        case .video(let element):
            return element.id
        case .shape(let element):
            return element.id
        }
    }

    private enum TypeKey: String, CodingKey {
        case type
    }

    private enum Kind: String, Codable {
        case text
        case image
        case video
        case shape
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try TextElement(from: decoder))
        case .image:
            self = .image(try ImageElement(from: decoder))
        case .video:
            self = .video(try VideoElement(from: decoder))
        case .shape:
            self = .shape(try ShapeElement(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .text(let element):
            try container.encode(Kind.text, forKey: .type)
            try element.encode(to: encoder)
        case .image(let element):
            try container.encode(Kind.image, forKey: .type)
            try element.encode(to: encoder)
        case .video(let element):
            try container.encode(Kind.video, forKey: .type)
            try element.encode(to: encoder)
        case .shape(let element):
            try container.encode(Kind.shape, forKey: .type)
            try element.encode(to: encoder)
        }
    }
}

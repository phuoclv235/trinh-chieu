import Foundation

/// Căn ngang của chữ.
public enum TextAlignment: String, Sendable, Hashable, Codable, CaseIterable {
    case left
    case center
    case right
    case justified
}

/// Căn dọc của chữ trong khung.
public enum VerticalAlignment: String, Sendable, Hashable, Codable, CaseIterable {
    case top
    case middle
    case bottom
}

/// Biến đổi chữ trước khi vẽ.
public enum TextTransform: String, Sendable, Hashable, Codable, CaseIterable {
    case none
    case uppercase
}

/// Viền chữ.
public struct TextStroke: Sendable, Hashable, Codable {
    public var color: RGBA
    public var width: Double

    public init(color: RGBA, width: Double) {
        self.color = color
        self.width = width
    }

    public static let none = TextStroke(color: .black, width: 0)
}

/// Bóng chữ.
public struct TextShadow: Sendable, Hashable, Codable {
    public var color: RGBA
    public var radius: Double
    public var offset: PixelPoint

    public init(color: RGBA, radius: Double, offset: PixelPoint) {
        self.color = color
        self.radius = radius
        self.offset = offset
    }

    public static let none = TextShadow(color: .clear, radius: 0, offset: .zero)
}

/// Hộp nền sau chữ.
public struct TextBox: Sendable, Hashable, Codable {
    public var color: RGBA
    public var padding: EdgeInsets
    public var cornerRadius: Double

    public init(color: RGBA, padding: EdgeInsets, cornerRadius: Double) {
        self.color = color
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    public static let none = TextBox(color: .clear, padding: .zero, cornerRadius: 0)
}

/// Cách co chữ khi không vừa khung.
public enum AutoFitMode: String, Sendable, Hashable, Codable, CaseIterable {
    case none
    case shrink
}

/// Quy tắc co chữ: `minScale` là tỉ lệ nhỏ nhất được phép co tới.
public struct AutoFit: Sendable, Hashable, Codable {
    public var mode: AutoFitMode
    public var minScale: Double

    public init(mode: AutoFitMode, minScale: Double) {
        self.mode = mode
        self.minScale = minScale
    }

    public static let none = AutoFit(mode: .none, minScale: 1)
}

/// Kiểu chữ đầy đủ, mọi trường bắt buộc. Dùng trong ô mẫu của `Theme`.
public struct TextStyle: Sendable, Hashable, Codable {
    /// `"system"` là phông hệ thống của macOS; tên khác là tên họ phông đã cài.
    public var fontFamily: String
    public var fontWeight: Int
    public var fontSize: Double
    public var color: RGBA
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment
    public var lineHeight: Double
    public var letterSpacing: Double
    public var transform: TextTransform
    public var stroke: TextStroke
    public var shadow: TextShadow
    public var box: TextBox
    public var autoFit: AutoFit
    public var maxLines: Int?

    public init(
        fontFamily: String = "system", fontWeight: Int = 400, fontSize: Double = 72, color: RGBA = .white,
        alignment: TextAlignment = .center, verticalAlignment: VerticalAlignment = .middle, lineHeight: Double = 1.2,
        letterSpacing: Double = 0, transform: TextTransform = .none, stroke: TextStroke = .none,
        shadow: TextShadow = .none, box: TextBox = .none, autoFit: AutoFit = .none, maxLines: Int? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.transform = transform
        self.stroke = stroke
        self.shadow = shadow
        self.box = box
        self.autoFit = autoFit
        self.maxLines = maxLines
    }

    /// Kiểu mới sau khi đè các trường có giá trị trong `override`.
    public func applying(_ override: TextStyleOverride) -> TextStyle {
        var result = self
        if let value = override.fontFamily { result.fontFamily = value }
        if let value = override.fontWeight { result.fontWeight = value }
        if let value = override.fontSize { result.fontSize = value }
        if let value = override.color { result.color = value }
        if let value = override.alignment { result.alignment = value }
        if let value = override.verticalAlignment { result.verticalAlignment = value }
        if let value = override.lineHeight { result.lineHeight = value }
        if let value = override.letterSpacing { result.letterSpacing = value }
        if let value = override.transform { result.transform = value }
        if let value = override.stroke { result.stroke = value }
        if let value = override.shadow { result.shadow = value }
        if let value = override.box { result.box = value }
        if let value = override.autoFit { result.autoFit = value }
        if let value = override.maxLines { result.maxLines = value }
        return result
    }
}

/// Phần đè kiểu chữ: mọi trường optional, chỉ trường có giá trị mới đè lên kiểu của mẫu. Dùng trong `Element`.
public struct TextStyleOverride: Sendable, Hashable, Codable {
    public var fontFamily: String?
    public var fontWeight: Int?
    public var fontSize: Double?
    public var color: RGBA?
    public var alignment: TextAlignment?
    public var verticalAlignment: VerticalAlignment?
    public var lineHeight: Double?
    public var letterSpacing: Double?
    public var transform: TextTransform?
    public var stroke: TextStroke?
    public var shadow: TextShadow?
    public var box: TextBox?
    public var autoFit: AutoFit?
    public var maxLines: Int?

    public init(
        fontFamily: String? = nil, fontWeight: Int? = nil, fontSize: Double? = nil, color: RGBA? = nil,
        alignment: TextAlignment? = nil, verticalAlignment: VerticalAlignment? = nil, lineHeight: Double? = nil,
        letterSpacing: Double? = nil, transform: TextTransform? = nil, stroke: TextStroke? = nil,
        shadow: TextShadow? = nil, box: TextBox? = nil, autoFit: AutoFit? = nil, maxLines: Int? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
        self.transform = transform
        self.stroke = stroke
        self.shadow = shadow
        self.box = box
        self.autoFit = autoFit
        self.maxLines = maxLines
    }

    /// Không đè trường nào.
    public var isEmpty: Bool { self == TextStyleOverride() }
}

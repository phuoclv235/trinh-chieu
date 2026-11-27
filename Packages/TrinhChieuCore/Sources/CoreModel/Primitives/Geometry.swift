import Foundation

/// Kích thước tính bằng điểm ảnh. Mã hoá JSON thành `[w, h]`.
public struct PixelSize: Sendable, Hashable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let fullHD = PixelSize(width: 1920, height: 1080)

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let width = try container.decode(Double.self)
        let height = try container.decode(Double.self)
        self.init(width: width, height: height)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }
}

/// Điểm hoặc độ dời tính bằng điểm ảnh. Mã hoá JSON thành `[x, y]`.
public struct PixelPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = PixelPoint(x: 0, y: 0)

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

/// Hình chữ nhật trong khung vẽ, gốc ở góc trên trái. Mã hoá JSON thành `[x, y, w, h]`.
public struct PixelRect: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Hình chữ nhật phủ cả khung vẽ có kích thước `size`.
    public init(size: PixelSize) {
        self.init(x: 0, y: 0, width: size.width, height: size.height)
    }

    public static let zero = PixelRect(x: 0, y: 0, width: 0, height: 0)

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        let width = try container.decode(Double.self)
        let height = try container.decode(Double.self)
        self.init(x: x, y: y, width: width, height: height)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(width)
        try container.encode(height)
    }
}

/// Lề bốn phía theo thứ tự trên, phải, dưới, trái. Mã hoá JSON thành `[t, r, b, l]`.
public struct EdgeInsets: Sendable, Hashable, Codable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static let zero = EdgeInsets(top: 0, right: 0, bottom: 0, left: 0)

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let top = try container.decode(Double.self)
        let right = try container.decode(Double.self)
        let bottom = try container.decode(Double.self)
        let left = try container.decode(Double.self)
        self.init(top: top, right: right, bottom: bottom, left: left)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(top)
        try container.encode(right)
        try container.encode(bottom)
        try container.encode(left)
    }
}

/// Cách đặt ảnh hoặc video vào khung.
public enum ContentFit: String, Sendable, Hashable, Codable, CaseIterable {
    /// Giữ tỉ lệ, nằm trọn trong khung.
    case fit
    /// Giữ tỉ lệ, phủ kín khung (có thể bị cắt).
    case fill
    /// Kéo giãn cho vừa khung.
    case stretch
}

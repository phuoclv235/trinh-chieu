import CoreGraphics
import CoreModel
import Foundation
import Metal

/// Mã của một đầu ra, do bên gắn đặt (ví dụ mã màn hình). Ổn định trong một phiên chạy.
public struct OutputID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    /// Mã hoá thành chuỗi trơn (như `OutputRole`).
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Vai của một đầu ra.
public enum OutputRole: String, Sendable, Codable, CaseIterable {
    /// Đầu ra chính (LED, máy chiếu).
    case program
    /// Màn hình nhắc trên sân khấu.
    case stage
}

/// Không tìm được tệp media nào. Dùng khi dựng cảnh không có ảnh hay video.
public struct NoMediaLocator: MediaLocator {
    public init() {}

    public func url(for id: MediaID) -> URL? { nil }
}

extension PixelRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

extension PixelSize {
    var cgSize: CGSize { CGSize(width: width, height: height) }
}

extension RGBA {
    /// Bốn byte BGRA đã nhân sẵn alpha, đúng định dạng texture `.bgra8Unorm` của lõi dựng hình.
    var premultipliedBGRA: [UInt8] {
        func multiply(_ channel: UInt8) -> UInt8 {
            UInt8((Int(channel) * Int(alpha) + 127) / 255)
        }
        return [multiply(blue), multiply(green), multiply(red), alpha]
    }

    /// Màu xoá khung (đã nhân sẵn alpha).
    var clearColor: MTLClearColor {
        let a = Double(alpha) / 255
        return MTLClearColor(
            red: Double(red) / 255 * a,
            green: Double(green) / 255 * a,
            blue: Double(blue) / 255 * a,
            alpha: a
        )
    }

    /// Trộn hai màu theo `t` (0 là màu này, 1 là `other`).
    func mixed(with other: RGBA, t: Double) -> RGBA {
        func lerp(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * min(max(t, 0), 1)).rounded())
        }
        return RGBA(
            red: lerp(red, other.red),
            green: lerp(green, other.green),
            blue: lerp(blue, other.blue),
            alpha: lerp(alpha, other.alpha)
        )
    }

    /// Màu Core Graphics trong không gian sRGB.
    var cgColor: CGColor {
        let components = [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, CGFloat(alpha) / 255]
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGColor(colorSpace: space, components: components)
            ?? CGColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}

/// Hàm êm `smoothstep` trên đoạn [0, 1]: chậm ở hai đầu, nhanh ở giữa, `smoothstep(0.5) == 0.5`.
func smoothstep(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

/// Hình chữ nhật giữ tỉ lệ `contentSize`, nằm trọn và căn giữa trong `frame`.
func aspectFitRect(contentSize: CGSize, in frame: CGRect) -> CGRect {
    guard contentSize.width > 0, contentSize.height > 0, frame.width > 0, frame.height > 0 else { return frame }
    let scale = min(frame.width / contentSize.width, frame.height / contentSize.height)
    let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    return CGRect(
        x: frame.minX + (frame.width - size.width) / 2,
        y: frame.minY + (frame.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}

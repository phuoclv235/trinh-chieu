import Foundation

/// Màu 8 bit mỗi kênh. Mã hoá JSON thành chuỗi `#RRGGBBAA`.
public struct RGBA: Sendable, Hashable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 255, green: 255, blue: 255)
    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)

    /// Đọc chuỗi `#RRGGBB` (alpha FF) hoặc `#RRGGBBAA`, không phân biệt hoa thường.
    public init(hex: String) throws {
        let digits = Array(hex.utf8)
        guard digits.first == UInt8(ascii: "#"), digits.count == 7 || digits.count == 9 else {
            throw DocumentError.invalidColor(hex)
        }
        var channels: [UInt8] = []
        var index = 1
        while index < digits.count {
            guard let high = RGBA.hexValue(digits[index]), let low = RGBA.hexValue(digits[index + 1]) else {
                throw DocumentError.invalidColor(hex)
            }
            channels.append(high << 4 | low)
            index += 2
        }
        let alpha = channels.count == 4 ? channels[3] : 255
        self.init(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// Chuỗi `#RRGGBBAA` chữ hoa.
    public var hexString: String {
        let table = Array("0123456789ABCDEF")
        var result = "#"
        for channel in [red, green, blue, alpha] {
            result.append(table[Int(channel >> 4)])
            result.append(table[Int(channel & 0x0F)])
        }
        return result
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        do {
            try self.init(hex: string)
        } catch let error as DocumentError {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: error.message)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return byte - UInt8(ascii: "A") + 10
        default:
            return nil
        }
    }
}

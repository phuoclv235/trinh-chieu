import Foundation

/// Mã media trong thư viện: 12 ký tự đầu của SHA-256 nội dung, hoặc `l-` + 10 ký tự cho media liên kết.
public struct MediaID: Sendable, Hashable, Codable, Comparable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }

    public static func < (lhs: MediaID, rhs: MediaID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// UUID tất định băm từ mã media, dùng làm `contentID` của lớp và `id` của trang media.
    public var contentUUID: UUID {
        UUID(hashing: "media:" + rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension UUID {
    /// UUID tất định (dạng phiên bản 8) băm từ chuỗi bằng hai lượt FNV-1a 64 bit.
    /// Cùng chuỗi luôn cho cùng UUID trên mọi máy.
    public init(hashing string: String) {
        let first = UUID.fnv1a(string.utf8, seed: 0xcbf2_9ce4_8422_2325)
        let second = UUID.fnv1a(string.utf8, seed: 0x8422_2325_cbf2_9ce4)
        var bytes: [UInt8] = []
        for value in [first, second] {
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let table = Array("0123456789ABCDEF")
        var text = ""
        for (index, byte) in bytes.enumerated() {
            if index == 4 || index == 6 || index == 8 || index == 10 {
                text.append("-")
            }
            text.append(table[Int(byte >> 4)])
            text.append(table[Int(byte & 0x0F)])
        }
        self = UUID(uuidString: text)!
    }

    private static func fnv1a(_ bytes: String.UTF8View, seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

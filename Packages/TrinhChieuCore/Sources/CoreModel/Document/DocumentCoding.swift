import Foundation

/// Bộ mã hoá JSON dùng chung cho mọi tệp tài liệu của thư viện.
/// Mọi nơi đọc ghi tài liệu dùng `makeEncoder()` và `makeDecoder()`.
public enum DocumentCoding {
    /// `JSONEncoder` với `.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`, ngày ISO 8601 UTC.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DocumentCoding.string(from: date))
        }
        return encoder
    }

    /// `JSONDecoder` tương ứng: nhận ngày ISO 8601 có hoặc không có phần lẻ giây.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = DocumentCoding.date(from: string) else {
                let message = "Ngày giờ không đúng định dạng ISO 8601: \(string)"
                throw DecodingError.dataCorruptedError(in: container, debugDescription: message)
            }
            return date
        }
        return decoder
    }

    /// Mã hoá một tài liệu thành JSON theo quy ước của thư viện.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }

    /// Giải mã một tài liệu từ JSON theo quy ước của thư viện.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }

    /// Ngày giờ ISO 8601 UTC; có phần nghìn giây khi khác 0 (ví dụ `2026-11-30T09:01:12.120Z`).
    public static func string(from date: Date) -> String {
        let millisecondsTotal = (date.timeIntervalSince1970 * 1000).rounded()
        let wholeSeconds = Date(timeIntervalSince1970: (millisecondsTotal / 1000).rounded(.down))
        let milliseconds = Int(millisecondsTotal - (millisecondsTotal / 1000).rounded(.down) * 1000)
        let base = wholeSeconds.formatted(Date.ISO8601FormatStyle())
        guard milliseconds != 0 else {
            return base
        }
        let fraction = String(milliseconds + 1000).dropFirst()
        return String(base.dropLast()) + "." + fraction + "Z"
    }

    /// Đọc ngày giờ ISO 8601, có hoặc không có phần lẻ giây.
    public static func date(from string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle().parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string)
    }
}

/// Lỗi khi đọc tài liệu, thông điệp tiếng Việt để hiện cho người dùng.
public enum DocumentError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidColor(String)
    case newerSchema(found: Int, supported: Int)
    case invalidSchemaVersion
    case notAnObject

    public var message: String {
        switch self {
        case .invalidColor(let value):
            return "Màu \"\(value)\" không hợp lệ: cần dạng #RRGGBB hoặc #RRGGBBAA."
        case .newerSchema(let found, let supported):
            let detail = "định dạng \(found), Hệ thống hiện đọc tới \(supported)"
            return "Tệp được tạo bởi phiên bản Hệ thống mới hơn (\(detail))."
        case .invalidSchemaVersion:
            return "Tệp có số phiên bản định dạng không hợp lệ."
        case .notAnObject:
            return "Tệp không phải tài liệu JSON hợp lệ của Hệ thống."
        }
    }

    public var description: String { message }
}

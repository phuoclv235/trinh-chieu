import Foundation
import VietText

/// Đoán bảng mã và giải mã tệp văn bản: UTF-8, rồi UTF-16 có BOM, rồi Windows-1258.
enum TextDecoding {
    enum Encoding: String, Sendable {
        case utf8
        case utf16LittleEndian
        case utf16BigEndian
        case windows1258
    }

    /// Chữ đã chuẩn hoá bằng `VietText.normalize` (NFC, LF, bỏ BOM và ký tự điều khiển) cùng bảng mã đã dùng.
    static func decode(_ data: Data) -> (text: String, encoding: Encoding) {
        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE], let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return (VietText.normalize(text), .utf16LittleEndian)
        }
        if bytes == [0xFE, 0xFF], let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return (VietText.normalize(text), .utf16BigEndian)
        }
        if let text = String(data: data, encoding: .utf8) {
            return (VietText.normalize(text), .utf8)
        }
        return (VietText.decodeWindows1258(data), .windows1258)
    }

    /// Dữ liệu trông như tệp nhị phân (PDF, ảnh, gói nén), không phải văn bản: có byte điều khiển lạ trong 4 KB đầu.
    /// Tệp UTF-16 có BOM không bị coi là nhị phân dù chứa byte 0.
    static func looksBinary(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(4096))
        if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) { return false }
        return head.contains { byte in
            byte < 0x09 || (byte > 0x0D && byte < 0x20 && byte != 0x1B)
        }
    }

    /// Ký tự đầu tiên khác khoảng trắng (bỏ BOM) là `<`: tệp XML hoặc HTML.
    static func looksLikeXML(_ data: Data) -> Bool {
        let head = decode(data.prefix(512)).text
        return head.first(where: { !$0.isWhitespace }) == "<"
    }
}

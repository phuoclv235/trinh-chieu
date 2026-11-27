import Foundation

/// Xử lý chữ tiếng Việt: gộp dấu để so khớp, chuẩn hoá để lưu trữ, tách từ truy vấn.
///
/// Mọi hàm là hàm thuần, an toàn gọi từ bất kỳ luồng nào.
public enum VietText {
    /// Gộp để so khớp: NFD, bỏ dấu kết hợp U+0300–U+036F, đ/Đ → d, chữ thường, gộp khoảng trắng liên tiếp
    /// thành một, bỏ khoảng trắng đầu cuối.
    ///
    /// "Nguyễn" → "nguyen", "ĐẤNG" → "dang", "Giăng 3:16" → "giang 3:16".
    public static func fold(_ s: String) -> String {
        fold(s, dropsPunctuation: false)
    }

    /// Như ``fold(_:)`` nhưng bỏ luôn dấu câu, ký hiệu và gạch nối (thay bằng khoảng trắng rồi gộp):
    /// "Sáng-thế Ký" → "sang the ky".
    public static func foldLoose(_ s: String) -> String {
        fold(s, dropsPunctuation: true)
    }

    /// Chuẩn hoá lưu trữ: NFC, thay CRLF/CR bằng LF, bỏ ký tự điều khiển trừ LF và TAB, bỏ BOM.
    public static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in s.unicodeScalars {
            let isCR = scalar == "\r"
            defer { previousWasCR = isCR }
            if isCR {
                out.append("\n")
            } else if scalar == "\n" {
                if !previousWasCR { out.append(scalar) }
            } else if scalar == "\t" {
                out.append(scalar)
            } else if scalar != byteOrderMark && scalar.properties.generalCategory != .control {
                out.append(scalar)
            }
        }
        return String(out).precomposedStringWithCanonicalMapping
    }

    /// Chia truy vấn thành các từ đã gộp bằng ``fold(_:)``, bỏ từ rỗng.
    public static func queryTerms(_ s: String) -> [String] {
        fold(s).split(separator: " ").map(String.init)
    }

    // MARK: - Nội bộ

    private static let byteOrderMark: Unicode.Scalar = "\u{FEFF}"
    private static let combiningMarks: ClosedRange<UInt32> = 0x0300...0x036F
    private static let lowercaseDStroke: Unicode.Scalar = "\u{0111}"  // đ

    private static func fold(_ s: String, dropsPunctuation: Bool) -> String {
        // Viết thường trước khi tách dấu: vài chữ hoa (như "İ") khi viết thường sinh thêm dấu kết hợp,
        // làm theo thứ tự này thì dấu đó cũng bị bỏ.
        let decomposed = s.lowercased().decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in decomposed.unicodeScalars {
            if combiningMarks.contains(scalar.value) { continue }
            if scalar.properties.isWhitespace || (dropsPunctuation && isPunctuationOrSymbol(scalar)) {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(scalar == lowercaseDStroke ? "d" : scalar)
        }
        return String(out)
    }

    private static func isPunctuationOrSymbol(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
            .initialPunctuation, .finalPunctuation, .otherPunctuation,
            .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }
}

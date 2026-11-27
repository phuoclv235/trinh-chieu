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

    /// So sánh hai chuỗi theo dạng đã gộp: cho cùng kết quả như so `fold(a)` với `fold(b)`, nhưng không cấp phát
    /// chuỗi mới khi cả hai chỉ gồm chữ Latin (có dấu hay không), số, dấu câu ASCII và khoảng trắng ASCII. Dùng để
    /// sắp xếp theo thứ tự chữ cái tiếng Việt ("Ân" trước "Ca", "Đấng" sau "Ca"), kể cả làm collation SQLite.
    public static func foldedCompare(_ a: String, _ b: String) -> ComparisonResult {
        var left = FoldedScalars(a.unicodeScalars)
        var right = FoldedScalars(b.unicodeScalars)
        while true {
            let l = left.next()
            let r = right.next()
            if left.unsupported || right.unsupported { break }
            switch (l, r) {
            case (nil, nil):
                return .orderedSame
            case (nil, _):
                return .orderedAscending
            case (_, nil):
                return .orderedDescending
            case let (l?, r?):
                if l != r { return l < r ? .orderedAscending : .orderedDescending }
            }
        }
        // Có ký tự ngoài bảng tra nhanh: gộp đầy đủ rồi so.
        let foldedA = fold(a)
        let foldedB = fold(b)
        if foldedA == foldedB { return .orderedSame }
        return foldedA < foldedB ? .orderedAscending : .orderedDescending
    }

    // MARK: - Nội bộ

    /// Bảng tra nhanh: chữ Latin có dấu (U+00C0–U+024F, U+1E00–U+1EFF) mà `fold` biến thành đúng một chữ ASCII.
    private static let latinFoldTable: [UInt32: UInt8] = {
        var table: [UInt32: UInt8] = [:]
        for range in [UInt32(0x00C0)...0x024F, 0x1E00...0x1EFF] {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let folded = Array(fold(String(scalar), dropsPunctuation: false).unicodeScalars)
                if folded.count == 1, folded[0].isASCII {
                    table[value] = UInt8(folded[0].value)
                }
            }
        }
        return table
    }()

    /// Dòng ký tự đã gộp của một chuỗi, sinh dần từng ký tự (ASCII), theo đúng quy tắc của `fold`: bỏ dấu kết hợp,
    /// viết thường, gộp khoảng trắng, bỏ khoảng trắng đầu cuối. Gặp ký tự ngoài bảng thì đặt `unsupported`.
    private struct FoldedScalars {
        private var iterator: String.UnicodeScalarView.Iterator
        private var emittedAny = false
        private var pendingSpace = false
        private var buffered: UInt8?
        private(set) var unsupported = false

        init(_ scalars: String.UnicodeScalarView) {
            iterator = scalars.makeIterator()
        }

        mutating func next() -> UInt8? {
            if let value = buffered {
                buffered = nil
                return value
            }
            while let scalar = iterator.next() {
                let value = scalar.value
                if VietText.combiningMarks.contains(value) { continue }
                let unit: UInt8
                if value < 0x80 {
                    if value == 0x20 || (0x09...0x0D).contains(value) {
                        pendingSpace = emittedAny
                        continue
                    }
                    unit = (0x41...0x5A).contains(value) ? UInt8(value + 0x20) : UInt8(value)
                } else if let mapped = VietText.latinFoldTable[value] {
                    unit = mapped
                } else {
                    unsupported = true
                    return nil
                }
                emittedAny = true
                if pendingSpace {
                    pendingSpace = false
                    buffered = unit
                    return 0x20
                }
                return unit
            }
            return nil
        }
    }

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

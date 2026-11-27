import Foundation

extension GroupLabel {
    /// Tên hiện cho người xem: "Câu 1", "Điệp khúc", "Cầu nối 2". Nhãn `custom` trả đúng chữ đã đặt.
    public var displayName: String {
        let base: String
        switch kind {
        case .verse:
            base = "Câu"
        case .chorus:
            base = "Điệp khúc"
        case .prechorus:
            base = "Tiền điệp khúc"
        case .bridge:
            base = "Cầu nối"
        case .tag:
            base = "Lặp cuối"
        case .intro:
            base = "Dạo đầu"
        case .ending:
            base = "Kết"
        case .custom:
            let text = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            base = text.isEmpty ? "Đoạn" : text
        }
        guard let number else {
            return base
        }
        return "\(base) \(number)"
    }
}

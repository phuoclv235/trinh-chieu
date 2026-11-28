import Foundation

extension Slide {
    /// Chỉ số của phần tử chữ chính: phần tử gắn ô `body`, không có thì phần tử chữ đầu tiên. `nil` khi trang không
    /// có phần tử chữ nào. Ô soạn lời và các thao tác tách, gộp trang chỉ đọc và sửa chữ của phần tử này.
    public var primaryTextIndex: Int? {
        var firstText: Int?
        for (index, element) in elements.enumerated() {
            guard case .text(let text) = element else { continue }
            if text.slot == .body { return index }
            if firstText == nil { firstText = index }
        }
        return firstText
    }

    /// Chữ của phần tử chữ chính; `nil` khi trang không có phần tử chữ.
    public var primaryText: String? {
        guard let index = primaryTextIndex, case .text(let text) = elements[index] else { return nil }
        return text.text
    }

    /// Đặt chữ cho phần tử chữ chính. Trang chưa có phần tử chữ thì thêm một phần tử ở ô `body`.
    public mutating func setPrimaryText(_ value: String) {
        guard let index = primaryTextIndex, case .text(var text) = elements[index] else {
            elements.append(.text(TextElement(slot: .body, text: value)))
            return
        }
        guard text.text != value else { return }
        text.text = value
        elements[index] = .text(text)
    }

    /// Bản sao có mã mới cho trang và mọi phần tử. Dùng khi nhân đôi hoặc tạo trang theo bố cục của trang khác.
    public func copyWithNewIDs() -> Slide {
        var copy = self
        copy.id = UUID()
        copy.elements = elements.map { $0.withNewID() }
        return copy
    }

    /// Trang trống theo bố cục của `template`: cùng phần tử và nền, mã mới, chữ chính rỗng, không ghi chú, không
    /// nhãn, đang bật. Không có mẫu thì một phần tử chữ ở ô `body`.
    public static func blank(like template: Slide?) -> Slide {
        guard let template else {
            return Slide(elements: [.text(TextElement(slot: .body, text: ""))])
        }
        var slide = template.copyWithNewIDs()
        slide.label = nil
        slide.notes = ""
        slide.enabled = true
        if slide.primaryTextIndex != nil {
            slide.setPrimaryText("")
        }
        return slide
    }
}

extension Element {
    /// Cùng phần tử với mã mới.
    public func withNewID() -> Element {
        switch self {
        case .text(var element):
            element.id = UUID()
            return .text(element)
        case .image(var element):
            element.id = UUID()
            return .image(element)
        case .video(var element):
            element.id = UUID()
            return .video(element)
        case .shape(var element):
            element.id = UUID()
            return .shape(element)
        }
    }
}

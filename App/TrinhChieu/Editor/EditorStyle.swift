import AppKit
import CoreModel
import SwiftUI

/// Màu đoạn: màu đặt riêng của đoạn, không thì theo loại đoạn (`--g-*` của mẫu).
enum GroupColors {
    static func color(kind: GroupLabelKind?, custom: RGBA?) -> Color {
        if let custom {
            return Color(
                .sRGB, red: Double(custom.red) / 255, green: Double(custom.green) / 255,
                blue: Double(custom.blue) / 255, opacity: Double(custom.alpha) / 255)
        }
        switch kind {
        case .verse: return Palette.groupVerse
        case .chorus, .prechorus: return Palette.groupChorus
        case .bridge: return Palette.groupBridge
        case .ending, .tag: return Palette.groupEnding
        case .intro: return Palette.groupIntro
        case .custom, nil: return Palette.text3
        }
    }

    static func color(_ group: SlideGroup) -> Color {
        color(kind: group.label.kind, custom: group.color)
    }

    /// Màu đặt được cho đoạn ("Đổi màu đoạn"): đúng bảng màu đoạn của giao diện tối, thêm xám đá. Không có cam đất
    /// (cam chỉ dành cho "đang lên màn").
    /// `name` là khoá chuỗi giao diện.
    static let choices: [(name: String, color: RGBA)] = [
        ("Blue", RGBA(red: 0x7F, green: 0x9E, blue: 0xD9)),
        ("Rose", RGBA(red: 0xD8, green: 0x8E, blue: 0xA2)),
        ("Violet", RGBA(red: 0xB9, green: 0xA3, blue: 0xE0)),
        ("Moss", RGBA(red: 0x98, green: 0xAD, blue: 0x6C)),
        ("Teal", RGBA(red: 0x6F, green: 0xC1, blue: 0xC9)),
        ("Slate", RGBA(red: 0x9A, green: 0xA3, blue: 0xB5)),
    ]
}

/// Hộp hỏi trước khi xoá: nút xoá đỏ, "Giữ lại" là nút mặc định (lỡ tay bấm Enter không xoá).
@MainActor enum DeleteConfirmation {
    static func ask(title: String, message: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let delete = alert.addButton(withTitle: confirm)
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        let keep = alert.addButton(withTitle: String(localized: "Keep"))
        keep.keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Dòng chữ nhỏ dùng trong trình soạn.
struct EditorCaption: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Typography.caption)
            .foregroundStyle(Palette.text3)
            .lineLimit(1)
    }
}

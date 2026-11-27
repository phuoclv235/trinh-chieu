import AppKit
import SwiftUI

/// Màu của hướng "Bàn trộn", chép đúng từ `design/tokens.css` (nguồn sự thật, xem `docs/ui-rules.md`).
/// Mỗi màu có bản tối và bản sáng; cửa sổ đổi sáng tối thì màu tự đổi theo.
enum Palette {
    static let bgWindow = dynamic(dark: 0x0E0F13, light: 0xEFEDEA)
    static let bgPanel = dynamic(dark: 0x121318, light: 0xF8F7F5)
    static let bgStage = dynamic(dark: 0x08090B, light: 0xE5E2DE)
    static let bgRaised = dynamic(dark: 0x1A1C22, light: 0xFFFFFF)
    static let bgHover = dynamic(dark: 0x22252C, light: 0xEBE8E4)
    static let bgPressed = dynamic(dark: 0x2A2D35, light: 0xE0DDD8)
    static let bgOverlay = dynamic(dark: 0x17191E, light: 0xFFFFFF)
    static let scrim = dynamic(dark: 0x030406, light: 0x141210, darkAlpha: 0.66, lightAlpha: 0.32)

    static let line = dynamic(dark: 0x23252C, light: 0xDCD8D3)
    static let lineStrong = dynamic(dark: 0x363944, light: 0xC9C4BE)

    static let text = dynamic(dark: 0xECEBE9, light: 0x17161A)
    static let text2 = dynamic(dark: 0xA7A6AA, light: 0x504E55)
    static let text3 = dynamic(dark: 0x8F8E94, light: 0x64616A)
    static let textDisabled = dynamic(dark: 0x5A5A61, light: 0xA9A5A0)

    /// Cam đất: nghĩa duy nhất là "đang hoạt động, đang lên màn".
    static let accent = dynamic(dark: 0xF0814A, light: 0x9E4317)
    static let onAccent = dynamic(dark: 0x1E0D03, light: 0xFFFFFF)
    static let accentSoft = dynamic(dark: 0xF0814A, light: 0x9E4317, darkAlpha: 0.13, lightAlpha: 0.1)
    static let accentLine = dynamic(dark: 0xF0814A, light: 0x9E4317, darkAlpha: 0.5, lightAlpha: 0.45)
    /// Quầng thở quanh thẻ đang lên màn (`--glow`).
    static let glow = dynamic(dark: 0xF0814A, light: 0x9E4317, darkAlpha: 0.32, lightAlpha: 0.25)

    /// Tập dượt: hồng sen.
    static let warn = dynamic(dark: 0xE6699D, light: 0xB3326B)
    static let warnSoft = dynamic(dark: 0xE6699D, light: 0xB3326B, darkAlpha: 0.14, lightAlpha: 0.1)
    /// Trễ giờ, mục thiếu tệp: vàng chanh.
    static let late = dynamic(dark: 0xE8CF55, light: 0x8A6D00)
    static let lateInk = dynamic(dark: 0x1A1600, light: 0xFFFFFF)
    /// Đóng băng: xanh băng.
    static let freeze = dynamic(dark: 0x8FD4F4, light: 0x1B78A3)
    static let freezeSoft = dynamic(dark: 0x8FD4F4, light: 0x1B78A3, darkAlpha: 0.13, lightAlpha: 0.1)
    static let danger = dynamic(dark: 0xF47272, light: 0xC22F2F)
    static let dangerFill = dynamic(dark: 0xC93A3A, light: 0xC22F2F)
    static let onDanger = dynamic(dark: 0xFFFFFF, light: 0xFFFFFF)
    /// Đúng giờ, khung hình đều.
    static let ok = dynamic(dark: 0x6FCF86, light: 0x1D7F45)

    /// Màu đoạn (`--g-*`): vạch dưới thẻ trang chiếu, chip thứ tự hát.
    static let groupVerse = dynamic(dark: 0x7F9ED9, light: 0x5F80C4)
    static let groupChorus = dynamic(dark: 0xD88EA2, light: 0xC46D85)
    static let groupBridge = dynamic(dark: 0xB9A3E0, light: 0x8A72C0)
    static let groupEnding = dynamic(dark: 0x98AD6C, light: 0x788F4B)
    static let groupIntro = dynamic(dark: 0x6FC1C9, light: 0x3F9AA3)

    /// Bản `NSColor` của một màu (cho lớp Core Animation).
    static func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }

    private static func dynamic(
        dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
            })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Cỡ, bo góc, khoảng cách của `design/tokens.css`.
enum Metrics {
    static let toolbarHeight: CGFloat = 52
    static let controlHeight: CGFloat = 30
    static let controlHeightSmall: CGFloat = 24
    static let railLeft: CGFloat = 288
    static let railRight: CGFloat = 320
    /// Bo góc điều khiển, thẻ trang chiếu, nút lớp.
    static let radius: CGFloat = 6
    /// Bo góc phiến chọn, nhóm biểu mẫu.
    static let radiusLarge: CGFloat = 8
    /// Bo góc hộp thoại, bảng lệnh.
    static let radiusPop: CGFloat = 10
    /// Chừa chỗ cho ba nút đỏ vàng xanh của cửa sổ.
    static let trafficLightInset: CGFloat = 80
}

/// Cỡ chữ của `docs/ui-rules.md`: 11, 12, 12.5 chữ nhỏ; 13 chữ thân; 15 tiêu đề khối; 16 tiêu đề cột; 26 tiêu đề nguồn.
enum Typography {
    static let small = Font.system(size: 11)
    static let caption = Font.system(size: 12)
    static let control = Font.system(size: 12.5)
    static let controlStrong = Font.system(size: 12.5, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let blockTitle = Font.system(size: 15, weight: .semibold)
    static let columnTitle = Font.system(size: 16, weight: .bold)
    static let sourceTitle = Font.system(size: 26, weight: .bold)
    /// Số, giờ, phím tắt: chữ số đều cột.
    static let numberSmall = Font.system(size: 11, design: .monospaced)
    static let number = Font.system(size: 12, design: .monospaced)
}

/// Hiệu ứng giao diện 120 đến 200 ms, đường cong `cubic-bezier(0.2, 0.8, 0.2, 1)`.
enum Motion {
    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16)
    }

    /// Một nhịp thở của đèn trạng thái (giây).
    static let breath: CFTimeInterval = 2.6
}

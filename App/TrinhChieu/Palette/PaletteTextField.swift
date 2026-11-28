import AppKit
import SwiftUI

/// Ô gõ của Bảng lệnh, viết bằng AppKit để chắc chắn nhận con trỏ ngay khi bảng hiện.
///
/// `@FocusState` của SwiftUI đặt trong `onAppear` của lớp phủ không lấy được con trỏ từ ô tìm của thư viện phía sau
/// (kiểm trên Mac 2026-11-28: chữ gõ rơi vào ô thư viện, `Esc` không đóng bảng). Ở đây ô tự làm first responder khi
/// vào cửa sổ, và một bộ nghe phím cục bộ giữ `↑ ↓ Enter Esc` cho Bảng lệnh dù con trỏ đang ở đâu; phím chữ gõ
/// khi con trỏ lạc chỗ thì kéo con trỏ về ô trước khi giao phím.
struct PaletteTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: @MainActor (Int) -> Void
    /// `true` là `⌘Enter`.
    let onSubmit: @MainActor (Bool) -> Void
    let onCancel: @MainActor () -> Void
    /// `false` khi dựng thử để làm ấm: không lấy con trỏ, không nghe phím.
    var isActive = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> PaletteNSTextField {
        let field = PaletteNSTextField()
        field.isActive = isActive
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isBezeled = false
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.font = .systemFont(ofSize: 15)
        field.textColor = Palette.nsColor(Palette.text)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: Palette.nsColor(Palette.text3), .font: NSFont.systemFont(ofSize: 15)])
        field.setAccessibilityLabel(placeholder)
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(field)
        return field
    }

    func updateNSView(_ field: PaletteNSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
            // Điền tên sách: đặt con trỏ cuối chữ để gõ tiếp chương câu.
            field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        configure(field)
    }

    static func dismantleNSView(_ field: PaletteNSTextField, coordinator: Coordinator) {
        field.stopMonitoring()
    }

    private func configure(_ field: PaletteNSTextField) {
        field.onMove = onMove
        field.onSubmit = onSubmit
        field.onCancel = onCancel
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// `NSTextField` tự lấy con trỏ khi vào cửa sổ và giữ các phím điều khiển của Bảng lệnh.
final class PaletteNSTextField: NSTextField {
    var onMove: (@MainActor (Int) -> Void)?
    var onSubmit: (@MainActor (Bool) -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var isActive = true
    private var monitor: Any?

    enum KeyCode {
        static let escape: UInt16 = 53
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window, isActive else { return }
        focus(in: window)
        // Lần vẽ đầu SwiftUI có thể đặt lại first responder: lấy lại sau vòng chạy kế tiếp.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.focus(in: window)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, flags: flags, windowNumber: windowNumber) ?? false
            }
            return consumed ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Con trỏ đang ở ô này (trình soạn chữ dùng chung của cửa sổ đang sửa ô này).
    var hasFocus: Bool {
        guard let editor = currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    private func focus(in window: NSWindow) {
        guard !hasFocus else { return }
        window.makeFirstResponder(self)
        currentEditor()?.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
    }

    /// Trả `true` khi phím đã dùng cho Bảng lệnh.
    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let window, window.windowNumber == windowNumber, window.attachedSheet == nil else { return false }
        let modifiers = flags.intersection([.command, .option, .control, .shift])
        // Bộ gõ tiếng Việt đang ghép chữ (chữ có gạch chân): Enter, Esc, mũi tên thuộc về bộ gõ.
        if hasFocus, let editor = currentEditor() as? NSTextView, editor.hasMarkedText() {
            return false
        }
        switch keyCode {
        case KeyCode.escape:
            onCancel?()
            return true
        case KeyCode.upArrow where modifiers.isEmpty:
            onMove?(-1)
            return true
        case KeyCode.downArrow where modifiers.isEmpty:
            onMove?(1)
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            onSubmit?(modifiers.contains(.command))
            return true
        default:
            // Phím chữ khi con trỏ lạc chỗ (ví dụ ô tìm thư viện): kéo con trỏ về ô này rồi để phím đi tiếp tới đây.
            if !modifiers.contains(.command) && !modifiers.contains(.control) {
                focus(in: window)
            }
            return false
        }
    }
}

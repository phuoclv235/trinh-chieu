import AppKit
import SwiftUI

/// Phím của chế độ Trực tiếp (đặc tả T1.8 mục 3, 4).
enum LiveKey: Equatable, Sendable {
    /// `→`, `Space`, `↓`, `PageDown`.
    case next
    /// `←`, `↑`, `PageUp`.
    case previous
    /// `Home`: trang đầu của nguồn đang xem.
    case first
    /// `F1`.
    case clearAll
    /// `F2`.
    case clearText
    /// `F3`.
    case clearBackground
    /// `F4`.
    case clearAudio
    /// `⌘Z` ngoài ô nhập chữ.
    case undo
    /// `⇧⌘Z` ngoài ô nhập chữ.
    case redo
    /// `⌫`, `⌦`: bỏ mục đang chọn khỏi chương trình buổi nhóm.
    case delete
}

enum LiveKeyMap {
    // Mã phím vật lý của bàn phím Mac (Carbon `kVK_*`).
    static let rightArrow: UInt16 = 124
    static let leftArrow: UInt16 = 123
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let space: UInt16 = 49
    static let pageDown: UInt16 = 121
    static let pageUp: UInt16 = 116
    static let home: UInt16 = 115
    static let f1: UInt16 = 122
    static let f2: UInt16 = 120
    static let f3: UInt16 = 99
    static let f4: UInt16 = 118
    static let z: UInt16 = 6
    static let backspace: UInt16 = 51
    static let forwardDelete: UInt16 = 117

    /// Phím ứng với một lần bấm. Bỏ qua cờ `fn` và bàn phím số: `F2` gõ thẳng hay giữ `fn` đều là `F2`
    /// (máy đặt phím F làm phím đặc biệt thì phải giữ `fn`).
    static func key(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> LiveKey? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])
        if relevant == .command, keyCode == z {
            return .undo
        }
        if relevant == [.command, .shift], keyCode == z {
            return .redo
        }
        guard relevant.isEmpty else { return nil }
        switch keyCode {
        case rightArrow, space, downArrow, pageDown: return .next
        case leftArrow, upArrow, pageUp: return .previous
        case home: return .first
        case f1: return .clearAll
        case f2: return .clearText
        case f3: return .clearBackground
        case f4: return .clearAudio
        case backspace, forwardDelete: return .delete
        default: return nil
        }
    }
}

/// Nghe phím cho cả cửa sổ chính khi đang ở chế độ Trực tiếp. Phím chỉ có tác dụng khi cửa sổ chính đang nhận
/// phím và con trỏ gõ không nằm trong ô nhập chữ; phím đã dùng thì không đi tiếp (không kêu "bíp").
struct LiveKeyMonitor: NSViewRepresentable {
    /// Trả `true` khi đã xử lý phím.
    let handler: @MainActor (LiveKey) -> Bool

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: KeyMonitorView, context: Context) {
        view.handler = handler
    }

    static func dismantleNSView(_ view: KeyMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class KeyMonitorView: NSView {
    var handler: (@MainActor (LiveKey) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
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

    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int) -> Bool {
        guard let window, window.isKeyWindow, window.windowNumber == windowNumber, window.attachedSheet == nil else {
            return false
        }
        if let text = window.firstResponder as? NSTextView, text.isEditable {
            return false
        }
        guard let key = LiveKeyMap.key(keyCode: keyCode, modifiers: flags), let handler else { return false }
        return handler(key)
    }
}

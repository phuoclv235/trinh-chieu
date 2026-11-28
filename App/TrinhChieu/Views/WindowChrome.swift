import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Đặt kiểu cửa sổ chính: thanh tiêu đề trong suốt, nội dung tràn lên vùng tiêu đề, thanh công cụ rỗng kiểu unified
/// để ba nút đỏ vàng xanh nằm giữa thanh công cụ tự vẽ cao 52 điểm (mẫu `design/live.html`).
struct WindowConfigurator: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> ConfiguringView {
        let view = ConfiguringView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ConfiguringView, context: Context) {
        view.onWindow = onWindow
    }

    final class ConfiguringView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            if window.toolbar == nil {
                window.toolbar = NSToolbar(identifier: "app.trinhchieu.main")
            }
            window.toolbarStyle = .unified
            window.tabbingMode = .disallowed
            onWindow?(window)
        }
    }
}

/// Vùng kéo cửa sổ: kéo để di chuyển, bấm đúp để phóng to như thanh tiêu đề thật.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/// Hộp chọn thư mục và tệp của macOS.
@MainActor enum FilePicker {
    static func folder(message: String, prompt: String, startingAt directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func files(message: String, prompt: String, types: [UTType]) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = types
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

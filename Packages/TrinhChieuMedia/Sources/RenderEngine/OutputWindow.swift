import AppKit
import Metal
import QuartzCore

/// Cửa sổ đầu ra: không viền, phủ kín một màn hình, nằm trên mọi cửa sổ khác, ẩn con trỏ khi rê vào.
@MainActor
public final class OutputWindow {
    public let screen: NSScreen
    public let window: NSWindow
    public let metalLayer: CAMetalLayer
    private let contentView: OutputContentView

    public init(screen: NSScreen, device: any MTLDevice) {
        self.screen = screen

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 3
        layer.isOpaque = true
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.contentsScale = screen.backingScaleFactor
        layer.drawableSize = CGSize(
            width: screen.frame.width * screen.backingScaleFactor,
            height: screen.frame.height * screen.backingScaleFactor
        )
        self.metalLayer = layer

        let window = OutputNSWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "TrinhChieu Output"

        let view = OutputContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        // View "layer-hosting": gán layer trước rồi mới bật wantsLayer.
        view.layer = layer
        view.wantsLayer = true
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        self.contentView = view
        self.window = window
    }

    /// Kích thước drawable theo điểm ảnh.
    public var pixelSize: CGSize { metalLayer.drawableSize }

    /// Tần số tối đa của màn hình (Hz).
    public var maximumFramesPerSecond: Int { screen.maximumFramesPerSecond }

    public func show() {
        window.orderFrontRegardless()
    }

    public func close() {
        contentView.releaseCursor()
        window.orderOut(nil)
        window.close()
    }
}

/// Cửa sổ không viền mặc định không nhận phím; cho phép để bắt phím Esc khi thử nghiệm.
private final class OutputNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class OutputContentView: NSView {
    private var cursorHidden = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override func mouseEntered(with event: NSEvent) {
        guard !cursorHidden else { return }
        NSCursor.hide()
        cursorHidden = true
    }

    override func mouseExited(with event: NSEvent) {
        releaseCursor()
    }

    func releaseCursor() {
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }
}

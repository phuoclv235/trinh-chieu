import AppKit
import CoreGraphics
import Metal
import QuartzCore
import RenderEngine

/// Cửa sổ nhỏ "giữ nhịp" trên một màn không phải đầu ra (giống lớp xem trước của giao diện điều khiển):
/// cửa sổ thường, không che màn, có `CAMetalLayer` và `FrameLoop` riêng, vẽ nội dung đổi mỗi khung.
/// Dùng để thử xem một lớp Metal chạy theo nhịp trên màn điều khiển có giúp màn đầu ra hết rớt khung không.
@MainActor
final class KeeperWindow {
    let window: NSWindow
    let loop: FrameLoop

    init(screen: NSScreen, gpu: GPUContext, compositor: Compositor, logo: any MTLTexture, frameRate: Float?) {
        let size = NSSize(width: 320, height: 180)
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.maxX - size.width - 40, y: visible.minY + 40)
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Giữ nhịp"
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let layer = CAMetalLayer()
        layer.device = gpu.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 3
        layer.isOpaque = true
        layer.contentsScale = screen.backingScaleFactor
        layer.drawableSize = CGSize(
            width: size.width * screen.backingScaleFactor,
            height: size.height * screen.backingScaleFactor
        )
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.layer = layer
        view.wantsLayer = true
        window.contentView = view
        window.setFrame(window.frameRect(forContentRect: NSRect(origin: origin, size: size)), display: false)
        self.window = window

        let screenRate = Float(max(1, screen.maximumFramesPerSecond))
        let rate = min(screenRate, frameRate ?? screenRate)
        self.loop = FrameLoop(
            label: "giu-nhip",
            layer: layer,
            gpu: gpu,
            renderer: KeeperRenderer(compositor: compositor, logo: logo),
            stats: FrameStats(label: "giu-nhip", nominalPeriod: 1 / Double(rate)),
            preferredFrameRate: rate,
            frameLatency: 1,
            commandQueue: gpu.device.makeCommandQueue()
        )
    }

    func show() {
        window.orderFrontRegardless()
        loop.start()
    }

    func close() {
        loop.stop()
        window.orderOut(nil)
        window.close()
    }
}

/// Vẽ logo chạy ngang để mỗi khung đều khác khung trước.
private final class KeeperRenderer: FrameRenderer, @unchecked Sendable {
    private let compositor: Compositor
    private let logo: any MTLTexture

    init(compositor: Compositor, logo: any MTLTexture) {
        self.compositor = compositor
        self.logo = logo
    }

    func encodeFrame(_ frame: FrameContext) -> FrameOutcome {
        let target = frame.targetSize
        let side = target.height * 0.5
        let phase = frame.targetPresentationTime.truncatingRemainder(dividingBy: 2) / 2
        let x = (target.width - side) * phase
        compositor.drawQuad(
            frame.encoder,
            texture: logo,
            rect: CGRect(x: x, y: (target.height - side) / 2, width: side, height: side),
            targetSize: target
        )
        return FrameOutcome()
    }
}

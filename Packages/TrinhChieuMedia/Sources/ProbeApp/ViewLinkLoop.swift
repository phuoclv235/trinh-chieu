import AppKit
import Metal
import QuartzCore
import RenderEngine

/// Vòng vẽ mà bản thử điều khiển: bắt đầu, dừng, đọc số đo.
@MainActor
protocol ProbeLoop: AnyObject {
    var stats: FrameStats { get }
    func start()
    func stop()
}

extension FrameLoop: ProbeLoop {}

/// Biến thể chỉ để so sánh (không đưa vào RenderEngine): `CADisplayLink` của NSView chạy trên luồng chính,
/// lấy drawable bằng `CAMetalLayer.nextDrawable()` thay vì `CAMetalDisplayLink`.
/// Đo cùng các mốc như `FrameLoop`; `targetTimestamp` của display link đóng vai `targetPresentationTimestamp`.
@MainActor
final class ViewLinkLoop: NSObject, ProbeLoop {
    let stats: FrameStats

    private let label: String
    private let window: OutputWindow
    private let gpu: GPUContext
    private let renderer: any FrameRenderer
    private let preferredFrameRate: Float
    private var displayLink: CADisplayLink?

    init(
        label: String,
        window: OutputWindow,
        gpu: GPUContext,
        renderer: any FrameRenderer,
        stats: FrameStats,
        preferredFrameRate: Float
    ) {
        self.label = label
        self.window = window
        self.gpu = gpu
        self.renderer = renderer
        self.stats = stats
        self.preferredFrameRate = preferredFrameRate
        super.init()
    }

    func start() {
        guard displayLink == nil, let view = window.window.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: preferredFrameRate,
            maximum: preferredFrameRate,
            preferred: preferredFrameRate
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let callbackTime = CACurrentMediaTime()
        let targetTime = link.targetTimestamp
        guard let drawable = window.metalLayer.nextDrawable(),
            let commandBuffer = gpu.commandQueue.makeCommandBuffer()
        else { return }
        commandBuffer.label = "ViewLinkFrame.\(label)"
        let texture = drawable.texture

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let outcome = renderer.encodeFrame(
            FrameContext(
                encoder: encoder,
                targetSize: CGSize(width: texture.width, height: texture.height),
                targetPresentationTime: targetTime
            )
        )
        encoder.endEncoding()
        let encodeEnd = CACurrentMediaTime()

        Self.attachHandlers(
            drawable: drawable,
            commandBuffer: commandBuffer,
            stats: stats,
            callbackTime: callbackTime,
            targetTime: targetTime,
            outcome: outcome
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
        stats.recordCallback(start: callbackTime, encodeEnd: encodeEnd, end: CACurrentMediaTime())
    }

    /// Gắn handler ngoài main actor: Metal gọi chúng trên luồng của nó, nên closure không được mang cách ly
    /// `@MainActor` (Swift 6 sẽ kiểm cách ly lúc chạy và dừng chương trình).
    nonisolated private static func attachHandlers(
        drawable: any CAMetalDrawable,
        commandBuffer: any MTLCommandBuffer,
        stats: FrameStats,
        callbackTime: Double,
        targetTime: Double,
        outcome: FrameOutcome
    ) {
        let postedAt = outcome.newScenePostedAt
        drawable.addPresentedHandler { presented in
            let presentedTime = presented.presentedTime
            stats.recordPresented(presentedTime, now: CACurrentMediaTime())
            stats.recordFrameTiming(callback: callbackTime, target: targetTime, presented: presentedTime)
            if let postedAt, presentedTime > 0 {
                stats.recordSceneLatency(presentedTime - postedAt)
            }
        }
        let retained = outcome.retainedResources
        commandBuffer.addCompletedHandler { buffer in
            stats.recordGPUTime(buffer.gpuEndTime - buffer.gpuStartTime)
            withExtendedLifetime(retained) {}
        }
    }
}

import Foundation
import Metal
import QuartzCore
import os

/// Bọc một giá trị không `Sendable` để chuyển qua ranh giới luồng khi chắc chắn chỉ một bên dùng tại một lúc.
public struct UncheckedSendableBox<Value>: @unchecked Sendable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}

/// Thông tin của một khung đang dựng, chỉ dùng trong lúc gọi `FrameRenderer.encodeFrame`.
public struct FrameContext {
    public let encoder: any MTLRenderCommandEncoder
    public let targetSize: CGSize
    /// Thời điểm (theo `CACurrentMediaTime`) khung này dự kiến lên màn.
    public let targetPresentationTime: CFTimeInterval
}

/// Kết quả dựng một khung.
public struct FrameOutcome: Sendable {
    /// Có giá trị khi khung này là khung đầu tiên chứa một cảnh mới: thời điểm cảnh được gửi.
    public var newScenePostedAt: CFTimeInterval?
    /// Tài nguyên phải giữ sống tới khi GPU dựng xong (ví dụ `CVMetalTexture` của khung video).
    public var retainedResources: UncheckedSendableBox<[AnyObject]>?

    public init(newScenePostedAt: CFTimeInterval? = nil, retainedResources: [AnyObject] = []) {
        self.newScenePostedAt = newScenePostedAt
        self.retainedResources = retainedResources.isEmpty ? nil : UncheckedSendableBox(retainedResources)
    }
}

/// Bên vẽ nội dung cho một đầu ra. Chỉ được gọi trên luồng vẽ của đầu ra đó.
public protocol FrameRenderer: AnyObject, Sendable {
    func encodeFrame(_ frame: FrameContext) -> FrameOutcome
}

/// Vòng vẽ của một đầu ra: một `CAMetalDisplayLink` chạy trên luồng riêng ưu tiên cao.
///
/// Mỗi khung: hỏi `FrameRenderer` vẽ vào drawable, đo thời gian GPU, đếm khung rớt bằng `presentedTime`,
/// và đo độ trễ từ lúc gửi cảnh tới khi khung đầu tiên chứa cảnh đó lên màn.
public final class FrameLoop: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    public let label: String
    public let stats: FrameStats

    private let layer: CAMetalLayer
    private let gpu: GPUContext
    private let renderer: any FrameRenderer
    private let preferredFrameRate: Float
    private let frameLatency: Int
    private let logger = Logger(subsystem: "app.trinhchieu.RenderEngine", category: "FrameLoop")

    private let stopped = OSAllocatedUnfairLock(initialState: false)
    private let finished = DispatchSemaphore(value: 0)
    private var thread: Thread?
    /// Chỉ đọc ghi trên luồng vẽ.
    private var displayLink: CAMetalDisplayLink?

    /// - Parameters:
    ///   - preferredFrameRate: tần số khung mong muốn, ví dụ 60.
    ///   - frameLatency: số khung giữa lúc dựng và lúc lên màn (1 hoặc 2). Càng nhỏ độ trễ càng thấp.
    public init(
        label: String,
        layer: CAMetalLayer,
        gpu: GPUContext,
        renderer: any FrameRenderer,
        stats: FrameStats,
        preferredFrameRate: Float = 60,
        frameLatency: Int = 1
    ) {
        self.label = label
        self.layer = layer
        self.gpu = gpu
        self.renderer = renderer
        self.stats = stats
        self.preferredFrameRate = preferredFrameRate
        self.frameLatency = frameLatency
        super.init()
    }

    /// Bắt đầu vòng vẽ trên luồng riêng.
    public func start() {
        guard thread == nil else { return }
        let thread = Thread { [self] in
            runLoopBody()
        }
        thread.name = "TrinhChieu.FrameLoop.\(label)"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// Dừng vòng vẽ và chờ luồng vẽ thoát (tối đa 1 giây).
    public func stop() {
        let wasStopped = stopped.withLock { value in
            let old = value
            value = true
            return old
        }
        guard !wasStopped, thread != nil else { return }
        _ = finished.wait(timeout: .now() + 1)
    }

    private func runLoopBody() {
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: preferredFrameRate,
            maximum: preferredFrameRate,
            preferred: preferredFrameRate
        )
        link.preferredFrameLatency = Float(frameLatency)
        link.add(to: .current, forMode: .default)
        displayLink = link
        logger.info("Bắt đầu vòng vẽ \(self.label, privacy: .public)")

        while !stopped.withLock({ $0 }) {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }

        link.invalidate()
        displayLink = nil
        logger.info("Dừng vòng vẽ \(self.label, privacy: .public)")
        finished.signal()
    }

    public func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let callbackTime = CACurrentMediaTime()
        let targetTime = update.targetPresentationTimestamp
        let drawable = update.drawable
        let texture = drawable.texture
        guard let commandBuffer = gpu.commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Frame.\(label)"

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

        let stats = stats
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
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

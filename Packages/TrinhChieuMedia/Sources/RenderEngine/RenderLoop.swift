import CoreModel
import Foundation
import Metal
import QuartzCore
import os

/// Vòng vẽ của một đầu ra (hoặc một bản xem trước) của `RenderEngine`.
///
/// Một `CAMetalDisplayLink` trên luồng riêng ưu tiên cao, chạy theo tần số gốc của màn đang chứa lớp.
/// Mỗi đầu ra có `MTLCommandQueue` riêng (cùng `MTLDevice`) và bộ trộn lớp riêng. Chỉ vẽ và present trong
/// nhịp display link. Mỗi khung lấy cảnh mới nhất của vai từ hộp thư; chưa có cảnh thì tô đen.
final class RenderLoop: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    let label: String
    let role: OutputRole
    let stats: FrameStats

    private let layer: CAMetalLayer
    private let commandQueue: any MTLCommandQueue
    private let compositor: LayerCompositor
    private let mailbox: SceneMailbox<RenderScene>
    private let frameRate: Float
    private let logger = Logger(subsystem: "app.trinhchieu.RenderEngine", category: "RenderLoop")

    private let stopped = OSAllocatedUnfairLock(initialState: false)
    private let finished = DispatchSemaphore(value: 0)
    private var thread: Thread?
    /// Chỉ đọc ghi trên luồng vẽ.
    private var lastRevision: UInt64 = 0

    /// - Parameters:
    ///   - frameRate: tần số display link (tần số gốc của màn cho đầu ra; 15 cho bản xem trước).
    ///   - audible: đầu ra thật thì `true`; bản xem trước thì `false` để không làm video phát tiếng.
    init(
        label: String,
        role: OutputRole,
        layer: CAMetalLayer,
        gpu: GPUContext,
        pipelines: Compositor,
        cache: TextureCache,
        video: any VideoFrameProvider,
        mailbox: SceneMailbox<RenderScene>,
        frameRate: Float,
        audible: Bool
    ) throws {
        guard let queue = gpu.device.makeCommandQueue() else {
            throw RenderEngineError.commandQueueUnavailable
        }
        queue.label = "TrinhChieu.\(label)"
        self.label = label
        self.role = role
        self.layer = layer
        commandQueue = queue
        compositor = LayerCompositor(
            gpu: gpu,
            pipelines: pipelines,
            cache: cache,
            blocking: false,
            video: video,
            consumer: VideoConsumer(role: role, audible: audible)
        )
        self.mailbox = mailbox
        self.frameRate = max(1, frameRate)
        stats = FrameStats(label: label, nominalPeriod: 1 / Double(max(1, frameRate)))
        super.init()
    }

    /// Bắt đầu vòng vẽ trên luồng riêng.
    func start() {
        guard thread == nil else { return }
        stats.startRecording(at: CACurrentMediaTime())
        let thread = Thread { [self] in
            runLoopBody()
        }
        thread.name = "TrinhChieu.RenderLoop.\(label)"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// Dừng vòng vẽ và chờ luồng vẽ thoát (tối đa 1 giây).
    func stop() {
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
        link.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        link.preferredFrameLatency = 1
        link.add(to: .current, forMode: .default)
        logger.info("Bắt đầu vòng vẽ \(self.label, privacy: .public)")
        while !stopped.withLock({ $0 }) {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        link.invalidate()
        logger.info("Dừng vòng vẽ \(self.label, privacy: .public)")
        finished.signal()
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let callbackTime = CACurrentMediaTime()
        let targetTime = update.targetPresentationTimestamp
        let drawable = update.drawable
        let texture = drawable.texture
        let targetSize = CGSize(width: texture.width, height: texture.height)

        var postedAt: CFTimeInterval?
        if let entry = mailbox.latest() {
            if entry.revision != lastRevision {
                lastRevision = entry.revision
                postedAt = entry.postedAt
            }
            // Gọi mỗi khung: lớp nào chưa dựng xong (chữ, ảnh, khung video đầu) được thử lại, lớp cũ giữ nguyên.
            compositor.update(scene: entry.scene, targetSize: targetSize, time: targetTime)
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Frame.\(label)"
        compositor.encode(into: commandBuffer, target: texture, time: targetTime)
        let encodeEnd = CACurrentMediaTime()

        let stats = stats
        drawable.addPresentedHandler { presented in
            let presentedTime = presented.presentedTime
            stats.recordPresented(presentedTime, now: CACurrentMediaTime())
            stats.recordFrameTiming(callback: callbackTime, target: targetTime, presented: presentedTime)
            if let postedAt, presentedTime > 0 {
                stats.recordSceneLatency(presentedTime - postedAt)
            }
        }
        commandBuffer.addCompletedHandler { buffer in
            stats.recordGPUTime(buffer.gpuEndTime - buffer.gpuStartTime)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        stats.recordCallback(start: callbackTime, encodeEnd: encodeEnd, end: CACurrentMediaTime())
    }

    /// Số đo của chu kỳ vừa qua, rồi bắt đầu chu kỳ mới (để bộ đếm không phình theo thời gian chạy).
    func takeStatistics(id: OutputID, now: CFTimeInterval) -> OutputStatistics {
        let snapshot = stats.snapshot(now: now)
        stats.startRecording(at: now)
        return OutputStatistics(
            id: id,
            role: role,
            refreshRate: Double(frameRate),
            framesPresented: snapshot.framesPresented,
            droppedFrames: snapshot.droppedFrames,
            gpuTimeP95: Percentile.value(snapshot.gpuTimes, 0.95),
            pipelineLatencyP99: Percentile.value(snapshot.pipelineLatencies, 0.99)
        )
    }
}

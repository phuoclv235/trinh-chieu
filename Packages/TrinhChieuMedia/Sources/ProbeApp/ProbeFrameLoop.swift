import Darwin
import Foundation
import Metal
import QuartzCore
import RenderEngine
import os

/// Nhu cầu vẽ của một nhịp khi vẽ theo nhu cầu (B1).
enum FrameDemand: Sendable, Equatable {
    /// Có gì mới: dựng và present.
    case render
    /// Chưa có gì mới nhưng sắp có (video đang phát, chữ chưa dựng xong): bỏ nhịp này, display link chạy tiếp.
    case skip
    /// Cảnh đứng yên: cho display link nghỉ tới khi có cảnh mới.
    case idle
}

/// Bên vẽ của bản thử T0.6: như `FrameRenderer`, thêm câu hỏi "nhịp này có cần vẽ không".
protocol ProbeFrameRenderer: FrameRenderer {
    func demand(at targetTime: CFTimeInterval) -> FrameDemand
}

/// Các cờ thử của vòng vẽ T0.6.
struct ProbeLoopConfig: Sendable {
    var preferredFrameRate: Float
    var frameLatency: Int
    /// B1: chỉ dựng và present khi có gì mới; cảnh đứng yên thì cho display link nghỉ.
    var onDemand = false
    /// B1 khi cảnh đứng yên: `true` cho display link nghỉ (`isPaused`), `false` để link chạy tiếp và chỉ bỏ nhịp.
    var idlePause = true
    /// B1 khi cảnh đứng yên: số dương n thì cứ n nhịp present lại một khung giống hệt (giữ đường trình chiếu
    /// "ấm"), display link không nghỉ. 0 là tắt.
    var idleKeepAliveEvery = 0
    /// B2: luồng vẽ theo chính sách thời gian thực của Mach.
    var realtime = false
    /// B5: tạo lại display link ở lần đổi cảnh kế tiếp khi đường ống dài ra.
    var recover = false
}

/// Vòng vẽ thử nghiệm của T0.6 (chỉ ở ProbeApp, không đưa vào RenderEngine). Khi tắt mọi cờ, làm đúng như
/// `FrameLoop` của RenderEngine: một `CAMetalDisplayLink` trên luồng riêng, mỗi nhịp dựng một khung.
/// Ghi số đo vào `FrameStats` (như `FrameLoop`) và `LoadStats` (khung rớt tính được cả khi vẽ theo nhu cầu).
final class ProbeFrameLoop: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    let label: String
    let stats: FrameStats
    let loadStats: LoadStats

    private let layer: CAMetalLayer
    private let commandQueue: any MTLCommandQueue
    private let renderer: any ProbeFrameRenderer
    private let config: ProbeLoopConfig
    private let logger = Logger(subsystem: "app.trinhchieu.ProbeApp", category: "ProbeFrameLoop")

    private let stopped = OSAllocatedUnfairLock(initialState: false)
    private let finished = DispatchSemaphore(value: 0)
    /// Run loop của luồng vẽ, để luồng chính đánh thức display link đang nghỉ.
    private let renderRunLoop = OSAllocatedUnfairLock<UncheckedSendableBox<CFRunLoop>?>(initialState: nil)
    /// Kết quả đặt chính sách thời gian thực (B2), đọc từ luồng chính khi lập báo cáo.
    private let realtimeResult = OSAllocatedUnfairLock<String?>(initialState: nil)
    private var thread: Thread?

    // Chỉ đọc ghi trên luồng vẽ.
    private var displayLink: CAMetalDisplayLink?
    private var paused = false
    /// Lần gọi vẽ kế tiếp là lần đầu sau lúc nghỉ hoặc sau khi tạo lại display link.
    private var discontinuity = true
    private var resumedFromIdle = false
    private var previousTarget: Double = 0
    private var recentCallToTarget: [Double] = []
    private var recoverArmed = false
    private var idleTicks = 0
    /// Cảnh mới nằm trong một khung không lên màn: chuyển thời điểm gửi sang khung lên màn kế tiếp, vì đó mới là
    /// lúc khán giả thấy cảnh mới. Chỉ handler `presented` (theo thứ tự khung) đọc ghi.
    private let carriedScene = OSAllocatedUnfairLock<CarriedScene?>(initialState: nil)

    private struct CarriedScene: Sendable {
        var postedAt: Double
        var afterIdle: Bool
    }

    init(
        label: String,
        layer: CAMetalLayer,
        commandQueue: any MTLCommandQueue,
        renderer: any ProbeFrameRenderer,
        stats: FrameStats,
        config: ProbeLoopConfig
    ) {
        self.label = label
        self.layer = layer
        self.commandQueue = commandQueue
        self.renderer = renderer
        self.stats = stats
        self.loadStats = LoadStats(nominalPeriod: stats.nominalPeriod)
        self.config = config
        super.init()
    }

    /// "đã đặt", "lỗi <mã>" hoặc `nil` khi không bật B2.
    var realtimeStatus: String? {
        realtimeResult.withLock { $0 }
    }

    func start() {
        guard thread == nil else { return }
        let thread = Thread { [self] in
            runLoopBody()
        }
        thread.name = "TrinhChieu.ProbeFrameLoop.\(label)"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        let wasStopped = stopped.withLock { value in
            let old = value
            value = true
            return old
        }
        guard !wasStopped, thread != nil else { return }
        wake()
        _ = finished.wait(timeout: .now() + 1)
    }

    /// Gọi sau khi gửi cảnh mới: nếu display link đang nghỉ (B1) thì cho chạy lại. An toàn từ mọi luồng.
    func wake() {
        guard config.onDemand, let box = renderRunLoop.withLock({ $0 }) else { return }
        let runLoop = box.value
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            resumeIfPaused()
        }
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - Luồng vẽ

    private func runLoopBody() {
        if config.realtime {
            let status = Self.applyTimeConstraintPolicy(period: 1 / Double(max(1, config.preferredFrameRate)))
            realtimeResult.withLock { $0 = status }
            logger.info("Chính sách thời gian thực \(self.label, privacy: .public): \(status, privacy: .public)")
        }
        renderRunLoop.withLock { $0 = UncheckedSendableBox(CFRunLoopGetCurrent()) }
        installDisplayLink()
        logger.info("Bắt đầu vòng vẽ thử \(self.label, privacy: .public)")

        while !stopped.withLock({ $0 }) {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }

        displayLink?.invalidate()
        displayLink = nil
        renderRunLoop.withLock { $0 = nil }
        finished.signal()
    }

    private func installDisplayLink() {
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        let rate = config.preferredFrameRate
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        link.preferredFrameLatency = Float(config.frameLatency)
        link.add(to: .current, forMode: .default)
        displayLink = link
        discontinuity = true
        recentCallToTarget.removeAll(keepingCapacity: true)
    }

    private func resumeIfPaused() {
        guard paused, let displayLink else { return }
        paused = false
        resumedFromIdle = true
        discontinuity = true
        loadStats.recordResume(at: CACurrentMediaTime())
        displayLink.isPaused = false
    }

    private func pause(_ link: CAMetalDisplayLink) {
        paused = true
        link.isPaused = true
        loadStats.recordPause(at: CACurrentMediaTime())
    }

    /// B5: tạo lại display link (gọi qua run loop, không gọi bên trong lần gọi vẽ của link cũ).
    private func recreateDisplayLink() {
        guard !stopped.withLock({ $0 }) else { return }
        displayLink?.invalidate()
        displayLink = nil
        installDisplayLink()
        if paused {
            displayLink?.isPaused = true
        }
        loadStats.recordRecovery(at: CACurrentMediaTime())
        logger.info("Tạo lại display link \(self.label, privacy: .public)")
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let callbackTime = CACurrentMediaTime()
        let targetTime = update.targetPresentationTimestamp
        loadStats.recordTick(target: targetTime, previousTarget: previousTarget, continuous: !discontinuity)
        previousTarget = targetTime
        discontinuity = false
        let afterIdle = resumedFromIdle
        resumedFromIdle = false

        if config.onDemand {
            switch renderer.demand(at: targetTime) {
            case .render:
                idleTicks = 0
            case .skip:
                loadStats.recordSkip()
                return
            case .idle where config.idleKeepAliveEvery > 0:
                idleTicks += 1
                guard idleTicks % config.idleKeepAliveEvery == 0 else {
                    loadStats.recordSkip()
                    return
                }
            case .idle:
                loadStats.recordSkip()
                if config.idlePause {
                    pause(link)
                }
                return
            }
        }

        let drawable = update.drawable
        let texture = drawable.texture
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "ProbeFrame.\(label)"
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
        loadStats.recordRendered()

        let stats = stats
        let loadStats = loadStats
        let continuous = !config.onDemand
        let postedAt = outcome.newScenePostedAt
        let carriedScene = carriedScene
        drawable.addPresentedHandler { presented in
            let presentedTime = presented.presentedTime
            let now = CACurrentMediaTime()
            // Vẽ theo nhu cầu có khoảng nghỉ có chủ ý: chỉ `LoadStats` đếm khung rớt đúng trong trường hợp đó.
            if continuous {
                stats.recordPresented(presentedTime, now: now)
            }
            loadStats.recordPresented(presentedTime, target: targetTime, now: now)
            stats.recordFrameTiming(callback: callbackTime, target: targetTime, presented: presentedTime)
            if presentedTime <= 0 {
                if let postedAt {
                    carriedScene.withLock { carried in
                        if carried == nil {
                            carried = CarriedScene(postedAt: postedAt, afterIdle: afterIdle)
                        }
                    }
                }
                return
            }
            let carried = carriedScene.withLock { carried in
                let value = carried
                carried = nil
                return value
            }
            // Cảnh của chính khung này mới hơn cảnh mang sang (cảnh mang sang chưa từng hiện, đã bị thay).
            guard let sceneTime = postedAt ?? carried?.postedAt else { return }
            stats.recordSceneLatency(presentedTime - sceneTime)
            if afterIdle || carried?.afterIdle == true {
                loadStats.recordFirstAfterIdle(presentedTime - sceneTime)
            }
        }
        let retained = outcome.retainedResources
        commandBuffer.addCompletedHandler { buffer in
            stats.recordGPUTime(buffer.gpuEndTime - buffer.gpuStartTime)
            withExtendedLifetime(retained) {}
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        stats.recordCallback(start: callbackTime, encodeEnd: encodeEnd, end: CACurrentMediaTime())

        if config.recover {
            checkRecovery(callToTarget: targetTime - callbackTime, newScene: postedAt != nil)
        }
    }

    /// B5: trung vị "gọi tới đích" của 60 khung gần nhất vượt 2.5 chu kỳ thì hẹn tạo lại display link
    /// ở lần đổi cảnh kế tiếp (lúc đó khán giả đang nhìn cảnh chuyển, một nhịp lệch khó thấy hơn).
    private func checkRecovery(callToTarget: Double, newScene: Bool) {
        recentCallToTarget.append(callToTarget)
        if recentCallToTarget.count > 60 {
            recentCallToTarget.removeFirst(recentCallToTarget.count - 60)
        }
        if !recoverArmed, recentCallToTarget.count == 60 {
            let sorted = recentCallToTarget.sorted()
            let median = sorted[sorted.count / 2]
            if median > stats.nominalPeriod * 2.5 {
                recoverArmed = true
                logger.info("Đường ống dài ra ở \(self.label, privacy: .public), chờ đổi cảnh để tạo lại link")
            }
        }
        guard recoverArmed, newScene, let runLoop = renderRunLoop.withLock({ $0 })?.value else { return }
        recoverArmed = false
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            recreateDisplayLink()
        }
    }

    /// B2: đặt `THREAD_TIME_CONSTRAINT_POLICY` cho luồng hiện tại: chu kỳ = chu kỳ làm tươi, tính toán 2 ms,
    /// ràng buộc 4 ms, cho phép bị chen ngang.
    static func applyTimeConstraintPolicy(period: Double) -> String {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        func ticks(_ seconds: Double) -> UInt32 {
            UInt32(seconds * 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer))
        }
        var policy = thread_time_constraint_policy_data_t(
            period: ticks(period),
            computation: ticks(0.002),
            constraint: ticks(0.004),
            preemptible: 1
        )
        let count = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        let thread = pthread_mach_thread_np(pthread_self())
        let result = withUnsafeMutablePointer(to: &policy) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                thread_policy_set(thread, thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), raw, count)
            }
        }
        return result == KERN_SUCCESS ? "đã đặt" : "lỗi \(result)"
    }
}

extension ProbeFrameLoop: ProbeLoop {}

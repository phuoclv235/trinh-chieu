import AppKit
import CoreGraphics
import CoreModel
import Foundation
import Metal
import QuartzCore

/// Lõi dựng hình: nhận cảnh cho từng vai, vẽ ra các đầu ra trên màn và các bản xem trước.
///
/// Mỗi đầu ra có cửa sổ, vòng vẽ (display link tối đa 60 khung/giây) và command queue riêng; mọi đầu ra
/// dùng chung thiết bị Metal, đệm texture và bể video. Nguồn lỗi không bao giờ hiện lên đầu ra: lớp giữ hình
/// cuối, cảnh báo đi qua `statistics`.
@MainActor
public final class RenderEngine {
    /// Cỡ bản xem trước (điểm ảnh, tỉ lệ 16:9) và tần số cập nhật.
    public static let previewSize = PixelSize(width: 640, height: 360)
    public static let previewFrameRate: Float = 15
    /// Tần số tối đa của đầu ra: 60 khung/giây khớp HDMI tới LED và máy chiếu, nửa tải so với màn 120 Hz (T0.6).
    public static let outputFrameRate: Float = 60

    let gpu: GPUContext
    let pipelines: Compositor
    let cache: TextureCache
    let health: SourceHealth
    let videoPool: VideoPlayerPool
    private let mailboxes: [OutputRole: SceneMailbox<RenderScene>]

    private struct DisplayOutput {
        let window: OutputWindow
        let loop: RenderLoop
        let screenNumber: UInt32?
    }

    private var displays: [OutputID: DisplayOutput] = [:]
    private var previews: [OutputRole: (layer: CAMetalLayer, loop: RenderLoop)] = [:]
    private var identifyWindows: [NSWindow] = []
    private var screenObserver: (any NSObjectProtocol)?
    private var statisticsTimer: Timer?
    private let statisticsStream = AsyncStream.makeStream(
        of: RenderStatistics.self,
        bufferingPolicy: .bufferingNewest(10)
    )

    /// Tạo thiết bị Metal dùng chung. Lỗi khi máy không có Metal. Tìm tệp media chỉ qua `mediaLocator`.
    public init(mediaLocator: any MediaLocator) throws {
        let gpu = try GPUContext()
        self.gpu = gpu
        pipelines = try Compositor(gpu: gpu)
        let health = SourceHealth()
        self.health = health
        cache = TextureCache(device: gpu.device, mediaLocator: mediaLocator, health: health)
        videoPool = VideoPlayerPool(gpu: gpu, mediaLocator: mediaLocator, health: health)
        var mailboxes: [OutputRole: SceneMailbox<RenderScene>] = [:]
        for role in OutputRole.allCases {
            mailboxes[role] = SceneMailbox()
        }
        self.mailboxes = mailboxes
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.detachMissingScreens() }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishStatistics() }
        }
        RunLoop.main.add(timer, forMode: .common)
        statisticsTimer = timer
    }

    /// Thống kê mỗi giây: khung rớt, thời gian GPU, trễ đường ống của từng đầu ra, cảnh báo nguồn lỗi.
    public var statistics: AsyncStream<RenderStatistics> { statisticsStream.stream }

    /// Các đầu ra đang gắn.
    public func outputs() -> [OutputID] {
        displays.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Gắn một đầu ra phủ kín `screen`. Mã đã gắn thì gỡ bản cũ trước.
    public func attachDisplayOutput(id: OutputID, screen: NSScreen, role: OutputRole) throws {
        detachOutput(id)
        guard let mailbox = mailboxes[role] else { return }
        let window = OutputWindow(screen: screen, device: gpu.device)
        let loop = try RenderLoop(
            label: "\(role.rawValue).\(id.rawValue)",
            role: role,
            layer: window.metalLayer,
            gpu: gpu,
            pipelines: pipelines,
            cache: cache,
            video: videoPool,
            mailbox: mailbox,
            frameRate: min(Self.outputFrameRate, Float(max(1, screen.maximumFramesPerSecond))),
            audible: true,
            onDemand: true
        )
        displays[id] = DisplayOutput(window: window, loop: loop, screenNumber: Self.screenNumber(screen))
        window.show()
        loop.start()
    }

    /// Gỡ một đầu ra: dừng vòng vẽ, đóng cửa sổ.
    public func detachOutput(_ id: OutputID) {
        guard let output = displays.removeValue(forKey: id) else { return }
        output.loop.stop()
        output.window.close()
    }

    /// Gửi cảnh mới cho một vai. Không chặn: vòng vẽ lấy cảnh mới nhất ở khung kế tiếp.
    public func setScene(_ scene: RenderScene, for role: OutputRole) {
        mailboxes[role]?.post(scene)
    }

    /// Lớp xem trước của một vai (640 điểm ảnh, 15 khung/giây), để giao diện gắn vào cây lớp của mình.
    ///
    /// Cập nhật liên tục kể cả khi cảnh tĩnh, theo display link của màn đang chứa lớp: lớp này kiêm "lớp giữ nhịp"
    /// cho màn điều khiển (bản thử T0.4, lần chạy 6).
    public func previewLayer(for role: OutputRole) -> CALayer {
        if let existing = previews[role] { return existing.layer }
        let layer = CAMetalLayer()
        layer.device = gpu.device
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.contentsGravity = .resizeAspect
        layer.drawableSize = Self.previewSize.cgSize
        if let mailbox = mailboxes[role],
            let loop = try? RenderLoop(
                label: "preview.\(role.rawValue)",
                role: role,
                layer: layer,
                gpu: gpu,
                pipelines: pipelines,
                cache: cache,
                video: videoPool,
                mailbox: mailbox,
                frameRate: Self.previewFrameRate,
                audible: false,
                onDemand: false
            )
        {
            previews[role] = (layer, loop)
            loop.start()
        }
        return layer
    }

    /// Thiết bị ra âm thanh của video; `nil` theo hệ thống.
    public func setAudioOutputDevice(_ uniqueID: String?) {
        videoPool.setAudioOutputDevice(uniqueID)
    }

    /// Vẽ số thứ tự lớn lên giữa từng màn trong `duration` giây (cho Cài đặt chọn màn).
    public func identifyScreens(_ screens: [NSScreen], duration: TimeInterval) {
        for window in identifyWindows {
            window.close()
        }
        identifyWindows = screens.enumerated().map { index, screen in
            Self.makeIdentifyWindow(number: index + 1, screen: screen)
        }
        for window in identifyWindows {
            window.orderFrontRegardless()
        }
        let windows = identifyWindows
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.1, duration)))
            for window in windows {
                window.close()
            }
            self?.identifyWindows.removeAll { window in windows.contains { $0 === window } }
        }
    }

    /// Dừng mọi đầu ra, bản xem trước và video. Gọi trước khi bỏ lõi dựng hình.
    public func shutdown() {
        for id in outputs() {
            detachOutput(id)
        }
        for preview in previews.values {
            preview.loop.stop()
        }
        previews.removeAll()
        for window in identifyWindows {
            window.close()
        }
        identifyWindows.removeAll()
        videoPool.invalidate()
        statisticsTimer?.invalidate()
        statisticsTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        statisticsStream.continuation.finish()
    }

    /// Cảnh mới nhất của một vai (vòng vẽ đọc mỗi khung, từ luồng vẽ).
    nonisolated func latestScene(for role: OutputRole) -> MailboxEntry<RenderScene>? {
        mailboxes[role]?.latest()
    }

    // MARK: - Bên trong

    /// Màn bị rút: tự gỡ đầu ra của màn đó và báo qua `statistics`. Cắm lại thì giao diện tự gắn lại (T1.7).
    private func detachMissingScreens() {
        let present = Set(NSScreen.screens.compactMap(Self.screenNumber))
        for (id, output) in displays {
            guard let number = output.screenNumber, !present.contains(number) else { continue }
            detachOutput(id)
            health.report(.outputDetached(id), message: "Màn của đầu ra \(id.rawValue) đã bị rút ra")
        }
    }

    private func publishStatistics() {
        let now = CACurrentMediaTime()
        let sorted = displays.sorted { $0.key.rawValue < $1.key.rawValue }
        let outputs = sorted.map { id, output in output.loop.takeStatistics(id: id, now: now) }
        let statistics = RenderStatistics(outputs: outputs, warnings: health.drain())
        statisticsStream.continuation.yield(statistics)
    }

    private static func screenNumber(_ screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private static func makeIdentifyWindow(number: Int, screen: NSScreen) -> NSWindow {
        let size = NSSize(width: 360, height: 360)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor(white: 0, alpha: 0.75)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let label = NSTextField(labelWithString: "\(number)")
        label.font = NSFont.systemFont(ofSize: 240, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (size.height - 290) / 2, width: size.width, height: 290)
        window.contentView?.addSubview(label)
        return window
    }

    /// Dựng một cảnh ra ảnh, không cần màn hình. Dùng cho test ảnh và ảnh thu nhỏ.
    ///
    /// - Parameters:
    ///   - scene: cảnh cần dựng.
    ///   - previous: cảnh đang hiện trước đó. Có thì `scene` được gửi lúc 0 giây và chuyển cảnh theo
    ///     `scene.transition`; không có thì `scene` hiện ngay, không chuyển cảnh.
    ///   - size: kích thước ảnh ra (điểm ảnh). Khác tỉ lệ khung vẽ thì khung vẽ nằm giữa, phần thừa tô màu nền.
    ///   - time: thời điểm dựng, tính bằng giây kể từ lúc gửi `scene`.
    ///   - mediaLocator: tìm tệp ảnh.
    nonisolated public static func renderOffscreen(
        _ scene: RenderScene,
        after previous: RenderScene? = nil,
        size: PixelSize,
        at time: Double,
        mediaLocator: any MediaLocator = NoMediaLocator()
    ) async throws -> CGImage {
        let shared = try OffscreenRenderer.shared.get()
        let video = await StillVideoProvider.prepare(
            scenes: [scene] + (previous.map { [$0] } ?? []),
            at: time,
            mediaLocator: mediaLocator,
            device: shared.gpu.device
        )
        let box: UncheckedSendableBox<CGImage> = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    with: Result<UncheckedSendableBox<CGImage>, any Error> {
                        let image = try OffscreenRenderer.render(
                            scene,
                            after: previous,
                            size: size,
                            at: time,
                            mediaLocator: mediaLocator,
                            video: video
                        )
                        return UncheckedSendableBox(image)
                    }
                )
            }
        }
        return box.value
    }
}

/// Dựng ngoài màn hình. Thiết bị Metal và pipeline dùng chung cho mọi lần gọi; đệm texture riêng từng lần.
enum OffscreenRenderer {
    final class Shared: @unchecked Sendable {
        let gpu: GPUContext
        let pipelines: Compositor

        init() throws {
            gpu = try GPUContext()
            pipelines = try Compositor(gpu: gpu)
        }
    }

    static let shared: Result<Shared, any Error> = Result { try Shared() }

    static func render(
        _ scene: RenderScene,
        after previous: RenderScene?,
        size: PixelSize,
        at time: Double,
        mediaLocator: any MediaLocator,
        video: StillVideoProvider = .empty
    ) throws -> CGImage {
        let shared = try shared.get()
        let gpu = shared.gpu
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let targetSize = CGSize(width: width, height: height)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        // Hàng của bộ đệm đọc về căn 256 byte: an toàn cho mọi bề rộng khi chép texture sang bộ đệm.
        let bytesPerRow = (width * 4 + 255) / 256 * 256
        guard let target = gpu.device.makeTexture(descriptor: descriptor),
            let readback = gpu.device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
            let commandBuffer = gpu.commandQueue.makeCommandBuffer()
        else {
            throw RenderEngineError.textureUnavailable
        }
        commandBuffer.label = "Offscreen"

        let cache = TextureCache(device: gpu.device, mediaLocator: mediaLocator)
        let compositor = LayerCompositor(
            gpu: gpu,
            pipelines: shared.pipelines,
            cache: cache,
            blocking: true,
            video: video
        )
        if let previous {
            var settled = previous
            settled.transition = .cut
            compositor.update(scene: settled, targetSize: targetSize, time: 0)
            compositor.update(scene: scene, targetSize: targetSize, time: 0)
        } else {
            var settled = scene
            settled.transition = .cut
            compositor.update(scene: settled, targetSize: targetSize, time: 0)
        }
        compositor.encode(into: commandBuffer, target: target, time: time)

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw RenderEngineError.textureUnavailable
        }
        do {
            blit.copy(
                from: target,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: readback,
                destinationOffset: 0,
                destinationBytesPerRow: bytesPerRow,
                destinationBytesPerImage: bytesPerRow * height
            )
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw RenderEngineError.gpuFailed(String(describing: error))
        }

        let data = Data(bytes: readback.contents(), count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let provider = CGDataProvider(data: data as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw RenderEngineError.textureUnavailable
        }
        return image
    }
}

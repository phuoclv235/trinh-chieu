import AppKit
import Foundation
import Metal
import QuartzCore
import RenderEngine
import os

/// Điều phối một lần thử: chuẩn bị media, mở đầu ra, đổi chữ định kỳ, đo, ghi báo cáo.
@MainActor
final class ProbeController {
    private struct Output {
        var screen: ScreenDescription
        var window: OutputWindow
        var loop: any ProbeLoop
        var renderer: ProbeRenderer
    }

    private let options: ProbeOptions
    private let logger = Logger(subsystem: "app.trinhchieu.ProbeApp", category: "Probe")
    private var stopRequested = false
    private var keyMonitor: Any?

    init(options: ProbeOptions) {
        self.options = options
    }

    /// Chạy trọn lần thử, trả về mã thoát: 0 đạt, 1 không đạt tiêu chí, 2 lỗi.
    func run() async -> Int32 {
        do {
            return try await runProbe()
        } catch {
            Console.err("Lỗi: \(error)")
            logger.error("Bản thử lỗi: \(String(describing: error), privacy: .public)")
            return 2
        }
    }

    private func runProbe() async throws -> Int32 {
        let startedAt = Date()
        let gpu = try GPUContext()
        let compositor = try Compositor(gpu: gpu)
        Console.out("Thiết bị Metal: \(gpu.device.name)")

        let screens = try selectScreens()
        for (index, screen) in NSScreen.screens.enumerated() {
            let size = Self.pixelSize(of: screen)
            let mark = screens.contains { $0 === screen } ? "*" : " "
            Console.out(
                "\(mark) Màn \(index): \(screen.localizedName) \(size.width)x\(size.height) "
                    + "\(screen.maximumFramesPerSecond) Hz"
            )
        }
        if screens.count < 2 {
            Console.out("Lưu ý: chỉ có \(screens.count) màn được chọn.")
        }

        let media = try await prepareMedia()
        let backgroundSource = media.background.map { VideoSource(url: $0) }
        let secondarySource = media.secondary.map { VideoSource(url: $0) }
        let solidBackground: (any MTLTexture)?
        if options.noVideo {
            // Xanh than đặc 2x2 điểm ảnh, kéo giãn phủ kín khung.
            let pixels = Array([[UInt8]](repeating: [0x40, 0x24, 0x14, 0xFF], count: 4).joined())
            let bitmap = BGRABitmap(width: 2, height: 2, bytesPerRow: 8, pixels: pixels)
            guard let texture = TextRasterizer.makeTexture(bitmap, device: gpu.device) else {
                throw RenderEngineError.textureUnavailable
            }
            solidBackground = texture
        } else {
            solidBackground = nil
        }

        let logoBitmap = ProbeMedia.logoBitmap()
        guard let logo = TextRasterizer.makeTexture(logoBitmap, device: gpu.device) else {
            throw RenderEngineError.textureUnavailable
        }
        let mailbox = SceneMailbox<ProbeScene>()
        let textCache = TextTextureCache(gpu: gpu)

        var outputs: [Output] = []
        for screen in screens {
            let window = OutputWindow(screen: screen, device: gpu.device)
            let screenRate = Float(max(1, screen.maximumFramesPerSecond))
            let rate = min(screenRate, options.frameRate ?? screenRate)
            let period = 1 / Double(rate)
            let index = NSScreen.screens.firstIndex { $0 === screen } ?? 0
            let renderer = ProbeRenderer(
                compositor: compositor,
                textCache: textCache,
                mailbox: mailbox,
                background: backgroundSource?.makeTap(gpu: gpu),
                solidBackground: solidBackground,
                pictureInPicture: secondarySource?.makeTap(gpu: gpu),
                logo: logo,
                dissolveDuration: options.dissolve,
                nominalPeriod: period
            )
            let label = "man-\(index)"
            let stats = FrameStats(label: label, nominalPeriod: period)
            let loop: any ProbeLoop
            if options.viewDisplayLink {
                loop = ViewLinkLoop(
                    label: label,
                    window: window,
                    gpu: gpu,
                    renderer: renderer,
                    stats: stats,
                    preferredFrameRate: rate
                )
            } else {
                loop = FrameLoop(
                    label: label,
                    layer: window.metalLayer,
                    gpu: gpu,
                    renderer: renderer,
                    stats: stats,
                    preferredFrameRate: rate,
                    frameLatency: options.frameLatency,
                    commandQueue: options.queuePerScreen ? gpu.device.makeCommandQueue() : nil
                )
            }
            let size = window.pixelSize
            let description = ScreenDescription(
                index: index,
                name: screen.localizedName,
                pixelWidth: Int(size.width),
                pixelHeight: Int(size.height),
                maximumFramesPerSecond: screen.maximumFramesPerSecond
            )
            outputs.append(Output(screen: description, window: window, loop: loop, renderer: renderer))
        }

        // Dựng trước chữ cho mọi màn, để độ trễ đo được là của vòng vẽ, không phải của Core Text.
        try await prewarmText(textCache, windows: outputs.map(\.window))

        var phraseIndex = 0
        mailbox.post(ProbeScene(text: ProbeLayout.phrases[phraseIndex]))
        backgroundSource?.play()
        secondarySource?.play()
        for output in outputs {
            output.window.show()
            if options.fullScreenMode {
                output.window.enterFullScreenMode()
            } else if options.nativeFullScreen {
                output.window.enterNativeFullScreen()
            }
            output.loop.start()
        }
        outputs.first?.window.window.makeKey()
        NSApp.activate()
        installKeyMonitor()

        let warmup = Int(options.warmup)
        let duration = Int(options.duration)
        Console.out("Khởi động \(warmup) giây rồi đo \(duration) giây. Bấm Esc để dừng sớm.")
        try? await Task.sleep(for: .seconds(options.warmup))

        let topBefore = await Self.topSnapshot()
        let sampler = ProcessSampler()
        let measureStart = CACurrentMediaTime()
        for output in outputs {
            output.loop.stats.startRecording(at: measureStart)
        }
        sampler.start()

        // Cộng ngẫu nhiên 0 đến 1 chu kỳ khung vào mỗi khoảng đổi chữ, để pha giữa lúc gửi cảnh và nhịp
        // display link trải đều (2 giây tròn là đúng 120 khung, pha gần như cố định).
        let jitterPeriod = outputs.map { $0.loop.stats.nominalPeriod }.max() ?? (1.0 / 60)
        func nextInterval() -> Double {
            options.sceneInterval + Double.random(in: 0..<jitterPeriod)
        }
        var nextChange = measureStart + nextInterval()
        var lastProgress = measureStart
        var sceneChanges: [CFTimeInterval] = []
        while !stopRequested, CACurrentMediaTime() - measureStart < options.duration {
            let wait = max(0.001, nextChange - CACurrentMediaTime())
            try? await Task.sleep(for: .seconds(min(wait, 0.25)))
            let now = CACurrentMediaTime()
            if now >= nextChange, !options.staticText {
                sceneChanges.append(now)
                phraseIndex = (phraseIndex + 1) % ProbeLayout.phrases.count
                mailbox.post(ProbeScene(text: ProbeLayout.phrases[phraseIndex]), at: now)
                nextChange += nextInterval()
            } else if now >= nextChange {
                nextChange += nextInterval()
            }
            if now - lastProgress >= 60 {
                lastProgress = now
                Console.out("Đã đo \(Int((now - measureStart) / 60)) phút")
            }
        }

        let measureEnd = CACurrentMediaTime()
        for output in outputs {
            output.loop.stats.stopRecording(at: measureEnd)
        }
        sampler.stop()
        for output in outputs {
            output.loop.stop()
            output.window.close()
        }
        backgroundSource?.invalidate()
        secondarySource?.invalidate()
        removeKeyMonitor()
        let topAfter = await Self.topSnapshot()

        var videoLoops: [(name: String, starts: [CFTimeInterval])] = []
        if let backgroundSource {
            videoLoops.append(("nền", backgroundSource.loopStarts))
        }
        if let secondarySource {
            videoLoops.append(("khung phụ", secondarySource.loopStarts))
        }
        let report = ProbeReport(
            startedAt: startedAt,
            options: options,
            mediaDescriptions: media.descriptions,
            screens: outputs.map(\.screen),
            outputs: outputs.map { $0.loop.stats.snapshot(now: measureEnd) },
            framesWithVideo: outputs.map(\.renderer.framesWithVideo),
            processSamples: sampler.samples,
            stoppedEarly: stopRequested,
            expectsVideo: backgroundSource != nil,
            sceneChanges: sceneChanges,
            videoLoops: videoLoops,
            topBefore: topBefore,
            topAfter: topAfter
        )
        let markdown = report.markdown()
        let reportURL = options.report ?? Self.defaultReportURL(startedAt: startedAt)
        // In ra terminal trước, để số đo không mất nếu ghi tệp lỗi.
        Console.out("")
        Console.out(markdown)
        do {
            try markdown.write(to: reportURL, atomically: true, encoding: .utf8)
            Console.out("Đã ghi báo cáo: \(reportURL.path)")
        } catch {
            Console.err("Không ghi được báo cáo vào \(reportURL.path): \(error)")
        }
        if report.isInvalid {
            Console.err("Lần chạy không hợp lệ: có màn không nhận khung nào hoặc video nền không giải mã được.")
            return 2
        }
        return report.allPassed ? 0 : 1
    }

    private func selectScreens() throws -> [NSScreen] {
        let all = NSScreen.screens
        guard !all.isEmpty else { throw ProbeError.noScreen }
        if options.screenIndices.isEmpty {
            return Array(all.prefix(2))
        }
        return try options.screenIndices.map { index in
            guard all.indices.contains(index) else { throw ProbeError.screenOutOfRange(index, all.count) }
            return all[index]
        }
    }

    private struct PreparedMedia {
        var background: URL?
        var secondary: URL?
        var descriptions: [String]
    }

    private func prepareMedia() async throws -> PreparedMedia {
        let directory = options.mediaDirectory ?? ProbeMedia.defaultDirectory()
        var descriptions: [String] = []

        let background: URL?
        if options.noVideo {
            background = nil
            descriptions.append("Nền: màu đặc, không video")
        } else if let video1 = options.video1 {
            background = video1
            descriptions.append("Nền: \(video1.lastPathComponent)")
        } else {
            Console.out("Chuẩn bị video nền 1080p H.264 trong \(directory.path)")
            let spec = ProbeMedia.background
            background = try await Task.detached { try ProbeMedia.ensureVideo(spec, in: directory) }.value
            descriptions.append("Nền: tự tạo " + Self.describe(spec))
        }

        var secondary: URL?
        if options.pictureInPicture {
            if let video2 = options.video2 {
                secondary = video2
                descriptions.append("Khung phụ: \(video2.lastPathComponent)")
            } else {
                Console.out("Chuẩn bị video khung phụ 4K HEVC (lần đầu mất khoảng một phút)")
                let spec = ProbeMedia.secondary
                secondary = try await Task.detached { try ProbeMedia.ensureVideo(spec, in: directory) }.value
                descriptions.append("Khung phụ: tự tạo " + Self.describe(spec))
            }
        }
        let phraseCount = ProbeLayout.phrases.count
        let textMode = options.staticText ? "một lời cố định" : "đổi vòng \(phraseCount) lời"
        descriptions.append("Chữ: 4 dòng cỡ 72, viền đen, \(textMode); logo vẽ sẵn 256 px")
        return PreparedMedia(background: background, secondary: secondary, descriptions: descriptions)
    }

    private func prewarmText(_ cache: TextTextureCache, windows: [OutputWindow]) async throws {
        var keys: [TextKey] = []
        for window in windows {
            let layout = CanvasLayout(canvasSize: ProbeLayout.canvas, targetSize: window.pixelSize)
            for phrase in ProbeLayout.phrases {
                let key = ProbeLayout.textKey(phrase, layout: layout)
                cache.request(key)
                keys.append(key)
            }
        }
        let deadline = CACurrentMediaTime() + 15
        while !keys.allSatisfy({ cache.contains($0) }) {
            guard CACurrentMediaTime() < deadline else { throw ProbeError.textNotReady }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Phím Esc.
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                self?.stopRequested = true
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Ảnh chụp `top` (8 tiến trình tốn CPU nhất) để biết máy đang bận gì.
    private static func topSnapshot() async -> String {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
            // Mẫu đầu của top luôn ghi CPU 0%: lấy hai mẫu cách 1 giây và giữ mẫu sau.
            process.arguments = ["-l", "2", "-s", "1", "-o", "cpu", "-n", "8"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return "Không chạy được top: \(error)"
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            guard let range = text.range(of: "Processes:", options: .backwards) else { return text }
            return String(text[range.lowerBound...])
        }.value
    }

    private static func describe(_ spec: ProbeMedia.VideoSpec) -> String {
        "\(spec.width)x\(spec.height) \(spec.codec.rawValue) \(spec.framesPerSecond) khung/giây, lặp"
    }

    private static func pixelSize(of screen: NSScreen) -> (width: Int, height: Int) {
        let scale = screen.backingScaleFactor
        return (Int(screen.frame.width * scale), Int(screen.frame.height * scale))
    }

    private static func defaultReportURL(startedAt: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "ket-qua-ban-thu-\(formatter.string(from: startedAt)).md"
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name)
    }
}

enum ProbeError: Error, CustomStringConvertible {
    case noScreen
    case screenOutOfRange(Int, Int)
    case textNotReady

    var description: String {
        switch self {
        case .noScreen:
            return "Không tìm thấy màn hình nào"
        case .screenOutOfRange(let index, let count):
            return "Không có màn \(index); máy đang có \(count) màn (đánh số từ 0)"
        case .textNotReady:
            return "Dựng chữ quá 15 giây, dừng"
        }
    }
}

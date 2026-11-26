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
        var loop: FrameLoop
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
        let backgroundSource = VideoSource(url: media.background)
        let secondarySource = media.secondary.map { VideoSource(url: $0) }

        let logoBitmap = ProbeMedia.logoBitmap()
        guard let logo = TextRasterizer.makeTexture(logoBitmap, device: gpu.device) else {
            throw RenderEngineError.textureUnavailable
        }
        let mailbox = SceneMailbox<ProbeScene>()
        let textCache = TextTextureCache(gpu: gpu)

        var outputs: [Output] = []
        for screen in screens {
            let window = OutputWindow(screen: screen, device: gpu.device)
            let refresh = max(1, min(Double(screen.maximumFramesPerSecond), Double(options.frameRate)))
            let period = 1 / refresh
            let index = NSScreen.screens.firstIndex { $0 === screen } ?? 0
            let renderer = ProbeRenderer(
                compositor: compositor,
                textCache: textCache,
                mailbox: mailbox,
                background: backgroundSource.makeTap(gpu: gpu),
                pictureInPicture: secondarySource?.makeTap(gpu: gpu),
                logo: logo,
                dissolveDuration: options.dissolve,
                nominalPeriod: period
            )
            let label = "man-\(index)"
            let loop = FrameLoop(
                label: label,
                layer: window.metalLayer,
                gpu: gpu,
                renderer: renderer,
                stats: FrameStats(label: label, nominalPeriod: period),
                preferredFrameRate: options.frameRate,
                frameLatency: options.frameLatency
            )
            let size = window.pixelSize
            let description = ScreenDescription(
                index: index,
                name: screen.localizedName,
                pixelWidth: Int(size.width),
                pixelHeight: Int(size.height),
                maximumFramesPerSecond: screen.maximumFramesPerSecond
            )
            outputs.append(Output(screen: description, window: window, loop: loop))
        }

        // Dựng trước chữ cho mọi màn, để độ trễ đo được là của vòng vẽ, không phải của Core Text.
        try await prewarmText(textCache, windows: outputs.map(\.window))

        var phraseIndex = 0
        mailbox.post(ProbeScene(text: ProbeLayout.phrases[phraseIndex]))
        backgroundSource.play()
        secondarySource?.play()
        for output in outputs {
            output.window.show()
            output.loop.start()
        }
        outputs.first?.window.window.makeKey()
        NSApp.activate()
        installKeyMonitor()

        let warmup = Int(options.warmup)
        let duration = Int(options.duration)
        Console.out("Khởi động \(warmup) giây rồi đo \(duration) giây. Bấm Esc để dừng sớm.")
        try? await Task.sleep(for: .seconds(options.warmup))

        let sampler = ProcessSampler()
        let measureStart = CACurrentMediaTime()
        for output in outputs {
            output.loop.stats.startRecording(at: measureStart)
        }
        sampler.start()

        var nextChange = measureStart + options.sceneInterval
        var lastProgress = measureStart
        while !stopRequested, CACurrentMediaTime() - measureStart < options.duration {
            let wait = max(0.001, nextChange - CACurrentMediaTime())
            try? await Task.sleep(for: .seconds(min(wait, 0.25)))
            let now = CACurrentMediaTime()
            if now >= nextChange {
                phraseIndex = (phraseIndex + 1) % ProbeLayout.phrases.count
                mailbox.post(ProbeScene(text: ProbeLayout.phrases[phraseIndex]), at: now)
                nextChange += options.sceneInterval
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
        backgroundSource.invalidate()
        secondarySource?.invalidate()
        removeKeyMonitor()

        let report = ProbeReport(
            startedAt: startedAt,
            options: options,
            mediaDescriptions: media.descriptions,
            screens: outputs.map(\.screen),
            outputs: outputs.map { $0.loop.stats.snapshot(now: measureEnd) },
            processSamples: sampler.samples,
            stoppedEarly: stopRequested
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
            Console.err("Lần chạy không hợp lệ: có màn không nhận khung nào (màn hình khoá hoặc tắt?).")
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
        var background: URL
        var secondary: URL?
        var descriptions: [String]
    }

    private func prepareMedia() async throws -> PreparedMedia {
        let directory = options.mediaDirectory ?? ProbeMedia.defaultDirectory()
        var descriptions: [String] = []

        let background: URL
        if let video1 = options.video1 {
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
        descriptions.append("Chữ: 4 dòng cỡ 72, viền đen, đổi vòng \(phraseCount) lời; logo vẽ sẵn 256 px")
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

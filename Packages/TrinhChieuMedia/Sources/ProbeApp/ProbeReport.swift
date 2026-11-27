import Foundation
import RenderEngine

/// Thông tin một màn hình dùng trong lần thử.
struct ScreenDescription: Sendable {
    var index: Int
    var name: String
    var pixelWidth: Int
    var pixelHeight: Int
    var maximumFramesPerSecond: Int
}

/// Số đo riêng của T0.6, cùng thứ tự màn với `ProbeReport.outputs`.
struct LoadRun {
    /// `nil` khi màn đó không chạy bằng `ProbeFrameLoop` (`--engine-loop`, `--view-display-link`).
    var loads: [LoadStats.Snapshot?]
    var realtime: [String?]
    /// Cỡ giải mã yêu cầu cho video nền và khung phụ của từng màn.
    var decodeSizes: [[CGSize?]]
    /// Cỡ khung video nền thật nhận được ở cuối lần đo.
    var decodedBackground: [CGSize?]
    var thermalBefore: String
    var thermalAfter: String
}

/// Dựng báo cáo Markdown từ số đo, đối chiếu với tiêu chí nghiệm thu của T0.4 và T0.6.
struct ProbeReport {
    var startedAt: Date
    var options: ProbeOptions
    var mediaDescriptions: [String]
    var screens: [ScreenDescription]
    var outputs: [FrameStats.Snapshot]
    /// Số khung có video nền của từng màn, cùng thứ tự với `outputs`.
    var framesWithVideo: [Int]
    var processSamples: [ProcessSampler.Sample]
    var stoppedEarly: Bool
    /// Có video nền hay không (`--no-video` thì không), để xét lần chạy hợp lệ.
    var expectsVideo = true
    /// Các thời điểm đổi chữ (theo `CACurrentMediaTime`).
    var sceneChanges: [Double] = []
    /// Các thời điểm từng video bắt đầu phát lại từ đầu.
    var videoLoops: [(name: String, starts: [Double])] = []
    /// Ảnh chụp `top` trước và sau khi đo.
    var topBefore = ""
    var topAfter = ""
    var loadRun: LoadRun?

    struct OutputVerdict {
        var averageDropsPerMinute: Double
        var worstMinute: Int
        var latencyP95: Double
        var framesPassed: Bool
        var latencyPassed: Bool
        /// Tiêu chí đề xuất 2a: trễ đường ống p99 ≤ 2 chu kỳ + 2 ms.
        var pipelineP99: Double
        var pipelinePassed: Bool
        /// Tiêu chí đề xuất 2b: trễ đầu cuối p95 ≤ 3 chu kỳ + 1 ms và không mẫu nào > 4 chu kỳ.
        var endToEndPassed: Bool
    }

    func evaluate(_ output: FrameStats.Snapshot) -> OutputVerdict {
        let minutes = max(output.recordingDuration / 60, 1.0 / 60)
        let average = Double(output.droppedFrames) / minutes
        let p95 = Percentile.value(output.sceneLatencies, 0.95)
        let period = output.nominalPeriod
        let pipelineP99 = Percentile.value(output.pipelineLatencies, 0.99)
        let latencyMax = output.sceneLatencies.max() ?? 0
        return OutputVerdict(
            averageDropsPerMinute: average,
            worstMinute: output.dropsPerMinute.max() ?? 0,
            latencyP95: p95,
            framesPassed: average < 1,
            latencyPassed: !output.sceneLatencies.isEmpty && p95 < period * 2,
            pipelineP99: pipelineP99,
            pipelinePassed: !output.pipelineLatencies.isEmpty && pipelineP99 <= period * 2 + 0.002,
            endToEndPassed: !output.sceneLatencies.isEmpty && p95 <= period * 3 + 0.001 && latencyMax <= period * 4
        )
    }

    /// Lần chạy không có khung nào lên màn (thường do màn hình đang khoá hoặc tắt): số đo vô nghĩa.
    var isInvalid: Bool {
        // Vẽ theo nhu cầu không ghi khung lên màn vào `FrameStats`: lấy số của `LoadStats`.
        let presented = outputs.enumerated().map { index, output in
            let load = loadRun.flatMap { index < $0.loads.count ? $0.loads[index] : nil }
            return options.onDemand ? (load?.presentedFrames ?? 0) : output.framesPresented
        }
        return outputs.isEmpty || presented.contains(0) || (expectsVideo && framesWithVideo.contains(0))
    }

    var allPassed: Bool {
        !outputs.isEmpty
            && outputs.allSatisfy { output in
                let verdict = evaluate(output)
                return verdict.framesPassed && verdict.latencyPassed
            }
    }

    func markdown() -> String {
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        lines.append("## Lần chạy \(formatter.string(from: startedAt))")
        lines.append("")
        if isInvalid {
            lines.append(
                "> **Lần chạy không hợp lệ:** có màn không nhận khung nào (màn hình khoá, tắt hoặc Mac đang ngủ), "
                    + "hoặc video nền không giải mã được. Số khung có video từng màn: "
                    + framesWithVideo.map(String.init).joined(separator: ", ")
            )
            lines.append("")
        }
        lines.append("| Mục | Giá trị |")
        lines.append("| --- | --- |")
        for (name, value) in SystemInfo.summary {
            lines.append("| \(name) | \(value) |")
        }
        let measured = outputs.map(\.recordingDuration).max() ?? 0
        let early = stoppedEarly ? " (dừng sớm bằng Esc)" : ""
        let interval = Self.format(options.sceneInterval, digits: 2)
        let dissolve = Self.format(options.dissolve, digits: 2)
        let rate = options.frameRate.map { Self.format(Double($0), digits: 0) } ?? "theo từng màn"
        lines.append("| Thời gian đo | \(Self.format(measured, digits: 0)) giây\(early) |")
        lines.append("| Khởi động trước khi đo | \(Self.format(options.warmup, digits: 0)) giây |")
        lines.append("| Đổi chữ | mỗi \(interval) giây cộng ngẫu nhiên 0 đến 1 chu kỳ, hoà tan \(dissolve) giây |")
        let linkKind = options.viewDisplayLink ? "CADisplayLink của NSView (luồng chính)" : "CAMetalDisplayLink"
        let queueKind = options.queuePerScreen ? "mỗi màn một command queue" : "một command queue chung"
        lines.append(
            "| Display link | \(linkKind), \(rate) khung/giây, trễ \(options.frameLatency) khung; \(queueKind) |"
        )
        let windowMode =
            options.fullScreenMode
            ? "toàn màn hình AppKit (enterFullScreenMode)"
            : options.nativeFullScreen ? "toàn màn hình gốc (toggleFullScreen)" : "cửa sổ không viền mức screenSaver"
        var blank = options.blankOtherScreens ? "; màn không đo phủ đen" : ""
        if let keeper = options.keeperFrameRate {
            let keeperRate = keeper > 0 ? "\(Int(keeper)) khung/giây" : "tần số gốc"
            blank += "; cửa sổ giữ nhịp 320x180 trên màn không đo, \(keeperRate)"
        }
        lines.append("| Chế độ cửa sổ | \(windowMode)\(blank) |")
        for media in mediaDescriptions {
            lines.append("| Media | \(media) |")
        }
        lines.append("")

        lines.append("### Từng màn")
        lines.append("")
        let headers = [
            "Màn",
            "Độ phân giải",
            "Tần số",
            "Khung lên màn",
            "Khung rớt",
            "Rớt TB/phút",
            "Phút tệ nhất",
            "GPU TB",
            "GPU p99",
            "Trễ đổi cảnh p50",
            "p95",
            "Lớn nhất",
        ]
        lines.append("| " + headers.joined(separator: " | ") + " |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for (screen, output) in zip(screens, outputs) {
            let verdict = evaluate(output)
            let cells = [
                "\(screen.index): \(screen.name)",
                "\(screen.pixelWidth)x\(screen.pixelHeight)",
                "\(screen.maximumFramesPerSecond) Hz (chu kỳ danh định \(Self.ms(output.nominalPeriod)), "
                    + "khoảng cách trung vị \(Self.ms(Percentile.value(output.presentIntervals, 0.5))))",
                "\(output.framesPresented)",
                "\(output.droppedFrames) (không lên \(output.framesNotPresented), trễ \(output.lateFrames))",
                Self.format(verdict.averageDropsPerMinute, digits: 2),
                "\(verdict.worstMinute)",
                Self.ms(Percentile.mean(output.gpuTimes)),
                Self.ms(Percentile.value(output.gpuTimes, 0.99)),
                Self.ms(Percentile.value(output.sceneLatencies, 0.5)),
                Self.ms(verdict.latencyP95),
                Self.ms(output.sceneLatencies.max() ?? 0),
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        lines.append("")

        lines.append(contentsOf: pipelineSection())
        lines.append(contentsOf: pipelineSeriesSection())
        lines.append(contentsOf: callbackSection())
        lines.append(contentsOf: dropLogSection())

        let cpu = processSamples.map(\.cpuPercent)
        let memory = processSamples.map(\.footprintMB)
        lines.append("### Tiến trình")
        lines.append("")
        lines.append("| CPU TB | CPU lớn nhất | RAM TB | RAM lớn nhất |")
        lines.append("| --- | --- | --- | --- |")
        let processCells = [
            Self.format(Percentile.mean(cpu), digits: 1) + "%",
            Self.format(cpu.max() ?? 0, digits: 1) + "%",
            Self.format(Percentile.mean(memory), digits: 0) + " MB",
            Self.format(memory.max() ?? 0, digits: 0) + " MB",
        ]
        lines.append("| " + processCells.joined(separator: " | ") + " |")
        lines.append("")
        lines.append("CPU tính theo phần trăm một nhân. RAM là phys_footprint (như Activity Monitor).")
        lines.append("")

        lines.append("### Đối chiếu tiêu chí")
        lines.append("")
        lines.append("| Tiêu chí | Kết quả |")
        lines.append("| --- | --- |")
        for (screen, output) in zip(screens, outputs) {
            let verdict = evaluate(output)
            let framesResult = verdict.framesPassed ? "ĐẠT" : "KHÔNG ĐẠT"
            let latencyResult = Self.result(verdict.latencyPassed, applicable: !output.sceneLatencies.isEmpty)
            let rateText = Self.format(verdict.averageDropsPerMinute, digits: 2)
            let limit = Self.ms(output.nominalPeriod * 2)
            lines.append("| 1. Dưới 1 khung rớt mỗi phút, màn \(screen.index) | \(framesResult) (\(rateText)/phút) |")
            lines.append(
                "| 2. Trễ đổi cảnh p95 dưới 2 khung, màn \(screen.index) | "
                    + "\(latencyResult) (\(Self.ms(verdict.latencyP95)) so với \(limit)) |"
            )
        }
        for (screen, output) in zip(screens, outputs) {
            let verdict = evaluate(output)
            let period = output.nominalPeriod
            let pipelineResult = verdict.pipelinePassed ? "ĐẠT" : "KHÔNG ĐẠT"
            let endResult = Self.result(verdict.endToEndPassed, applicable: !output.sceneLatencies.isEmpty)
            lines.append(
                "| 2a (đề xuất). Trễ đường ống p99 ≤ 2 chu kỳ + 2 ms, màn \(screen.index) | "
                    + "\(pipelineResult) (\(Self.ms(verdict.pipelineP99)) so với \(Self.ms(period * 2 + 0.002))) |"
            )
            lines.append(
                "| 2b (đề xuất). Trễ đổi cảnh p95 ≤ 3 chu kỳ + 1 ms, lớn nhất ≤ 4 chu kỳ, màn \(screen.index) | "
                    + "\(endResult) (p95 \(Self.ms(verdict.latencyP95)) so với \(Self.ms(period * 3 + 0.001)); "
                    + "lớn nhất \(Self.ms(output.sceneLatencies.max() ?? 0)) so với \(Self.ms(period * 4))) |"
            )
        }
        lines.append("| 3. Dấu chồng không bị cắt | Kiểm bằng mắt trên màn và test `TextRasterizerTests` |")
        lines.append("| 4. Thread Sanitizer | Chạy riêng bản debug `--sanitize=thread` |")
        lines.append("")
        lines.append(contentsOf: loadSection())
        lines.append("### Máy lúc đo (`top -l 2 -s 1 -o cpu -n 10`, mẫu sau)")
        lines.append("")
        for (title, text) in [("Trước khi đo", topBefore), ("Sau khi đo", topAfter)] where !text.isEmpty {
            lines.append(title + ":")
            lines.append("")
            lines.append("```")
            lines.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("```")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Bảng ba mốc thời gian của từng khung và phân bố trễ đổi cảnh.
    private func pipelineSection() -> [String] {
        var lines = ["### Đường ống từng màn", ""]
        lines.append(
            "Ba mốc mỗi khung: lúc display link gọi vẽ, `targetPresentationTimestamp`, `presentedTime`. "
                + "Chu kỳ đo là trung vị khoảng cách giữa hai `presentedTime` liên tiếp."
        )
        lines.append("")
        lines.append("| Màn | Chu kỳ đo | Số đo | p50 | p95 | p99 | Nhỏ nhất | Lớn nhất |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
        for (screen, output) in zip(screens, outputs) {
            let measured = Self.format(Percentile.value(output.presentIntervals, 0.5) * 1000, digits: 4) + " ms"
            let rows: [(String, [Double])] = [
                ("Gọi tới đích", output.callToTarget),
                ("Đích tới thật", output.targetToPresented),
                ("Đường ống (gọi tới thật)", output.pipelineLatencies),
                ("Trễ đổi cảnh (gửi tới thật)", output.sceneLatencies),
            ]
            for (index, row) in rows.enumerated() {
                let values = row.1
                let cells = [
                    index == 0 ? "\(screen.index)" : "",
                    index == 0 ? measured : "",
                    "\(row.0), \(values.count) mẫu",
                    Self.ms(Percentile.value(values, 0.5)),
                    Self.ms(Percentile.value(values, 0.95)),
                    Self.ms(Percentile.value(values, 0.99)),
                    Self.ms(values.min() ?? 0),
                    Self.ms(values.max() ?? 0),
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        lines.append("")
        return lines
    }

    /// Nhật ký khung rớt của từng màn (tối đa 200 dòng mỗi màn), kèm khoảng cách tới lần đổi chữ gần nhất
    /// và vị trí phát ước lượng của từng video (tính từ lần phát lại từ đầu gần nhất).
    private func dropLogSection() -> [String] {
        var lines = ["### Nhật ký khung rớt", ""]
        lines.append(
            "\"Tới đổi chữ\" là thời điểm rớt trừ lần đổi chữ gần nhất (âm là rớt trước lúc đổi). "
                + "Vị trí video là ước lượng: thời điểm rớt trừ lần phát lại từ đầu gần nhất."
        )
        lines.append("")
        let limit = 200
        let videoHeaders = videoLoops.map { "Video \($0.name)" }
        for (screen, output) in zip(screens, outputs) {
            let events = output.dropEvents
            lines.append("Màn \(screen.index): \(events.count) lần rớt.")
            lines.append("")
            guard !events.isEmpty else { continue }
            let headers =
                ["Thời điểm (giây)", "Loại", "Số nhịp", "Khoảng trống", "Cách lần rớt trước", "Tới đổi chữ"]
                + videoHeaders
            lines.append("| " + headers.joined(separator: " | ") + " |")
            lines.append("|" + String(repeating: " --- |", count: headers.count))
            var previous: Double?
            for event in events.prefix(limit) {
                let absolute = output.recordingStart + event.time
                let kind = event.kind == .late ? "trễ" : "không lên"
                let gap = event.gap.map { Self.ms($0) } ?? ""
                let since = previous.map { Self.format(event.time - $0, digits: 3) + " giây" } ?? ""
                let scene = Self.nearest(sceneChanges, to: absolute).map { Self.ms(absolute - $0) } ?? ""
                let videos = videoLoops.map { loop in
                    loop.starts.last { $0 <= absolute }.map { Self.format(absolute - $0, digits: 3) + " giây" } ?? ""
                }
                let cells = [Self.format(event.time, digits: 3), kind, "\(event.count)", gap, since, scene] + videos
                lines.append("| " + cells.joined(separator: " | ") + " |")
                previous = event.time
            }
            if events.count > limit {
                lines.append("")
                lines.append("(Bỏ bớt \(events.count - limit) dòng.)")
            }
            lines.append("")
        }
        return lines
    }

    /// Trung vị "gọi tới đích" theo số chu kỳ, mỗi 10 giây, để thấy đường ống đổi độ dài lúc nào.
    private func pipelineSeriesSection() -> [String] {
        var lines = ["### Chuỗi thời gian đường ống", ""]
        lines.append("Trung vị \"gọi tới đích\" mỗi \(Int(FrameStats.timingBucketSeconds)) giây, tính theo số chu kỳ.")
        lines.append("")
        let headers = ["Từ giây"] + screens.map { "Màn \($0.index)" }
        lines.append("| " + headers.joined(separator: " | ") + " |")
        lines.append("|" + String(repeating: " --- |", count: headers.count))
        let count = outputs.map(\.callToTargetBuckets.count).max() ?? 0
        for bucket in 0..<count {
            var cells = [Self.format(Double(bucket) * FrameStats.timingBucketSeconds, digits: 0)]
            for output in outputs {
                let values = bucket < output.callToTargetBuckets.count ? output.callToTargetBuckets[bucket] : []
                cells.append(
                    values.isEmpty ? "" : Self.format(Percentile.value(values, 0.5) / output.nominalPeriod, digits: 2)
                )
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        lines.append("")
        return lines
    }

    /// Thời gian chạy trong lần gọi vẽ và khoảng cách giữa hai lần gọi; liệt kê các lần chạy lâu.
    private func callbackSection() -> [String] {
        var lines = ["### Lần gọi vẽ", ""]
        let threshold = Self.ms(FrameStats.slowCallbackThreshold)
        lines.append("| Màn | Số đo | p50 | p99 | Lớn nhất |")
        lines.append("| --- | --- | --- | --- | --- |")
        for (screen, output) in zip(screens, outputs) {
            let rows: [(String, [Double])] = [
                ("Trọn lần gọi", output.callbackDurations),
                ("encodeFrame", output.encodeDurations),
                ("present và commit", output.commitDurations),
                ("Khoảng cách hai lần gọi", output.callbackIntervals),
            ]
            for (index, row) in rows.enumerated() {
                let cells = [
                    index == 0 ? "\(screen.index)" : "",
                    "\(row.0), \(row.1.count) mẫu",
                    Self.ms(Percentile.value(row.1, 0.5)),
                    Self.ms(Percentile.value(row.1, 0.99)),
                    Self.ms(row.1.max() ?? 0),
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        lines.append("")
        for (screen, output) in zip(screens, outputs) {
            let slow = output.slowCallbacks
            lines.append("Màn \(screen.index): \(slow.count) lần gọi vẽ lâu hơn \(threshold).")
            lines.append("")
            guard !slow.isEmpty else { continue }
            lines.append("| Thời điểm (giây) | Trọn lần gọi | encodeFrame | present và commit | Tới đổi chữ |")
            lines.append("| --- | --- | --- | --- | --- |")
            for item in slow.prefix(100) {
                let absolute = output.recordingStart + item.time
                let scene = Self.nearest(sceneChanges, to: absolute).map { Self.ms(absolute - $0) } ?? ""
                let cells = [
                    Self.format(item.time, digits: 3), Self.ms(item.total), Self.ms(item.encode), Self.ms(item.commit),
                    scene,
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
            if slow.count > 100 {
                lines.append("")
                lines.append("(Bỏ bớt \(slow.count - 100) dòng.)")
            }
            lines.append("")
        }
        return lines
    }

    // MARK: - T0.6

    /// Ngưỡng của T0.6 (đặc tả `plans/giai-doan-0-1/T0.6-ben-duoi-tai.md`).
    enum LoadLimits {
        static let dropsUnderLoad = 6.0
        static let dropsQuiet = 1.0
        static let stallFrames = 3
        static let cpuPercent = 25.0
        static let cpuPercentStatic = 3.0
        static let gpuSeconds = 0.003
        static let memoryMB = 500.0
    }

    /// Cảnh tĩnh vẽ theo nhu cầu (L4): ngân sách CPU riêng.
    private var isStaticOnDemand: Bool {
        options.onDemand && options.noVideo
    }

    private var cpuMean: Double {
        Percentile.mean(processSamples.map(\.cpuPercent))
    }

    private var memoryMax: Double {
        processSamples.map(\.footprintMB).max() ?? 0
    }

    private var thermalWorst: String {
        ThermalName.of(processSamples.map(\.thermalState).max() ?? 0)
    }

    private static func size(_ size: CGSize?) -> String {
        guard let size else { return "gốc" }
        return "\(Int(size.width))x\(Int(size.height))"
    }

    /// Số đo và tiêu chí của T0.6 cho từng màn.
    private func loadSection() -> [String] {
        guard let loadRun else { return [] }
        var lines = ["### Đo dưới tải (T0.6)", ""]
        lines.append("| Mục | Giá trị |")
        lines.append("| --- | --- |")
        lines.append("| Mã lần chạy | \(options.runLabel ?? "không ghi") |")
        lines.append("| Biện pháp | \(options.measures) |")
        lines.append("| Tải nền | \(options.loadDescription ?? "không ghi") |")
        lines.append(
            "| Nhiệt | trước \(loadRun.thermalBefore), sau \(loadRun.thermalAfter), "
                + "cao nhất lúc đo \(thermalWorst) |"
        )
        for (screen, realtime) in zip(screens, loadRun.realtime) {
            if let realtime {
                lines.append("| Luồng vẽ thời gian thực, màn \(screen.index) | \(realtime) |")
            }
        }
        for (index, screen) in screens.enumerated() where options.decodeToOutputSize {
            let sizes = index < loadRun.decodeSizes.count ? loadRun.decodeSizes[index] : []
            let decoded = index < loadRun.decodedBackground.count ? loadRun.decodedBackground[index] : nil
            let requested = sizes.map { Self.size($0) }.joined(separator: ", ")
            lines.append(
                "| Cỡ giải mã (nền, khung phụ), màn \(screen.index) | yêu cầu \(requested); "
                    + "nền nhận được \(Self.size(decoded)) |"
            )
        }
        lines.append("")

        lines.append(
            "Khung rớt T0.6 đếm nhịp display link bị lỡ, khung lên màn muộn hơn đích và khung không lên màn; "
                + "khoảng nghỉ có chủ ý của vẽ theo nhu cầu không tính. Khựng là lần rớt từ 3 nhịp liền nhau."
        )
        lines.append("")
        let headers = [
            "Màn",
            "Rớt/phút",
            "Khung rớt (nhịp lỡ / muộn / không lên)",
            "Khựng ≥3",
            "Rớt dài nhất",
            "Đường ống p50",
            "p99",
            "Đổi cảnh p95",
            "Lớn nhất",
            "Sau nghỉ lớn nhất",
            "Dựng / bỏ nhịp / nghỉ",
            "Không lên ngay sau nghỉ",
            "Tạo lại link",
        ]
        lines.append("| " + headers.joined(separator: " | ") + " |")
        lines.append("|" + String(repeating: " --- |", count: headers.count))
        for (index, (screen, output)) in zip(screens, outputs).enumerated() {
            guard index < loadRun.loads.count, let load = loadRun.loads[index] else {
                let empty = String(repeating: " |", count: headers.count - 2)
                lines.append("| \(screen.index) | không đo (không dùng vòng vẽ thử T0.6) |" + empty)
                continue
            }
            let afterIdle = load.firstAfterIdleLatencies.max().map { Self.ms($0) } ?? ""
            let pausedSeconds = Self.format(load.pausedSeconds, digits: 0)
            let paused = load.pauses > 0 ? "\(load.pauses) lần, \(pausedSeconds) giây" : "0"
            let recoveries = load.recoveries.map { Self.format($0, digits: 0) + " giây" }.joined(separator: ", ")
            let cells: [String] = [
                "\(screen.index)",
                Self.format(load.dropsPerMinuteAverage, digits: 2),
                "\(load.droppedFrames) (\(load.missedTicks) / \(load.latePresents) / \(load.notPresented))",
                "\(load.stalls.count)",
                "\(load.longestDrop) nhịp (\(Self.ms(Double(load.longestDrop) * load.nominalPeriod)))",
                Self.ms(Percentile.value(output.pipelineLatencies, 0.5)),
                Self.ms(Percentile.value(output.pipelineLatencies, 0.99)),
                Self.ms(Percentile.value(output.sceneLatencies, 0.95)),
                Self.ms(output.sceneLatencies.max() ?? 0),
                afterIdle,
                "\(load.renderedFrames) / \(load.skippedTicks) / \(paused)",
                String(load.notPresentedAfterResume),
                recoveries.isEmpty ? "0" : "\(load.recoveries.count) (\(recoveries))",
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        lines.append("")
        for (index, screen) in screens.enumerated() {
            guard index < loadRun.loads.count, let load = loadRun.loads[index], !load.stalls.isEmpty else { continue }
            let list = load.stalls.prefix(30).map { stall in
                "\(Self.format(stall.time, digits: 1)) giây (\(stall.frames) nhịp)"
            }
            let more = load.stalls.count > 30 ? ", ..." : ""
            lines.append("Các lần khựng màn \(screen.index): " + list.joined(separator: ", ") + more)
            lines.append("")
        }
        lines.append(contentsOf: loadCriteria(loadRun))
        return lines
    }

    private func loadCriteria(_ loadRun: LoadRun) -> [String] {
        var lines = ["#### Tiêu chí T0.6", ""]
        lines.append("| Tiêu chí | Kết quả |")
        lines.append("| --- | --- |")
        for (index, (screen, output)) in zip(screens, outputs).enumerated() {
            guard index < loadRun.loads.count, let load = loadRun.loads[index] else { continue }
            let rate = load.dropsPerMinuteAverage
            let rateText = Self.format(rate, digits: 2)
            let underLoad = load.stalls.isEmpty && rate < LoadLimits.dropsUnderLoad
            lines.append(
                "| 1. Dưới tải: không khựng ≥3 nhịp, dưới 6 khung rớt/phút, màn \(screen.index) | "
                    + "\(underLoad ? "ĐẠT" : "KHÔNG ĐẠT") (\(load.stalls.count) lần khựng, \(rateText)/phút) |"
            )
            lines.append(
                "| 2. Máy lặng: dưới 1 khung rớt/phút, màn \(screen.index) | "
                    + "\(rate < LoadLimits.dropsQuiet ? "ĐẠT" : "KHÔNG ĐẠT") (\(rateText)/phút) |"
            )
            if options.onDemand {
                let limit = output.nominalPeriod * 3 + 0.001
                let worst = load.firstAfterIdleLatencies.max()
                let result = worst.map { $0 <= limit ? "ĐẠT" : "KHÔNG ĐẠT" } ?? "KHÔNG ÁP DỤNG (không nghỉ lần nào)"
                lines.append(
                    "| 3. Khung đầu sau lúc nghỉ ≤ 3 chu kỳ + 1 ms, màn \(screen.index) | "
                        + "\(result) (\(worst.map { Self.ms($0) } ?? "") so với \(Self.ms(limit))) |"
                )
            }
            let gpu = Percentile.mean(output.gpuTimes)
            lines.append(
                "| 4. GPU dưới 3 ms mỗi khung, màn \(screen.index) | "
                    + "\(gpu < LoadLimits.gpuSeconds ? "ĐẠT" : "KHÔNG ĐẠT") (\(Self.ms(gpu))) |"
            )
        }
        let cpuLimit = isStaticOnDemand ? LoadLimits.cpuPercentStatic : LoadLimits.cpuPercent
        let cpuText = Self.format(cpuMean, digits: 1)
        lines.append(
            "| 4. CPU trung bình dưới \(Self.format(cpuLimit, digits: 0))% một nhân"
                + "\(isStaticOnDemand ? " (cảnh tĩnh)" : "") | "
                + "\(cpuMean < cpuLimit ? "ĐẠT" : "KHÔNG ĐẠT") (\(cpuText)%) |"
        )
        lines.append(
            "| 4. RAM lớn nhất dưới 500 MB | "
                + "\(memoryMax < LoadLimits.memoryMB ? "ĐẠT" : "KHÔNG ĐẠT") (\(Self.format(memoryMax, digits: 0)) MB) |"
        )
        lines.append("")
        lines.append(
            "Tiêu chí 1 chấm ở L6 (dưới tải chuẩn), tiêu chí 2 ở L7 (máy lặng); tiêu chí 2a, 2b của T0.4 ở bảng trên."
        )
        lines.append("")
        return lines
    }

    static let summaryHeader = [
        "| Lần | Thời điểm | Biện pháp | Tải | Màn | Rớt/phút | Khựng ≥3 | Rớt dài nhất | Ống p50 | Ống p99 "
            + "| Đổi cảnh p95 | Lớn nhất | Sau nghỉ lớn nhất | CPU TB | GPU TB | RAM lớn nhất | Nhiệt | Tạo lại link |",
        "|" + String(repeating: " --- |", count: 18),
    ]

    /// Các dòng tóm tắt (mỗi màn một dòng) để gom nhiều lần chạy vào một bảng.
    func summaryRows() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: startedAt)
        let invalid = isInvalid ? " (không hợp lệ)" : ""
        let label = (options.runLabel ?? "?") + invalid + (stoppedEarly ? " (dừng sớm)" : "")
        let thermal = loadRun.map { "\($0.thermalBefore) → \($0.thermalAfter)" } ?? ""
        var rows: [String] = []
        for (index, (screen, output)) in zip(screens, outputs).enumerated() {
            let load = loadRun.flatMap { index < $0.loads.count ? $0.loads[index] : nil }
            let rate: Double = load?.dropsPerMinuteAverage ?? evaluate(output).averageDropsPerMinute
            let stalls: String = load.map { String($0.stalls.count) } ?? ""
            let longest: String = load.map { String($0.longestDrop) } ?? ""
            let afterIdle: String = load?.firstAfterIdleLatencies.max().map { Self.ms($0) } ?? ""
            let recoveries: String = load.map { String($0.recoveries.count) } ?? ""
            let cells: [String] = [
                label,
                time,
                options.measures,
                options.loadDescription ?? "",
                String(screen.index),
                Self.format(rate, digits: 2),
                stalls,
                longest,
                Self.ms(Percentile.value(output.pipelineLatencies, 0.5)),
                Self.ms(Percentile.value(output.pipelineLatencies, 0.99)),
                Self.ms(Percentile.value(output.sceneLatencies, 0.95)),
                Self.ms(output.sceneLatencies.max() ?? 0),
                afterIdle,
                Self.format(cpuMean, digits: 1) + "%",
                Self.ms(Percentile.mean(output.gpuTimes)),
                Self.format(memoryMax, digits: 0) + " MB",
                thermal,
                recoveries,
            ]
            rows.append("| " + cells.joined(separator: " | ") + " |")
        }
        return rows
    }

    /// Thêm các dòng tóm tắt vào cuối `url`; tệp chưa có thì tạo kèm dòng tiêu đề.
    func appendSummary(to url: URL) throws {
        var text = ""
        if !FileManager.default.fileExists(atPath: url.path) {
            text = Self.summaryHeader.joined(separator: "\n") + "\n"
        }
        text += summaryRows().joined(separator: "\n") + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Chữ kết quả của một tiêu chí; tiêu chí trễ đổi cảnh không áp dụng khi chạy chữ tĩnh.
    static func result(_ passed: Bool, applicable: Bool) -> String {
        guard applicable else { return "KHÔNG ÁP DỤNG (không đổi chữ)" }
        return passed ? "ĐẠT" : "KHÔNG ĐẠT"
    }

    /// Phần tử gần `value` nhất trong `values`.
    static func nearest(_ values: [Double], to value: Double) -> Double? {
        values.min { abs($0 - value) < abs($1 - value) }
    }

    static func ms(_ seconds: Double) -> String {
        format(seconds * 1000, digits: 2) + " ms"
    }

    static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}

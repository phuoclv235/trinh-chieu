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

/// Dựng báo cáo Markdown từ số đo, đối chiếu với tiêu chí nghiệm thu của T0.4.
struct ProbeReport {
    var startedAt: Date
    var options: ProbeOptions
    var mediaDescriptions: [String]
    var screens: [ScreenDescription]
    var outputs: [FrameStats.Snapshot]
    var processSamples: [ProcessSampler.Sample]
    var stoppedEarly: Bool

    struct OutputVerdict {
        var averageDropsPerMinute: Double
        var worstMinute: Int
        var latencyP95: Double
        var framesPassed: Bool
        var latencyPassed: Bool
    }

    func evaluate(_ output: FrameStats.Snapshot) -> OutputVerdict {
        let minutes = max(output.recordingDuration / 60, 1.0 / 60)
        let average = Double(output.droppedFrames) / minutes
        let p95 = Percentile.value(output.sceneLatencies, 0.95)
        return OutputVerdict(
            averageDropsPerMinute: average,
            worstMinute: output.dropsPerMinute.max() ?? 0,
            latencyP95: p95,
            framesPassed: average < 1,
            latencyPassed: !output.sceneLatencies.isEmpty && p95 < output.nominalPeriod * 2
        )
    }

    /// Lần chạy không có khung nào lên màn (thường do màn hình đang khoá hoặc tắt): số đo vô nghĩa.
    var isInvalid: Bool {
        outputs.isEmpty || outputs.contains { $0.framesPresented == 0 }
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
                "> **Lần chạy không hợp lệ:** có màn không nhận khung nào. "
                    + "Thường do màn hình đang khoá, tắt hoặc Mac đang ngủ. Mở khoá rồi chạy lại."
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
        let rate = Self.format(Double(options.frameRate), digits: 0)
        lines.append("| Thời gian đo | \(Self.format(measured, digits: 0)) giây\(early) |")
        lines.append("| Khởi động trước khi đo | \(Self.format(options.warmup, digits: 0)) giây |")
        lines.append("| Đổi chữ | mỗi \(interval) giây, hoà tan \(dissolve) giây |")
        lines.append("| Display link | \(rate) khung/giây, trễ \(options.frameLatency) khung |")
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
                "\(screen.maximumFramesPerSecond) Hz (chu kỳ đo \(Self.ms(output.nominalPeriod)))",
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
            let latencyResult = verdict.latencyPassed ? "ĐẠT" : "KHÔNG ĐẠT"
            let rateText = Self.format(verdict.averageDropsPerMinute, digits: 2)
            let limit = Self.ms(output.nominalPeriod * 2)
            lines.append("| 1. Dưới 1 khung rớt mỗi phút, màn \(screen.index) | \(framesResult) (\(rateText)/phút) |")
            lines.append(
                "| 2. Trễ đổi cảnh p95 dưới 2 khung, màn \(screen.index) | "
                    + "\(latencyResult) (\(Self.ms(verdict.latencyP95)) so với \(limit)) |"
            )
        }
        lines.append("| 3. Dấu chồng không bị cắt | Kiểm bằng mắt trên màn và test `TextRasterizerTests` |")
        lines.append("| 4. Thread Sanitizer | Chạy riêng bản debug `--sanitize=thread` |")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func ms(_ seconds: Double) -> String {
        format(seconds * 1000, digits: 2) + " ms"
    }

    static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}

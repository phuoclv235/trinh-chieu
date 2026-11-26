import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import RenderEngine

/// Tạo media mẫu cho bản thử: video nền chuyển màu chậm có vạch quét (để mắt thấy giật), và logo.
enum ProbeMedia {
    enum Codec: String, Sendable {
        case h264 = "H.264"
        case hevc = "HEVC"

        var avType: AVVideoCodecType {
            switch self {
            case .h264:
                return .h264
            case .hevc:
                return .hevc
            }
        }
    }

    struct VideoSpec: Sendable {
        var fileName: String
        var width: Int
        var height: Int
        var codec: Codec
        var bitRate: Int
        var seconds: Int
        var framesPerSecond: Int
        var hueOffset: Double
    }

    enum MediaError: Error, CustomStringConvertible {
        case writerFailed(String)

        var description: String {
            switch self {
            case .writerFailed(let message):
                return "Không tạo được video mẫu: \(message)"
            }
        }
    }

    static let background = VideoSpec(
        fileName: "nen-1080p-h264.mp4",
        width: 1920,
        height: 1080,
        codec: .h264,
        bitRate: 12_000_000,
        seconds: 20,
        framesPerSecond: 30,
        hueOffset: 0.58
    )

    static let secondary = VideoSpec(
        fileName: "khung-phu-4k-hevc.mp4",
        width: 3840,
        height: 2160,
        codec: .hevc,
        bitRate: 30_000_000,
        seconds: 20,
        framesPerSecond: 30,
        hueOffset: 0.08
    )

    static func defaultDirectory() -> URL {
        let caches =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("TrinhChieuProbe", isDirectory: true)
    }

    /// Trả về tệp đã có, hoặc tạo mới. Chạy trên luồng nền (tạo 4K mất khoảng nửa phút).
    static func ensureVideo(_ spec: VideoSpec, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(spec.fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("dang-tao-" + spec.fileName)
        try? FileManager.default.removeItem(at: temporary)
        try writeVideo(spec, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: url)
        return url
    }

    private static func writeVideo(_ spec: VideoSpec, to url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: spec.codec.avType,
            AVVideoWidthKey: spec.width,
            AVVideoHeightKey: spec.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: spec.bitRate,
                AVVideoExpectedSourceFrameRateKey: spec.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: spec.framesPerSecond * 2,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: spec.width,
                kCVPixelBufferHeightKey as String: spec.height,
            ]
        )
        guard writer.canAdd(input) else { throw MediaError.writerFailed("không thêm được luồng video") }
        writer.add(input)
        guard writer.startWriting() else {
            throw MediaError.writerFailed(writer.error.map { "\($0)" } ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = spec.seconds * spec.framesPerSecond
        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw MediaError.writerFailed("không có pixel buffer pool")
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw MediaError.writerFailed("không tạo được pixel buffer") }
            drawFrame(into: buffer, spec: spec, progress: Double(frame) / Double(totalFrames))
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(spec.framesPerSecond))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw MediaError.writerFailed(writer.error.map { "\($0)" } ?? "append")
            }
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finished.signal()
        }
        finished.wait()
        guard writer.status == .completed else {
            throw MediaError.writerFailed(writer.error.map { "\($0)" } ?? "finishWriting")
        }
    }

    /// Một khung: nền chuyển màu (lặp liền mạch theo `progress`), vài vòng sáng trôi, vạch quét dưới đáy.
    private static func drawFrame(into buffer: CVPixelBuffer, spec: VideoSpec, progress: Double) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return }

        let phase = progress * 2 * Double.pi
        let hueA = spec.hueOffset + 0.06 * sin(phase)
        let hueB = spec.hueOffset + 0.12 + 0.06 * cos(phase)
        let colors = [
            color(hue: hueA, saturation: 0.75, brightness: 0.35, colorSpace: colorSpace),
            color(hue: hueB, saturation: 0.65, brightness: 0.12, colorSpace: colorSpace),
        ]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(height)),
                end: CGPoint(x: CGFloat(width), y: 0),
                options: []
            )
        }

        let unit = CGFloat(height)
        for index in 0..<5 {
            let angle = phase + Double(index) * 1.3
            let centerX = CGFloat(width) * (0.5 + 0.35 * CGFloat(cos(angle + Double(index))))
            let centerY = CGFloat(height) * (0.5 + 0.3 * CGFloat(sin(angle)))
            let radius = unit * (0.12 + 0.04 * CGFloat(index % 3))
            context.setFillColor(CGColor(gray: 1, alpha: 0.06))
            let diameter = radius * 2
            let circle = CGRect(x: centerX - radius, y: centerY - radius, width: diameter, height: diameter)
            context.fillEllipse(in: circle)
        }

        // Vạch quét: đi hết bề ngang trong 2 giây, để thấy ngay khi video hoặc khung hình bị giật.
        let sweep = (progress * Double(spec.seconds) / 2).truncatingRemainder(dividingBy: 1)
        let barWidth = max(4, CGFloat(width) / 240)
        context.setFillColor(CGColor(gray: 1, alpha: 0.85))
        let barX = CGFloat(sweep) * CGFloat(width)
        context.fill(CGRect(x: barX, y: unit * 0.02, width: barWidth, height: unit * 0.03))
    }

    private static func color(
        hue: Double,
        saturation: Double,
        brightness: Double,
        colorSpace: CGColorSpace
    ) -> CGColor {
        let wrapped = hue - hue.rounded(.down)
        let sector = wrapped * 6
        let index = Int(sector) % 6
        let fraction = sector - sector.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        let rgb: (Double, Double, Double)
        switch index {
        case 0:
            rgb = (brightness, rising, low)
        case 1:
            rgb = (falling, brightness, low)
        case 2:
            rgb = (low, brightness, rising)
        case 3:
            rgb = (low, falling, brightness)
        case 4:
            rgb = (rising, low, brightness)
        default:
            rgb = (brightness, low, falling)
        }
        let components = [CGFloat(rgb.0), CGFloat(rgb.1), CGFloat(rgb.2), 1]
        return CGColor(colorSpace: colorSpace, components: components) ?? CGColor(gray: brightness, alpha: 1)
    }

    /// Logo mẫu: vòng tròn và thập tự, trắng trên nền trong suốt.
    static func logoBitmap(size: Int = 256) -> BGRABitmap {
        BGRABitmap.draw(width: size, height: size) { context in
            let side = CGFloat(size)
            let line = side * 0.06
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(line)
            context.strokeEllipse(in: CGRect(x: line, y: line, width: side - line * 2, height: side - line * 2))
            let barWidth = side * 0.1
            context.fill(CGRect(x: (side - barWidth) / 2, y: side * 0.2, width: barWidth, height: side * 0.6))
            context.fill(CGRect(x: side * 0.3, y: side * 0.52, width: side * 0.4, height: barWidth))
        }
    }
}

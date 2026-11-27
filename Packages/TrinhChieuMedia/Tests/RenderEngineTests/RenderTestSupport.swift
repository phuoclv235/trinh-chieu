import CoreGraphics
import CoreModel
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

@testable import RenderEngine

/// Có thiết bị Metal không (CI macOS ảo hoá có thể không có).
let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// Ảnh RGBA 8 bit (không nhân alpha) để đọc điểm ảnh trong test.
struct PixelImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    init(_ bitmap: BGRABitmap) {
        width = bitmap.width
        height = bitmap.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let source = y * bitmap.bytesPerRow + x * 4
                let target = (y * width + x) * 4
                bytes[target] = bitmap.pixels[source + 2]
                bytes[target + 1] = bitmap.pixels[source + 1]
                bytes[target + 2] = bitmap.pixels[source]
                bytes[target + 3] = bitmap.pixels[source + 3]
            }
        }
        self.bytes = bytes
    }

    /// Màu ở (x, y), gốc góc trên trái.
    func color(_ x: Int, _ y: Int) -> RGBA {
        let index = (y * width + x) * 4
        return RGBA(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
    }

    /// Hộp bao các điểm ảnh khác màu `background` quá `threshold` trên một kênh nào đó.
    func inkBounds(background: RGBA, threshold: Int = 40) -> CGRect? {
        var minX = Int.max
        var minY = Int.max
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where color(x, y).distance(to: background) > threshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// So với ảnh khác: sai số trung bình (0 đến 1), sai số lớn nhất trên một kênh (0 đến 255),
    /// và số điểm ảnh có kênh lệch quá `channelTolerance`.
    func difference(to other: PixelImage, channelTolerance: Int) -> (mean: Double, max: Int, outliers: Int)? {
        guard width == other.width, height == other.height else { return nil }
        var total = 0
        var largest = 0
        var outliers = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            var pixelLargest = 0
            for index in pixel..<pixel + 4 {
                let delta = abs(Int(bytes[index]) - Int(other.bytes[index]))
                total += delta
                pixelLargest = max(pixelLargest, delta)
            }
            largest = max(largest, pixelLargest)
            if pixelLargest > channelTolerance { outliers += 1 }
        }
        return (Double(total) / Double(bytes.count) / 255, largest, outliers)
    }
}

extension RGBA {
    /// Sai khác lớn nhất trên một kênh màu (bỏ alpha).
    func distance(to other: RGBA) -> Int {
        max(
            abs(Int(red) - Int(other.red)),
            abs(Int(green) - Int(other.green)),
            abs(Int(blue) - Int(other.blue))
        )
    }

    func isClose(to other: RGBA, tolerance: Int = 3) -> Bool {
        distance(to: other) <= tolerance
    }
}

/// Đọc và ghi PNG.
enum PNG {
    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Ảnh mẫu dựng bằng Core Graphics: nửa trái một màu, nửa phải một màu.
    static func makeSplitImage(width: Int, height: Int, left: RGBA, right: RGBA) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(left.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(right.cgColor)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }
}

/// Tìm media trong một thư mục tạm của test.
struct DictionaryMediaLocator: MediaLocator {
    let urls: [MediaID: URL]

    func url(for id: MediaID) -> URL? { urls[id] }
}

/// Dựng nhanh `RenderScene` cho test.
enum SceneKit {
    static let canvas = PixelSize.fullHD
    static let navy = RGBA(red: 0x1E, green: 0x3A, blue: 0x5F)
    static let red = RGBA(red: 255, green: 0, blue: 0)
    static let blue = RGBA(red: 0, green: 0, blue: 255)
    static let green = RGBA(red: 0, green: 160, blue: 0)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    static func style(
        size: Double = 72,
        color: RGBA = .white,
        alignment: CoreModel.TextAlignment = .center,
        vertical: VerticalAlignment = .middle,
        lineHeight: Double = 1.2,
        letterSpacing: Double = 0,
        stroke: TextStroke = .none,
        family: String = "system",
        weight: Int = 600,
        shadow: TextShadow = .none,
        box: TextBox = .none
    ) -> ResolvedTextStyle {
        ResolvedTextStyle(
            fontFamily: family,
            fontWeight: weight,
            fontSize: size,
            color: color,
            alignment: alignment,
            verticalAlignment: vertical,
            lineHeight: lineHeight,
            letterSpacing: letterSpacing,
            stroke: stroke,
            shadow: shadow,
            box: box
        )
    }

    static func background(_ color: RGBA, id: Int = 1, canvas: PixelSize = SceneKit.canvas) -> RenderLayer {
        RenderLayer(kind: .background, contentID: Self.id(id), items: [.color(color, frame: PixelRect(size: canvas))])
    }

    static func text(
        _ string: String,
        frame: PixelRect = PixelRect(x: 120, y: 120, width: 1680, height: 840),
        style: ResolvedTextStyle = SceneKit.style(),
        autoFit: AutoFit = .none,
        maxLines: Int? = nil,
        id: Int = 100
    ) -> RenderLayer {
        let block = TextBlock(string: string, style: style, autoFit: autoFit, maxLines: maxLines)
        return RenderLayer(kind: .slide, contentID: Self.id(id), items: [.text(block, frame: frame)])
    }

    static func scene(
        _ layers: [RenderLayer],
        canvas: PixelSize = SceneKit.canvas,
        transition: TransitionSpec = .cut
    ) -> RenderScene {
        RenderScene(canvasSize: canvas, layers: layers, transition: transition)
    }
}

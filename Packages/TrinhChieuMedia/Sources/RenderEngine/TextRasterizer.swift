import CoreGraphics
import CoreText
import Foundation
import Metal
import os

/// Kiểu chữ tối thiểu cho bản thử: cỡ, màu, viền, giãn dòng. Cỡ chữ tính theo điểm của khung vẽ logic.
public struct TextStyle: Sendable, Hashable {
    public var fontSize: CGFloat
    public var fillColor: SIMD4<Double>
    public var strokeColor: SIMD4<Double>
    /// Độ dày viền theo phần trăm cỡ chữ (quy ước của `kCTStrokeWidthAttributeName`). 0 là không viền.
    public var strokeWidthPercent: CGFloat
    public var lineHeightMultiple: CGFloat

    public init(
        fontSize: CGFloat,
        fillColor: SIMD4<Double> = SIMD4(1, 1, 1, 1),
        strokeColor: SIMD4<Double> = SIMD4(0, 0, 0, 1),
        strokeWidthPercent: CGFloat = 0,
        lineHeightMultiple: CGFloat = 1.15
    ) {
        self.fontSize = fontSize
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidthPercent = strokeWidthPercent
        self.lineHeightMultiple = lineHeightMultiple
    }
}

/// Ảnh BGRA premultiplied sRGB trên bộ nhớ CPU (chữ, logo), sẵn sàng chép lên texture.
public struct BGRABitmap: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, bytesPerRow: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    /// Vẽ bằng Core Graphics vào một ảnh trong suốt mới. Gốc toạ độ CG ở góc dưới trái.
    public static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> BGRABitmap {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                )
            else { return }
            body(context)
        }
        return BGRABitmap(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
    }

    /// Alpha của điểm ảnh (x, y), gốc ở góc trên trái.
    public func alpha(x: Int, y: Int) -> UInt8 {
        pixels[y * bytesPerRow + x * 4 + 3]
    }

    /// Hàng trên cùng và dưới cùng có điểm ảnh không trong suốt, hoặc `nil` khi ảnh trống.
    public func inkRows() -> ClosedRange<Int>? {
        var top: Int?
        var bottom: Int?
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            var hasInk = false
            for x in 0..<width where pixels[rowStart + x * 4 + 3] != 0 {
                hasInk = true
                break
            }
            if hasInk {
                top = top ?? y
                bottom = y
            }
        }
        guard let top, let bottom else { return nil }
        return top...bottom
    }
}

/// Vẽ chữ bằng Core Text vào bitmap rồi chép lên `MTLTexture`.
public enum TextRasterizer {
    /// Khoảng chừa quanh chữ, theo tỉ lệ cỡ chữ, để dấu chồng ("Ẩ", "Ở", "Người") và viền không bị cắt.
    public static let paddingRatio: CGFloat = 0.3

    /// Vẽ `text` căn giữa (ngang và dọc) vào ảnh kích thước `width` x `height` điểm ảnh.
    /// - Parameter scale: tỉ lệ từ khung vẽ logic sang điểm ảnh đích (cỡ chữ nhân với tỉ lệ này).
    public static func rasterize(
        _ text: String,
        style: TextStyle,
        width: Int,
        height: Int,
        scale: CGFloat
    ) -> BGRABitmap {
        BGRABitmap.draw(width: width, height: height) { context in
            draw(text, style: style, in: context, width: width, height: height, scale: scale)
        }
    }

    private static func draw(
        _ text: String,
        style: TextStyle,
        in context: CGContext,
        width: Int,
        height: Int,
        scale: CGFloat
    ) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(false)
        context.setShouldSubpixelPositionFonts(true)

        let fontSize = style.fontSize * scale
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, "vi" as CFString)
            ?? CTFontCreateWithName("Helvetica Neue" as CFString, fontSize, nil)

        var alignment = CTTextAlignment.center
        var lineHeightMultiple = style.lineHeightMultiple
        let paragraph = withUnsafeBytes(of: &alignment) { alignmentBytes in
            withUnsafeBytes(of: &lineHeightMultiple) { lineBytes in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: alignmentBytes.baseAddress!
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineHeightMultiple,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: lineBytes.baseAddress!
                    ),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }

        let fill = cgColor(style.fillColor, colorSpace: colorSpace)
        let stroke = cgColor(style.strokeColor, colorSpace: colorSpace)
        var attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: fill,
            kCTParagraphStyleAttributeName: paragraph,
        ]
        if style.strokeWidthPercent > 0 {
            // Số âm: vừa tô vừa viền.
            attributes[kCTStrokeWidthAttributeName] = -style.strokeWidthPercent
            attributes[kCTStrokeColorAttributeName] = stroke
        }
        let normalized = text.precomposedStringWithCanonicalMapping
        let attributed = CFAttributedStringCreate(nil, normalized as CFString, attributes as CFDictionary)
        guard let attributed else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        let padding = (fontSize * paddingRatio).rounded(.up)
        let available = CGSize(
            width: max(1, CGFloat(width) - padding * 2),
            height: max(1, CGFloat(height) - padding * 2)
        )
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: available.width, height: .greatestFiniteMagnitude),
            nil
        )
        let textHeight = min(available.height, suggested.height.rounded(.up))
        // Gốc toạ độ Core Graphics ở góc dưới trái: căn giữa theo chiều dọc.
        let originY = padding + (available.height - textHeight) / 2
        let frameRect = CGRect(x: padding, y: originY, width: available.width, height: textHeight)
        let path = CGPath(rect: frameRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }

    private static func cgColor(_ rgba: SIMD4<Double>, colorSpace: CGColorSpace) -> CGColor {
        let components = [CGFloat(rgba.x), CGFloat(rgba.y), CGFloat(rgba.z), CGFloat(rgba.w)]
        return CGColor(colorSpace: colorSpace, components: components)
            ?? CGColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    /// Chép bitmap lên texture `.bgra8Unorm`, bộ nhớ dùng chung (Apple Silicon).
    public static func makeTexture(_ bitmap: BGRABitmap, device: any MTLDevice) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: bitmap.width,
            height: bitmap.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bitmap.pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: bitmap.bytesPerRow
            )
        }
        texture.label = "Text"
        return texture
    }
}

/// Khoá của một ảnh chữ: nội dung, kiểu và kích thước điểm ảnh đích.
public struct TextKey: Sendable, Hashable {
    public var text: String
    public var style: TextStyle
    public var width: Int
    public var height: Int
    public var scale: CGFloat

    public init(text: String, style: TextStyle, width: Int, height: Int, scale: CGFloat) {
        self.text = text
        self.style = style
        self.width = width
        self.height = height
        self.scale = scale
    }
}

/// Đệm texture chữ. Dựng trên hàng đợi nền; vòng vẽ chỉ hỏi, không bao giờ chờ.
public final class TextTextureCache: Sendable {
    private struct State: @unchecked Sendable {
        var textures: [TextKey: any MTLTexture] = [:]
        var pending: Set<TextKey> = []
    }

    private let device: UncheckedSendableBox<any MTLDevice>
    private let queue = DispatchQueue(label: "TrinhChieu.TextRasterizer", qos: .userInitiated)
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(gpu: GPUContext) {
        self.device = UncheckedSendableBox(gpu.device)
    }

    /// Texture đã dựng xong, hoặc `nil` (và xếp lịch dựng) khi chưa có.
    public func texture(for key: TextKey) -> (any MTLTexture)? {
        let found = state.withLock { state -> UncheckedSendableBox<(any MTLTexture)?> in
            if let texture = state.textures[key] {
                return UncheckedSendableBox(texture)
            }
            return UncheckedSendableBox(nil)
        }
        if let texture = found.value {
            return texture
        }
        request(key)
        return nil
    }

    /// Có sẵn texture cho khoá này chưa.
    public func contains(_ key: TextKey) -> Bool {
        state.withLock { $0.textures[key] != nil }
    }

    /// Xếp lịch dựng (bỏ qua nếu đã có hoặc đang dựng).
    public func request(_ key: TextKey) {
        let shouldStart = state.withLock { state in
            guard state.textures[key] == nil, !state.pending.contains(key) else { return false }
            state.pending.insert(key)
            return true
        }
        guard shouldStart else { return }
        let device = device
        let state = state
        queue.async {
            let bitmap = TextRasterizer.rasterize(
                key.text,
                style: key.style,
                width: key.width,
                height: key.height,
                scale: key.scale
            )
            let texture = UncheckedSendableBox(TextRasterizer.makeTexture(bitmap, device: device.value))
            state.withLock { state in
                state.pending.remove(key)
                if let made = texture.value {
                    state.textures[key] = made
                }
            }
        }
    }
}

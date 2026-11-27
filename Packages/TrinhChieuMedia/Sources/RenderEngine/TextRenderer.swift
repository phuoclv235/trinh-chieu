import AppKit
import CoreGraphics
import CoreModel
import CoreText
import Foundation

/// Kết quả dựng một khối chữ.
public struct TextRenderResult: Sendable {
    /// Ảnh chữ, rộng hơn khung `padding` điểm ảnh mỗi phía để dấu chồng và viền không bị cắt.
    public let bitmap: BGRABitmap
    /// Số điểm ảnh chừa thêm quanh khung ở mỗi phía.
    public let padding: Int
    /// Tỉ lệ cỡ chữ đã dùng (1 là không co).
    public let fontScale: Double
    /// Số dòng đã vẽ.
    public let lineCount: Int
    /// Chữ vẫn tràn sau khi co tới `minScale`, dòng cuối bị cắt bằng "…".
    /// Báo trên màn điều khiển, không báo trên đầu ra.
    public let truncated: Bool
    /// Phông yêu cầu không có trên máy, đã thay bằng phông hệ thống.
    public let usedFallbackFont: Bool
}

/// Đo, co, căn và vẽ một `TextBlock` bằng Core Text, kèm hiệu ứng: viền (vẽ ngoài nét chữ), bóng (làm mờ của
/// Core Graphics) và hộp nền bo góc. Hiệu ứng dựng một lần vào ảnh chữ rồi nằm trong đệm, không tốn GPU mỗi khung.
///
/// Đơn vị: `fontSize`, `letterSpacing`, `stroke.width`, `shadow.radius`, `shadow.offset`, `box.padding`,
/// `box.cornerRadius` tính theo điểm ảnh của khung vẽ logic; nhân với `scale`
/// để ra điểm ảnh đầu ra. `lineHeight` là bội số của chiều cao dòng tự nhiên của phông.
public enum TextRenderer {
    /// Khoảng chừa quanh khung, theo tỉ lệ cỡ chữ, để dấu chồng ("Ẩ", "Ở", "Người") không bị cắt.
    public static let paddingRatio: CGFloat = 0.3
    /// Bước co chữ: mỗi lần giảm 2% cỡ chữ.
    public static let shrinkStep = 0.02

    /// Dựng khối chữ cho khung có kích thước `frameSize` (điểm ảnh đầu ra).
    /// - Parameter scale: tỉ lệ từ khung vẽ logic sang điểm ảnh đầu ra.
    public static func render(_ block: TextBlock, frameSize: CGSize, scale: CGFloat) -> TextRenderResult {
        let style = block.style
        let width = max(1, Int(frameSize.width.rounded()))
        let height = max(1, Int(frameSize.height.rounded()))
        let baseFontSize = max(1, CGFloat(style.fontSize) * scale)
        let strokeWidth = max(0, CGFloat(style.stroke.width) * scale)
        let hasStroke = strokeWidth > 0 && style.stroke.color.alpha > 0
        let decoration = TextDecoration(style: style, scale: scale)
        let padding = Int(
            (baseFontSize * paddingRatio + (hasStroke ? strokeWidth : 0) + decoration.extent).rounded(.up)
        )
        let string = block.string.precomposedStringWithCanonicalMapping
        let available = CGSize(width: CGFloat(width), height: CGFloat(height))

        let fonts = FontSource(family: style.fontFamily, weight: style.fontWeight)
        let maxLines = block.maxLines.map { max(1, $0) }

        var fontScale = 1.0
        var layout = TextLayout(
            string: string,
            style: style,
            fonts: fonts,
            scale: scale,
            fontScale: 1,
            width: available.width
        )
        if !layout.fits(height: available.height, maxLines: maxLines), block.autoFit.mode == .shrink {
            let minScale = min(1, max(0.05, block.autoFit.minScale))
            var step = 1
            while true {
                let candidate = 1 - Double(step) * shrinkStep
                guard candidate >= minScale - 1e-9 else { break }
                fontScale = candidate
                layout = TextLayout(
                    string: string,
                    style: style,
                    fonts: fonts,
                    scale: scale,
                    fontScale: candidate,
                    width: available.width
                )
                if layout.fits(height: available.height, maxLines: maxLines) { break }
                step += 1
            }
        }
        let fits = layout.fits(height: available.height, maxLines: maxLines)
        let visible = fits ? layout.lines.count : layout.visibleLineCount(height: available.height, maxLines: maxLines)

        let bitmap = BGRABitmap.draw(width: width + padding * 2, height: height + padding * 2) { context in
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(false)
            context.setShouldSubpixelPositionFonts(true)
            let area = CGRect(origin: CGPoint(x: padding, y: padding), size: available)
            layout.draw(
                in: context,
                area: area,
                visibleLines: visible,
                truncateLast: !fits,
                stroke: hasStroke ? (style.stroke.color, strokeWidth * CGFloat(fontScale)) : nil,
                shadow: decoration.shadow,
                box: decoration.box
            )
        }
        return TextRenderResult(
            bitmap: bitmap,
            padding: padding,
            fontScale: fontScale,
            lineCount: visible,
            truncated: !fits,
            usedFallbackFont: fonts.usedFallback
        )
    }
}

/// Tạo phông theo họ và độ đậm; nhớ việc đã phải thay bằng phông hệ thống.
final class FontSource {
    let family: String
    let weight: Int
    private(set) var usedFallback = false

    init(family: String, weight: Int) {
        self.family = family
        self.weight = weight
    }

    /// Họ phông hệ thống có chữ số đều (đồng hồ màn hình nhắc), xem `SceneResolver.monospacedDigitFontFamily`.
    static let monospacedDigitFamily = "system-monospaced-digits"

    func font(size: CGFloat) -> CTFont {
        let nsWeight = Self.weight(weight)
        if family == Self.monospacedDigitFamily {
            return NSFont.monospacedDigitSystemFont(ofSize: size, weight: nsWeight) as CTFont
        }
        if family != "system", !family.isEmpty {
            let traits: [CFString: Any] = [kCTFontWeightTrait: nsWeight.rawValue]
            let attributes: [CFString: Any] = [
                kCTFontFamilyNameAttribute: family,
                kCTFontTraitsAttribute: traits,
            ]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            if (CTFontCopyFamilyName(font) as String).caseInsensitiveCompare(family) == .orderedSame {
                return font
            }
            usedFallback = true
        }
        return NSFont.systemFont(ofSize: size, weight: nsWeight) as CTFont
    }

    /// Đổi độ đậm kiểu CSS (100 đến 900) sang thang của macOS.
    static func weight(_ value: Int) -> NSFont.Weight {
        switch value {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }
}

/// Bố cục dòng của một khối chữ ở một cỡ chữ. Ngắt dòng bằng `CTTypesetter`, tự đặt đường cơ sở:
/// dòng đầu cách đỉnh khung đúng độ cao chữ (ascent) của phông, các dòng sau cách nhau `lineHeight` lần
/// chiều cao dòng tự nhiên. Nhờ vậy căn dọc giữa khung cân đối, không thừa khoảng giãn dòng ở trên hay dưới.
struct TextLayout {
    struct Line {
        let range: CFRange
        /// Dòng kết thúc một đoạn (trước "\n" hoặc cuối chuỗi): không giãn đều khi căn đều hai bên.
        let endsParagraph: Bool
    }

    let string: String
    let style: ResolvedTextStyle
    let fontSize: CGFloat
    let letterSpacing: CGFloat
    let font: CTFont
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let lineAdvance: CGFloat
    let attributed: CFAttributedString
    let lines: [Line]

    init(
        string: String,
        style: ResolvedTextStyle,
        fonts: FontSource,
        scale: CGFloat,
        fontScale: Double,
        width: CGFloat
    ) {
        self.string = string
        self.style = style
        self.width = width
        fontSize = max(1, CGFloat(style.fontSize) * scale * CGFloat(fontScale))
        letterSpacing = CGFloat(style.letterSpacing) * scale * CGFloat(fontScale)
        font = fonts.font(size: fontSize)
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
        let natural = ascent + descent + CTFontGetLeading(font)
        lineAdvance = natural * CGFloat(max(0.1, style.lineHeight))
        attributed = Self.attributedString(string, font: font, color: style.color.cgColor, kern: letterSpacing)
        lines = Self.breakLines(attributed, width: width)
    }

    static func attributedString(
        _ string: String,
        font: CTFont,
        color: CGColor,
        kern: CGFloat,
        stroke: (color: CGColor, percent: CGFloat)? = nil
    ) -> CFAttributedString {
        var attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
            kCTLanguageAttributeName: "vi" as CFString,
        ]
        if kern != 0 {
            attributes[kCTKernAttributeName] = kern as CFNumber
        }
        if let stroke {
            attributes[kCTStrokeColorAttributeName] = stroke.color
            attributes[kCTStrokeWidthAttributeName] = stroke.percent as CFNumber
        }
        return CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)
            ?? CFAttributedStringCreate(nil, "" as CFString, nil)!
    }

    static func breakLines(_ attributed: CFAttributedString, width: CGFloat) -> [Line] {
        let length = CFAttributedStringGetLength(attributed)
        guard length > 0 else { return [] }
        let text = CFAttributedStringGetString(attributed) as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var lines: [Line] = []
        var start = 0
        while start < length {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            if count <= 0 { count = 1 }
            // Không để dòng vượt qua dấu xuống dòng: dấu "\n" thuộc về dòng trước nó.
            let searchRange = NSRange(location: start, length: count)
            let newline = text.rangeOfCharacter(from: .newlines, options: [], range: searchRange)
            if newline.location != NSNotFound {
                count = newline.location - start + newline.length
            }
            let end = start + count
            let endsParagraph = end >= length || newline.location != NSNotFound
            lines.append(Line(range: CFRange(location: start, length: count), endsParagraph: endsParagraph))
            start = end
        }
        return lines
    }

    /// Chiều cao từ đỉnh dòng đầu tới đáy dòng thứ `count`.
    func blockHeight(lines count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return ascent + CGFloat(count - 1) * lineAdvance + descent
    }

    func fits(height: CGFloat, maxLines: Int?) -> Bool {
        if let maxLines, lines.count > maxLines { return false }
        return blockHeight(lines: lines.count) <= height + 0.5
    }

    /// Số dòng lớn nhất vừa khung (ít nhất 1 khi có chữ).
    func visibleLineCount(height: CGFloat, maxLines: Int?) -> Int {
        var count = min(lines.count, maxLines ?? Int.max)
        while count > 1, blockHeight(lines: count) > height + 0.5 {
            count -= 1
        }
        return count
    }

    /// Vẽ `visibleLines` dòng vào `area` (toạ độ Core Graphics, gốc dưới trái).
    /// Viền (nếu có) vẽ trước với độ dày gấp đôi rồi tô chữ đè lên, để viền chỉ nằm ngoài nét chữ.
    func draw(
        in context: CGContext,
        area: CGRect,
        visibleLines: Int,
        truncateLast: Bool,
        stroke: (color: RGBA, width: CGFloat)?,
        shadow: TextDecoration.Shadow? = nil,
        box: TextDecoration.Box? = nil
    ) {
        guard visibleLines > 0 else { return }
        let height = blockHeight(lines: visibleLines)
        let offset: CGFloat
        switch style.verticalAlignment {
        case .top: offset = 0
        case .middle: offset = (area.height - height) / 2
        case .bottom: offset = area.height - height
        }
        let fillLines = makeLines(attributed, visible: visibleLines, truncateLast: truncateLast)
        var strokeLines: [(CTLine, CGFloat)] = []
        if let stroke {
            // Độ dày viền của Core Text tính theo phần trăm cỡ chữ; nét nằm giữa đường bao nên nhân đôi.
            let percent = stroke.width / fontSize * 100 * 2
            let strokeString = Self.attributedString(
                string,
                font: font,
                color: style.color.cgColor,
                kern: letterSpacing,
                stroke: (stroke.color.cgColor, percent)
            )
            strokeLines = makeLines(strokeString, visible: visibleLines, truncateLast: truncateLast)
        }

        func baseline(_ index: Int) -> CGFloat {
            area.maxY - offset - ascent - CGFloat(index) * lineAdvance
        }
        if let box {
            drawBox(
                box,
                in: context,
                lines: fillLines,
                area: area,
                top: baseline(0) + ascent,
                bottom: baseline(fillLines.count - 1) - descent
            )
        }
        if let shadow {
            context.saveGState()
            context.setShadow(offset: shadow.offset, blur: shadow.blur, color: shadow.color.cgColor)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer {
            if shadow != nil {
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
        if !strokeLines.isEmpty {
            context.saveGState()
            context.setLineJoin(.round)
            context.setLineCap(.round)
            for (index, (line, x)) in strokeLines.enumerated() {
                context.textPosition = CGPoint(x: area.minX + x, y: baseline(index))
                CTLineDraw(line, context)
            }
            context.restoreGState()
        }
        for (index, (line, x)) in fillLines.enumerated() {
            context.textPosition = CGPoint(x: area.minX + x, y: baseline(index))
            CTLineDraw(line, context)
        }
    }

    /// Hộp nền bo góc ôm các dòng đã căn, nới theo `box.insets`.
    private func drawBox(
        _ box: TextDecoration.Box,
        in context: CGContext,
        lines: [(CTLine, CGFloat)],
        area: CGRect,
        top: CGFloat,
        bottom: CGFloat
    ) {
        guard !lines.isEmpty else { return }
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        for (line, x) in lines {
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            minX = min(minX, x)
            maxX = max(maxX, x + lineWidth)
        }
        let rect = CGRect(
            x: area.minX + minX - box.left,
            y: bottom - box.bottom,
            width: maxX - minX + box.left + box.right,
            height: top - bottom + box.top + box.bottom
        )
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = max(0, min(box.cornerRadius, rect.width / 2, rect.height / 2))
        context.saveGState()
        context.setFillColor(box.color.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    /// Dựng các dòng hiển thị cùng độ dời ngang theo cách căn. Dòng cuối cắt bằng "…" khi `truncateLast`.
    private func makeLines(
        _ source: CFAttributedString,
        visible: Int,
        truncateLast: Bool
    ) -> [(CTLine, CGFloat)] {
        let typesetter = CTTypesetterCreateWithAttributedString(source)
        let length = CFAttributedStringGetLength(source)
        var result: [(CTLine, CGFloat)] = []
        for index in 0..<visible {
            let info = lines[index]
            let isLast = index == visible - 1
            if isLast, truncateLast {
                result.append(truncatedLine(source, from: info.range.location, length: length))
                continue
            }
            var line = CTTypesetterCreateLine(typesetter, info.range)
            if style.alignment == .justified, !info.endsParagraph,
                let justified = CTLineCreateJustifiedLine(line, 1, Double(width))
            {
                line = justified
                result.append((line, 0))
                continue
            }
            result.append((line, offset(for: line)))
        }
        return result
    }

    private func truncatedLine(_ source: CFAttributedString, from start: Int, length: Int) -> (CTLine, CGFloat) {
        let remainder: CFMutableAttributedString = CFAttributedStringCreateMutableCopy(nil, 0, source)
        CFAttributedStringReplaceString(remainder, CFRange(location: 0, length: start), "" as CFString)
        // Gộp phần còn lại thành một dòng: xuống dòng thành khoảng trắng. Thuộc tính của cả chuỗi như nhau.
        let text = CFAttributedStringGetString(remainder) as String
        let flattened = text.components(separatedBy: .newlines).joined(separator: " ")
        CFAttributedStringReplaceString(
            remainder,
            CFRange(location: 0, length: CFAttributedStringGetLength(remainder)),
            flattened as CFString
        )
        let attributes = CFAttributedStringGetAttributes(source, max(0, min(start, length - 1)), nil)
        let token = CFAttributedStringCreate(nil, "…" as CFString, attributes)!
        let tokenLine = CTLineCreateWithAttributedString(token)
        let full = CTLineCreateWithAttributedString(remainder)
        let line = CTLineCreateTruncatedLine(full, Double(width), .end, tokenLine) ?? full
        return (line, offset(for: line))
    }

    private func offset(for line: CTLine) -> CGFloat {
        let flush: CGFloat
        switch style.alignment {
        case .left, .justified: flush = 0
        case .center: flush = 0.5
        case .right: flush = 1
        }
        return CGFloat(CTLineGetPenOffsetForFlush(line, flush, Double(width)))
    }
}

/// Bóng và hộp nền của một khối chữ, đã nhân tỉ lệ đầu ra (điểm ảnh, toạ độ Core Graphics gốc dưới trái).
struct TextDecoration {
    struct Shadow {
        let color: RGBA
        let blur: CGFloat
        /// Độ dời theo Core Graphics: `height` dương là lên trên (ngược `PixelPoint.y`).
        let offset: CGSize
    }

    struct Box {
        let color: RGBA
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat
        let left: CGFloat
        let cornerRadius: CGFloat
    }

    let shadow: Shadow?
    let box: Box?

    init(style: ResolvedTextStyle, scale: CGFloat) {
        let shadowStyle = style.shadow
        let blur = max(0, CGFloat(shadowStyle.radius) * scale)
        let offset = CGSize(
            width: CGFloat(shadowStyle.offset.x) * scale,
            height: -CGFloat(shadowStyle.offset.y) * scale
        )
        if shadowStyle.color.alpha > 0, blur > 0 || offset != .zero {
            shadow = Shadow(color: shadowStyle.color, blur: blur, offset: offset)
        } else {
            shadow = nil
        }
        let boxStyle = style.box
        if boxStyle.color.alpha > 0 {
            box = Box(
                color: boxStyle.color,
                top: max(0, CGFloat(boxStyle.padding.top) * scale),
                right: max(0, CGFloat(boxStyle.padding.right) * scale),
                bottom: max(0, CGFloat(boxStyle.padding.bottom) * scale),
                left: max(0, CGFloat(boxStyle.padding.left) * scale),
                cornerRadius: max(0, CGFloat(boxStyle.cornerRadius) * scale)
            )
        } else {
            box = nil
        }
    }

    /// Điểm ảnh cần chừa thêm quanh khung để bóng và hộp không bị cắt.
    var extent: CGFloat {
        var value: CGFloat = 0
        if let shadow {
            value += shadow.blur * 1.5 + max(abs(shadow.offset.width), abs(shadow.offset.height))
        }
        if let box {
            value += max(box.top, box.right, box.bottom, box.left)
        }
        return value
    }
}

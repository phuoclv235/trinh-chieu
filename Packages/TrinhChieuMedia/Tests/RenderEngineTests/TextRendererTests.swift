import AppKit
import CoreGraphics
import CoreModel
import CoreText
import Foundation
import Testing

@testable import RenderEngine

@Suite("TextRenderer")
struct TextRendererTests {
    static let frame = CGSize(width: 1680, height: 640)
    static let verse = [
        "Ẩn náu nơi Đấng Chí Cao,",
        "Ở dưới bóng Đấng Toàn Năng,",
        "Tôi nói về Đức Giê-hô-va rằng:",
        "Ngài là nơi nương náu tôi",
    ]
    .joined(separator: "\n")

    static func block(
        _ string: String,
        style: ResolvedTextStyle = SceneKit.style(),
        autoFit: AutoFit = .none,
        maxLines: Int? = nil
    ) -> TextBlock {
        TextBlock(string: string, style: style, autoFit: autoFit, maxLines: maxLines)
    }

    @Test("Chữ vừa khung: không co, không cắt, đủ 4 dòng")
    func fitsWithoutShrink() {
        let result = TextRenderer.render(Self.block(Self.verse), frameSize: Self.frame, scale: 1)
        #expect(result.fontScale == 1)
        #expect(result.lineCount == 4)
        #expect(!result.truncated)
        #expect(result.bitmap.width == 1680 + result.padding * 2)
        #expect(result.bitmap.height == 640 + result.padding * 2)
    }

    @Test("Dấu chồng ở dòng trên cùng không bị cắt: còn khoảng trống phía trên nét cao nhất")
    func diacriticsNotClipped() throws {
        let style = SceneKit.style(vertical: .top)
        let result = TextRenderer.render(Self.block(Self.verse, style: style), frameSize: Self.frame, scale: 1)
        let rows = try #require(result.bitmap.inkRows())
        #expect(rows.lowerBound > 0)
        #expect(rows.upperBound < result.bitmap.height - 1)
    }

    @Test("Co chữ theo bước 2% tới khi vừa, không thấp hơn minScale")
    func shrinksToFit() {
        let long = Array(repeating: Self.verse, count: 2).joined(separator: "\n")
        let autoFit = AutoFit(mode: .shrink, minScale: 0.5)
        let result = TextRenderer.render(Self.block(long, autoFit: autoFit), frameSize: Self.frame, scale: 1)
        #expect(result.fontScale < 1)
        #expect(result.fontScale >= 0.5)
        let steps = (1 - result.fontScale) / TextRenderer.shrinkStep
        #expect(abs(steps - steps.rounded()) < 1e-6)
        #expect(!result.truncated)
        #expect(result.lineCount == 8)
    }

    @Test("Co tới minScale vẫn tràn: cắt dòng cuối bằng dấu ba chấm và báo cắt")
    func truncatesWhenStillOverflowing() {
        let long = Array(repeating: Self.verse, count: 6).joined(separator: "\n")
        let autoFit = AutoFit(mode: .shrink, minScale: 0.9)
        let result = TextRenderer.render(Self.block(long, autoFit: autoFit), frameSize: Self.frame, scale: 1)
        #expect(result.truncated)
        #expect(abs(result.fontScale - 0.9) < 1e-9)
        #expect(result.lineCount < 24)
    }

    @Test("maxLines giới hạn số dòng")
    func respectsMaxLines() {
        let result = TextRenderer.render(Self.block(Self.verse, maxLines: 2), frameSize: Self.frame, scale: 1)
        #expect(result.lineCount == 2)
        #expect(result.truncated)
    }

    @Test("Không co (autoFit none) mà tràn: vẫn cắt, không vẽ ra ngoài khung quá phần chừa")
    func noShrinkStillTruncates() {
        let long = Array(repeating: Self.verse, count: 4).joined(separator: "\n")
        let result = TextRenderer.render(Self.block(long), frameSize: Self.frame, scale: 1)
        #expect(result.fontScale == 1)
        #expect(result.truncated)
    }

    @Test("Căn trên và căn dưới đặt chữ ở hai đầu khung")
    func verticalAlignment() throws {
        let top = TextRenderer.render(
            Self.block("Ngợi khen Chúa", style: SceneKit.style(vertical: .top)),
            frameSize: Self.frame,
            scale: 1
        )
        let bottom = TextRenderer.render(
            Self.block("Ngợi khen Chúa", style: SceneKit.style(vertical: .bottom)),
            frameSize: Self.frame,
            scale: 1
        )
        let topRows = try #require(top.bitmap.inkRows())
        let bottomRows = try #require(bottom.bitmap.inkRows())
        #expect(topRows.lowerBound < top.padding + 60)
        #expect(bottomRows.upperBound > bottom.bitmap.height - bottom.padding - 60)
    }

    @Test("Căn trái và căn phải đặt chữ ở hai bên khung")
    func horizontalAlignment() throws {
        let left = PixelImage(
            TextRenderer.render(
                Self.block("Hallelujah", style: SceneKit.style(alignment: .left)),
                frameSize: Self.frame,
                scale: 1
            ).bitmap
        )
        let right = PixelImage(
            TextRenderer.render(
                Self.block("Hallelujah", style: SceneKit.style(alignment: .right)),
                frameSize: Self.frame,
                scale: 1
            ).bitmap
        )
        let leftInk = try #require(left.inkBounds(background: .clear))
        let rightInk = try #require(right.inkBounds(background: .clear))
        #expect(leftInk.minX < CGFloat(left.width) / 4)
        #expect(rightInk.maxX > CGFloat(right.width) * 3 / 4)
    }

    @Test("Tỉ lệ đầu ra nhân cỡ chữ: dựng ở scale 0.5 cho chữ thấp bằng nửa")
    func scaleHalvesGlyphs() throws {
        let full = TextRenderer.render(Self.block("Đấng"), frameSize: Self.frame, scale: 1)
        let half = TextRenderer.render(
            Self.block("Đấng"),
            frameSize: CGSize(width: 840, height: 320),
            scale: 0.5
        )
        let fullRows = try #require(full.bitmap.inkRows())
        let halfRows = try #require(half.bitmap.inkRows())
        let ratio = Double(halfRows.count) / Double(fullRows.count)
        #expect(abs(ratio - 0.5) < 0.06)
    }

    @Test("Chuỗi tổ hợp (NFD) cho cùng ảnh với chuỗi dựng sẵn (NFC)")
    func normalizesToNFC() {
        let composed = "Người"
        let first = TextRenderer.render(Self.block(composed), frameSize: Self.frame, scale: 1)
        let second = TextRenderer.render(
            Self.block(composed.decomposedStringWithCanonicalMapping),
            frameSize: Self.frame,
            scale: 1
        )
        #expect(first.bitmap.pixels == second.bitmap.pixels)
    }

    @Test("Phông không có trên máy thì dùng phông hệ thống và báo lại")
    func fallsBackToSystemFont() {
        let style = SceneKit.style(family: "Phông Không Tồn Tại")
        let result = TextRenderer.render(Self.block("Chúa Nhật", style: style), frameSize: Self.frame, scale: 1)
        #expect(result.usedFallbackFont)
        #expect(result.bitmap.inkRows() != nil)
        let system = TextRenderer.render(Self.block("Chúa Nhật"), frameSize: Self.frame, scale: 1)
        #expect(!system.usedFallbackFont)
    }

    @Test("Viền nằm ngoài nét: phần tô gần như giữ nguyên, có viền đen bao ngoài")
    func strokeOutsideGlyph() {
        let text = "Ẩn náu nơi Đấng Chí Cao, Người"
        let plainStyle = SceneKit.style(size: 64)
        let plain = TextRenderer.render(Self.block(text, style: plainStyle), frameSize: Self.frame, scale: 1)
        let strokedStyle = SceneKit.style(size: 64, stroke: TextStroke(color: .black, width: 4))
        let stroked = TextRenderer.render(Self.block(text, style: strokedStyle), frameSize: Self.frame, scale: 1)
        let plainFill = Self.count(plain.bitmap) { $0.alpha == 255 && $0.red >= 250 }
        let strokedFill = Self.count(stroked.bitmap) { $0.alpha == 255 && $0.red >= 250 }
        let dark = Self.count(stroked.bitmap) { $0.alpha == 255 && $0.red <= 5 }
        #expect(plainFill > 0)
        #expect(Double(strokedFill) >= Double(plainFill) * 0.9)
        #expect(dark > plainFill / 10)
        #expect(stroked.padding > plain.padding)
    }

    @Test("Bóng chữ: có điểm ảnh tối lệch theo độ dời, phần chừa nới ra")
    func shadowDrawn() {
        let text = "A-men"
        let plainStyle = SceneKit.style(size: 96)
        let plain = TextRenderer.render(Self.block(text, style: plainStyle), frameSize: Self.frame, scale: 1)
        let shadow = TextShadow(color: .black, radius: 6, offset: PixelPoint(x: 8, y: 8))
        let shadowStyle = SceneKit.style(size: 96, shadow: shadow)
        let shaded = TextRenderer.render(Self.block(text, style: shadowStyle), frameSize: Self.frame, scale: 1)
        let dark = Self.count(shaded.bitmap) { $0.alpha > 60 && $0.red < 40 }
        #expect(dark > 200)
        #expect(Self.count(plain.bitmap) { $0.alpha > 60 && $0.red < 40 } == 0)
        #expect(shaded.padding > plain.padding)
        let plainRows = plain.bitmap.inkRows()
        let shadedRows = shaded.bitmap.inkRows()
        #expect(plainRows != nil && shadedRows != nil)
        if let plainRows, let shadedRows {
            // Bóng lệch xuống dưới: nét thấp nhất của ảnh có bóng nằm thấp hơn (tính từ đỉnh ảnh).
            let plainBottom = plainRows.upperBound - plain.padding
            let shadedBottom = shadedRows.upperBound - shaded.padding
            #expect(shadedBottom > plainBottom)
        }
    }

    @Test("Hộp nền: phủ quanh chữ theo phần nới, góc bo trong suốt")
    func boxDrawn() throws {
        let navy = SceneKit.navy
        let box = TextBox(color: navy, padding: EdgeInsets(top: 20, right: 30, bottom: 20, left: 30), cornerRadius: 24)
        let style = SceneKit.style(size: 72, box: box)
        let result = TextRenderer.render(Self.block("Hallelujah", style: style), frameSize: Self.frame, scale: 1)
        let image = PixelImage(result.bitmap)
        let filled = Self.count(result.bitmap) { $0.alpha == 255 && $0.isClose(to: navy) }
        #expect(filled > 10_000)
        let bounds = try #require(image.inkBounds(background: .clear, threshold: 0))
        // Góc trên trái của hộp bo tròn: điểm ảnh đúng góc trong suốt, điểm giữa cạnh trái tô màu hộp.
        let corner = image.color(Int(bounds.minX), Int(bounds.minY))
        #expect(corner.alpha < 128)
        let middleLeft = image.color(Int(bounds.minX) + 2, Int(bounds.midY))
        #expect(middleLeft.isClose(to: navy))
    }

    @Test("Họ phông chữ số đều: không báo thiếu phông, chữ số rộng bằng nhau")
    func monospacedDigits() {
        let fonts = FontSource(family: FontSource.monospacedDigitFamily, weight: 600)
        let font = fonts.font(size: 80)
        func width(_ string: String) -> Double {
            let attributed = NSAttributedString(string: string, attributes: [.font: font as NSFont])
            return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
        }
        #expect(!fonts.usedFallback)
        #expect(abs(width("1111") - width("8888")) < 0.01)
        let style = SceneKit.style(size: 80, family: FontSource.monospacedDigitFamily)
        let result = TextRenderer.render(Self.block("10:58", style: style), frameSize: Self.frame, scale: 1)
        #expect(!result.usedFallbackFont)
        #expect(result.bitmap.inkRows() != nil)
    }

    @Test("Chuỗi rỗng cho ảnh trong suốt")
    func emptyString() {
        let result = TextRenderer.render(Self.block(""), frameSize: Self.frame, scale: 1)
        #expect(result.lineCount == 0)
        #expect(result.bitmap.inkRows() == nil)
    }

    @Test("Độ đậm CSS đổi sang thang macOS")
    func weightMapping() {
        #expect(FontSource.weight(100) == .ultraLight)
        #expect(FontSource.weight(400) == .regular)
        #expect(FontSource.weight(600) == .semibold)
        #expect(FontSource.weight(700) == .bold)
        #expect(FontSource.weight(900) == .black)
    }

    private static func count(_ bitmap: BGRABitmap, where predicate: (RGBA) -> Bool) -> Int {
        let image = PixelImage(bitmap)
        var total = 0
        for y in 0..<image.height {
            for x in 0..<image.width where predicate(image.color(x, y)) {
                total += 1
            }
        }
        return total
    }
}

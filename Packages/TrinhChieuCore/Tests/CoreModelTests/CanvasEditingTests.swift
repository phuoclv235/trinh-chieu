import Foundation
import Testing

@testable import CoreModel

@Suite("Khung vẽ: hút và đường gióng")
struct CanvasSnappingTests {
    private let canvas = PixelSize.fullHD

    @Test("Tâm phần tử hút vào tâm khung vẽ trong 6 điểm ảnh, có đường gióng tâm")
    func snapsToCanvasCenter() {
        let rect = PixelRect(x: 955 - 200, y: 300, width: 400, height: 100)
        let snapped = CanvasSnapping.snapMove(rect, canvas: canvas, others: [])
        #expect(snapped.rect.x == 760)
        #expect(snapped.guides.contains(CanvasGuide(axis: .vertical, position: 960, source: .canvasCenter)))
    }

    @Test("Mép phần tử hút vào mép vùng an toàn 5%")
    func snapsToSafeArea() {
        let rect = PixelRect(x: 100, y: 58, width: 400, height: 100)
        let snapped = CanvasSnapping.snapMove(rect, canvas: canvas, others: [])
        #expect(snapped.rect.x == 96)
        #expect(snapped.rect.y == 54)
        #expect(snapped.guides.map(\.source) == [.safeEdge, .safeEdge])
    }

    @Test("Cách quá 6 điểm ảnh thì không hút")
    func noSnapOutsideThreshold() {
        let rect = PixelRect(x: 300, y: 300, width: 401, height: 101)
        let snapped = CanvasSnapping.snapMove(rect, canvas: canvas, others: [])
        #expect(snapped.rect == rect)
        #expect(snapped.guides.isEmpty)
    }

    @Test("Hút vào mép và tâm phần tử khác")
    func snapsToOtherElements() {
        let other = PixelRect(x: 1200, y: 600, width: 300, height: 200)
        let rect = PixelRect(x: 1203, y: 400, width: 100, height: 100)
        let snapped = CanvasSnapping.snapMove(rect, canvas: canvas, others: [other])
        #expect(snapped.rect.x == 1200)
        #expect(snapped.guides.first?.source == .element)
        let centered = CanvasSnapping.snapMove(
            PixelRect(x: 1302, y: 100, width: 100, height: 50), canvas: canvas, others: [other])
        #expect(centered.rect.x == 1300)
        #expect(centered.guides.first?.source == .elementCenter)
    }

    @Test("Đổi cỡ: chỉ mép đang kéo hút")
    func resizeSnapsMovingEdge() {
        let rect = PixelRect(x: 400, y: 300, width: 1420, height: 200)
        let snapped = CanvasSnapping.snapResize(rect, handle: .right, canvas: canvas, others: [])
        #expect(snapped.rect.x == 400)
        #expect(snapped.rect.width == 1424)
        #expect(snapped.guides.count == 1)
    }

    @Test("Kéo tay nắm góc, giữ tỉ lệ thì góc đối diện đứng yên")
    func resizeKeepsAspect() {
        let start = PixelRect(x: 100, y: 100, width: 400, height: 200)
        let free = CanvasSnapping.resized(start, handle: .bottomRight, dx: 100, dy: 10, keepAspect: false)
        #expect(free == PixelRect(x: 100, y: 100, width: 500, height: 210))
        let kept = CanvasSnapping.resized(start, handle: .bottomRight, dx: 100, dy: 10, keepAspect: true)
        #expect(kept == PixelRect(x: 100, y: 100, width: 500, height: 250))
        let fromTopLeft = CanvasSnapping.resized(start, handle: .topLeft, dx: -200, dy: 0, keepAspect: true)
        #expect(fromTopLeft == PixelRect(x: -100, y: 0, width: 600, height: 300))
        let tiny = CanvasSnapping.resized(start, handle: .left, dx: 1000, dy: 0, keepAspect: false)
        #expect(tiny.width == 8)
    }
}

@Suite("Khung vẽ: phần tử")
struct CanvasElementTests {
    private func makeSlide() -> (Slide, slotted: UUID, free: UUID) {
        let slotted = TextElement(slot: .body, text: "Lời", style: TextStyleOverride(fontSize: 90))
        let free = ShapeElement(frame: PixelRect(x: 0, y: 0, width: 100, height: 100), fill: .white)
        return (Slide(elements: [.text(slotted), .shape(free)]), slotted.id, free.id)
    }

    @Test("Phần tử gắn ô mẫu bị khoá khung; phần tử tự do đổi được")
    func lockedFrames() {
        var (slide, slotted, free) = makeSlide()
        let theme = Theme.fallback()
        slide.setFrame(PixelRect(x: 1, y: 2, width: 3, height: 4), of: slotted)
        #expect(slide.displayFrame(of: slotted, theme: theme) == theme.slots.body.frame)
        slide.setFrame(PixelRect(x: 1, y: 2, width: 3, height: 4), of: free)
        #expect(slide.displayFrame(of: free, theme: theme) == PixelRect(x: 1, y: 2, width: 3, height: 4))
    }

    @Test("Tách khỏi mẫu: bỏ ô, chép khung và kiểu đầy đủ, giữ phần đè")
    func detach() {
        var (slide, slotted, _) = makeSlide()
        let theme = Theme.fallback()
        slide.detachFromTheme(slotted, theme: theme)
        guard case .text(let text) = slide.elements[0] else {
            Issue.record("Mất phần tử chữ")
            return
        }
        #expect(text.slot == nil)
        #expect(text.frame == theme.slots.body.frame)
        #expect(text.style?.fontSize == 90)
        #expect(text.style?.fontWeight == theme.slots.body.style.fontWeight)
        slide.setFrame(PixelRect(x: 5, y: 5, width: 50, height: 50), of: slotted)
        #expect(slide.displayFrame(of: slotted, theme: theme) == PixelRect(x: 5, y: 5, width: 50, height: 50))
    }

    @Test("Đưa lên trên, đưa xuống dưới một lớp; xoá phần tử")
    func layerOrder() {
        var (slide, slotted, free) = makeSlide()
        slide.bringForward(slotted)
        #expect(slide.elements.map(\.id) == [free, slotted])
        slide.bringForward(slotted)
        #expect(slide.elements.map(\.id) == [free, slotted])
        slide.sendBackward(slotted)
        #expect(slide.elements.map(\.id) == [slotted, free])
        slide.removeElement(free)
        #expect(slide.elements.map(\.id) == [slotted])
    }
}

@Suite("Bảng thuộc tính: phần đè kiểu chữ")
struct StyleOverrideTests {
    @Test("Đặt giá trị trùng mẫu thì bỏ phần đè; đếm số thuộc tính khác mẫu")
    func setClearsWhenEqual() {
        let base = Theme.fallback().slots.body.style
        var override = TextStyleOverride()
        override.set(\.fontSize, base.fontSize + 10, base: base, basePath: \.fontSize)
        override.set(\.alignment, .left, base: base, basePath: \.alignment)
        #expect(override.overriddenCount == (base.alignment == .left ? 1 : 2))
        override.set(\.fontSize, base.fontSize, base: base, basePath: \.fontSize)
        #expect(override.fontSize == nil)
    }

    @Test("Phần tử chữ tự do lấy kiểu gốc từ ô lời chính")
    func freeTextUsesBodySlot() {
        let theme = Theme.fallback()
        let free = TextElement(frame: PixelRect(x: 0, y: 0, width: 10, height: 10), text: "A")
        #expect(free.resolvedStyle(in: theme) == theme.slots.body.style)
        #expect(free.displayFrame(in: theme) == PixelRect(x: 0, y: 0, width: 10, height: 10))
        let sized = TextElement(slot: .title, text: "B", style: TextStyleOverride(fontSize: 12))
        #expect(sized.resolvedStyle(in: theme).fontSize == 12)
        #expect(sized.displayFrame(in: theme) == theme.slots.title.frame)
    }
}

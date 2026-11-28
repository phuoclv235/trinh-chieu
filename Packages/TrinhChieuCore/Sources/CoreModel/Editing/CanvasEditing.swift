import Foundation

/// Hướng của một đường gióng: dọc (theo trục x) hoặc ngang (theo trục y).
public enum GuideAxis: String, Sendable, Hashable {
    case vertical
    case horizontal
}

/// Nguồn của đường gióng, để giao diện ghi nhãn ("Tâm", "Vùng an toàn").
public enum GuideSource: String, Sendable, Hashable {
    case canvasEdge
    case canvasCenter
    case safeEdge
    case element
    case elementCenter
}

/// Một đường gióng hiện khi phần tử hút vào nó.
public struct CanvasGuide: Sendable, Hashable {
    public var axis: GuideAxis
    /// Toạ độ x (đường dọc) hoặc y (đường ngang), điểm ảnh khung vẽ.
    public var position: Double
    public var source: GuideSource

    public init(axis: GuideAxis, position: Double, source: GuideSource) {
        self.axis = axis
        self.position = position
        self.source = source
    }
}

/// Mép hoặc tay nắm đang kéo khi đổi cỡ.
public struct ResizeHandle: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let left = ResizeHandle(rawValue: 1)
    public static let right = ResizeHandle(rawValue: 2)
    public static let top = ResizeHandle(rawValue: 4)
    public static let bottom = ResizeHandle(rawValue: 8)

    public static let topLeft: ResizeHandle = [.top, .left]
    public static let topRight: ResizeHandle = [.top, .right]
    public static let bottomLeft: ResizeHandle = [.bottom, .left]
    public static let bottomRight: ResizeHandle = [.bottom, .right]

    /// Tám tay nắm theo thứ tự vẽ.
    public static let all: [ResizeHandle] = [
        .topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left,
    ]
}

/// Hút và đường gióng thông minh của khung vẽ (đặc tả T1.9 mục 2): mép và tâm của khung vẽ, mép vùng an toàn (5% mỗi
/// cạnh), mép và tâm của phần tử khác; hút khi cách dưới `threshold` điểm ảnh khung vẽ.
public enum CanvasSnapping {
    /// Vùng an toàn: 5% mỗi cạnh.
    public static let safeInset = 0.05
    /// Khoảng hút mặc định, điểm ảnh khung vẽ.
    public static let defaultThreshold = 6.0

    struct Target {
        var position: Double
        var source: GuideSource
    }

    /// Các đích hút theo trục x (đường dọc) và y (đường ngang).
    static func targets(canvas: PixelSize, others: [PixelRect]) -> (x: [Target], y: [Target]) {
        var x: [Target] = [
            Target(position: 0, source: .canvasEdge), Target(position: canvas.width, source: .canvasEdge),
            Target(position: canvas.width / 2, source: .canvasCenter),
            Target(position: canvas.width * safeInset, source: .safeEdge),
            Target(position: canvas.width * (1 - safeInset), source: .safeEdge),
        ]
        var y: [Target] = [
            Target(position: 0, source: .canvasEdge), Target(position: canvas.height, source: .canvasEdge),
            Target(position: canvas.height / 2, source: .canvasCenter),
            Target(position: canvas.height * safeInset, source: .safeEdge),
            Target(position: canvas.height * (1 - safeInset), source: .safeEdge),
        ]
        for rect in others {
            x.append(Target(position: rect.x, source: .element))
            x.append(Target(position: rect.x + rect.width, source: .element))
            x.append(Target(position: rect.x + rect.width / 2, source: .elementCenter))
            y.append(Target(position: rect.y, source: .element))
            y.append(Target(position: rect.y + rect.height, source: .element))
            y.append(Target(position: rect.y + rect.height / 2, source: .elementCenter))
        }
        return (x, y)
    }

    /// Điểm gần nhất trong `targets` của một trong các `points` (khoảng cách dưới `threshold`): độ dời cần áp và đích.
    static func nearest(_ points: [Double], targets: [Target], threshold: Double) -> (delta: Double, target: Target)? {
        var best: (delta: Double, target: Target)?
        for point in points {
            for target in targets {
                let delta = target.position - point
                guard abs(delta) <= threshold else { continue }
                if best == nil || abs(delta) < abs(best?.delta ?? 0) {
                    best = (delta, target)
                }
            }
        }
        return best
    }

    /// Hút khi di chuyển: mép trái, tâm, mép phải (và trên, tâm, dưới) của `rect` hút vào đích gần nhất.
    public static func snapMove(
        _ rect: PixelRect, canvas: PixelSize, others: [PixelRect], threshold: Double = defaultThreshold
    ) -> (rect: PixelRect, guides: [CanvasGuide]) {
        let all = targets(canvas: canvas, others: others)
        var result = rect
        var guides: [CanvasGuide] = []
        let xs = [rect.x, rect.x + rect.width / 2, rect.x + rect.width]
        if let hit = nearest(xs, targets: all.x, threshold: threshold) {
            result.x += hit.delta
            guides.append(CanvasGuide(axis: .vertical, position: hit.target.position, source: hit.target.source))
        }
        let ys = [rect.y, rect.y + rect.height / 2, rect.y + rect.height]
        if let hit = nearest(ys, targets: all.y, threshold: threshold) {
            result.y += hit.delta
            guides.append(CanvasGuide(axis: .horizontal, position: hit.target.position, source: hit.target.source))
        }
        return (result, guides)
    }

    /// Hút khi đổi cỡ: chỉ mép đang kéo hút vào đích. Không áp khi giữ tỉ lệ (tỉ lệ được ưu tiên).
    public static func snapResize(
        _ rect: PixelRect, handle: ResizeHandle, canvas: PixelSize, others: [PixelRect],
        threshold: Double = defaultThreshold
    ) -> (rect: PixelRect, guides: [CanvasGuide]) {
        let all = targets(canvas: canvas, others: others)
        var result = rect
        var guides: [CanvasGuide] = []
        if handle.contains(.left), let hit = nearest([rect.x], targets: all.x, threshold: threshold) {
            result.x += hit.delta
            result.width -= hit.delta
            guides.append(CanvasGuide(axis: .vertical, position: hit.target.position, source: hit.target.source))
        } else if handle.contains(.right),
            let hit = nearest([rect.x + rect.width], targets: all.x, threshold: threshold)
        {
            result.width += hit.delta
            guides.append(CanvasGuide(axis: .vertical, position: hit.target.position, source: hit.target.source))
        }
        if handle.contains(.top), let hit = nearest([rect.y], targets: all.y, threshold: threshold) {
            result.y += hit.delta
            result.height -= hit.delta
            guides.append(CanvasGuide(axis: .horizontal, position: hit.target.position, source: hit.target.source))
        } else if handle.contains(.bottom),
            let hit = nearest([rect.y + rect.height], targets: all.y, threshold: threshold)
        {
            result.height += hit.delta
            guides.append(CanvasGuide(axis: .horizontal, position: hit.target.position, source: hit.target.source))
        }
        return (result, guides)
    }

    /// Khung mới khi kéo tay nắm `handle` thêm `dx`, `dy` từ khung `start`. Giữ tỉ lệ thì cạnh đổi nhiều hơn quyết
    /// định, góc đối diện đứng yên. Cỡ không nhỏ hơn `minSize`.
    public static func resized(
        _ start: PixelRect, handle: ResizeHandle, dx: Double, dy: Double, keepAspect: Bool, minSize: Double = 8
    ) -> PixelRect {
        var left = start.x
        var right = start.x + start.width
        var top = start.y
        var bottom = start.y + start.height
        if handle.contains(.left) { left = min(left + dx, right - minSize) }
        if handle.contains(.right) { right = max(right + dx, left + minSize) }
        if handle.contains(.top) { top = min(top + dy, bottom - minSize) }
        if handle.contains(.bottom) { bottom = max(bottom + dy, top + minSize) }
        var rect = PixelRect(x: left, y: top, width: right - left, height: bottom - top)
        guard keepAspect, start.width > 0, start.height > 0 else { return rect }
        let ratio = start.width / start.height
        let horizontal = handle.contains(.left) || handle.contains(.right)
        let vertical = handle.contains(.top) || handle.contains(.bottom)
        let widthChange = abs(rect.width / start.width - 1)
        let heightChange = abs(rect.height / start.height - 1)
        let widthLeads = horizontal && (!vertical || widthChange >= heightChange)
        if widthLeads {
            rect.height = rect.width / ratio
        } else {
            rect.width = rect.height * ratio
        }
        // Cạnh ngắn hơn cũng không nhỏ hơn `minSize`.
        let shortest = max(min(rect.width, rect.height), .leastNonzeroMagnitude)
        let grow = max(1, minSize / shortest)
        rect.width *= grow
        rect.height *= grow
        // Neo theo góc hoặc cạnh đối diện; cạnh không kéo thì giữ tâm.
        if handle.contains(.left) {
            rect.x = start.x + start.width - rect.width
        } else if !handle.contains(.right) {
            rect.x = start.x + (start.width - rect.width) / 2
        }
        if handle.contains(.top) {
            rect.y = start.y + start.height - rect.height
        } else if !handle.contains(.bottom) {
            rect.y = start.y + (start.height - rect.height) / 2
        }
        return rect
    }

    /// Khung làm tròn về số nguyên điểm ảnh (bảng thuộc tính hiện số nguyên).
    public static func rounded(_ rect: PixelRect) -> PixelRect {
        PixelRect(x: rect.x.rounded(), y: rect.y.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }
}

// MARK: - Phần tử trên trang

extension Element {
    /// Khung đã ghi của phần tử (phần tử chữ gắn ô mẫu thì khung này bị bỏ qua khi dựng).
    public var frame: PixelRect {
        get {
            switch self {
            case .text(let element): return element.frame
            case .image(let element): return element.frame
            case .video(let element): return element.frame
            case .shape(let element): return element.frame
            }
        }
        set {
            switch self {
            case .text(var element):
                element.frame = newValue
                self = .text(element)
            case .image(var element):
                element.frame = newValue
                self = .image(element)
            case .video(var element):
                element.frame = newValue
                self = .video(element)
            case .shape(var element):
                element.frame = newValue
                self = .shape(element)
            }
        }
    }

    /// Phần tử chữ đang gắn ô mẫu: khung bị khoá theo mẫu.
    public var isLockedToTheme: Bool {
        if case .text(let text) = self { return text.slot != nil }
        return false
    }
}

extension TextStyleOverride {
    /// Phần đè ghi đủ mọi trường của `style` (khi tách phần tử khỏi mẫu).
    public init(full style: TextStyle) {
        self.init(
            fontFamily: style.fontFamily, fontWeight: style.fontWeight, fontSize: style.fontSize, color: style.color,
            alignment: style.alignment, verticalAlignment: style.verticalAlignment, lineHeight: style.lineHeight,
            letterSpacing: style.letterSpacing, transform: style.transform, stroke: style.stroke,
            shadow: style.shadow, box: style.box, autoFit: style.autoFit, maxLines: style.maxLines)
    }
}

extension Slide {
    /// Chỉ số của phần tử `elementID`.
    public func elementIndex(_ elementID: UUID) -> Int? {
        elements.firstIndex { $0.id == elementID }
    }

    /// Khung hiển thị của phần tử: phần tử chữ gắn ô mẫu lấy khung của ô.
    public func displayFrame(of elementID: UUID, theme: Theme) -> PixelRect? {
        guard let index = elementIndex(elementID) else { return nil }
        if case .text(let text) = elements[index], let slot = text.slot {
            return theme.slots[slot].frame
        }
        return elements[index].frame
    }

    /// Đặt khung cho phần tử. Phần tử chữ gắn ô mẫu bị khoá: không đổi.
    public mutating func setFrame(_ frame: PixelRect, of elementID: UUID) {
        guard let index = elementIndex(elementID), !elements[index].isLockedToTheme else { return }
        elements[index].frame = frame
    }

    /// "Tách khỏi mẫu": bỏ `slot`, chép khung và kiểu hiện tại (kiểu ô mẫu đã áp phần đè) vào phần tử.
    public mutating func detachFromTheme(_ elementID: UUID, theme: Theme) {
        guard let index = elementIndex(elementID), case .text(var text) = elements[index], let slot = text.slot
        else { return }
        let base = theme.slots[slot]
        let style = text.style.map { base.style.applying($0) } ?? base.style
        text.frame = base.frame
        text.style = TextStyleOverride(full: style)
        text.slot = nil
        elements[index] = .text(text)
    }

    /// Đưa phần tử lên trên một lớp (`⌘]`).
    public mutating func bringForward(_ elementID: UUID) {
        guard let index = elementIndex(elementID), index + 1 < elements.count else { return }
        elements.swapAt(index, index + 1)
    }

    /// Đưa phần tử xuống dưới một lớp (`⌘[`).
    public mutating func sendBackward(_ elementID: UUID) {
        guard let index = elementIndex(elementID), index > 0 else { return }
        elements.swapAt(index, index - 1)
    }

    /// Xoá phần tử.
    public mutating func removeElement(_ elementID: UUID) {
        elements.removeAll { $0.id == elementID }
    }
}

extension Presentation {
    /// Sửa trang `slideID` tại chỗ. Không tìm thấy thì không làm gì.
    public mutating func updateSlide(_ slideID: UUID, _ change: (inout Slide) -> Void) {
        guard let location = location(ofSlide: slideID) else { return }
        change(&groups[location.group].slides[location.slide])
    }
}

extension TextElement {
    /// Ô mẫu làm gốc kiểu chữ: ô đang gắn, hoặc ô lời chính với phần tử tự do (như `SceneResolver`).
    public func baseSlot(in theme: Theme) -> ThemeSlot {
        theme.slots[slot ?? .body]
    }

    /// Kiểu chữ đang thấy: kiểu ô mẫu đã áp phần đè.
    public func resolvedStyle(in theme: Theme) -> TextStyle {
        let base = baseSlot(in: theme).style
        return style.map { base.applying($0) } ?? base
    }

    /// Khung đang thấy: khung ô mẫu khi gắn ô, khung riêng khi tự do.
    public func displayFrame(in theme: Theme) -> PixelRect {
        slot.map { theme.slots[$0].frame } ?? frame
    }
}

extension TextStyleOverride {
    /// Số thuộc tính đang khác mẫu (trường có giá trị).
    public var overriddenCount: Int {
        let fields: [Bool] = [
            fontFamily != nil, fontWeight != nil, fontSize != nil, color != nil, alignment != nil,
            verticalAlignment != nil, lineHeight != nil, letterSpacing != nil, transform != nil, stroke != nil,
            shadow != nil, box != nil, autoFit != nil, maxLines != nil,
        ]
        return fields.filter { $0 }.count
    }

    /// Đặt một trường; giá trị trùng kiểu của mẫu thì bỏ phần đè của trường đó.
    public mutating func set<Value: Equatable>(
        _ path: WritableKeyPath<TextStyleOverride, Value?>, _ value: Value,
        base: TextStyle, basePath: KeyPath<TextStyle, Value>
    ) {
        self[keyPath: path] = base[keyPath: basePath] == value ? nil : value
    }
}

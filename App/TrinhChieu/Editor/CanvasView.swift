import AppKit
import CoreModel
import RenderEngine
import SwiftUI

/// Khung vẽ của trình soạn (đặc tả T1.9 mục 2): ảnh dựng của trang ở dưới, lớp điều khiển AppKit ở trên vẽ khung
/// chọn, tay nắm, đường gióng. Chọn, kéo, đổi cỡ (`⇧` giữ tỉ lệ), phím mũi tên dời 1 px (`⇧` 10 px), nhấp đúp phần tử
/// chữ để sửa tại chỗ. Mọi thay đổi đi qua các hàm gọi lại, mỗi lần thả chuột là một bước hoàn tác.
struct CanvasView: NSViewRepresentable {
    struct Callbacks {
        var select: (UUID?) -> Void
        /// Khung mới của phần tử; `coalescing` gộp các lần dời bằng phím thành một bước.
        var commitFrame: (UUID, PixelRect, _ coalescing: String?) -> Void
        /// Khung đang kéo (chưa lưu), để dựng thử.
        var previewFrame: (UUID, PixelRect?) -> Void
        var commitText: (UUID, String) -> Void
        /// Bắt đầu (id) hoặc thôi (nil) sửa chữ tại chỗ: ảnh dựng giấu chữ của phần tử đang sửa để khỏi lộ bóng.
        var editingText: (UUID?) -> Void
        /// Tách trang tại dòng con trỏ khi đang sửa chữ chính.
        var splitAtLine: (Int) -> Void
        var delete: (UUID) -> Void
        var bringForward: (UUID) -> Void
        var sendBackward: (UUID) -> Void
        var detach: (UUID) -> Void
        var dropFiles: ([URL], PixelPoint) -> Void
        /// Phím "T": thêm ô chữ giữa khung vẽ.
        var addText: () -> Void
    }

    let slide: Slide?
    let theme: Theme
    let image: CGImage?
    let selectedElementID: UUID?
    let callbacks: Callbacks

    func makeNSView(context: Context) -> EditorCanvasView {
        let view = EditorCanvasView()
        view.configure(slide: slide, theme: theme, image: image, selected: selectedElementID, callbacks: callbacks)
        return view
    }

    func updateNSView(_ view: EditorCanvasView, context: Context) {
        view.configure(slide: slide, theme: theme, image: image, selected: selectedElementID, callbacks: callbacks)
    }
}

/// Lớp vẽ và nhận thao tác của khung vẽ. Toạ độ: hệ lật (gốc trên trái) như toạ độ khung vẽ của mẫu.
final class EditorCanvasView: NSView, NSTextViewDelegate {
    private var slide: Slide?
    private var theme = Theme.fallback()
    private var image: CGImage?
    /// Bản `NSImage` của ảnh dựng, vẽ theo hệ lật.
    private var picture: NSImage?
    private var selectedID: UUID?
    private var callbacks: CanvasView.Callbacks?

    /// Thao tác chuột đang diễn ra.
    private enum Drag {
        case move(id: UUID, start: PixelRect, origin: NSPoint)
        case resize(id: UUID, handle: ResizeHandle, start: PixelRect, origin: NSPoint)
    }

    private var drag: Drag?
    /// Khung đang kéo, vẽ thay khung đã lưu cho tới khi thả chuột.
    private var draftFrame: (id: UUID, rect: PixelRect)?
    private var guides: [CanvasGuide] = []
    private var editor: NSTextView?
    private var editingID: UUID?
    /// Theo dõi nhấp chuột khi đang sửa chữ: nhấp ra ngoài khung vẽ (vùng xám, bảng bên) thì kết thúc sửa.
    private var clickMonitor: Any?
    /// Căn dọc của ô đang sửa, để ô gõ nằm đúng chỗ chữ hiện trên trang.
    private var editingVerticalAlignment: CoreModel.VerticalAlignment = .middle
    /// Khung phần tử đang sửa (toạ độ khung nhìn); ô gõ cao vừa chữ, đặt trong khung này theo căn dọc.
    private var editingFrame: NSRect = .zero
    /// Kiểu chữ và số đo (theo bộ dựng chữ) của ô đang sửa.
    private var editingStyle: CoreModel.TextStyle?
    private var editingMetrics: TextMetrics?
    /// Lịch sử hoàn tác riêng của ô gõ. Ô gõ không ghi vào lịch sử của cửa sổ: nó bị huỷ khi thôi sửa, các bước
    /// còn lại sẽ trỏ vào đối tượng đã giải phóng và ⌘Z làm sập ứng dụng.
    private var editorUndo: UndoManager?

    private static let handleSize: CGFloat = 9

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Canvas"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Rời cửa sổ (đổi chế độ) khi đang sửa chữ: lưu chữ và gỡ bộ theo dõi nhấp chuột.
        if window == nil {
            endTextEditing(commit: true)
        }
    }
    override var acceptsFirstResponder: Bool { true }

    func configure(slide: Slide?, theme: Theme, image: CGImage?, selected: UUID?, callbacks: CanvasView.Callbacks) {
        let slideChanged = self.slide?.id != slide?.id
        // Đổi trang khi đang sửa chữ: lưu chữ vào trang cũ trước khi nhận trang mới.
        if slideChanged {
            endTextEditing(commit: true, deferred: true)
        }
        self.slide = slide
        self.theme = theme
        self.callbacks = callbacks
        if self.image !== image {
            self.image = image
            picture = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        if selectedID != selected {
            selectedID = selected
            // Bỏ chọn (Esc) hay chọn phần tử khác giữa lúc kéo: thôi kéo, không giữ khung tạm.
            if drag != nil {
                cancelDrag()
            }
        }
        if slideChanged, drag != nil {
            cancelDrag()
        }
        if let draftFrame, drag == nil,
            slideChanged || slide?.displayFrame(of: draftFrame.id, theme: theme) == draftFrame.rect
        {
            self.draftFrame = nil
        }
        needsDisplay = true
    }

    /// Thôi thao tác chuột đang dở mà không lưu: bỏ khung tạm, đường gióng.
    private func cancelDrag() {
        drag = nil
        draftFrame = nil
        guides = []
    }

    // MARK: - Toạ độ

    private var scale: CGFloat {
        theme.canvasSize.width > 0 ? bounds.width / CGFloat(theme.canvasSize.width) : 1
    }

    private func viewRect(_ rect: PixelRect) -> NSRect {
        NSRect(
            x: CGFloat(rect.x) * scale, y: CGFloat(rect.y) * scale, width: CGFloat(rect.width) * scale,
            height: CGFloat(rect.height) * scale)
    }

    private func canvasPoint(_ point: NSPoint) -> PixelPoint {
        PixelPoint(x: Double(point.x / scale), y: Double(point.y / scale))
    }

    /// Khung đang hiện của phần tử (khung đang kéo nếu có).
    private func frame(of id: UUID) -> PixelRect? {
        if let draftFrame, draftFrame.id == id { return draftFrame.rect }
        return slide?.displayFrame(of: id, theme: theme)
    }

    private func element(_ id: UUID) -> Element? {
        slide?.elements.first { $0.id == id }
    }

    /// Phần tử trên cùng dưới điểm.
    private func hitElement(at point: NSPoint) -> UUID? {
        guard let slide else { return nil }
        for element in slide.elements.reversed() {
            if let rect = frame(of: element.id), viewRect(rect).insetBy(dx: -2, dy: -2).contains(point) {
                return element.id
            }
        }
        return nil
    }

    private func handleRects(for rect: NSRect) -> [(ResizeHandle, NSRect)] {
        let size = Self.handleSize
        return ResizeHandle.all.map { handle in
            let x: CGFloat
            if handle.contains(.left) {
                x = rect.minX
            } else if handle.contains(.right) {
                x = rect.maxX
            } else {
                x = rect.midX
            }
            let y: CGFloat
            if handle.contains(.top) {
                y = rect.minY
            } else if handle.contains(.bottom) {
                y = rect.maxY
            } else {
                y = rect.midY
            }
            return (handle, NSRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
        }
    }

    // MARK: - Vẽ

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        picture?.draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue])
        drawSafeArea()
        drawGuides()
        guard let selectedID, let rect = frame(of: selectedID), let element = element(selectedID) else { return }
        let box = viewRect(rect)
        let accent = NSColor(Palette.accent)
        accent.setStroke()
        let outline = NSBezierPath(rect: box.insetBy(dx: -0.75, dy: -0.75))
        outline.lineWidth = 1.5
        outline.stroke()
        if element.isLockedToTheme {
            drawPill(String(localized: "Theme slot, locked"), at: NSPoint(x: box.minX, y: box.minY - 24))
        } else if editingID == nil {
            for (_, handle) in handleRects(for: box) {
                let path = NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2)
                NSColor.white.setFill()
                path.fill()
                accent.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
        let size = String(
            format: "X %.0f · Y %.0f · %.0f × %.0f", rect.x, rect.y, rect.width, rect.height)
        drawPill(size, at: NSPoint(x: box.midX, y: box.maxY + 8), centered: true)
    }

    private func drawSafeArea() {
        let inset = CGFloat(CanvasSnapping.safeInset)
        let safe = bounds.insetBy(dx: bounds.width * inset, dy: bounds.height * inset)
        let path = NSBezierPath(rect: safe)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.22).setStroke()
        path.stroke()
    }

    private func drawGuides() {
        guard !guides.isEmpty else { return }
        let accent = NSColor(Palette.accent)
        for guide in guides {
            let path = NSBezierPath()
            let position = CGFloat(guide.position) * scale
            if guide.axis == .vertical {
                path.move(to: NSPoint(x: position, y: 0))
                path.line(to: NSPoint(x: position, y: bounds.height))
            } else {
                path.move(to: NSPoint(x: 0, y: position))
                path.line(to: NSPoint(x: bounds.width, y: position))
            }
            path.lineWidth = 1
            path.setLineDash([5, 3], count: 2, phase: 0)
            accent.setStroke()
            path.stroke()
            let label: String
            switch guide.source {
            case .canvasCenter: label = String(localized: "Center")
            case .safeEdge: label = String(localized: "Safe area")
            case .canvasEdge: label = String(localized: "Edge")
            case .element, .elementCenter: label = ""
            }
            if !label.isEmpty {
                let point = guide.axis == .vertical ? NSPoint(x: position + 6, y: 8) : NSPoint(x: 8, y: position + 6)
                drawPill(label, at: point, accent: true)
            }
        }
    }

    private func drawPill(_ text: String, at point: NSPoint, centered: Bool = false, accent: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: accent ? NSColor(Palette.onAccent) : NSColor(Palette.text),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var origin = point
        if centered { origin.x -= (size.width + 16) / 2 }
        let pill = NSRect(x: origin.x, y: origin.y, width: size.width + 16, height: 20)
        (accent ? NSColor(Palette.accent) : NSColor(Palette.bgPressed)).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        string.draw(at: NSPoint(x: pill.minX + 8, y: pill.minY + (20 - size.height) / 2))
    }

    // MARK: - Chuột

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if editor != nil {
            endTextEditing(commit: true)
        }
        if let selectedID, let rect = frame(of: selectedID), element(selectedID)?.isLockedToTheme == false,
            let handle = handleRects(for: viewRect(rect)).first(where: { $0.1.insetBy(dx: -3, dy: -3).contains(point) })
        {
            drag = .resize(id: selectedID, handle: handle.0, start: rect, origin: point)
            return
        }
        let hit = hitElement(at: point)
        if hit != selectedID {
            selectedID = hit
            callbacks?.select(hit)
        }
        guard let hit, let rect = frame(of: hit) else {
            needsDisplay = true
            return
        }
        if event.clickCount == 2, case .text = element(hit) {
            beginTextEditing(hit)
            return
        }
        if element(hit)?.isLockedToTheme == false {
            drag = .move(id: hit, start: rect, origin: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let others = (slide?.elements ?? []).compactMap { element -> PixelRect? in
            guard element.id != draggedID else { return nil }
            return slide?.displayFrame(of: element.id, theme: theme)
        }
        switch drag {
        case .move(let id, let start, let origin):
            var rect = start
            rect.x += Double((point.x - origin.x) / scale)
            rect.y += Double((point.y - origin.y) / scale)
            let snapped = CanvasSnapping.snapMove(
                rect, canvas: theme.canvasSize, others: others, threshold: snapThreshold(event))
            draftFrame = (id, snapped.rect)
            guides = snapped.guides
        case .resize(let id, let handle, let start, let origin):
            let keepAspect = event.modifierFlags.contains(.shift)
            var rect = CanvasSnapping.resized(
                start, handle: handle, dx: Double((point.x - origin.x) / scale),
                dy: Double((point.y - origin.y) / scale), keepAspect: keepAspect)
            guides = []
            if !keepAspect {
                let snapped = CanvasSnapping.snapResize(
                    rect, handle: handle, canvas: theme.canvasSize, others: others, threshold: snapThreshold(event))
                rect = snapped.rect
                guides = snapped.guides
            }
            draftFrame = (id, rect)
        }
        if let draftFrame {
            callbacks?.previewFrame(draftFrame.id, draftFrame.rect)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            guides = []
            needsDisplay = true
        }
        guard drag != nil, let draft = draftFrame else { return }
        // Giữ khung đã làm tròn tới khi trang lưu xong khớp khung này (xem `configure`), để không nháy khung cũ.
        let rounded = CanvasSnapping.rounded(draft.rect)
        draftFrame = (draft.id, rounded)
        callbacks?.commitFrame(draft.id, rounded, nil)
        callbacks?.previewFrame(draft.id, nil)
    }

    private var draggedID: UUID? {
        switch drag {
        case .move(let id, _, _), .resize(let id, _, _, _): return id
        case nil: return nil
        }
    }

    /// 6 điểm trên màn (khung vẽ thu nhỏ nên 6 điểm ảnh khung vẽ chỉ còn vài điểm), không dưới 6 điểm ảnh khung vẽ;
    /// giữ `⌘` khi kéo thì tắt hút.
    private func snapThreshold(_ event: NSEvent) -> Double {
        guard !event.modifierFlags.contains(.command) else { return 0 }
        let threshold = CanvasSnapping.defaultThreshold
        return scale > 0 ? max(threshold, threshold / Double(scale)) : threshold
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitElement(at: point), let element = element(hit) else { return nil }
        if hit != selectedID {
            selectedID = hit
            callbacks?.select(hit)
        }
        let menu = NSMenu()
        let forward = item(String(localized: "Bring forward"), key: "]") { [weak self] in
            self?.callbacks?.bringForward(hit)
        }
        let backward = item(String(localized: "Send backward"), key: "[") { [weak self] in
            self?.callbacks?.sendBackward(hit)
        }
        menu.addItem(forward)
        menu.addItem(backward)
        if element.isLockedToTheme {
            let detach = item(String(localized: "Detach from theme"), key: "") { [weak self] in
                self?.callbacks?.detach(hit)
            }
            menu.addItem(.separator())
            menu.addItem(detach)
        }
        let delete = item(String(localized: "Delete element"), key: "") { [weak self] in
            self?.callbacks?.delete(hit)
        }
        menu.addItem(.separator())
        menu.addItem(delete)
        return menu
    }

    private func item(_ title: String, key: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = key.isEmpty ? [] : .command
        return item
    }

    // MARK: - Phím

    override func keyDown(with event: NSEvent) {
        // "T": thêm ô chữ (mẫu `design/editor.html`), chỉ khi khung vẽ đang nhận phím để không cướp phím khi gõ.
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if editor == nil, plain, event.charactersIgnoringModifiers?.lowercased() == "t" {
            callbacks?.addText()
            return
        }
        guard editor == nil, let selectedID else {
            super.keyDown(with: event)
            return
        }
        let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        var delta: (Double, Double)?
        switch event.keyCode {
        case 123: delta = (-step, 0)
        case 124: delta = (step, 0)
        case 125: delta = (0, step)
        case 126: delta = (0, -step)
        case 51, 117:
            callbacks?.delete(selectedID)
            return
        case 36:
            if case .text = element(selectedID) {
                beginTextEditing(selectedID)
                return
            }
        default:
            break
        }
        guard let delta, element(selectedID)?.isLockedToTheme == false, var rect = frame(of: selectedID) else {
            super.keyDown(with: event)
            return
        }
        rect.x += delta.0
        rect.y += delta.1
        callbacks?.commitFrame(selectedID, rect, "nudge.\(selectedID.uuidString)")
    }

    // MARK: - Sửa chữ tại chỗ

    /// Phủ một `NSTextView` đúng vị trí phần tử. Phông, cỡ (kể cả khi co chữ), khoảng dòng, giãn chữ và màu lấy từ
    /// `TextRenderer.metrics` để chữ đang gõ trùng chữ đã dựng; ảnh dựng giấu chữ gốc trong lúc sửa.
    func beginTextEditing(_ id: UUID) {
        guard editor == nil, case .text(let text)? = element(id), let rect = frame(of: id) else { return }
        let base = text.slot.map { theme.slots[$0] } ?? theme.slots.body
        let style = text.style.map { base.style.applying($0) } ?? base.style
        let view = NSTextView(frame: viewRect(rect))
        view.isVerticallyResizable = false
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.containerSize = NSSize(width: view.frame.width, height: .greatestFiniteMagnitude)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.insertionPointColor = NSColor(Palette.accent)
        view.string = text.text
        view.delegate = self
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.textContainerInset = .zero
        view.setAccessibilityLabel(String(localized: "Edit text"))
        addSubview(view)
        editor = view
        editingID = id
        editingStyle = style
        editingMetrics = nil
        editorUndo = UndoManager()
        editingVerticalAlignment = style.verticalAlignment
        editingFrame = viewRect(rect)
        applyEditorMetrics()
        window?.makeFirstResponder(view)
        view.selectAll(nil)
        startClickMonitor()
        callbacks?.editingText(id)
        needsDisplay = true
    }

    /// Đo lại khối chữ như bộ dựng (co chữ đổi theo độ dài) và áp phông, nhịp dòng, màu cho ô gõ.
    private func applyEditorMetrics() {
        guard let editor, let style = editingStyle else { return }
        let block = TextBlock(
            string: editor.string.isEmpty ? " " : editor.string, style: ResolvedTextStyle(style),
            autoFit: style.autoFit, maxLines: style.maxLines)
        let metrics = TextRenderer.metrics(block, frameSize: editingFrame.size, scale: scale)
        if let current = editingMetrics, current.fontScale == metrics.fontScale {
            alignEditor()
            return
        }
        editingMetrics = metrics
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = Self.alignment(style.alignment)
        paragraph.minimumLineHeight = metrics.lineAdvance
        paragraph.maximumLineHeight = metrics.lineAdvance
        var attributes: [NSAttributedString.Key: Any] = [
            .font: metrics.font,
            .foregroundColor: Self.color(style.color),
            .paragraphStyle: paragraph,
        ]
        if metrics.letterSpacing != 0 {
            attributes[.kern] = metrics.letterSpacing
        }
        editor.typingAttributes = attributes
        if let storage = editor.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        alignEditor()
    }

    /// Ô gõ cao vừa chữ. Đường cơ sở dòng đầu đặt đúng chỗ bộ dựng đặt nó: khối chữ căn dọc trong khung phần tử,
    /// dòng đầu cách đỉnh khối một `ascent`.
    private func alignEditor() {
        guard let editor, let metrics = editingMetrics, let layout = editor.layoutManager,
            let container = editor.textContainer
        else { return }
        layout.ensureLayout(for: container)
        var lines = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in
            lines += 1
        }
        if layout.extraLineFragmentTextContainer != nil {
            lines += 1
        }
        lines = max(1, lines)
        let firstBaseline: CGFloat
        if layout.numberOfGlyphs > 0 {
            let fragment = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            firstBaseline = fragment.minY + layout.location(forGlyphAt: 0).y
        } else {
            firstBaseline = metrics.lineAdvance - metrics.descent
        }
        let free = editingFrame.height - metrics.blockHeight(lines: lines)
        let offset: CGFloat
        switch editingVerticalAlignment {
        case .top: offset = 0
        case .middle: offset = free / 2
        case .bottom: offset = free
        }
        let baseline = editingFrame.minY + offset + metrics.ascent
        let height = max(layout.usedRect(for: container).height, metrics.lineAdvance).rounded(.up)
        let frame = NSRect(
            x: editingFrame.minX, y: baseline - firstBaseline, width: editingFrame.width, height: height)
        if editor.frame != frame {
            editor.frame = frame
        }
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        applyEditorMetrics()
    }

    private func startClickMonitor() {
        stopClickMonitor()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let location = event.locationInWindow
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                self?.handleClickWhileEditing(at: location, windowNumber: windowNumber)
            }
            return event
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }

    /// Nhấp trong khung vẽ đã có `mouseDown` lo; nhấp ra ngoài khung vẽ thì lưu chữ và thôi sửa.
    private func handleClickWhileEditing(at location: NSPoint, windowNumber: Int) {
        guard editor != nil, let window, window.windowNumber == windowNumber else { return }
        if !bounds.contains(convert(location, from: nil)) {
            endTextEditing(commit: true)
        }
    }

    /// Xong sửa chữ: `commit` thì gửi chữ mới. `deferred` khi đang trong lượt cập nhật của SwiftUI: gửi ở vòng chạy
    /// sau để không sửa trạng thái giữa lượt vẽ.
    func endTextEditing(commit: Bool, deferred: Bool = false) {
        guard let editor, let editingID else { return }
        let text = editor.string
        stopClickMonitor()
        self.editor = nil
        self.editingID = nil
        editingStyle = nil
        editingMetrics = nil
        editorUndo?.removeAllActions()
        editorUndo = nil
        editor.removeFromSuperview()
        let changed: Bool
        if commit, case .text(let original)? = element(editingID), original.text != text {
            changed = true
        } else {
            changed = false
        }
        if deferred {
            let send = callbacks?.commitText
            let finish = callbacks?.editingText
            DispatchQueue.main.async {
                if changed { send?(editingID, text) }
                finish?(nil)
            }
        } else {
            if changed { callbacks?.commitText(editingID, text) }
            callbacks?.editingText(nil)
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        editorUndo
    }

    /// Lịch sử hoàn tác của ô sửa chữ tại chỗ khi ô gõ đang nhận phím trong cửa sổ chính; `nil` khi không sửa.
    /// Nút Hoàn tác giữ phím tắt ⌘Z nên phải hỏi ở đây, không thì ⌘Z rơi vào lịch sử bộ trình chiếu.
    static var activeTextUndoManager: UndoManager? {
        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView,
            let canvas = view.delegate as? EditorCanvasView, canvas.editor === view
        else { return nil }
        return canvas.editorUndo
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endTextEditing(commit: true)
            return true
        }
        return false
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard let editingID, slide?.primaryTextIndex.map({ slide?.elements[$0].id == editingID }) == true else {
            return menu
        }
        let split = item(String(localized: "Split slide at cursor"), key: "") { [weak self, weak view] in
            guard let self, let view else { return }
            let location = view.selectedRange().location
            let before = (view.string as NSString).substring(to: min(location, (view.string as NSString).length))
            let line = before.components(separatedBy: "\n").count - 1
            self.endTextEditing(commit: true)
            self.callbacks?.splitAtLine(line)
        }
        menu.insertItem(split, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    func textDidEndEditing(_ notification: Notification) {
        endTextEditing(commit: true)
    }

    private static func color(_ color: RGBA) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255)
    }

    private static func alignment(_ alignment: CoreModel.TextAlignment) -> NSTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        }
    }

    // MARK: - Kéo tệp vào

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard
            let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
            !urls.isEmpty
        else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        callbacks?.dropFiles(urls, canvasPoint(point))
        return true
    }
}

/// Mục menu chạy một closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    @objc private func run() {
        handler()
    }
}

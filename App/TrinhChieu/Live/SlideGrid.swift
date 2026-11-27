import AppKit
import CoreModel
import SwiftUI

/// Lưới trang chiếu (mẫu `design/live.html`, `.grid`): `NSCollectionView` để hàng trăm thẻ vẫn cuộn nhẹ.
///
/// Bấm một thẻ là lên màn (hành vi chuẩn của phần mềm trình chiếu). Lưới không nhận phím: phím sang trang do
/// ``LiveKeyMonitor`` xử lý cho cả cửa sổ.
struct SlideGrid: NSViewRepresentable {
    let cards: [SlideCard]
    /// Thẻ đang lên màn (chỉ khi nguồn đang xem là nguồn đang chiếu).
    let liveIndex: Int?
    let nextIndex: Int?
    /// Số cột, 3 đến 8.
    let columns: Int
    let thumbnails: SlideThumbnailCache?
    let onActivate: @MainActor (Int) -> Void

    func makeCoordinator() -> SlideGridController {
        SlideGridController()
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }
}

@MainActor final class SlideGridController: NSObject, NSCollectionViewDataSource {
    private static let itemIdentifier = NSUserInterfaceItemIdentifier("SlideCard")

    private let layout = SlideGridLayout()
    private var collectionView: NSCollectionView?
    private var cards: [SlideCard] = []
    private var liveIndex: Int?
    private var nextIndex: Int?
    private weak var thumbnails: SlideThumbnailCache?
    private var onActivate: @MainActor (Int) -> Void = { _ in }

    func makeScrollView() -> NSScrollView {
        let collection = SlideCollectionView()
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.isSelectable = false
        collection.backgroundColors = [NSColor(Palette.bgStage)]
        collection.register(SlideCardItem.self, forItemWithIdentifier: Self.itemIdentifier)
        collection.setAccessibilityLabel(String(localized: "Slides"))

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        collectionView = collection
        return scroll
    }

    func update(_ grid: SlideGrid) {
        onActivate = grid.onActivate
        if thumbnails !== grid.thumbnails {
            thumbnails = grid.thumbnails
        }
        grid.thumbnails?.onRendered = { [weak self] key in self?.thumbnailDidRender(key) }
        if layout.columns != grid.columns {
            layout.columns = grid.columns
            layout.invalidateLayout()
        }
        let liveChanged = liveIndex != grid.liveIndex
        if cards != grid.cards {
            cards = grid.cards
            liveIndex = grid.liveIndex
            nextIndex = grid.nextIndex
            collectionView?.reloadData()
        } else if liveChanged || nextIndex != grid.nextIndex {
            liveIndex = grid.liveIndex
            nextIndex = grid.nextIndex
            refreshVisibleStates()
        }
        if liveChanged, let live = grid.liveIndex {
            reveal(live)
        }
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        cards.count
    }

    func collectionView(
        _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.itemIdentifier, for: indexPath)
        if let cardItem = item as? SlideCardItem, cards.indices.contains(indexPath.item) {
            let card = cards[indexPath.item]
            cardItem.cardView.configure(
                card: card, state: state(of: card.index), image: thumbnails?.image(for: card.thumbnail))
            cardItem.cardView.onActivate = { [weak self] index in self?.onActivate(index) }
        }
        return item
    }

    // MARK: - Cập nhật

    private func state(of index: Int) -> SlideCardView.State {
        if index == liveIndex { return .live }
        if index == nextIndex { return .next }
        return .normal
    }

    private func refreshVisibleStates() {
        guard let collectionView else { return }
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) as? SlideCardItem else { continue }
            item.cardView.setState(state(of: indexPath.item))
        }
    }

    private func thumbnailDidRender(_ key: ThumbnailKey) {
        guard let collectionView, let image = thumbnails?.image(for: key) else { return }
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard cards.indices.contains(indexPath.item), cards[indexPath.item].thumbnail == key,
                let item = collectionView.item(at: indexPath) as? SlideCardItem
            else { continue }
            item.cardView.setImage(image)
        }
    }

    /// Cuộn tới thẻ đang lên màn khi nó nằm ngoài vùng đang thấy.
    private func reveal(_ index: Int) {
        guard let collectionView, cards.indices.contains(index) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard let attributes = layout.layoutAttributesForItem(at: indexPath) else { return }
        if !collectionView.visibleRect.contains(attributes.frame) {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
        }
    }
}

/// Lưới không giữ focus bàn phím: phím sang trang thuộc về cả cửa sổ.
final class SlideCollectionView: NSCollectionView {
    override var acceptsFirstResponder: Bool { false }
}

/// Bố cục lưới: chia đều bề ngang theo số cột, thẻ 16:9 kèm dòng số và nhãn đoạn.
final class SlideGridLayout: NSCollectionViewFlowLayout {
    var columns = 5
    static let inset: CGFloat = 20
    static let columnGap: CGFloat = 12
    static let rowGap: CGFloat = 20
    /// Khoảng giữa hình và dòng nhãn, và chiều cao dòng nhãn.
    static let metaGap: CGFloat = 6
    static let metaHeight: CGFloat = 16
    private var preparedWidth: CGFloat = 0

    override func prepare() {
        if let collectionView {
            let width = collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width
            preparedWidth = width
            let count = CGFloat(max(1, columns))
            let available = width - Self.inset * 2 - Self.columnGap * (count - 1)
            let cardWidth = max(80, (available / count).rounded(.down))
            itemSize = NSSize(width: cardWidth, height: (cardWidth * 9 / 16).rounded() + Self.metaGap + Self.metaHeight)
            sectionInset = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
            minimumInteritemSpacing = Self.columnGap
            minimumLineSpacing = Self.rowGap
        }
        super.prepare()
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - preparedWidth) > 0.5
    }
}

final class SlideCardItem: NSCollectionViewItem {
    let cardView = SlideCardView()

    override func loadView() {
        view = cardView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView.resetForReuse()
    }
}

/// Một thẻ trang chiếu (`.slide-card`): hình 16:9 bo 6 px, vạch màu đoạn ở đáy hình, nhãn "Trên màn"/"Kế tiếp",
/// dòng số thứ tự và nhãn đoạn.
final class SlideCardView: NSView {
    enum State: Equatable {
        case normal
        case next
        case live
    }

    var onActivate: (@MainActor (Int) -> Void)?

    private let frameView = FlippedView()
    private let imageView = NSView()
    private let fallbackText = NSTextField(wrappingLabelWithString: "")
    private let groupBar = NSView()
    private let ring = NSView()
    private let glow = NSView()
    private let badge = PaddedLabel()
    private let numberLabel = NSTextField(labelWithString: "")
    private let groupLabel = NSTextField(labelWithString: "")

    private var card: SlideCard?
    private var state: State = .normal
    private var isHovered = false
    private var tracking: NSTrackingArea?
    private static let breathKey = "breath"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        glow.wantsLayer = true
        ring.wantsLayer = true
        frameView.wantsLayer = true
        frameView.layer?.cornerRadius = Metrics.radius
        frameView.layer?.masksToBounds = true
        frameView.layer?.backgroundColor = NSColor.black.cgColor
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspectFill
        groupBar.wantsLayer = true
        groupBar.layer?.cornerRadius = 1

        fallbackText.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        fallbackText.textColor = NSColor.white.withAlphaComponent(0.85)
        fallbackText.alignment = .center
        fallbackText.maximumNumberOfLines = 4
        fallbackText.lineBreakMode = .byTruncatingTail

        badge.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        badge.isHidden = true

        numberLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        groupLabel.font = NSFont.systemFont(ofSize: 12)
        groupLabel.lineBreakMode = .byTruncatingTail
        groupLabel.cell?.truncatesLastVisibleLine = true

        addSubview(glow)
        addSubview(frameView)
        frameView.addSubview(imageView)
        frameView.addSubview(fallbackText)
        frameView.addSubview(groupBar)
        frameView.addSubview(badge)
        addSubview(ring)
        addSubview(numberLabel)
        addSubview(groupLabel)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override var isFlipped: Bool { true }

    func configure(card: SlideCard, state: State, image: CGImage?) {
        self.card = card
        self.state = state
        numberLabel.stringValue = card.number
        groupLabel.stringValue = card.label
        groupLabel.toolTip = card.label.isEmpty ? nil : card.label
        fallbackText.stringValue = card.text
        setImage(image)
        let disabled = card.enabled ? 1.0 : 0.3
        imageView.alphaValue = disabled
        fallbackText.alphaValue = disabled
        let label = String(format: String(localized: "Slide %@, %@"), card.number, card.label)
        setAccessibilityLabel(card.enabled ? label : label + ", " + String(localized: "disabled"))
        applyAppearance()
        needsLayout = true
    }

    func setState(_ state: State) {
        guard state != self.state else { return }
        self.state = state
        applyAppearance()
    }

    func setImage(_ image: CGImage?) {
        imageView.layer?.contents = image
        fallbackText.isHidden = image != nil
    }

    // MARK: - Bố cục

    override func layout() {
        super.layout()
        let frameHeight = max(0, bounds.height - SlideGridLayout.metaGap - SlideGridLayout.metaHeight)
        let frameRect = NSRect(x: 0, y: 0, width: bounds.width, height: frameHeight)
        frameView.frame = frameRect
        imageView.frame = frameView.bounds
        fallbackText.frame = frameView.bounds.insetBy(dx: 10, dy: 10)
        groupBar.frame = NSRect(x: 8, y: frameHeight - 8, width: max(0, bounds.width - 16), height: 2)
        let badgeWidth = badge.fittingWidth
        badge.frame = NSRect(x: bounds.width - badgeWidth, y: 0, width: badgeWidth, height: 20)
        ring.frame = frameRect.insetBy(dx: -2, dy: -2)
        glow.frame = frameRect.insetBy(dx: -5, dy: -5)
        let metaY = frameHeight + SlideGridLayout.metaGap
        numberLabel.sizeToFit()
        numberLabel.frame = NSRect(x: 0, y: metaY, width: numberLabel.frame.width, height: SlideGridLayout.metaHeight)
        let labelX = numberLabel.frame.maxX + 8
        groupLabel.frame = NSRect(
            x: labelX, y: metaY, width: max(0, bounds.width - labelX), height: SlideGridLayout.metaHeight)
    }

    // MARK: - Màu và trạng thái

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyColors()
        }
        updateBreathing()
    }

    private func applyColors() {
        let accent = NSColor(Palette.accent).cgColor
        guard let ringLayer = ring.layer, let glowLayer = glow.layer, let frameLayer = frameView.layer else { return }
        ringLayer.cornerRadius = Metrics.radius + 2
        glowLayer.cornerRadius = Metrics.radius + 5
        glowLayer.borderWidth = 0
        frameLayer.borderWidth = 0
        switch state {
        case .live:
            ringLayer.borderWidth = 2
            ringLayer.borderColor = accent
            glowLayer.borderWidth = 3
            glowLayer.borderColor = NSColor(Palette.glow).cgColor
        case .next:
            ringLayer.borderWidth = 0
            frameLayer.borderWidth = 1
            frameLayer.borderColor = accent
        case .normal:
            ringLayer.borderWidth = 0
            frameLayer.borderWidth = 1
            frameLayer.borderColor = NSColor(isHovered ? Palette.accentLine : Palette.lineStrong).cgColor
        }
        if state == .next && isHovered {
            frameLayer.borderColor = accent
        }

        switch state {
        case .live:
            badge.stringValue = String(localized: "On screen")
            badge.textColor = NSColor(Palette.onAccent)
            badge.fill = NSColor(Palette.accent).cgColor
            badge.isHidden = false
        case .next:
            badge.stringValue = String(localized: "Up next")
            badge.textColor = .white
            badge.fill = NSColor.black.withAlphaComponent(0.65).cgColor
            badge.isHidden = false
        case .normal:
            badge.isHidden = true
        }
        groupBar.layer?.backgroundColor = groupColor()?.cgColor ?? NSColor.clear.cgColor
        numberLabel.textColor = NSColor(state == .live ? Palette.accent : Palette.text3)
        groupLabel.textColor = NSColor(state == .live ? Palette.accent : Palette.text2)
        needsLayout = true
    }

    private func groupColor() -> NSColor? {
        guard let card else { return nil }
        if let custom = card.groupColor {
            return NSColor(
                srgbRed: CGFloat(custom.red) / 255, green: CGFloat(custom.green) / 255,
                blue: CGFloat(custom.blue) / 255, alpha: CGFloat(custom.alpha) / 255)
        }
        switch card.groupKind {
        case .verse: return NSColor(Palette.groupVerse)
        case .chorus, .prechorus: return NSColor(Palette.groupChorus)
        case .bridge: return NSColor(Palette.groupBridge)
        case .ending, .tag: return NSColor(Palette.groupEnding)
        case .intro: return NSColor(Palette.groupIntro)
        case .custom, nil: return nil
        }
    }

    /// Quầng thở 2,6 giây quanh thẻ đang lên màn, chạy bằng Core Animation. Giảm chuyển động: quầng tĩnh.
    private func updateBreathing() {
        guard let glowLayer = glow.layer else { return }
        glowLayer.removeAnimation(forKey: Self.breathKey)
        guard state == .live else {
            glowLayer.opacity = 0
            return
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            glowLayer.opacity = 0.8
            return
        }
        glowLayer.opacity = 1
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0.35, 1, 0.35]
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = Motion.breath
        animation.repeatCount = .infinity
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        glowLayer.add(animation, forKey: Self.breathKey)
    }

    // MARK: - Chuột

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        activate()
    }

    override func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    /// Thẻ cũ được dùng lại cho trang khác.
    func resetForReuse() {
        isHovered = false
        setImage(nil)
    }

    /// Cả thẻ là một nút: bấm vào hình, viền hay nhãn đều lên màn.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    private func activate() {
        guard let card else { return }
        onActivate?(card.index)
    }
}

/// Nhãn nhỏ có nền và lề (`.pill`), bo góc dưới trái như `.slide-card__tag`.
final class PaddedLabel: NSView {
    private let label = NSTextField(labelWithString: "")

    var stringValue: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            needsLayout = true
        }
    }

    var textColor: NSColor? {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    var font: NSFont? {
        get { label.font }
        set { label.font = newValue }
    }

    var fill: CGColor? {
        didSet { layer?.backgroundColor = fill }
    }

    /// Bề ngang vừa chữ cộng lề 8 px mỗi bên.
    var fittingWidth: CGFloat {
        label.intrinsicContentSize.width.rounded(.up) + 16
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Metrics.radius
        layer?.maskedCorners = [.layerMinXMinYCorner]
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override func layout() {
        super.layout()
        let size = label.intrinsicContentSize
        label.frame = NSRect(
            x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width.rounded(.up), height: size.height)
    }
}

/// Khung có gốc toạ độ ở góc trên trái, cho bố cục từ trên xuống.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

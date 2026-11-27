import Foundation

/// Biến `ShowState` thành hai cảnh: đầu ra chính và màn hình nhắc. Đây là nơi duy nhất quyết định "nội dung trông
/// ra sao"; `RenderEngine` chỉ vẽ. Chỉ đọc dữ liệu qua `ShowContentProvider` (`sequence`, `theme`, `mediaURL`, `plan`).
///
/// Đầu ra chính:
/// - Khung vẽ là `canvasSize` của mẫu áp cho trang đang chiếu (không có trang thì của mẫu mặc định).
/// - Lớp nền phủ cả khung vẽ (`fill`; riêng trang media đơn thì `fit`). Video nền giữ `playbackID` chừng nào lớp nền
///   còn cùng nguồn (`origin`) và cùng media, nên đổi trang chữ cùng nền không làm video chạy lại từ đầu.
/// - Lớp trang: phần tử theo thứ tự; chữ có ô mẫu lấy khung và kiểu của ô rồi áp phần đè; chữ không ô mẫu lấy khung
///   của phần tử và kiểu `body` của mẫu áp phần đè. Media không còn trên đĩa thì bỏ phần tử và ghi log một lần.
/// - Chuyển cảnh là của mẫu.
///
/// Màn hình nhắc: bố cục cố định 1920x1080 nền đen (xem ``StageLayout``).
///
/// Bộ dựng nhớ lần phát video nền gần nhất để giữ `playbackID`, nên mỗi `ShowController` dùng một bộ dựng riêng.
/// Đóng băng và tập dượt không ảnh hưởng bộ dựng (controller lo).
@MainActor public final class SceneResolver: SceneResolving {
    /// Họ phông của đồng hồ màn hình nhắc: phông hệ thống với chữ số đều (mỗi chữ số rộng bằng nhau), để đồng hồ
    /// không rung khi đổi giây. `RenderEngine` ánh xạ sang `NSFont.monospacedDigitSystemFont`.
    public nonisolated static let monospacedDigitFontFamily = "system-monospaced-digits"

    private let log: any LogSink
    private let calendar: Calendar
    /// Lần phát video nền đang dùng.
    private var backgroundPlayback: BackgroundPlayback?
    /// Media đã báo mất, để không ghi log lặp lại mỗi giây.
    private var reportedMissingMedia: Set<MediaID> = []

    /// - Parameters:
    ///   - log: nơi ghi media bị mất.
    ///   - timeZone: múi giờ của đồng hồ trên màn hình nhắc.
    public init(log: any LogSink = NullLogSink(), timeZone: TimeZone = .current) {
        self.log = log
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func resolve(state: ShowState, provider: any ShowContentProvider, now: Date) -> ScenePublication {
        let live = LiveContext(state: state, provider: provider)
        let program = programScene(state: state, live: live, provider: provider, now: now)
        let stage = stageScene(state: state, live: live, provider: provider, now: now)
        return ScenePublication(program: program, stage: stage)
    }

    // MARK: - Đầu ra chính

    private func programScene(
        state: ShowState, live: LiveContext, provider: any ShowContentProvider, now: Date
    ) -> RenderScene {
        let theme = provider.theme(live.sequence?.themeID)
        let canvas = theme.canvasSize
        var layers: [RenderLayer] = []
        if case .background(let background, let origin)? = state.layers[.background] {
            let layer = backgroundLayer(
                background, origin: origin, canvas: canvas, startedAt: state.live?.wentLiveAt ?? now,
                provider: provider)
            if let layer {
                layers.append(layer)
            }
        } else {
            backgroundPlayback = nil
        }
        if case .slide(let slideID)? = state.layers[.slide], let position = state.live,
            let entry = live.entry, entry.slide.id == slideID
        {
            let items = slideItems(entry.slide, theme: theme, wentLiveAt: position.wentLiveAt, provider: provider)
            layers.append(RenderLayer(kind: .slide, contentID: slideID, items: items))
        }
        guard !layers.isEmpty else {
            var scene = RenderScene.empty(canvas: canvas)
            scene.transition = theme.transition
            return scene
        }
        return RenderScene(canvasSize: canvas, layers: layers, transition: theme.transition)
    }

    private func backgroundLayer(
        _ background: SlideBackground, origin: UUID, canvas: PixelSize, startedAt: Date,
        provider: any ShowContentProvider
    ) -> RenderLayer? {
        let frame = PixelRect(size: canvas)
        switch background.kind {
        case .none:
            backgroundPlayback = nil
            return nil
        case .color:
            backgroundPlayback = nil
            let item = RenderItem.color(background.color ?? .black, frame: frame)
            return RenderLayer(kind: .background, contentID: origin, items: [item])
        case .media:
            guard let mediaID = background.mediaID, let url = locate(mediaID, provider: provider) else {
                backgroundPlayback = nil
                return nil
            }
            // Trang của nguồn media đơn có id là `contentUUID` của media: giữ nguyên tỉ lệ, không cắt.
            let fit: ContentFit = origin == mediaID.contentUUID ? .fit : .fill
            let item: RenderItem
            if Self.isVideo(url) {
                let run = playback(origin: origin, mediaID: mediaID, startedAt: startedAt)
                let video = VideoRef(
                    media: MediaRef(id: mediaID), loop: background.loop ?? true, muted: background.muted ?? false,
                    playbackID: run.playbackID, startedAt: run.startedAt)
                item = .video(video, frame: frame, fit: fit)
            } else {
                backgroundPlayback = nil
                item = .image(MediaRef(id: mediaID), frame: frame, fit: fit)
            }
            return RenderLayer(kind: .background, contentID: origin, items: [item])
        }
    }

    /// Giữ lần phát nếu lớp nền vẫn cùng nguồn và cùng media; không thì mở lần phát mới bắt đầu từ `startedAt`.
    private func playback(origin: UUID, mediaID: MediaID, startedAt: Date) -> BackgroundPlayback {
        if let current = backgroundPlayback, current.origin == origin, current.mediaID == mediaID {
            return current
        }
        let key = "background:\(origin.uuidString):\(mediaID.rawValue):\(Self.stamp(startedAt))"
        let playback = BackgroundPlayback(
            origin: origin, mediaID: mediaID, playbackID: UUID(hashing: key), startedAt: startedAt)
        backgroundPlayback = playback
        return playback
    }

    private func slideItems(
        _ slide: Slide, theme: Theme, wentLiveAt: Date, provider: any ShowContentProvider
    ) -> [RenderItem] {
        var items: [RenderItem] = []
        for element in slide.elements {
            switch element {
            case .text(let text):
                if let item = textItem(text, theme: theme) {
                    items.append(item)
                }
            case .image(let image):
                guard locate(image.mediaID, provider: provider) != nil else {
                    continue
                }
                items.append(.image(MediaRef(id: image.mediaID), frame: image.frame, fit: image.fit))
            case .video(let video):
                guard locate(video.mediaID, provider: provider) != nil else {
                    continue
                }
                let key = "video:\(video.id.uuidString):\(Self.stamp(wentLiveAt))"
                let reference = VideoRef(
                    media: MediaRef(id: video.mediaID), loop: video.loop, muted: video.muted,
                    playbackID: UUID(hashing: key), startedAt: wentLiveAt)
                items.append(.video(reference, frame: video.frame, fit: video.fit))
            case .shape(let shape):
                items.append(.color(shape.fill, frame: shape.frame))
            }
        }
        return items
    }

    /// Khối chữ của phần tử; chữ rỗng (chỉ có khoảng trắng) thì không vẽ, kể cả hộp nền.
    private func textItem(_ element: TextElement, theme: Theme) -> RenderItem? {
        let base: ThemeSlot
        let frame: PixelRect
        if let slot = element.slot {
            base = theme.slots[slot]
            frame = base.frame
        } else {
            base = theme.slots.body
            frame = element.frame
        }
        let style = element.style.map { base.style.applying($0) } ?? base.style
        guard !element.text.allSatisfy(\.isWhitespace) else {
            return nil
        }
        let string = Self.transformed(element.text, style.transform)
        let block = TextBlock(
            string: string, style: ResolvedTextStyle(style), autoFit: style.autoFit, maxLines: style.maxLines)
        return .text(block, frame: frame)
    }

    /// Đường dẫn của media, hoặc `nil` và ghi log (một lần cho tới khi media có lại).
    private func locate(_ id: MediaID, provider: any ShowContentProvider) -> URL? {
        guard let url = provider.mediaURL(id) else {
            if reportedMissingMedia.insert(id).inserted {
                log.log(.warning, "Media \(id.rawValue) không còn trên đĩa, bỏ khỏi cảnh.", category: "SceneResolver")
            }
            return nil
        }
        reportedMissingMedia.remove(id)
        return url
    }

    // MARK: - Màn hình nhắc

    private func stageScene(
        state: ShowState, live: LiveContext, provider: any ShowContentProvider, now: Date
    ) -> RenderScene {
        let canvas = StageLayout.canvas
        let background = RenderLayer(
            kind: .background, contentID: StageLayout.backgroundContentID,
            items: [.color(.black, frame: PixelRect(size: canvas))])
        var items: [RenderItem] = []
        let contentID: UUID
        if let sequence = live.sequence, let index = live.index, state.live != nil {
            let entry = sequence.slides[index]
            contentID = entry.slide.id
            var title = sequence.title
            if let label = entry.groupLabel {
                title += " · " + label.displayName
            }
            items.append(StageLayout.text(title, .title))
            items.append(StageLayout.text(Self.plainText(of: entry.slide), .current))
            if let upcoming = upcomingText(sequence: sequence, index: index, provider: provider) {
                items.append(StageLayout.text(upcoming, .next))
            }
            items.append(StageLayout.text(entry.slide.notes, .notes))
        } else {
            contentID = StageLayout.idleContentID
            if let selected = state.selected, let title = provider.sequence(for: selected)?.title {
                items.append(StageLayout.text(Self.upNext(title), .next))
            }
        }
        items = items.filter { item in
            guard case .text(let block, _) = item else {
                return true
            }
            return !block.string.allSatisfy(\.isWhitespace)
        }
        let content = RenderLayer(kind: .slide, contentID: contentID, items: items)
        let clock = RenderLayer(
            kind: .overlay, contentID: StageLayout.clockContentID,
            items: [StageLayout.text(clockText(now), .clock)])
        return RenderScene(canvasSize: canvas, layers: [background, content, clock])
    }

    /// Chữ trang kế; ở trang cuối của mục thì "Tiếp theo: <tiêu đề mục kế>" của chương trình.
    private func upcomingText(sequence: SlideSequence, index: Int, provider: any ShowContentProvider) -> String? {
        let slides = sequence.slides
        if let next = slides.indices.first(where: { $0 > index && slides[$0].slide.enabled }) {
            let text = Self.plainText(of: slides[next].slide)
            return text.isEmpty ? "Trang kế không có chữ" : text
        }
        guard case .planItem(let planID, let itemID) = sequence.source, let plan = provider.plan(planID),
            let position = plan.items.firstIndex(where: { $0.id == itemID })
        else {
            return nil
        }
        for item in plan.items[(position + 1)...] where item.isLiveable {
            let source = LiveSource.planItem(planID: planID, itemID: item.id)
            guard let upcoming = provider.sequence(for: source), upcoming.slides.contains(where: \.slide.enabled) else {
                continue
            }
            return Self.upNext(upcoming.title)
        }
        return nil
    }

    private func clockText(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return [parts.hour, parts.minute, parts.second].map { Self.twoDigits($0 ?? 0) }.joined(separator: ":")
    }

    // MARK: - Tiện ích

    static func upNext(_ title: String) -> String {
        "Tiếp theo: " + title
    }

    /// Chữ của mọi phần tử chữ trên trang (NFC), mỗi phần tử một dòng, bỏ phần tử rỗng.
    static func plainText(of slide: Slide) -> String {
        var lines: [String] = []
        for case .text(let element) in slide.elements {
            let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(text.precomposedStringWithCanonicalMapping)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func transformed(_ text: String, _ transform: TextTransform) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping
        switch transform {
        case .none:
            return normalized
        case .uppercase:
            return normalized.uppercased(with: Locale(identifier: "vi_VN")).precomposedStringWithCanonicalMapping
        }
    }

    static func isVideo(_ url: URL) -> Bool {
        MediaKind(fileExtension: url.pathExtension) == .video
    }

    /// Dấu thời gian ổn định trên mọi máy để băm thành `playbackID`.
    static func stamp(_ date: Date) -> String {
        String(date.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}

/// Lần phát video nền: giữ nguyên khi lớp nền không đổi nguồn và media.
private struct BackgroundPlayback {
    var origin: UUID
    var mediaID: MediaID
    var playbackID: UUID
    var startedAt: Date
}

/// Chuỗi và vị trí của trang đang chiếu, tra một lần cho cả hai cảnh.
@MainActor private struct LiveContext {
    var sequence: SlideSequence?
    var index: Int?

    init(state: ShowState, provider: any ShowContentProvider) {
        guard let live = state.live, let sequence = provider.sequence(for: live.source) else {
            return
        }
        self.sequence = sequence
        self.index = sequence.index(of: live)
    }

    var entry: SequencedSlide? {
        guard let sequence, let index else {
            return nil
        }
        return sequence.slides[index]
    }
}

/// Bố cục cố định của màn hình nhắc ở giai đoạn 1: khung vẽ 1920x1080, nền đen.
public enum StageLayout {
    public static let canvas = PixelSize.fullHD

    /// Mã nội dung cố định của các lớp màn hình nhắc.
    static let backgroundContentID = UUID(hashing: "stage:background")
    static let idleContentID = UUID(hashing: "stage:idle")
    static let clockContentID = UUID(hashing: "stage:clock")

    /// Các vùng của màn hình nhắc.
    public enum Region: CaseIterable, Sendable {
        /// Tiêu đề chuỗi đang chiếu và nhãn đoạn.
        case title
        /// Giờ thật `HH:mm:ss`.
        case clock
        /// Toàn bộ chữ của trang đang chiếu.
        case current
        /// Chữ trang kế, hoặc "Tiếp theo: ...".
        case next
        /// Ghi chú của trang.
        case notes

        public var frame: PixelRect {
            switch self {
            case .title:
                return PixelRect(x: 48, y: 32, width: 1200, height: 56)
            case .clock:
                return PixelRect(x: 1392, y: 32, width: 480, height: 56)
            case .current:
                return PixelRect(x: 48, y: 120, width: 1824, height: 560)
            case .next:
                return PixelRect(x: 48, y: 712, width: 1824, height: 240)
            case .notes:
                return PixelRect(x: 48, y: 984, width: 1824, height: 64)
            }
        }

        public var style: ResolvedTextStyle {
            switch self {
            case .title:
                return StageLayout.style(size: 40, weight: 500, color: StageLayout.white(alpha: 179))
            case .clock:
                return StageLayout.style(
                    size: 48, weight: 600, color: .white, alignment: .right,
                    fontFamily: SceneResolver.monospacedDigitFontFamily)
            case .current:
                return StageLayout.style(size: 64, weight: 600, color: .white, vertical: .top)
            case .next:
                return StageLayout.style(size: 44, weight: 500, color: StageLayout.white(alpha: 140), vertical: .top)
            case .notes:
                return StageLayout.style(size: 36, weight: 500, color: StageLayout.amber)
            }
        }

        public var autoFit: AutoFit {
            switch self {
            case .title, .clock:
                return .none
            case .current, .next, .notes:
                return AutoFit(mode: .shrink, minScale: 0.5)
            }
        }

        public var maxLines: Int? {
            switch self {
            case .title, .clock:
                return 1
            case .current, .next, .notes:
                return nil
            }
        }
    }

    /// Vàng hổ phách của ghi chú.
    static let amber = RGBA(red: 0xFF, green: 0xBF, blue: 0x00)

    static func white(alpha: UInt8) -> RGBA {
        RGBA(red: 255, green: 255, blue: 255, alpha: alpha)
    }

    static func style(
        size: Double, weight: Int, color: RGBA, alignment: TextAlignment = .left, vertical: VerticalAlignment = .middle,
        fontFamily: String = "system"
    ) -> ResolvedTextStyle {
        ResolvedTextStyle(
            fontFamily: fontFamily, fontWeight: weight, fontSize: size, color: color, alignment: alignment,
            verticalAlignment: vertical, lineHeight: 1.15, letterSpacing: 0, stroke: .none, shadow: .none, box: .none)
    }

    static func text(_ string: String, _ region: Region) -> RenderItem {
        let block = TextBlock(string: string, style: region.style, autoFit: region.autoFit, maxLines: region.maxLines)
        return .text(block, frame: region.frame)
    }
}

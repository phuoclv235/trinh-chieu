import Foundation

/// Nguồn nội dung cho `ShowController` và `SceneResolving`. Chạy đồng bộ trên luồng chính:
/// thư viện giữ toàn bộ tài liệu trong bộ nhớ (T1.3) và tra Kinh Thánh dưới 1 ms (T1.2).
@MainActor public protocol ShowContentProvider: AnyObject {
    func plan(_ id: UUID) -> ServicePlan?
    /// `nil` là không tìm thấy hoặc không chiếu được (mục `header`, `note`).
    func sequence(for source: LiveSource) -> SlideSequence?
    /// `nil` hoặc không tìm thấy là mẫu mặc định của thư viện.
    func theme(_ id: UUID?) -> Theme
    /// `nil` là media không còn trên đĩa.
    func mediaURL(_ id: MediaID) -> URL?
}

/// Nguồn nội dung giữ trong bộ nhớ, dùng cho test và bản xem thử.
@MainActor public final class InMemoryContentProvider: ShowContentProvider {
    public var presentations: [UUID: Presentation]
    public var plans: [UUID: ServicePlan]
    public var themes: [UUID: Theme]
    public var defaultTheme: Theme
    public var mediaURLs: [MediaID: URL]
    /// Chuỗi Kinh Thánh dựng sẵn, khoá theo `(translation, reference)` qua `LiveSource.scripture`.
    public var scriptureSequences: [LiveSource: SlideSequence]

    public init(
        presentations: [Presentation] = [], plans: [ServicePlan] = [], themes: [Theme] = [],
        defaultTheme: Theme = .fallback(), mediaURLs: [MediaID: URL] = [:],
        scriptureSequences: [LiveSource: SlideSequence] = [:]
    ) {
        self.presentations = Dictionary(uniqueKeysWithValues: presentations.map { ($0.id, $0) })
        self.plans = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        self.themes = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })
        self.defaultTheme = defaultTheme
        self.mediaURLs = mediaURLs
        self.scriptureSequences = scriptureSequences
    }

    public func plan(_ id: UUID) -> ServicePlan? {
        plans[id]
    }

    public func theme(_ id: UUID?) -> Theme {
        guard let id, let theme = themes[id] else {
            return defaultTheme
        }
        return theme
    }

    public func mediaURL(_ id: MediaID) -> URL? {
        mediaURLs[id]
    }

    public func sequence(for source: LiveSource) -> SlideSequence? {
        switch source {
        case .presentation(let id, let order):
            guard let presentation = presentations[id] else {
                return nil
            }
            let theme = presentation.themeID
            return SlideSequence(presentation: presentation, source: source, arrangementID: order, themeID: theme)
        case .scripture:
            return scriptureSequences[source]
        case .media(let id):
            guard mediaURLs[id] != nil else {
                return nil
            }
            return SlideSequence(media: id, source: source, title: id.rawValue)
        case .planItem(let planID, let itemID):
            guard let item = plans[planID]?.items.first(where: { $0.id == itemID }) else {
                return nil
            }
            return sequence(for: item, source: source)
        }
    }

    private func sequence(for item: ServicePlanItem, source: LiveSource) -> SlideSequence? {
        switch item {
        case .header, .note:
            return nil
        case .presentation(let entry):
            guard let presentation = presentations[entry.presentationID] else {
                return nil
            }
            let theme = entry.themeID ?? presentation.themeID
            let order = entry.arrangementID
            return SlideSequence(presentation: presentation, source: source, arrangementID: order, themeID: theme)
        case .scripture(let entry):
            let key = LiveSource.scripture(translation: entry.translation, reference: entry.reference)
            guard var sequence = scriptureSequences[key] else {
                return nil
            }
            sequence.source = source
            sequence.themeID = entry.themeID ?? sequence.themeID
            return sequence
        case .media(let entry):
            guard mediaURLs[entry.mediaID] != nil else {
                return nil
            }
            return SlideSequence(media: entry.mediaID, source: source, title: entry.mediaID.rawValue)
        }
    }
}

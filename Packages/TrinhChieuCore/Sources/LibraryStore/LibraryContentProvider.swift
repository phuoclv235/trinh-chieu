import CoreModel
import Foundation
import Scripture

/// Nguồn nội dung thật cho `ShowController` và `SceneResolver`: đọc `LibraryStore` và các bản dịch Kinh Thánh đã mở.
///
/// Chuỗi trang được lưu đệm theo nguồn. Đệm của một nguồn bị xoá khi một ``LibraryChange`` chạm vào id mà chuỗi đó
/// dựa vào (bộ trình chiếu, chương trình, mục, mẫu trình bày, thông tin thư viện, media). Thứ tự đúng khi nối với
/// controller: gọi ``libraryDidChange(_:)`` trước, rồi mới gửi `ShowCommand.contentDidChange`; ``startObserving(_:)``
/// làm sẵn việc này.
///
/// Bản dịch Kinh Thánh mở bất đồng bộ qua `BibleStore`, rồi đăng ký bằng ``register(_:)`` để tra đồng bộ (dưới 1 ms).
@MainActor public final class LibraryContentProvider: ShowContentProvider {
    public let store: LibraryStore

    /// Mẫu dùng khi thư viện không còn mẫu nào. Mã cố định để lớp nền lấy từ mẫu này không đổi `contentID`.
    static let fallbackTheme = Theme.fallback(id: UUID(hashing: "theme:fallback"))

    private let parser: ReferenceParser
    private let builder: ScriptureSlideBuilder
    private let log: any LogSink
    /// Bản dịch đã mở, khoá theo mã viết thường.
    private var translations: [String: BibleTranslation] = [:]
    private var cache: [LiveSource: CacheEntry] = [:]
    private var observation: Task<Void, Never>?
    /// Lỗi đã ghi log, để nhịp mỗi giây của màn hình nhắc không ghi lặp lại.
    private var reportedProblems: Set<String> = []

    public init(
        store: LibraryStore, translations: [BibleTranslation] = [], catalog: BookCatalog = .standard,
        log: any LogSink = NullLogSink()
    ) {
        self.store = store
        self.parser = ReferenceParser(catalog: catalog)
        self.builder = ScriptureSlideBuilder(catalog: catalog)
        self.log = log
        for translation in translations {
            self.translations[Self.key(translation.info.code)] = translation
        }
    }

    // MARK: - Bản dịch

    /// Thêm hoặc thay một bản dịch; xoá đệm Kinh Thánh của mã đó.
    public func register(_ translation: BibleTranslation) {
        let code = Self.key(translation.info.code)
        translations[code] = translation
        cache = cache.filter { $0.value.translation != code }
        reportedProblems.removeAll()
    }

    /// Bỏ một bản dịch (ví dụ khi xoá khỏi thư viện); xoá đệm Kinh Thánh của mã đó.
    public func unregisterTranslation(code: String) {
        let code = Self.key(code)
        translations[code] = nil
        cache = cache.filter { $0.value.translation != code }
        reportedProblems.removeAll()
    }

    // MARK: - Thay đổi thư viện

    /// Xoá đệm của mọi nguồn dựa vào id trong `change`.
    public func libraryDidChange(_ change: LibraryChange) {
        cache = cache.filter { _, entry in
            entry.documentIDs.isDisjoint(with: change.documentIDs) && entry.mediaIDs.isDisjoint(with: change.mediaIDs)
        }
    }

    /// Nghe ``LibraryStore/changes``: mỗi thay đổi xoá đệm liên quan rồi mới gọi `onChange` (nơi gửi
    /// `ShowCommand.contentDidChange`). Gọi lại thì thay lần nghe cũ.
    public func startObserving(_ onChange: @escaping @MainActor (LibraryChange) -> Void = { _ in }) {
        observation?.cancel()
        let stream = store.changes
        observation = Task { [weak self] in
            for await change in stream {
                guard let self else {
                    return
                }
                self.libraryDidChange(change)
                onChange(change)
            }
        }
    }

    public func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    /// Số nguồn đang có trong đệm. Dùng cho test.
    var cachedSourceCount: Int { cache.count }

    // MARK: - ShowContentProvider

    public func plan(_ id: UUID) -> ServicePlan? {
        store.plans[id]
    }

    public func theme(_ id: UUID?) -> Theme {
        if let id, let theme = store.themes[id] {
            return theme
        }
        if let id = store.info.defaultThemeID, let theme = store.themes[id] {
            return theme
        }
        // Mẫu mặc định bị xoá: lấy mẫu có mã nhỏ nhất cho ổn định giữa các lần gọi.
        return store.themes.values.min { $0.id.uuidString < $1.id.uuidString } ?? Self.fallbackTheme
    }

    public func mediaURL(_ id: MediaID) -> URL? {
        store.mediaURL(id)
    }

    public func sequence(for source: LiveSource) -> SlideSequence? {
        if let entry = cache[source] {
            return entry.sequence
        }
        guard let entry = makeEntry(for: source) else {
            return nil
        }
        cache[source] = entry
        return entry.sequence
    }

    // MARK: - Dựng chuỗi

    private func makeEntry(for source: LiveSource) -> CacheEntry? {
        switch source {
        case .presentation(let id, let arrangementID):
            return presentationEntry(id, arrangementID: arrangementID, themeID: nil, source: source)
        case .scripture(let translation, let reference):
            return scriptureEntry(translation: translation, reference: reference, themeID: nil, source: source)
        case .media(let id):
            return mediaEntry(id, source: source)
        case .planItem(let planID, let itemID):
            guard let item = store.plans[planID]?.items.first(where: { $0.id == itemID }) else {
                return nil
            }
            var entry: CacheEntry?
            switch item {
            case .header, .note:
                return nil
            case .presentation(let value):
                entry = presentationEntry(
                    value.presentationID, arrangementID: value.arrangementID, themeID: value.themeID, source: source)
            case .scripture(let value):
                entry = scriptureEntry(
                    translation: value.translation, reference: value.reference, themeID: value.themeID, source: source)
            case .media(let value):
                entry = mediaEntry(value.mediaID, source: source)
            }
            entry?.documentIDs.formUnion([planID, itemID])
            return entry
        }
    }

    /// Bộ trình chiếu: mẫu theo ưu tiên mục chương trình > bộ trình chiếu > mặc định thư viện.
    private func presentationEntry(
        _ id: UUID, arrangementID: UUID?, themeID override: UUID?, source: LiveSource
    ) -> CacheEntry? {
        guard let presentation = store.presentations[id] else {
            return nil
        }
        let themeID = override ?? presentation.themeID ?? store.info.defaultThemeID
        let sequence = SlideSequence(
            presentation: presentation, source: source, arrangementID: arrangementID, themeID: themeID)
        var ids: Set<UUID> = [id, store.info.id]
        ids.formUnion([override, presentation.themeID, store.info.defaultThemeID].compactMap { $0 })
        return CacheEntry(sequence: sequence, documentIDs: ids)
    }

    /// Kinh Thánh: phân tích lại địa chỉ, tra bản dịch, chia trang theo thiết lập Kinh Thánh của mẫu đang áp
    /// (mục chương trình đè, không thì mẫu Kinh Thánh mặc định của thư viện).
    private func scriptureEntry(
        translation code: String, reference: String, themeID override: UUID?, source: LiveSource
    ) -> CacheEntry? {
        let key = Self.key(code)
        guard let translation = translations[key] else {
            report("Chưa mở bản dịch \(code) để chiếu \(reference).")
            return nil
        }
        guard case .reference(let parsed) = parser.parse(reference) else {
            report("Không hiểu địa chỉ câu \"\(reference)\".")
            return nil
        }
        let themeID = override ?? store.info.defaultScriptureThemeID ?? store.info.defaultThemeID
        let theme = self.theme(themeID)
        let verses: [Verse]
        do {
            verses = try translation.verses(parsed)
        } catch {
            report("Không tra được \(reference) (\(code)): \(error)")
            return nil
        }
        let options = ScriptureLayoutOptions(settings: theme.scripture)
        let slides = builder.slides(for: parsed, verses: verses, translation: translation.info, options: options)
        let place = ReferenceFormatter.format(parsed.ranges, catalog: builder.catalog, dash: "–")
        let title = "\(place) (\(translation.info.displayAbbreviation))"
        let sequence = SlideSequence(
            source: source, title: title, themeID: themeID,
            slides: slides.enumerated().map { index, slide in
                SequencedSlide(slide: slide, groupID: nil, groupLabel: nil, indexInGroup: index, presentationID: nil)
            })
        var ids: Set<UUID> = [store.info.id, theme.id]
        ids.formUnion([override, store.info.defaultScriptureThemeID, store.info.defaultThemeID].compactMap { $0 })
        return CacheEntry(sequence: sequence, documentIDs: ids, translation: key)
    }

    /// Media đơn: một trang, nền là media đó, không có chữ.
    private func mediaEntry(_ id: MediaID, source: LiveSource) -> CacheEntry? {
        guard let info = store.media[id] else {
            return nil
        }
        let sequence = SlideSequence(media: id, source: source, title: info.originalName)
        return CacheEntry(sequence: sequence, documentIDs: [store.info.id], mediaIDs: [id])
    }

    private func report(_ message: String) {
        if reportedProblems.insert(message).inserted {
            log.log(.warning, message, category: "LibraryContentProvider")
        }
    }

    private static func key(_ code: String) -> String {
        code.lowercased()
    }
}

/// Chuỗi đã dựng cùng các id nó dựa vào.
private struct CacheEntry {
    var sequence: SlideSequence
    var documentIDs: Set<UUID>
    var mediaIDs: Set<MediaID> = []
    /// Mã bản dịch (viết thường) với chuỗi Kinh Thánh.
    var translation: String?
}

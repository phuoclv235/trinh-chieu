import CoreModel
import Foundation

/// Nguồn nội dung cho ảnh thu nhỏ và khung vẽ của trình soạn: mọi thứ lấy từ thư viện, riêng bộ đang soạn lấy từ
/// bản soạn và trải phẳng theo thứ tự gốc (mọi đoạn, kể cả đoạn không có trong thứ tự hát).
@MainActor final class EditorContentProvider: ShowContentProvider {
    let base: any ShowContentProvider
    let presentation: Presentation
    let sequence: SlideSequence

    init(base: any ShowContentProvider, presentation: Presentation) {
        self.base = base
        self.presentation = presentation
        var flat = presentation
        flat.arrangements = []
        flat.activeArrangementID = nil
        sequence = SlideSequence(
            presentation: flat, source: .presentation(id: presentation.id, arrangementID: nil), arrangementID: nil,
            themeID: presentation.themeID)
    }

    func plan(_ id: UUID) -> ServicePlan? {
        base.plan(id)
    }

    func sequence(for source: LiveSource) -> SlideSequence? {
        if case .presentation(let id, _) = source, id == presentation.id {
            return sequence
        }
        return base.sequence(for: source)
    }

    func theme(_ id: UUID?) -> Theme {
        base.theme(id)
    }

    func mediaURL(_ id: MediaID) -> URL? {
        base.mediaURL(id)
    }
}

extension AppEnvironment {
    /// Nguồn nội dung của bộ đang soạn; `nil` khi chưa mở bộ nào.
    func editorContent() -> EditorContentProvider? {
        guard let content, let presentation = editingPresentation else { return nil }
        return EditorContentProvider(base: content, presentation: presentation)
    }

    /// Thẻ của mọi trang trong bộ đang soạn theo thứ tự gốc, kèm nguồn nội dung để dựng ảnh.
    func editorCards() -> (cards: [SlideCard], provider: EditorContentProvider)? {
        guard let provider = editorContent() else { return nil }
        let theme = provider.theme(provider.sequence.themeID)
        let colors = SlideCards.groupColors(provider.presentation)
        return (SlideCards.make(provider.sequence, theme: theme, groupColors: colors), provider)
    }
}

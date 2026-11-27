import CoreModel
import Foundation
import LibraryStore

/// Thao tác của chế độ Trực tiếp. Mọi thao tác lên màn đi qua `ShowController.send` (qua ``AppEnvironment/send(_:)``).
extension AppEnvironment {
    /// Nguồn đang xem ở lưới giữa: nguồn vừa chọn, không thì nguồn đang chiếu.
    var browsedSource: LiveSource? {
        guard let state = show?.state else { return nil }
        return state.selected ?? state.live?.source
    }

    /// Chuỗi trang của một nguồn; `nil` khi không tìm thấy hoặc không chiếu được.
    func sequence(for source: LiveSource?) -> SlideSequence? {
        guard let source else { return nil }
        return content?.sequence(for: source)
    }

    /// Mẫu đang áp cho một chuỗi trang.
    func theme(for sequence: SlideSequence) -> Theme? {
        content?.theme(sequence.themeID)
    }

    /// Thẻ của một chuỗi trang.
    func cards(for sequence: SlideSequence) -> [SlideCard] {
        guard let content else { return [] }
        let presentationID = sequence.slides.first?.presentationID
        let colors = SlideCards.groupColors(presentationID.flatMap { library?.presentations[$0] })
        return SlideCards.make(sequence, theme: content.theme(sequence.themeID), groupColors: colors)
    }

    /// Xếp hàng dựng ảnh thu nhỏ cho các thẻ chưa có ảnh (gọi khi danh sách thẻ đổi).
    func prepareThumbnails(_ cards: [SlideCard], sequence: SlideSequence) {
        guard let content else { return }
        thumbnails.prepare(cards, sequence: sequence, provider: content)
    }

    /// Thứ tự hát đang dùng cho nguồn (mục chương trình đè thứ tự hát của bộ trình chiếu).
    func arrangementID(for source: LiveSource) -> UUID? {
        switch source {
        case .presentation(_, let arrangementID):
            return arrangementID
        case .planItem(let planID, let itemID):
            guard case .presentation(let entry)? = library?.plans[planID]?.items.first(where: { $0.id == itemID })
            else { return nil }
            return entry.arrangementID
        case .scripture, .media:
            return nil
        }
    }

    /// Đổi thứ tự hát của nguồn đang xem. Bộ trình chiếu xem từ thư viện: chỉ đổi cách xem, không sửa bộ.
    func selectArrangement(_ arrangementID: UUID, for source: LiveSource) {
        switch source {
        case .presentation(let id, _):
            send(.selectItem(.presentation(id: id, arrangementID: arrangementID)))
        case .planItem(_, let itemID):
            // Thứ tự hát riêng của mục chương trình; lõi điều phối đọc lại nguồn khi nội dung đổi.
            setArrangement(arrangementID, forPlanItem: itemID)
        case .scripture, .media:
            break
        }
    }

    /// Bấm thẻ: trang đó lên màn.
    func goLive(_ source: LiveSource, slideIndex: Int) {
        send(.goLive(source, slideIndex: slideIndex))
    }

    /// Trang kế. Chưa có gì trên màn thì trang bật đầu tiên của nguồn đang xem lên màn.
    @discardableResult func advance() -> Bool {
        guard let show else { return false }
        if show.state.live == nil {
            return goToFirst()
        }
        return show.send(.next) == .applied
    }

    /// Trang đầu (trang bật đầu tiên) của nguồn đang xem.
    @discardableResult func goToFirst() -> Bool {
        guard let source = browsedSource, let sequence = sequence(for: source),
            let first = SlideCards.firstEnabled(in: sequence)
        else { return false }
        return send(.goLive(source, slideIndex: first)) == .applied
    }

    /// Nền đang chiếu là video (hoặc âm thanh) có tiếng: nút Âm thanh (F4) có tác dụng.
    var backgroundHasSound: Bool {
        guard case .background(let background, _)? = show?.state.layers[.background], background.kind == .media,
            background.muted != true, let id = background.mediaID
        else { return false }
        guard let info = library?.media[id] else { return false }
        return info.kind != .image
    }

    /// Tắt tiếng media đang phát. Giai đoạn 1 chưa có lớp âm thanh riêng: xoá lớp nền khi nền là video có tiếng.
    @discardableResult func clearAudio() -> Bool {
        guard backgroundHasSound else { return false }
        return send(.clearLayer(.background)) == .applied
    }

    /// Xử lý một phím của chế độ Trực tiếp. Trả `true` khi phím có nghĩa ở đây (kể cả khi lệnh bị bỏ qua vì đã
    /// hết trang), để phím không đi tiếp xuống giao diện.
    func perform(_ key: LiveKey) -> Bool {
        guard show != nil else { return false }
        switch key {
        case .next: advance()
        case .previous: send(.previous)
        case .first: goToFirst()
        case .clearAll: send(.clearAll)
        case .clearText: send(.clearLayer(.slide))
        case .clearBackground: send(.clearLayer(.background))
        case .clearAudio: clearAudio()
        case .undo: return undoPlan()
        case .redo: return redoPlan()
        case .delete: return deleteSelectedPlanItem()
        }
        return true
    }
}

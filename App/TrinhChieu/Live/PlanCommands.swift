import CoreModel
import Foundation
import LibraryStore
import Observation
import Scripture

/// Chương trình buổi nhóm đang mở ở cột trái: bản soạn có hoàn tác, mục đang chọn, giờ bắt đầu thật của từng mục.
@MainActor @Observable final class PlanEditing {
    /// Bản soạn của chương trình đang mở; `nil` khi chưa mở chương trình nào.
    fileprivate(set) var editor: DocumentEditor<ServicePlan>?
    /// Mục đang chọn trong danh sách (kể cả tiêu đề phần, ghi chú): `⌫` xoá mục này.
    var selectedItemID: UUID?
    /// Giờ mục lên màn lần đầu trong phiên này.
    fileprivate(set) var itemStartedAt: [UUID: Date] = [:]
    @ObservationIgnored fileprivate var lastLiveItemID: UUID?

    var plan: ServicePlan? { editor?.document }

    /// Chuyển các phần tử ở `offsets` tới trước vị trí `destination` (tính theo mảng trước khi chuyển), như
    /// `List.onMove`.
    nonisolated static func move<Element>(_ items: inout [Element], from offsets: IndexSet, to destination: Int) {
        let valid = offsets.filter { items.indices.contains($0) }
        let moving = valid.sorted().map { items[$0] }
        for offset in valid.sorted(by: >) {
            items.remove(at: offset)
        }
        let shift = valid.filter { $0 < destination }.count
        items.insert(contentsOf: moving, at: min(items.count, max(0, destination - shift)))
    }

    /// Đóng thư viện: bỏ chương trình đang mở cùng lịch sử hoàn tác.
    func reset() {
        editor = nil
        selectedItemID = nil
        itemStartedAt = [:]
        lastLiveItemID = nil
    }
}

/// Thao tác trên chương trình buổi nhóm. Mọi sửa đổi đi qua `DocumentEditor<ServicePlan>` (có `⌘Z`) và lưu bằng
/// `LibraryStore.save`; xoá mục chỉ bỏ mục khỏi chương trình, không xoá bộ trình chiếu.
extension AppEnvironment {
    var activePlan: ServicePlan? { planEditing.plan }

    /// Mở chương trình (hoặc đóng khi `nil`) và báo lõi điều phối.
    func openPlan(_ id: UUID?) {
        guard let library else { return }
        planEditing.selectedItemID = nil
        planEditing.itemStartedAt = [:]
        planEditing.lastLiveItemID = nil
        guard let id, let plan = library.plans[id] else {
            planEditing.editor = nil
            send(.loadPlan(planID: nil))
            return
        }
        let editor = DocumentEditor(document: plan)
        editor.onChange = { [weak library] updated in library?.save(updated) }
        planEditing.editor = editor
        send(.loadPlan(planID: id))
    }

    /// Lần đầu vào chế độ Trực tiếp: mở chương trình có ngày gần hôm nay nhất.
    func openDefaultPlanIfNeeded(today: Date = Date()) {
        guard planEditing.editor == nil, let library else { return }
        if let plan = PlanDefaults.nearest(Array(library.plans.values), to: today) {
            openPlan(plan.id)
        }
    }

    /// "Chương trình mới": Chúa Nhật kế tiếp, bắt đầu 9:00.
    func createPlan(today: Date = Date()) {
        guard let library else { return }
        let plan = PlanDefaults.newPlan(today: today)
        library.save(plan)
        openPlan(plan.id)
    }

    /// Thư viện đổi từ ngoài (đồng bộ, sửa tay): lấy lại chương trình đang mở. Chương trình bị xoá thì đóng.
    func syncActivePlan() {
        guard let editor = planEditing.editor else { return }
        guard let stored = library?.plans[editor.document.id] else {
            openPlan(nil)
            return
        }
        if stored != editor.document {
            let fresh = DocumentEditor(document: stored)
            fresh.onChange = { [weak library] updated in library?.save(updated) }
            planEditing.editor = fresh
        }
    }

    // MARK: - Sửa

    private func editPlan(_ actionName: String, _ change: (inout ServicePlan) -> Void) {
        if planEditing.editor == nil {
            createPlan()
        }
        planEditing.editor?.apply(change, actionName: actionName)
    }

    /// Thêm mục vào cuối chương trình (chưa có chương trình thì tạo mới).
    func appendToPlan(_ item: ServicePlanItem) {
        editPlan(String(localized: "Add item")) { $0.items.append(item) }
        planEditing.selectedItemID = item.id
    }

    /// Chèn các mục ở vị trí `index` (kéo từ thư viện vào).
    func insertIntoPlan(_ items: [ServicePlanItem], at index: Int) {
        guard !items.isEmpty else { return }
        editPlan(String(localized: "Add item")) { plan in
            plan.items.insert(contentsOf: items, at: min(max(0, index), plan.items.count))
        }
    }

    /// Mục chương trình ứng với một dòng thư viện; `nil` với mẫu trình bày.
    func planItem(for row: LibraryRow) -> ServicePlanItem? {
        switch row.source {
        case .presentation(let id, let arrangementID):
            return .presentation(PlanPresentationItem(presentationID: id, arrangementID: arrangementID))
        case .media(let id):
            let duration = library?.media[id]?.duration
            return .media(PlanMediaItem(mediaID: id, plannedDuration: duration.map { ($0 / 60).rounded(.up) * 60 }))
        case .scripture(let translation, let reference):
            return .scripture(PlanScriptureItem(reference: reference, translation: translation))
        case .planItem, nil:
            return nil
        }
    }

    func removePlanItem(_ id: UUID) {
        guard let position = activePlan?.items.firstIndex(where: { $0.id == id }) else { return }
        editPlan(String(localized: "Remove item")) { $0.items.remove(at: position) }
        if planEditing.selectedItemID == id {
            let items = activePlan?.items ?? []
            planEditing.selectedItemID = items.isEmpty ? nil : items[min(position, items.count - 1)].id
        }
    }

    func movePlanItems(from offsets: IndexSet, to destination: Int) {
        editPlan(String(localized: "Move item")) { plan in
            PlanEditing.move(&plan.items, from: offsets, to: destination)
        }
    }

    /// Thời lượng dự kiến (phút); `nil` là bỏ.
    func setPlannedDuration(minutes: Int?, for id: UUID) {
        let seconds = minutes.map { Double($0 * 60) }
        editPlan(String(localized: "Change duration")) { plan in
            guard let index = plan.items.firstIndex(where: { $0.id == id }) else { return }
            plan.items[index] = plan.items[index].withPlannedDuration(seconds)
        }
    }

    /// Giờ bắt đầu "HH:mm"; trả `false` khi sai dạng.
    @discardableResult func setPlannedStart(_ text: String) -> Bool {
        guard let stored = PlanSchedule.storedClock(text) else { return false }
        editPlan(String(localized: "Change start time")) { $0.plannedStart = stored }
        return true
    }

    func renamePlan(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editPlan(String(localized: "Rename service plan")) { $0.title = trimmed }
    }

    /// Thêm tiêu đề phần hoặc ghi chú ngay sau mục đang chọn (không chọn gì thì ở cuối).
    func addTextItem(header: Bool, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item: ServicePlanItem =
            header ? .header(PlanHeaderItem(title: trimmed)) : .note(PlanNoteItem(text: trimmed))
        let selected = planEditing.selectedItemID
        editPlan(String(localized: "Add item")) { plan in
            let after = selected.flatMap { id in plan.items.firstIndex { $0.id == id } }
            plan.items.insert(item, at: after.map { $0 + 1 } ?? plan.items.count)
        }
        planEditing.selectedItemID = item.id
    }

    /// Đổi chữ của tiêu đề phần hoặc ghi chú.
    func setText(_ text: String, for id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editPlan(String(localized: "Rename item")) { plan in
            guard let index = plan.items.firstIndex(where: { $0.id == id }) else { return }
            switch plan.items[index] {
            case .header(var header):
                header.title = trimmed
                plan.items[index] = .header(header)
            case .note(var note):
                note.text = trimmed
                plan.items[index] = .note(note)
            case .presentation, .scripture, .media:
                break
            }
        }
    }

    /// Thứ tự hát riêng cho một mục chương trình (không sửa bộ trình chiếu).
    func setArrangement(_ arrangementID: UUID, forPlanItem id: UUID) {
        editPlan(String(localized: "Change song order")) { plan in
            guard let index = plan.items.firstIndex(where: { $0.id == id }),
                case .presentation(var entry) = plan.items[index]
            else { return }
            entry.arrangementID = arrangementID
            plan.items[index] = .presentation(entry)
        }
    }

    func undoPlan() -> Bool {
        guard let editor = planEditing.editor, editor.canUndo else { return false }
        editor.undo()
        return true
    }

    func redoPlan() -> Bool {
        guard let editor = planEditing.editor, editor.canRedo else { return false }
        editor.redo()
        return true
    }

    /// `⌫`: bỏ mục đang chọn khỏi chương trình.
    func deleteSelectedPlanItem() -> Bool {
        guard let id = planEditing.selectedItemID, activePlan?.items.contains(where: { $0.id == id }) == true else {
            return false
        }
        removePlanItem(id)
        return true
    }

    // MARK: - Chọn và giờ thật

    /// Bấm một mục: chọn; mục chiếu được thì hiện lưới trang của mục ở giữa.
    func selectPlanItem(_ item: ServicePlanItem) {
        planEditing.selectedItemID = item.id
        guard item.isLiveable, let plan = activePlan else { return }
        send(.selectItem(.planItem(planID: plan.id, itemID: item.id)))
    }

    /// Ghi giờ mục lên màn lần đầu (gọi mỗi khi trang đang chiếu đổi).
    func noteLiveChange() {
        guard let live = show?.state.live, case .planItem(let planID, let itemID) = live.source,
            planID == activePlan?.id
        else {
            planEditing.lastLiveItemID = nil
            return
        }
        guard itemID != planEditing.lastLiveItemID else { return }
        planEditing.lastLiveItemID = itemID
        if planEditing.itemStartedAt[itemID] == nil {
            planEditing.itemStartedAt[itemID] = live.wentLiveAt
        }
    }

    /// Mục chương trình đang chiếu.
    var livePlanItemID: UUID? {
        guard case .planItem(let planID, let itemID)? = show?.state.live?.source, planID == activePlan?.id else {
            return nil
        }
        return itemID
    }

    /// Giờ mục đang chiếu bắt đầu thật.
    func actualStart(of itemID: UUID) -> Date? {
        planEditing.itemStartedAt[itemID]
    }

    // MARK: - Kinh Thánh

    /// Bản dịch đã mở theo mã.
    func bibleTranslation(_ code: String?) -> BibleTranslation? {
        guard let code else { return nil }
        return openedTranslations[code.lowercased()]
    }
}

extension ServicePlanItem {
    /// Bản sao với thời lượng dự kiến mới.
    func withPlannedDuration(_ seconds: Double?) -> ServicePlanItem {
        switch self {
        case .header(var item):
            item.plannedDuration = seconds
            return .header(item)
        case .presentation(var item):
            item.plannedDuration = seconds
            return .presentation(item)
        case .scripture(var item):
            item.plannedDuration = seconds
            return .scripture(item)
        case .media(var item):
            item.plannedDuration = seconds
            return .media(item)
        case .note(var item):
            item.plannedDuration = seconds
            return .note(item)
        }
    }
}

import Foundation
import Observation

/// Soạn một tài liệu với hoàn tác và làm lại theo ảnh chụp giá trị.
/// Hai lần `apply` liên tiếp cùng `coalescingKey` trong vòng 1 giây gộp thành một bước (gõ chữ).
@MainActor @Observable public final class DocumentEditor<Doc: Equatable & Sendable> {
    public private(set) var document: Doc

    /// Số bước hoàn tác tối đa được giữ.
    public static var maxUndoSteps: Int { 200 }
    /// Khoảng thời gian tối đa giữa hai lần `apply` để gộp thành một bước.
    public static var coalescingInterval: TimeInterval { 1 }

    private struct Step {
        var snapshot: Doc
        var actionName: String
    }

    private var undoStack: [Step] = []
    private var redoStack: [Step] = []
    @ObservationIgnored private var lastCoalescingKey: String?
    @ObservationIgnored private var lastApplyAt: Date?
    @ObservationIgnored private let now: @MainActor () -> Date

    /// Gọi sau mỗi thay đổi (kể cả hoàn tác, làm lại). `LibraryStore` gắn vào để lưu có hoãn.
    @ObservationIgnored public var onChange: ((Doc) -> Void)?

    /// - Parameter now: nguồn thời gian, test truyền đồng hồ giả.
    public init(document: Doc, now: @escaping @MainActor () -> Date = { Date() }) {
        self.document = document
        self.now = now
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoActionName: String? { undoStack.last?.actionName }
    public var redoActionName: String? { redoStack.last?.actionName }

    /// Áp một thay đổi. Thay đổi không làm tài liệu khác đi thì không tạo bước hoàn tác.
    public func apply(_ change: (inout Doc) -> Void, actionName: String, coalescingKey: String? = nil) {
        var updated = document
        change(&updated)
        guard updated != document else {
            return
        }
        let time = now()
        if !coalesces(key: coalescingKey, at: time) {
            undoStack.append(Step(snapshot: document, actionName: actionName))
            if undoStack.count > Self.maxUndoSteps {
                undoStack.removeFirst(undoStack.count - Self.maxUndoSteps)
            }
        }
        redoStack.removeAll()
        lastCoalescingKey = coalescingKey
        lastApplyAt = time
        document = updated
        onChange?(document)
    }

    private func coalesces(key: String?, at time: Date) -> Bool {
        guard let key, key == lastCoalescingKey, !undoStack.isEmpty, let lastApplyAt else {
            return false
        }
        return time.timeIntervalSince(lastApplyAt) < Self.coalescingInterval
    }

    public func undo() {
        guard let step = undoStack.popLast() else {
            return
        }
        redoStack.append(Step(snapshot: document, actionName: step.actionName))
        restore(step.snapshot)
    }

    public func redo() {
        guard let step = redoStack.popLast() else {
            return
        }
        undoStack.append(Step(snapshot: document, actionName: step.actionName))
        restore(step.snapshot)
    }

    private func restore(_ snapshot: Doc) {
        lastCoalescingKey = nil
        lastApplyAt = nil
        document = snapshot
        onChange?(document)
    }
}

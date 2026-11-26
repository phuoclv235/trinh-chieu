import QuartzCore
import os

/// Một cảnh kèm số hiệu và thời điểm gửi, để vòng vẽ biết cảnh nào mới và đo độ trễ.
public struct MailboxEntry<Scene: Sendable>: Sendable {
    public let revision: UInt64
    public let postedAt: CFTimeInterval
    public let scene: Scene
}

/// Hộp thư giữ cảnh mới nhất. Bên gửi không bao giờ chờ vòng vẽ, vòng vẽ không bao giờ chờ bên gửi:
/// mỗi khung chỉ lấy bản mới nhất, các bản ở giữa bị bỏ qua.
public final class SceneMailbox<Scene: Sendable>: Sendable {
    private let slot = OSAllocatedUnfairLock<MailboxEntry<Scene>?>(initialState: nil)

    public init() {}

    /// Gửi cảnh mới. Trả về số hiệu đã gán.
    @discardableResult
    public func post(_ scene: Scene, at time: CFTimeInterval = CACurrentMediaTime()) -> UInt64 {
        slot.withLock { entry in
            let revision = (entry?.revision ?? 0) + 1
            entry = MailboxEntry(revision: revision, postedAt: time, scene: scene)
            return revision
        }
    }

    /// Cảnh mới nhất, hoặc `nil` khi chưa có cảnh nào.
    public func latest() -> MailboxEntry<Scene>? {
        slot.withLock { $0 }
    }
}

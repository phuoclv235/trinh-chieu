import Foundation

/// Đồng hồ của trình chiếu: thời điểm hiện tại và nhịp mỗi giây để màn hình nhắc cập nhật đồng hồ.
/// Test dùng đồng hồ giả.
@MainActor public protocol ShowClock: AnyObject {
    var now: Date { get }
    /// Bắt đầu gọi `handler` mỗi giây. Gọi lại thì thay `handler` cũ.
    func startTicking(_ handler: @escaping @MainActor () -> Void)
    func stopTicking()
}

/// Đồng hồ hệ thống, đếm nhịp bằng một `Task` trên luồng chính.
@MainActor public final class SystemShowClock: ShowClock {
    private var tickTask: Task<Void, Never>?

    public init() {}

    public var now: Date { Date() }

    public func startTicking(_ handler: @escaping @MainActor () -> Void) {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    return
                }
                handler()
            }
        }
    }

    public func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}

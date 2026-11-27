import os

/// Vẽ theo nhu cầu, dạng giữ ấm (T0.6, biện pháp B1 được giữ; `docs/ket-qua-ban-thu-metal.md`, lần chạy 7).
///
/// Cảnh đổi, đang hoà tan, có video, hay còn lớp chưa dựng xong thì vẽ mỗi nhịp. Cảnh đứng yên thì chỉ present lại
/// mỗi `keepWarmEvery` nhịp, display link không nghỉ: nghỉ hẳn làm mất khoảng 3 khung đầu khi cảnh đổi (chữ hiện trễ
/// khoảng 100 ms). Chỉ chuyển sang giữ ấm sau khi một khung đứng yên đã thật sự lên màn (`presentedTime > 0`), để
/// màn không dừng ở khung giữa hoà tan.
///
/// `tick` gọi trên luồng vẽ; `presented` gọi từ `presentedHandler` (luồng bất kỳ).
final class FramePacer: @unchecked Sendable {
    static let keepWarmEvery = 4

    /// Một khung được vẽ ở nhịp này.
    struct Frame: Equatable {
        /// Lần đổi gần nhất mà khung này thuộc về; khung đứng yên của lần đổi cũ không xác nhận lần đổi mới.
        let generation: UInt64
        /// Cảnh đứng yên khi vẽ khung này.
        let settled: Bool
        /// Nhịp trước bị bỏ (khoảng cách tới khung trước là cố ý, không phải rớt khung).
        let afterGap: Bool
    }

    private struct State {
        var generation: UInt64 = 0
        var confirmed = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Chỉ luồng vẽ đọc ghi.
    private var idleTicks = 0
    private var skippedLastTick = false

    /// Quyết định ở mỗi nhịp. `active`: cảnh đổi, đang hoà tan, có video hoặc còn lớp chưa dựng xong.
    /// Trả `nil` khi bỏ nhịp này.
    func tick(active: Bool) -> Frame? {
        let (generation, confirmed): (UInt64, Bool) = state.withLock { state in
            if active {
                state.generation &+= 1
                state.confirmed = false
            }
            return (state.generation, state.confirmed)
        }
        var render = true
        if active || !confirmed {
            idleTicks = 0
        } else {
            idleTicks += 1
            render = idleTicks % Self.keepWarmEvery == 0
        }
        defer { skippedLastTick = !render }
        guard render else { return nil }
        return Frame(generation: generation, settled: !active, afterGap: skippedLastTick)
    }

    /// Báo kết quả lên màn của một khung đã vẽ.
    func presented(_ frame: Frame, presentedTime: Double) {
        guard frame.settled, presentedTime > 0 else { return }
        state.withLock { state in
            if state.generation == frame.generation {
                state.confirmed = true
            }
        }
    }

    /// Đã xác nhận khung đứng yên lên màn (đang ở chế độ giữ ấm).
    var isSettled: Bool { state.withLock { $0.confirmed } }
}

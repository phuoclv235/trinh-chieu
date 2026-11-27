import Foundation
import os

/// Số đo bổ sung của T0.6 cho một đầu ra: khung rớt tính được cả khi vẽ theo nhu cầu, các lần khựng,
/// trễ của khung đầu tiên sau lúc nghỉ, số lần hồi phục.
///
/// Cách đếm khung rớt (dùng chung cho vẽ liên tục và vẽ theo nhu cầu):
/// - Nhịp bị lỡ: `targetPresentationTimestamp` của hai lần gọi vẽ liên tiếp cách nhau k chu kỳ (k > 1) khi display
///   link đang chạy thì có k - 1 nhịp không được gọi.
/// - Khung lên màn muộn hơn dự kiến: so khoảng cách thật giữa hai khung lên màn với khoảng cách giữa hai đích của
///   chúng. Vẽ liên tục thì đích cách nhau đúng một chu kỳ nên trùng với cách đếm của `FrameStats`; vẽ theo nhu cầu
///   thì khoảng nghỉ có chủ ý không bị tính là rớt.
/// - Khung không lên màn (`presentedTime == 0`).
/// Các nhịp rớt liền nhau gom thành một lần rớt; lần rớt từ 3 nhịp trở lên là một lần khựng.
final class LoadStats: Sendable {
    struct Stall: Sendable, Equatable {
        /// Giây kể từ lúc bắt đầu ghi.
        var time: Double
        /// Số nhịp liền nhau bị rớt.
        var frames: Int
    }

    struct Snapshot: Sendable {
        var nominalPeriod: Double
        var recordingDuration: Double
        var droppedFrames: Int
        var dropsPerMinute: [Int]
        var missedTicks: Int
        var latePresents: Int
        var notPresented: Int
        var stalls: [Stall]
        var renderedFrames: Int
        var skippedTicks: Int
        var pauses: Int
        var pausedSeconds: Double
        /// Trễ đổi cảnh của khung đầu tiên sau lúc display link nghỉ (chỉ có khi vẽ theo nhu cầu).
        var firstAfterIdleLatencies: [Double]
        /// Thời điểm (giây kể từ lúc bắt đầu ghi) tạo lại display link.
        var recoveries: [Double]
        /// Số khung lên màn (để biết lần chạy có hợp lệ không khi vẽ theo nhu cầu).
        var presentedFrames: Int
        /// Khung không lên màn ngay sau lúc display link chạy lại (trước khung đầu tiên lên màn).
        var notPresentedAfterResume: Int

        var dropsPerMinuteAverage: Double {
            Double(droppedFrames) / max(recordingDuration / 60, 1.0 / 60)
        }

        var longestStall: Int {
            stalls.map(\.frames).max() ?? 0
        }

        /// Lần rớt dài nhất kể cả khi dưới 3 nhịp.
        var longestDrop: Int
    }

    private struct State: Sendable {
        var recording = false
        var startedAt: Double = 0
        var stoppedAt: Double?
        var lastPresented: Double = 0
        var lastPresentedTarget: Double = 0
        var pendingMissedTicks = 0
        var notPresentedSinceLast = 0
        var droppedFrames = 0
        var dropsPerMinute: [Int] = []
        var missedTicks = 0
        var latePresents = 0
        var notPresented = 0
        var stalls: [Stall] = []
        var longestDrop = 0
        var renderedFrames = 0
        var skippedTicks = 0
        var pauses = 0
        var pausedSeconds: Double = 0
        var pausedAt: Double?
        var firstAfterIdleLatencies: [Double] = []
        var recoveries: [Double] = []
        var presentedFrames = 0
        var notPresentedAfterResume = 0
        /// Vừa chạy lại sau lúc nghỉ, chưa có khung nào lên màn.
        var awaitingFirstAfterResume = false
    }

    let nominalPeriod: Double
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(nominalPeriod: Double) {
        self.nominalPeriod = nominalPeriod
    }

    func startRecording(at time: Double) {
        state.withLock { state in
            let pausedAt = state.pausedAt
            state = State()
            state.recording = true
            state.startedAt = time
            state.pausedAt = pausedAt.map { _ in time }
        }
    }

    func stopRecording(at time: Double) {
        state.withLock { state in
            if let pausedAt = state.pausedAt, state.recording {
                state.pausedSeconds += max(0, time - pausedAt)
            }
            state.recording = false
            state.stoppedAt = time
        }
    }

    /// Gọi ở đầu mỗi lần display link gọi vẽ. `continuous` là `false` khi lần gọi trước đó là trước lúc nghỉ,
    /// hoặc display link vừa được tạo lại (khi đó khoảng cách hai đích không phải nhịp bị lỡ).
    func recordTick(target: Double, previousTarget: Double, continuous: Bool) {
        let period = nominalPeriod
        guard continuous, previousTarget > 0, period > 0 else { return }
        let slots = Int(((target - previousTarget) / period).rounded())
        guard slots > 1 else { return }
        state.withLock { state in
            guard state.recording else { return }
            state.pendingMissedTicks += slots - 1
            state.missedTicks += slots - 1
        }
    }

    /// Lần gọi vẽ không dựng khung (vẽ theo nhu cầu, chưa có gì mới).
    func recordSkip() {
        state.withLock { state in
            guard state.recording else { return }
            state.skippedTicks += 1
        }
    }

    func recordRendered() {
        state.withLock { state in
            guard state.recording else { return }
            state.renderedFrames += 1
        }
    }

    func recordPause(at time: Double) {
        state.withLock { state in
            guard state.pausedAt == nil else { return }
            state.pausedAt = time
            if state.recording {
                state.pauses += 1
            }
        }
    }

    func recordResume(at time: Double) {
        state.withLock { state in
            guard let pausedAt = state.pausedAt else { return }
            if state.recording {
                state.pausedSeconds += max(0, time - pausedAt)
            }
            state.pausedAt = nil
            state.awaitingFirstAfterResume = true
        }
    }

    func recordRecovery(at time: Double) {
        state.withLock { state in
            guard state.recording else { return }
            state.recoveries.append(time - state.startedAt)
        }
    }

    func recordFirstAfterIdle(_ latency: Double) {
        state.withLock { state in
            guard state.recording else { return }
            state.firstAfterIdleLatencies.append(latency)
        }
    }

    /// Gọi từ `presentedHandler`. Sau lúc nghỉ, tới khi có khung đầu tiên lên màn, màn vẫn đứng yên ở cảnh cũ:
    /// khung không lên hoặc lên chậm lúc đó làm cảnh mới hiện trễ (đã tính vào trễ đổi cảnh), không phải khựng.
    func recordPresented(_ presented: Double, target: Double, now: Double) {
        let period = nominalPeriod
        state.withLock { state in
            guard state.recording else { return }
            if presented <= 0 {
                state.notPresented += 1
                if state.awaitingFirstAfterResume {
                    state.notPresentedAfterResume += 1
                } else {
                    state.notPresentedSinceLast += 1
                }
                return
            }
            state.presentedFrames += 1
            let afterIdle = state.awaitingFirstAfterResume
            state.awaitingFirstAfterResume = false
            var late = 0
            if state.lastPresented > 0, !afterIdle, period > 0 {
                let actualGap = presented - state.lastPresented
                let expectedGap = target - state.lastPresentedTarget
                late = max(0, Int(((actualGap - expectedGap) / period).rounded()))
            }
            let missed = state.pendingMissedTicks + max(late, state.notPresentedSinceLast)
            state.latePresents += max(0, late - state.notPresentedSinceLast)
            if missed > 0 {
                state.droppedFrames += missed
                state.longestDrop = max(state.longestDrop, missed)
                let minute = max(0, Int((now - state.startedAt) / 60))
                while state.dropsPerMinute.count <= minute {
                    state.dropsPerMinute.append(0)
                }
                state.dropsPerMinute[minute] += missed
                if missed >= 3 {
                    state.stalls.append(Stall(time: presented - state.startedAt, frames: missed))
                }
            }
            state.pendingMissedTicks = 0
            state.notPresentedSinceLast = 0
            state.lastPresented = presented
            state.lastPresentedTarget = target
        }
    }

    func snapshot(now: Double) -> Snapshot {
        let period = nominalPeriod
        return state.withLock { state in
            let end = state.stoppedAt ?? now
            // Các nhịp rớt chưa có khung lên màn nào khép lại (cuối lần đo) vẫn được tính.
            let pending = state.pendingMissedTicks + state.notPresentedSinceLast
            var stalls = state.stalls
            var perMinute = state.dropsPerMinute
            if pending > 0 {
                let minute = max(0, Int((end - state.startedAt) / 60))
                while perMinute.count <= minute {
                    perMinute.append(0)
                }
                perMinute[minute] += pending
            }
            if pending >= 3 {
                stalls.append(Stall(time: end - state.startedAt, frames: pending))
            }
            var paused = state.pausedSeconds
            if let pausedAt = state.pausedAt, state.stoppedAt == nil {
                paused += max(0, now - pausedAt)
            }
            return Snapshot(
                nominalPeriod: period,
                recordingDuration: state.startedAt > 0 ? max(0, end - state.startedAt) : 0,
                droppedFrames: state.droppedFrames + pending,
                dropsPerMinute: perMinute,
                missedTicks: state.missedTicks,
                latePresents: state.latePresents,
                notPresented: state.notPresented,
                stalls: stalls,
                renderedFrames: state.renderedFrames,
                skippedTicks: state.skippedTicks,
                pauses: state.pauses,
                pausedSeconds: paused,
                firstAfterIdleLatencies: state.firstAfterIdleLatencies,
                recoveries: state.recoveries,
                presentedFrames: state.presentedFrames,
                notPresentedAfterResume: state.notPresentedAfterResume,
                longestDrop: max(state.longestDrop, pending)
            )
        }
    }
}

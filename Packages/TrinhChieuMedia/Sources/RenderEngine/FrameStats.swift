import Foundation
import os

/// Số đo của một đầu ra. Ghi từ luồng vẽ và từ các handler của Metal, đọc từ luồng chính.
public final class FrameStats: Sendable {
    /// Ảnh chụp số đo tại một thời điểm.
    public struct Snapshot: Sendable, Equatable {
        public var label: String
        public var nominalPeriod: Double
        public var framesPresented: Int
        public var framesNotPresented: Int
        public var lateFrames: Int
        public var recordingDuration: Double
        public var dropsPerMinute: [Int]
        public var presentIntervals: [Double]
        public var gpuTimes: [Double]
        public var sceneLatencies: [Double]
        /// Từ lúc display link gọi vẽ tới `targetPresentationTimestamp` của khung đó.
        public var callToTarget: [Double] = []
        /// Từ `targetPresentationTimestamp` tới `presentedTime` thật (chỉ khung lên màn).
        public var targetToPresented: [Double] = []
        /// Trễ đường ống: từ lúc display link gọi vẽ tới `presentedTime` thật.
        public var pipelineLatencies: [Double] = []
        /// Nhật ký khung rớt theo thứ tự thời gian.
        public var dropEvents: [DropEvent] = []

        /// Khung rớt = khung không lên màn + khung lên màn cách khung trước hơn 1.5 chu kỳ.
        public var droppedFrames: Int { framesNotPresented + lateFrames }
    }

    /// Một lần rớt khung trong nhật ký.
    public struct DropEvent: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// Khung không được hiển thị (`presentedTime == 0`).
            case notPresented
            /// Khoảng trống giữa hai khung lên màn dài hơn 1.5 chu kỳ.
            case late
        }

        /// Giây kể từ lúc bắt đầu ghi.
        public var time: Double
        public var kind: Kind
        /// Số nhịp làm tươi bị bỏ lỡ tính vào lần rớt này.
        public var count: Int
        /// Độ dài khoảng trống (chỉ có với `.late`).
        public var gap: Double?
    }

    private struct State: Sendable {
        var recording = false
        var startedAt: Double = 0
        var stoppedAt: Double?
        var lastPresented: Double = 0
        var framesPresented = 0
        var framesNotPresented = 0
        var lateFrames = 0
        /// Số khung không lên màn kể từ khung lên màn gần nhất (đã được đếm là khung rớt).
        var notPresentedSinceLast = 0
        var dropsPerMinute: [Int] = []
        var presentIntervals: [Double] = []
        var gpuTimes: [Double] = []
        var sceneLatencies: [Double] = []
        var callToTarget: [Double] = []
        var targetToPresented: [Double] = []
        var pipelineLatencies: [Double] = []
        var dropEvents: [DropEvent] = []
    }

    public let label: String
    /// Chu kỳ khung danh định, ví dụ 1/60 giây.
    public let nominalPeriod: Double
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(label: String, nominalPeriod: Double) {
        self.label = label
        self.nominalPeriod = nominalPeriod
    }

    /// Xoá số đo cũ và bắt đầu ghi (dùng sau thời gian khởi động).
    public func startRecording(at time: Double) {
        state.withLock { state in
            state = State()
            state.recording = true
            state.startedAt = time
        }
    }

    /// Ngừng ghi.
    public func stopRecording(at time: Double) {
        state.withLock { state in
            state.recording = false
            state.stoppedAt = time
        }
    }

    /// Gọi từ `presentedHandler`. `presentedTime == 0` nghĩa là khung không được hiển thị;
    /// khi đó `now` (theo `CACurrentMediaTime`) dùng để xếp khung rớt vào đúng phút.
    /// Khung không lên màn được trừ khỏi số nhịp bỏ lỡ của khoảng trống kế tiếp, để không đếm hai lần.
    public func recordPresented(_ presentedTime: Double, now: Double) {
        let period = nominalPeriod
        state.withLock { state in
            guard state.recording else { return }
            if presentedTime <= 0 {
                state.framesNotPresented += 1
                state.notPresentedSinceLast += 1
                Self.addDrop(&state, at: now)
                state.dropEvents.append(
                    DropEvent(time: now - state.startedAt, kind: .notPresented, count: 1, gap: nil)
                )
                return
            }
            if state.lastPresented > 0 {
                let interval = presentedTime - state.lastPresented
                state.presentIntervals.append(interval)
                if period > 0, interval > period * 1.5 {
                    // Khoảng trống dài bỏ lỡ nhiều nhịp làm tươi: đếm đủ số nhịp bị bỏ lỡ,
                    // trừ những nhịp đã được đếm qua khung không lên màn.
                    let slots = max(1, Int((interval / period).rounded()) - 1)
                    let missed = max(0, slots - state.notPresentedSinceLast)
                    state.lateFrames += missed
                    if missed > 0 {
                        let time = state.lastPresented + period - state.startedAt
                        state.dropEvents.append(DropEvent(time: time, kind: .late, count: missed, gap: interval))
                    }
                    // Xếp mỗi nhịp bỏ lỡ vào đúng phút nó xảy ra (khoảng trống có thể vắt qua ranh giới phút).
                    for index in 0..<missed {
                        Self.addDrop(&state, at: state.lastPresented + period * Double(index + 1))
                    }
                }
            }
            state.notPresentedSinceLast = 0
            state.lastPresented = presentedTime
            state.framesPresented += 1
        }
    }

    /// Gọi từ `presentedHandler`: ba mốc thời gian của một khung (theo `CACurrentMediaTime`).
    /// `presented == 0` (khung không lên màn) chỉ ghi phần "gọi tới đích".
    public func recordFrameTiming(callback: Double, target: Double, presented: Double) {
        state.withLock { state in
            guard state.recording else { return }
            state.callToTarget.append(target - callback)
            guard presented > 0 else { return }
            state.targetToPresented.append(presented - target)
            state.pipelineLatencies.append(presented - callback)
        }
    }

    /// Gọi từ `addCompletedHandler` của command buffer.
    public func recordGPUTime(_ seconds: Double) {
        guard seconds > 0 else { return }
        state.withLock { state in
            guard state.recording else { return }
            state.gpuTimes.append(seconds)
        }
    }

    /// Độ trễ từ lúc gửi cảnh tới khung đầu tiên chứa cảnh đó lên màn.
    public func recordSceneLatency(_ seconds: Double) {
        state.withLock { state in
            guard state.recording else { return }
            state.sceneLatencies.append(seconds)
        }
    }

    public func snapshot(now: Double) -> Snapshot {
        let label = label
        let period = nominalPeriod
        return state.withLock { state in
            let end = state.stoppedAt ?? now
            return Snapshot(
                label: label,
                nominalPeriod: period,
                framesPresented: state.framesPresented,
                framesNotPresented: state.framesNotPresented,
                lateFrames: state.lateFrames,
                recordingDuration: state.startedAt > 0 ? max(0, end - state.startedAt) : 0,
                dropsPerMinute: state.dropsPerMinute,
                presentIntervals: state.presentIntervals,
                gpuTimes: state.gpuTimes,
                sceneLatencies: state.sceneLatencies,
                callToTarget: state.callToTarget,
                targetToPresented: state.targetToPresented,
                pipelineLatencies: state.pipelineLatencies,
                dropEvents: state.dropEvents
            )
        }
    }

    private static func addDrop(_ state: inout State, at time: Double) {
        let reference = time > 0 ? time : state.startedAt
        let minute = max(0, Int((reference - state.startedAt) / 60))
        while state.dropsPerMinute.count <= minute {
            state.dropsPerMinute.append(0)
        }
        state.dropsPerMinute[minute] += 1
    }
}

/// Thống kê đơn giản cho báo cáo.
public enum Percentile {
    /// Phân vị `p` (0...1) theo cách lấy hạng gần nhất. Trả về 0 khi mảng rỗng.
    public static func value(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    public static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

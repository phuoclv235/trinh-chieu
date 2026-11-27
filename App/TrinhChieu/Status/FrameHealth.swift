import Foundation
import RenderEngine

/// Chỉ báo khung hình trên thanh công cụ, tính từ `RenderStatistics` mỗi giây.
///
/// Mức theo tiêu chí hai mức của `docs/kien-truc.md` mục 4.1, trong 60 giây gần nhất:
/// - xanh: không rớt khung nào;
/// - vàng: có rớt nhưng còn trong ngân sách dưới tải (dưới 6 khung mỗi phút, không giây nào rớt từ 3 khung);
/// - đỏ: vượt ngân sách.
struct FrameHealth: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        /// Chưa có đầu ra nào gắn.
        case idle
        case smooth
        case degraded
        case poor
    }

    struct OutputSummary: Equatable, Sendable, Identifiable {
        let id: OutputID
        let role: OutputRole
        let framesPerSecond: Int
        let droppedLastMinute: Int
        let gpuMilliseconds: Double
        let latencyMilliseconds: Double
        /// Lần đo gần nhất từ lúc gửi cảnh mới tới lúc lên màn (ms), giữ qua các giây không có cảnh mới.
        let sceneLatencyMilliseconds: Double?
        let refreshRate: Double

        /// Trễ cảnh mới tính bằng số khung của màn.
        var sceneLatencyFrames: Double? {
            guard let sceneLatencyMilliseconds, refreshRate > 0 else { return nil }
            return sceneLatencyMilliseconds * refreshRate / 1_000
        }
    }

    static let window = 60
    static let budgetPerMinute = 6
    static let burstLimit = 3

    /// Số khung rớt mỗi giây (cộng mọi đầu ra), cũ trước mới sau, tối đa 60 giây.
    private(set) var droppedPerSecond: [Int] = []
    private var droppedByOutput: [OutputID: [Int]] = [:]
    private var lastSceneLatency: [OutputID: Double] = [:]
    private(set) var outputs: [OutputSummary] = []

    mutating func record(_ statistics: RenderStatistics) {
        let total = statistics.outputs.reduce(0) { $0 + $1.droppedFrames }
        droppedPerSecond.append(total)
        if droppedPerSecond.count > Self.window {
            droppedPerSecond.removeFirst(droppedPerSecond.count - Self.window)
        }
        var history: [OutputID: [Int]] = [:]
        for output in statistics.outputs {
            var series = droppedByOutput[output.id] ?? []
            series.append(output.droppedFrames)
            history[output.id] = Array(series.suffix(Self.window))
        }
        droppedByOutput = history
        var latencies: [OutputID: Double] = [:]
        for output in statistics.outputs {
            latencies[output.id] = output.sceneLatencyMax ?? lastSceneLatency[output.id]
        }
        lastSceneLatency = latencies
        outputs = statistics.outputs.map { output in
            OutputSummary(
                id: output.id,
                role: output.role,
                framesPerSecond: output.framesPresented,
                droppedLastMinute: history[output.id]?.reduce(0, +) ?? 0,
                gpuMilliseconds: output.gpuTimeP95 * 1_000,
                latencyMilliseconds: output.pipelineLatencyP99 * 1_000,
                sceneLatencyMilliseconds: latencies[output.id].map { $0 * 1_000 },
                refreshRate: output.refreshRate
            )
        }
    }

    var droppedLastMinute: Int {
        droppedPerSecond.reduce(0, +)
    }

    var level: Level {
        guard !outputs.isEmpty else { return .idle }
        let worstSecond = droppedPerSecond.max() ?? 0
        if droppedLastMinute >= Self.budgetPerMinute || worstSecond >= Self.burstLimit {
            return .poor
        }
        return droppedLastMinute > 0 ? .degraded : .smooth
    }

    /// Số khung mỗi giây hiển thị trên chỉ báo: của đầu ra chính nếu có, không thì đầu ra đầu tiên.
    var headlineFramesPerSecond: Int? {
        (outputs.first { $0.role == .program } ?? outputs.first)?.framesPerSecond
    }
}

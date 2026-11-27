import Foundation

/// Số đo của một đầu ra trong một chu kỳ thống kê (1 giây).
public struct OutputStatistics: Sendable, Equatable {
    public let id: OutputID
    public let role: OutputRole
    /// Tần số làm tươi của màn (Hz).
    public let refreshRate: Double
    public let framesPresented: Int
    /// Khung không lên màn hoặc lên trễ trong chu kỳ.
    public let droppedFrames: Int
    /// Thời gian GPU mỗi khung, phân vị 95 (giây).
    public let gpuTimeP95: Double
    /// Trễ đường ống (từ lúc gọi vẽ tới lúc lên màn), phân vị 99 (giây).
    public let pipelineLatencyP99: Double
    /// Trễ lớn nhất từ lúc gửi cảnh mới (`setScene`) tới lúc khung có cảnh đó lên màn, trong chu kỳ (giây).
    /// `nil` khi chu kỳ không có cảnh mới. Dùng để đo "bấm thẻ đến lên màn" (T1.8 tiêu chí 2).
    public let sceneLatencyMax: Double?

    public init(
        id: OutputID, role: OutputRole, refreshRate: Double, framesPresented: Int, droppedFrames: Int,
        gpuTimeP95: Double, pipelineLatencyP99: Double, sceneLatencyMax: Double? = nil
    ) {
        self.id = id
        self.role = role
        self.refreshRate = refreshRate
        self.framesPresented = framesPresented
        self.droppedFrames = droppedFrames
        self.gpuTimeP95 = gpuTimeP95
        self.pipelineLatencyP99 = pipelineLatencyP99
        self.sceneLatencyMax = sceneLatencyMax
    }
}

/// Thống kê phát ra mỗi giây qua `RenderEngine.statistics`.
public struct RenderStatistics: Sendable, Equatable {
    public let outputs: [OutputStatistics]
    /// Cảnh báo mới trong chu kỳ: nguồn lỗi, chữ tràn, phông thiếu, màn bị rút.
    public let warnings: [RenderWarning]

    public init(outputs: [OutputStatistics], warnings: [RenderWarning]) {
        self.outputs = outputs
        self.warnings = warnings
    }
}

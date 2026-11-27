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
}

/// Thống kê phát ra mỗi giây qua `RenderEngine.statistics`.
public struct RenderStatistics: Sendable, Equatable {
    public let outputs: [OutputStatistics]
    /// Cảnh báo mới trong chu kỳ: nguồn lỗi, chữ tràn, phông thiếu, màn bị rút.
    public let warnings: [RenderWarning]
}

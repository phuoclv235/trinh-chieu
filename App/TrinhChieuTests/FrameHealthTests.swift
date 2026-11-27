import Foundation
import RenderEngine
import Testing

@testable import TrinhChieu

@Suite("Chỉ báo khung hình")
struct FrameHealthTests {
    private func second(dropped: Int, presented: Int = 60) -> RenderStatistics {
        RenderStatistics(
            outputs: [
                OutputStatistics(
                    id: OutputID("display-LED"), role: .program, refreshRate: 60, framesPresented: presented,
                    droppedFrames: dropped, gpuTimeP95: 0.002, pipelineLatencyP99: 0.04)
            ],
            warnings: [])
    }

    @Test("Chưa có đầu ra: idle")
    func idleWithoutOutputs() {
        var health = FrameHealth()
        health.record(RenderStatistics(outputs: [], warnings: []))
        #expect(health.level == .idle)
        #expect(health.headlineFramesPerSecond == nil)
    }

    @Test("Không rớt: xanh; rớt ít: vàng; vượt ngân sách: đỏ")
    func levels() {
        var health = FrameHealth()
        health.record(second(dropped: 0))
        #expect(health.level == .smooth)
        #expect(health.headlineFramesPerSecond == 60)
        health.record(second(dropped: 2))
        #expect(health.level == .degraded)
        health.record(second(dropped: 3))
        #expect(health.level == .poor)
    }

    @Test("Tổng 6 khung trong một phút là đỏ; sau 60 giây sạch thì về xanh")
    func windowSlides() {
        var health = FrameHealth()
        for _ in 0..<3 {
            health.record(second(dropped: 2))
        }
        #expect(health.droppedLastMinute == 6)
        #expect(health.level == .poor)
        for _ in 0..<FrameHealth.window {
            health.record(second(dropped: 0))
        }
        #expect(health.droppedLastMinute == 0)
        #expect(health.level == .smooth)
        #expect(health.outputs.first?.droppedLastMinute == 0)
    }
}

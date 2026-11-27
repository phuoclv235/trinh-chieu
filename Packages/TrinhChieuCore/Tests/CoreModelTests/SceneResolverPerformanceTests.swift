import Foundation
import Testing

@testable import CoreModel

/// Nghiệm thu 4 của T1.5: dựng cảnh cho một trang bình thường dưới 0,5 ms (trung bình 1.000 lần, đo trên Linux CI).
/// Số đo ghi ra luồng lỗi chuẩn (dòng "ĐO HIỆU NĂNG"). Máy ảo macOS của GitHub Actions dao động mạnh nên chỉ áp ngưỡng
/// chặn thoái lui lớn (gấp 4 lần).
@MainActor @Suite("SceneResolver: hiệu năng", .serialized)
struct SceneResolverPerformanceTests {
    #if os(Linux)
        static let budget: Duration = .microseconds(500)
    #else
        static let budget: Duration = .milliseconds(2)
    #endif

    @Test("resolve một trang bài hát (nền video của mẫu, chữ có ô mẫu) trung bình dưới 0,5 ms")
    func resolveBudget() {
        let library = ResolverLibrary()
        let resolver = SceneResolver()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let live = LivePosition(source: library.songSource, slideIndex: 0, slideID: fixedID(1), wentLiveAt: start)
        let theme = library.theme
        let state = ShowState(
            live: live,
            layers: [.background: .background(theme.background, origin: theme.id), .slide: .slide(slideID: fixedID(1))])
        // Làm nóng: lần đầu nạp lịch, bộ nhớ đệm của Foundation.
        _ = resolver.resolve(state: state, provider: library.provider, now: start)
        let iterations = 1_000
        var layerCount = 0
        let elapsed = ContinuousClock().measure {
            for index in 0..<iterations {
                let now = start.addingTimeInterval(Double(index))
                layerCount += resolver.resolve(state: state, provider: library.provider, now: now).program.layers.count
            }
        }
        let average = elapsed / iterations
        let microseconds = Double(average.components.attoseconds) / 1e12 + Double(average.components.seconds) * 1e6
        FileHandle.standardError.write(Data("ĐO HIỆU NĂNG: SceneResolver.resolve trung bình \(microseconds) µs\n".utf8))
        #expect(layerCount == iterations * 2)
        #expect(average < Self.budget, "Trung bình \(average)")
    }
}

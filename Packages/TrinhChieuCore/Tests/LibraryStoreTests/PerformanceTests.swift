import CoreModel
import Foundation
import Testing

@testable import LibraryStore

/// Nghiệm thu 7: mở thư viện 5.000 bài hát dưới 2 giây trên Linux CI. Số đo ghi ra luồng lỗi chuẩn
/// (dòng "ĐO HIỆU NĂNG") để chép vào PR. Máy macOS của GitHub Actions là máy ảo chậm hơn, chỉ áp ngưỡng chặn
/// thoái lui rộng hơn (như test hiệu năng của T1.1).
@Suite("LibraryStore: hiệu năng", .serialized)
@MainActor
struct PerformanceTests {
    static let songCount = 5_000

    #if os(Linux)
        static let openBudget: Duration = .seconds(2)
    #else
        static let openBudget: Duration = .seconds(5)
    #endif

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test("Mở thư viện 5.000 bài hát dưới 2 giây")
    func openFiveThousandSongs() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let verse = (1...4).map { "Câu thứ \($0): Chúa là Đấng chăn giữ tôi, tôi chẳng thiếu thốn gì" }
            .joined(separator: "\n")
        let encoder = DocumentCoding.makeEncoder()
        let presentations = dir.url.appendingPathComponent("presentations")
        try FileManager.default.createDirectory(at: presentations, withIntermediateDirectories: true)
        for number in 1...Self.songCount {
            var song = makeSong(number, lyrics: verse)
            let extra = (2...6).map { index in
                Slide(elements: [.text(TextElement(slot: .body, text: "Đoạn \(index) bài \(number)\n" + verse))])
            }
            song.groups[0].slides.append(contentsOf: extra)
            try encoder.encode(song).write(to: presentations.appendingPathComponent("\(song.id.uuidString).json"))
        }

        let start = ContinuousClock.now
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let elapsed = ContinuousClock.now - start
        reportMeasurement("mở thư viện \(Self.songCount) bài hát: \(Self.milliseconds(elapsed)) ms")
        #expect(store.presentations.count == Self.songCount)
        #expect(store.loadProblems.isEmpty)
        #expect(elapsed < Self.openBudget, "Mở mất \(elapsed)")

        let indexStart = ContinuousClock.now
        await store.waitForIndexing()
        let indexElapsed = Self.milliseconds(ContinuousClock.now - indexStart)
        reportMeasurement("dựng chỉ mục \(Self.songCount) bài ở nền: \(indexElapsed) ms")
        #expect(await store.search("4321", kinds: [.presentation]).first?.title == "Thánh ca 4321")
        await store.close()
    }
}

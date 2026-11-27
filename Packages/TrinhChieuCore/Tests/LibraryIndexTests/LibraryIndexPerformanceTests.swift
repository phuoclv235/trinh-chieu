import Foundation
import Testing

@testable import LibraryIndex

/// Số đo yêu cầu ở đặc tả T1.1: chèn 5.000 bài hát và 31.102 câu dưới 5 giây; truy vấn 2 từ dưới 20 ms (p95 của
/// 100 lần). Số đo thật ghi ra luồng lỗi chuẩn (dòng "ĐO HIỆU NĂNG") để chép vào PR.
///
/// Đặc tả đo ngưỡng trên Linux CI, nên ngưỡng đặc tả chỉ áp ở Linux. Máy macOS của GitHub Actions là máy ảo dùng
/// SQLite của hệ thống, đo chậm hơn Linux khoảng 2 lần với cùng dữ liệu; ở đó chỉ áp ngưỡng chặn thoái lui rộng hơn
/// (gấp 2,5 lần) và vẫn ghi số đo ra log.
@Suite("LibraryIndex: hiệu năng", .serialized)
struct LibraryIndexPerformanceTests {
    static let songCount = 5_000
    static let verseCount = 31_102

    /// Từ thường gặp trong lời bài hát và Kinh Thánh, lặp lại nhiều để truy vấn phải quét nhiều tài liệu.
    static let commonWords = [
        "Chúa", "là", "Đức", "Ngài", "con", "người", "ta", "các", "và", "của", "trong", "sẽ", "đã", "Đấng",
        "Trời", "Giê-xu", "yêu", "thương", "ơn", "phước", "thánh", "linh", "đời", "lòng", "danh", "ngợi", "khen",
    ]

    /// Âm tiết ghép ngẫu nhiên để có vốn từ rộng như văn bản thật.
    static let syllables: [String] = {
        let initials = [
            "", "b", "c", "ch", "d", "đ", "g", "gi", "h", "k", "kh", "l", "m", "n", "ng", "nh", "ph", "s", "t", "th",
            "tr", "v", "x",
        ]
        let rhymes = [
            "a", "à", "an", "ánh", "ăn", "âm", "ơn", "ời", "ên", "ình", "ọc", "ung", "ương", "ước", "uyên", "ai", "ao",
            "ầu", "iếng", "oan",
        ]
        return initials.flatMap { initial in rhymes.map { initial + $0 } }
    }()

    static func text(words: Int, using rng: inout SplitMix64) -> String {
        (0..<words).map { _ in
            Int.random(in: 0..<10, using: &rng) < 4
                ? commonWords.randomElement(using: &rng)! : syllables.randomElement(using: &rng)!
        }
        .joined(separator: " ")
    }

    static func dataset() -> (songs: [IndexEntry], verses: [IndexEntry]) {
        var rng = SplitMix64(state: 31_102)
        let songs = (1...songCount).map { number in
            song(
                "song-\(number)", text(words: 5, using: &rng), number: String(number),
                lyrics: text(words: 150, using: &rng))
        }
        let verses = (0..<verseCount).map { n in
            let reference = "Sách \(n / 1_000 + 1) \(n / 30 + 1):\(n % 30 + 1)"
            return verse("bible:TT1925:\(n)", reference: reference, text: text(words: 25, using: &rng))
        }
        return (songs, verses)
    }

    #if os(Linux)
        static let insertBudget: Duration = .seconds(5)
        static let queryBudget: Duration = .milliseconds(20)
    #else
        static let insertBudget: Duration = .milliseconds(12_500)
        static let queryBudget: Duration = .milliseconds(50)
    #endif

    static func p95(_ samples: [Duration]) -> Duration {
        let sorted = samples.sorted()
        return sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1]
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    @Test("Chèn 5.000 bài hát và 31.102 câu dưới 5 giây; truy vấn 2 từ p95 dưới 20 ms")
    func insertAndQueryBudgets() async throws {
        let dir = try TemporaryDirectory()
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        let data = Self.dataset()
        let clock = ContinuousClock()

        let insertTime = try await clock.measure {
            try await index.upsert(data.songs)
            try await index.upsert(data.verses)
        }
        #expect(try await index.count(kind: .presentation) == Self.songCount)
        #expect(try await index.count(kind: .verse) == Self.verseCount)
        reportMeasurement("chèn \(Self.songCount) bài + \(Self.verseCount) câu: \(Self.milliseconds(insertTime)) ms")
        #expect(insertTime < Self.insertBudget, "Chèn mất \(insertTime)")

        let scopes: [(name: String, kinds: Set<IndexKind>)] = [
            ("mọi loại", Set(IndexKind.allCases)),
            ("bài hát", [.presentation]),
            ("câu", [.verse]),
        ]
        for scope in scopes {
            var samples: [Duration] = []
            var hitCount = 0
            for _ in 0..<100 {
                let elapsed = try await clock.measure {
                    hitCount = try await index.search("chua la", kinds: scope.kinds).count
                }
                samples.append(elapsed)
            }
            let p95 = Self.p95(samples)
            reportMeasurement("tìm \"chua la\" (\(scope.name)): p95 \(Self.milliseconds(p95)) ms, \(hitCount) kết quả")
            #expect(hitCount == 50)
            #expect(p95 < Self.queryBudget, "p95 \(scope.name) là \(p95)")
        }
    }
}

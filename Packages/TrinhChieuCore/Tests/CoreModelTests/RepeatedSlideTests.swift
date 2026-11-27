import Foundation
import Testing

@testable import CoreModel

/// Thứ tự hát lặp lại một đoạn (điệp khúc hát hai lần): cùng một trang xuất hiện ở nhiều vị trí trong chuỗi.
@MainActor @Suite("ShowController: trang lặp lại trong thứ tự hát")
struct RepeatedSlideTests {
    /// Thứ tự hát A, B, A: chuỗi a1, a2, b1, b2 (tắt), b3, a1, a2.
    private func makeHarness() -> (ControllerHarness, LiveSource) {
        let library = SampleLibrary()
        var song = library.song
        let arrangement = Arrangement(
            id: fixedID(50), name: "Lặp", groupIDs: [song.groups[0].id, song.groups[1].id, song.groups[0].id])
        song.arrangements = [arrangement]
        library.provider.presentations[song.id] = song
        return (ControllerHarness(library: library), .presentation(id: song.id, arrangementID: arrangement.id))
    }

    @Test("next từ lần lặp thứ hai của trang đi tiếp, không quay về sau lần đầu")
    func nextFromSecondOccurrence() {
        let (harness, source) = makeHarness()
        #expect(harness.controller.send(.goLive(source, slideIndex: 5)) == .applied)
        #expect(harness.state.live?.slideID == fixedID(1))
        #expect(harness.controller.send(.next) == .applied)
        #expect(harness.state.live?.slideIndex == 6)
        #expect(harness.controller.send(.next) == .ignored(.atEnd))
    }

    @Test("previous từ lần lặp thứ hai lùi về trang ngay trước nó")
    func previousFromSecondOccurrence() {
        let (harness, source) = makeHarness()
        harness.controller.send(.goLive(source, slideIndex: 5))
        #expect(harness.controller.send(.previous) == .applied)
        #expect(harness.state.live?.slideIndex == 4)
    }

    @Test("SlideSequence.index(of:) ưu tiên chỉ số đang chiếu khi trang ở đó đúng mã")
    func sequenceIndexPrefersLiveIndex() throws {
        let (harness, source) = makeHarness()
        let sequence = try #require(harness.library.provider.sequence(for: source))
        let second = LivePosition(source: source, slideIndex: 5, slideID: fixedID(1), wentLiveAt: Date())
        #expect(sequence.index(of: second) == 5)
        let stale = LivePosition(source: source, slideIndex: 2, slideID: fixedID(1), wentLiveAt: Date())
        #expect(sequence.index(of: stale) == 0)
    }
}

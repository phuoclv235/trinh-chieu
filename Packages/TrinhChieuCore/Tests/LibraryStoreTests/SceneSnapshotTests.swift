import CoreModel
import Foundation
import Testing

@testable import LibraryStore

/// Nghiệm thu 1, 2, 3 của T1.5: thư viện mẫu thật (`LibraryStore`, `LibraryContentProvider`, mẫu tạo sẵn) qua
/// `ShowController` và `SceneResolver` cho ra cảnh khớp tệp JSON mong đợi ở `Fixtures/scenes/`.
@MainActor @Suite("SceneResolver: ảnh chụp giá trị với thư viện mẫu", .serialized)
struct SceneSnapshotTests {
    @Test("Trang bài hát nền mẫu, trang nền riêng, xoá chữ còn nền, trống")
    func songScenes() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let harness = ShowHarness(fixture: fixture)

        harness.controller.send(.goLive(fixture.item(201), slideIndex: 0))
        try expectSnapshot(harness.publication, named: "bai-hat-nen-mau")

        harness.clock.advance(by: 5)
        harness.controller.send(.goLive(fixture.item(201), slideIndex: 2))
        try expectSnapshot(harness.publication, named: "trang-nen-rieng")

        harness.clock.advance(by: 5)
        harness.controller.send(.clearLayer(.slide))
        try expectSnapshot(harness.publication, named: "xoa-chu-con-nen")

        harness.clock.advance(by: 5)
        harness.controller.send(.clearAll)
        try expectSnapshot(harness.publication, named: "trong")
        await fixture.store.close()
    }

    @Test("Đổi trang cùng nền video giữ playbackID")
    func sameBackgroundKeepsPlayback() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let harness = ShowHarness(fixture: fixture)

        harness.controller.send(.goLive(fixture.item(205), slideIndex: 0))
        let first = harness.publication
        harness.clock.advance(by: 12)
        harness.controller.send(.next)
        let second = harness.publication
        try expectSnapshot(second, named: "doi-trang-cung-nen")
        let before = first.program.layers.first { $0.kind == .background }
        let after = second.program.layers.first { $0.kind == .background }
        guard case .video(let a, _, _)? = before?.items.first, case .video(let b, _, _)? = after?.items.first else {
            Issue.record("Nền không phải video")
            return
        }
        #expect(a.playbackID == b.playbackID)
        #expect(a.startedAt == b.startedAt)
        #expect(first.program.layers.first { $0.kind == .slide }?.contentID == fixedID(11))
        #expect(second.program.layers.first { $0.kind == .slide }?.contentID == fixedID(12))
        await fixture.store.close()
    }

    @Test("Kinh Thánh 2 trang, media đơn")
    func scriptureAndMedia() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let harness = ShowHarness(fixture: fixture)

        harness.controller.send(.goLive(fixture.item(203), slideIndex: 0))
        try expectSnapshot(harness.publication, named: "kinh-thanh-trang-1")
        harness.clock.advance(by: 20)
        harness.controller.send(.next)
        try expectSnapshot(harness.publication, named: "kinh-thanh-trang-2")
        #expect(fixture.provider.sequence(for: fixture.item(203))?.slides.count == 2)

        harness.clock.advance(by: 20)
        harness.controller.send(.next)
        try expectSnapshot(harness.publication, named: "media-don")
        await fixture.store.close()
    }

    @Test("Nghiệm thu 3: media bị xoá khỏi đĩa khi đang chiếu: cảnh bỏ phần tử đó, không ném lỗi")
    func mediaDeletedFromDisk() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let harness = ShowHarness(fixture: fixture)
        harness.controller.send(.goLive(fixture.item(201), slideIndex: 2))
        let program = harness.publication.program
        #expect(program.layers.map(\.kind) == [.background, .slide])
        #expect(program.layers[1].items.count == 2)

        let url = try #require(fixture.provider.mediaURL(fixture.image))
        try FileManager.default.removeItem(at: url)
        harness.clock.advance(by: 1)
        harness.clock.fire()
        let after = harness.publication.program
        #expect(after.layers.map(\.kind) == [.slide])
        #expect(after.layers[0].items.count == 1)
        guard case .text(let block, _)? = after.layers[0].items.first else {
            Issue.record("Thiếu khối chữ")
            return
        }
        #expect(block.string == "A-men")
        let warnings = harness.logSink.entries.filter { $0.category == "SceneResolver" }
        #expect(warnings.count == 1)
        await fixture.store.close()
    }
}

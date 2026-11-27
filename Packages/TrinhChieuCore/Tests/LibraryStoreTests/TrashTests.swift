import CoreModel
import Foundation
import Testing

@testable import LibraryStore

@Suite("LibraryStore: thùng rác")
@MainActor
struct TrashTests {
    @Test("Nghiệm thu 4: xoá rồi hoàn tác khôi phục đúng tệp, bộ nhớ và chỉ mục")
    func trashAndRestore() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let keep = makeSong(1)
        let remove = makeSong(2, title: "Ơn phước tuôn tràn")
        let plan = ServicePlan(
            title: "Chúa Nhật 30/11/2026", date: "2026-11-30",
            items: [.presentation(PlanPresentationItem(presentationID: remove.id))])
        store.save(keep)
        store.save(remove)
        store.save(plan)
        await store.flush()
        let saved = try #require(store.presentations[remove.id])
        let path = dir.url.appendingPathComponent("presentations/\(remove.id.uuidString).json")
        let original = try Data(contentsOf: path)
        let changes = store.changes

        let ticket = try store.moveToTrash([remove.id, UUID()])
        #expect(ticket.ids == [remove.id])
        #expect(store.presentations[remove.id] == nil)
        #expect(!fileExists(path))
        let trashed = try FileManager.default.contentsOfDirectory(atPath: dir.url.appendingPathComponent(".trash").path)
        #expect(trashed == [ticket.entries[0].trashFileName])
        #expect(trashed[0].hasPrefix(remove.id.uuidString + "."))
        // Chương trình không bị sửa: mục vẫn trỏ tới bộ đã xoá.
        #expect(store.plans[plan.id] == plan)
        await store.waitForIndexing()
        #expect(await store.search("on phuoc", kinds: [.presentation]).isEmpty)

        try store.restore(ticket)
        #expect(store.presentations[remove.id] == saved)
        #expect(try Data(contentsOf: path) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.appendingPathComponent(".trash").path)
            .isEmpty)
        await store.waitForIndexing()
        #expect(await store.search("on phuoc", kinds: [.presentation]).map(\.title) == ["Ơn phước tuôn tràn"])

        #expect(throws: LibraryStoreError.restoreConflict(remove.id)) { try store.restore(ticket) }
        await store.close()
        var reasons: [LibraryChange.Reason] = []
        for await change in changes {
            reasons.append(change.reason)
        }
        #expect(reasons == [.removed, .restored])
    }

    @Test("Xoá tài liệu còn thay đổi chưa ghi: thùng rác giữ bản mới nhất, lần ghi hoãn không dựng lại tệp")
    func trashKeepsUnsavedChanges() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        var song = makeSong(3)
        store.save(song)
        await store.flush()
        song.title = "Bản chưa ghi"
        store.save(song)
        let ticket = try store.moveToTrash([song.id])
        await store.flush()
        let path = dir.url.appendingPathComponent("presentations/\(song.id.uuidString).json")
        #expect(!fileExists(path))
        try store.restore(ticket)
        #expect(store.presentations[song.id]?.title == "Bản chưa ghi")
        let onDisk = try DocumentCoding.decode(Presentation.self, from: Data(contentsOf: path))
        #expect(onDisk.title == "Bản chưa ghi")
        await store.close()
    }

    @Test("Xoá được mẫu trình bày và chương trình; khôi phục khi tệp đã bị dọn thì báo lỗi")
    func trashOtherKindsAndMissingItem() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let theme = Theme.fallback(name: "Kinh Thánh")
        let plan = ServicePlan(title: "Buổi nhóm thanh niên", date: "2026-12-05")
        store.save(theme)
        store.save(plan)
        await store.flush()
        let ticket = try store.moveToTrash([theme.id, plan.id])
        #expect(ticket.entries.map(\.kind) == [.theme, .plan])
        #expect(store.themes[theme.id] == nil)
        #expect(store.plans[plan.id] == nil)

        let trash = dir.url.appendingPathComponent(".trash")
        try FileManager.default.removeItem(
            at: trash.appendingPathComponent(ticket.entries[1].trashFileName))
        #expect(throws: LibraryStoreError.trashItemMissing(plan.id)) { try store.restore(ticket) }
        #expect(store.themes[theme.id] == theme)
        #expect(store.plans[plan.id] == nil)
        await store.close()
    }

    @Test("Nghiệm thu 4: tệp trong thùng rác quá 30 ngày (đồng hồ giả) bị dọn khi mở; chưa tới 30 ngày thì giữ")
    func purgesOldTrash() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let old = makeSong(1)
        let recent = makeSong(2)
        store.save(old)
        store.save(recent)
        await store.flush()
        let oldTicket = try store.moveToTrash([old.id])
        clock.advance(by: 2 * 24 * 3_600)
        let recentTicket = try store.moveToTrash([recent.id])
        await store.close()
        let trash = dir.url.appendingPathComponent(".trash")
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).count == 2)

        clock.advance(by: 29 * 24 * 3_600)  // Bản đầu đã 31 ngày, bản sau 29 ngày.
        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: trash.path)
        #expect(remaining == [recentTicket.entries[0].trashFileName])
        #expect(throws: LibraryStoreError.trashItemMissing(old.id)) { try reopened.restore(oldTicket) }
        try reopened.restore(recentTicket)
        #expect(reopened.presentations[recent.id] != nil)
        await reopened.close()
    }

    @Test("Tên tệp thùng rác đọc lại được thời điểm xoá")
    func trashNaming() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let name = TrashNaming.fileName(id: id, deletedAt: date, attempt: 0)
        #expect(name == "\(id.uuidString).\(FileTimestamp.string(from: date)).json")
        #expect(TrashNaming.deletedAt(fileName: name) == date)
        let retry = TrashNaming.fileName(id: id, deletedAt: date, attempt: 2)
        #expect(retry.hasSuffix("-2.json"))
        #expect(TrashNaming.deletedAt(fileName: retry) == date)
        #expect(TrashNaming.deletedAt(fileName: "rac.json") == nil)
        #expect(FileTimestamp.string(from: date).count == 16)
    }
}

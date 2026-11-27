import CoreModel
import Foundation
import Testing

@testable import LibraryStore

@Suite("LibraryStore: theo dõi thay đổi ngoài Hệ thống")
@MainActor
struct WatchingTests {
    /// Thư viện có một bài đã ghi xuống đĩa, theo dõi bằng bộ giả.
    private func openLibrary(_ dir: borrowing TemporaryDirectory, clock: FakeClock) async throws
        -> (LibraryStore, ManualFileWatcher, Presentation)
    {
        let watcher = ManualFileWatcher()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: watcher, configuration: testConfiguration(clock: clock))
        store.save(makeSong(1))
        await store.flush()
        let song = try #require(store.presentations.values.first)
        return (store, watcher, song)
    }

    private func fileURL(_ dir: borrowing TemporaryDirectory, _ id: UUID) -> URL {
        dir.url.appendingPathComponent("presentations/\(id.uuidString).json")
    }

    @Test("Tệp đổi ngoài Hệ thống khi không có thay đổi chưa ghi: nạp lại, cập nhật chỉ mục, phát thay đổi")
    func reloadsExternalChange() async throws {
        let dir = try TemporaryDirectory()
        let (store, watcher, song) = try await openLibrary(dir, clock: FakeClock())
        let changes = store.changes
        var external = song
        external.title = "Hồng ân bao la"
        try writeDocument(external, to: dir.url, path: "presentations/\(song.id.uuidString).json")
        watcher.send(changedFile: fileURL(dir, song.id))
        await store.waitForFileEvents(count: 1)

        #expect(store.presentations[song.id] == external)
        #expect(store.loadProblems.isEmpty)
        await store.waitForIndexing()
        #expect(await store.search("hong an", kinds: [.presentation]).map(\.id) == [song.id.uuidString])
        await store.close()
        var received: [LibraryChange] = []
        for await change in changes {
            received.append(change)
        }
        #expect(received == [LibraryChange(reason: .reloaded, documentIDs: [song.id])])
    }

    @Test("Nghiệm thu 6: tệp đổi ngoài Hệ thống khi còn thay đổi chưa ghi: giữ bản bộ nhớ, ghi tệp .conflict-")
    func keepsUnsavedChangesOnConflict() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let (store, watcher, song) = try await openLibrary(dir, clock: clock)
        var mine = song
        mine.title = "Bản của tôi"
        store.save(mine)
        let local = try #require(store.presentations[song.id])

        var theirs = song
        theirs.title = "Bản từ máy khác"
        let path = "presentations/\(song.id.uuidString).json"
        try writeDocument(theirs, to: dir.url, path: path)
        let theirsData = try Data(contentsOf: dir.url.appendingPathComponent(path))
        watcher.send(changedFile: fileURL(dir, song.id))
        await store.waitForFileEvents(count: 1)

        #expect(store.presentations[song.id] == local)
        let problem = try #require(store.loadProblems.first)
        #expect(store.loadProblems.count == 1)
        #expect(problem.kind == .syncConflict)
        let conflictName = "\(song.id.uuidString).conflict-\(FileTimestamp.string(from: clock.now)).json"
        #expect(problem.relativePath == "presentations/\(conflictName)")
        let conflictURL = dir.url.appendingPathComponent(problem.relativePath)
        #expect(try Data(contentsOf: conflictURL) == theirsData)

        // Bản trong bộ nhớ thắng khi ghi.
        await store.flush()
        let onDisk = try DocumentCoding.decode(Presentation.self, from: Data(contentsOf: fileURL(dir, song.id)))
        #expect(onDisk == local)
        await store.close()

        // Mở lại: tệp xung đột vẫn được báo, không bị nạp như tài liệu.
        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(reopened.presentations.count == 1)
        #expect(reopened.loadProblems.map(\.kind) == [.syncConflict])
        await reopened.close()
    }

    @Test("Sự kiện do chính Hệ thống ghi không làm nạp lại hay báo xung đột, kể cả khi đến trễ")
    func ignoresOwnWrites() async throws {
        let dir = try TemporaryDirectory()
        let (store, watcher, song) = try await openLibrary(dir, clock: FakeClock())
        var edited = song
        edited.title = "Lần sửa hai"
        store.save(edited)
        await store.flush()
        edited.title = "Lần sửa ba"
        store.save(edited)
        // Sự kiện của lần ghi trước đến khi đã có thay đổi mới chưa ghi.
        watcher.send(changedFile: fileURL(dir, song.id))
        await store.waitForFileEvents(count: 1)
        #expect(store.loadProblems.isEmpty)
        #expect(store.presentations[song.id]?.title == "Lần sửa ba")
        await store.close()
    }

    @Test("Tệp bị xoá ngoài Hệ thống: bỏ khỏi bộ nhớ và chỉ mục; tệp mới xuất hiện: nạp vào")
    func handlesExternalRemovalAndAddition() async throws {
        let dir = try TemporaryDirectory()
        let (store, watcher, song) = try await openLibrary(dir, clock: FakeClock())
        try FileManager.default.removeItem(at: fileURL(dir, song.id))
        let added = makeSong(2, title: "Bài mới từ Dropbox")
        try writeDocument(added, to: dir.url, path: "presentations/\(added.id.uuidString).json")
        watcher.send(FileChangeEvent(urls: [dir.url.appendingPathComponent("presentations")]))
        await store.waitForFileEvents(count: 1)
        #expect(store.presentations[song.id] == nil)
        #expect(store.presentations[added.id] == added)

        // Tệp tạm, .bak, thùng rác, tệp ngoài thư viện: bỏ qua.
        let ignored = [
            dir.url.appendingPathComponent("presentations/\(added.id.uuidString).json.tmp"),
            dir.url.appendingPathComponent(".trash/x.json"),
            dir.url.deletingLastPathComponent().appendingPathComponent("khac.json"),
        ]
        for url in ignored {
            #expect(store.classify(url) == nil)
        }
        watcher.send(FileChangeEvent(urls: [], rescanAll: true))
        await store.waitForFileEvents(count: 2)
        #expect(store.presentations.count == 1)
        await store.close()
    }

    @Test("Tệp hỏng do đồng bộ dở: báo trong loadProblems, giữ bản trong bộ nhớ; sửa xong thì hết báo")
    func corruptExternalFile() async throws {
        let dir = try TemporaryDirectory()
        let (store, watcher, song) = try await openLibrary(dir, clock: FakeClock())
        try Data("{ \"id\": ".utf8).write(to: fileURL(dir, song.id))
        watcher.send(changedFile: fileURL(dir, song.id))
        await store.waitForFileEvents(count: 1)
        #expect(store.presentations[song.id] == song)
        #expect(store.loadProblems.map(\.kind) == [.unreadable])

        var fixed = song
        fixed.title = "Đã sửa"
        try writeDocument(fixed, to: dir.url, path: "presentations/\(song.id.uuidString).json")
        watcher.send(changedFile: fileURL(dir, song.id))
        await store.waitForFileEvents(count: 2)
        #expect(store.presentations[song.id] == fixed)
        #expect(store.loadProblems.isEmpty)
        await store.close()
    }
}

import CoreModel
import Foundation
import LibraryIndex
import Testing

@testable import LibraryStore

@Suite("LibraryStore: mở, lưu, ghi an toàn")
@MainActor
struct LibraryStoreTests {
    @Test("Thư viện mới có cấu trúc thư mục, library.json và mẫu tạo sẵn làm mẫu mặc định")
    func createsNewLibrary() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        for name in ["presentations", "themes", "plans", "media", "logs", "bibles", ".trash", ".cache"] {
            #expect(fileExists(dir.url.appendingPathComponent(name)), "thiếu thư mục \(name)")
        }
        #expect(fileExists(dir.url.appendingPathComponent("library.json")))
        #expect(store.themes.count == 1)
        let theme = try #require(store.themes.values.first)
        #expect(store.info.defaultThemeID == theme.id)
        #expect(store.info.defaultScriptureThemeID == theme.id)
        #expect(fileExists(dir.url.appendingPathComponent("themes/\(theme.id.uuidString).json")))
        #expect(store.loadProblems.isEmpty)
        await store.close()

        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(reopened.info == store.info)
        #expect(reopened.themes == store.themes)
        await reopened.close()
    }

    @Test("Nghiệm thu 1: lưu 100 bộ trình chiếu, đóng, mở lại: dữ liệu giống hệt, tìm kiếm ra đúng")
    func roundTripHundredPresentations() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        for number in 1...100 {
            store.save(makeSong(number))
        }
        #expect(store.presentations.count == 100)
        let saved = store.presentations
        #expect(saved.values.allSatisfy { $0.modifiedAt == clock.now.wholeSeconds })
        await store.close()

        let files = try FileManager.default.contentsOfDirectory(
            atPath: dir.url.appendingPathComponent("presentations").path)
        #expect(files.count == 100)
        #expect(files.allSatisfy { $0.hasSuffix(".json") })

        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(reopened.presentations == saved)
        #expect(reopened.loadProblems.isEmpty)
        await reopened.waitForIndexing()
        let hits = await reopened.search("thanh ca 57", kinds: [.presentation])
        #expect(hits.first?.title == "Thánh ca 57")
        let byNumber = await reopened.search("42", kinds: [.presentation])
        #expect(byNumber.first?.title == "Thánh ca 42")
        let byLyrics = await reopened.search("diep khuc bai 99", kinds: [.presentation])
        #expect(byLyrics.first?.title == "Thánh ca 99")
        await reopened.close()
    }

    @Test("Chỉ mục bị xoá thì dựng lại toàn bộ ở nền khi mở; bộ trình chiếu đổi ngoài Hệ thống được cập nhật")
    func rebuildsAndSynchronizesIndex() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let songs = (1...20).map { makeSong($0) }
        for song in songs {
            store.save(song)
        }
        await store.close()

        try FileManager.default.removeItem(at: dir.url.appendingPathComponent(".cache"))
        var edited = try #require(store.presentations[songs[0].id])
        edited.title = "Ngợi khen Đức Giê-hô-va"
        edited.modifiedAt = clock.now.addingTimeInterval(60).wholeSeconds
        try writeDocument(edited, to: dir.url, path: "presentations/\(edited.id.uuidString).json")
        try FileManager.default.removeItem(
            at: dir.url.appendingPathComponent("presentations/\(songs[1].id.uuidString).json"))

        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        await reopened.waitForIndexing()
        #expect(reopened.isIndexing == false)
        #expect(await reopened.search("ngoi khen", kinds: [.presentation]).map(\.id) == [edited.id.uuidString])
        #expect(await reopened.search("thanh ca 2", kinds: [.presentation]).allSatisfy { $0.title != "Thánh ca 2" })
        #expect(await reopened.search("thanh ca", kinds: [.presentation]).count == 18)
        let themeHits = await reopened.search("mau co ban", kinds: [.theme])
        #expect(themeHits.count == 1)
        await reopened.close()

        // Chỉ mục còn nguyên: lần mở sau chỉ cập nhật phần chênh theo modifiedAt.
        var second = try #require(reopened.presentations[songs[2].id])
        second.title = "Tôn vinh Cha Thiên Thượng"
        second.modifiedAt = clock.now.addingTimeInterval(120).wholeSeconds
        try writeDocument(second, to: dir.url, path: "presentations/\(second.id.uuidString).json")
        try FileManager.default.removeItem(
            at: dir.url.appendingPathComponent("presentations/\(songs[3].id.uuidString).json"))
        let third = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        await third.waitForIndexing()
        #expect(await third.search("ton vinh", kinds: [.presentation]).map(\.id) == [second.id.uuidString])
        #expect(await third.search("ngoi khen", kinds: [.presentation]).map(\.id) == [edited.id.uuidString])
        #expect(await third.search("thanh ca", kinds: [.presentation]).count == 16)
        await third.close()
    }

    @Test("Lưu hoãn ghi theo id: chưa tới hạn thì chưa ghi; lưu lần hai thay lần một; flush ghi bản mới nhất")
    func debouncesWrites() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        var song = makeSong(1)
        store.save(song)
        let url = dir.url.appendingPathComponent("presentations/\(song.id.uuidString).json")
        #expect(!fileExists(url))
        song.title = "Bản thứ hai"
        clock.advance(by: 5)
        store.save(song)
        #expect(store.presentations[song.id]?.title == "Bản thứ hai")
        #expect(store.pendingWrites.count == 1)
        await store.flush()
        #expect(store.pendingWrites.isEmpty)
        let written = try DocumentCoding.decode(Presentation.self, from: Data(contentsOf: url))
        #expect(written == store.presentations[song.id])
        #expect(written.modifiedAt == clock.now.wholeSeconds)
        await store.close()
    }

    @Test("Ghi hoãn tự chạy sau thời gian hoãn")
    func delayedWriteHappens() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(),
            configuration: testConfiguration(clock: clock, writeDelay: .milliseconds(10)))
        let song = makeSong(1)
        store.save(song)
        let task = try #require(store.pendingWrites.values.first)
        await task.value
        await store.flush()
        #expect(store.dirty.isEmpty)
        #expect(fileExists(dir.url.appendingPathComponent("presentations/\(song.id.uuidString).json")))
        await store.close()
    }

    @Test("Nghiệm thu 2: ghi bị ngắt để lại tệp .tmp: khi mở, tệp gốc nguyên vẹn, .tmp bị dọn")
    func interruptedWriteLeavesOriginalIntact() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let song = makeSong(7)
        store.save(song)
        await store.close()
        let saved = try #require(store.presentations[song.id])

        let path = "presentations/\(song.id.uuidString).json"
        let temporaries = [
            dir.url.appendingPathComponent(path + ".tmp"),
            dir.url.appendingPathComponent("library.json.tmp"),
            dir.url.appendingPathComponent("media/.import-\(UUID().uuidString).tmp"),
        ]
        for url in temporaries {
            try Data("{ \"schemaVersion\": 1, \"title\": \"ghi dở".utf8).write(to: url)
        }

        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(reopened.presentations[song.id] == saved)
        #expect(reopened.loadProblems.isEmpty)
        for url in temporaries {
            #expect(!fileExists(url), "còn \(url.lastPathComponent)")
        }
        await reopened.close()
    }

    @Test("Nghiệm thu 3: tệp schemaVersion 99 vào loadProblems, các tệp khác vẫn mở")
    func newerSchemaGoesToLoadProblems() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let songs = (1...3).map { makeSong($0) }
        for song in songs {
            store.save(song)
        }
        await store.close()

        var future = makeSong(4)
        future.schemaVersion = 99
        let futurePath = "presentations/\(future.id.uuidString).json"
        try writeDocument(future, to: dir.url, path: futurePath)
        let brokenPath = "plans/\(UUID().uuidString).json"
        try writeDocument(["schemaVersion": 1], to: dir.url, path: brokenPath)
        let mismatched = makeSong(5)
        let mismatchedPath = "presentations/\(UUID().uuidString).json"
        try writeDocument(mismatched, to: dir.url, path: mismatchedPath)

        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(Set(reopened.presentations.keys) == Set(songs.map(\.id)))
        let problems = Dictionary(uniqueKeysWithValues: reopened.loadProblems.map { ($0.relativePath, $0) })
        let newer = try #require(problems[futurePath])
        #expect(newer.kind == .newerSchema)
        #expect(newer.message.hasPrefix("Tệp được tạo bởi phiên bản Hệ thống mới hơn"))
        #expect(problems[brokenPath]?.kind == .unreadable)
        #expect(problems[mismatchedPath]?.kind == .idMismatch)
        #expect(reopened.loadProblems.count == 3)
        // Tệp lỗi không bị ghi đè.
        let futureData = try Data(contentsOf: dir.url.appendingPathComponent(futurePath))
        #expect(try DocumentCoding.decode(Presentation.self, from: futureData).schemaVersion == 99)

        reopened.dismissProblem(newer.id)
        #expect(reopened.loadProblems.count == 2)
        await reopened.close()
    }

    @Test("Tệp được chuyển đổi định dạng thì có bản .bak cạnh tệp gốc trước khi ghi đè")
    func migrationWritesBackup() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        var old = makeSong(1)
        old.schemaVersion = 0
        let path = "presentations/\(old.id.uuidString).json"
        try writeDocument(old, to: dir.url, path: path)
        let original = try Data(contentsOf: dir.url.appendingPathComponent(path))

        var configuration = testConfiguration(clock: clock)
        configuration.migrate = { data, _ in
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DocumentError.notAnObject
            }
            let version = object["schemaVersion"] as? Int ?? 1
            guard version < 1 else { return (data, nil) }
            object["schemaVersion"] = 1
            let migrated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return (migrated, version)
        }
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: configuration)
        #expect(store.presentations[old.id]?.schemaVersion == 1)
        #expect(store.loadProblems.isEmpty)
        let backup = dir.url.appendingPathComponent(path + ".bak")
        #expect(try Data(contentsOf: backup) == original)
        let rewritten = try DocumentCoding.decode(
            Presentation.self, from: Data(contentsOf: dir.url.appendingPathComponent(path)))
        #expect(rewritten.schemaVersion == 1)
        await store.close()
    }

    @Test("Mỗi lần lưu phát LibraryChange cho người theo dõi")
    func emitsChanges() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let changes = store.changes
        let song = makeSong(1)
        let plan = ServicePlan(title: "Chúa Nhật 30/11/2026", date: "2026-11-30")
        store.save(song)
        store.save(plan)
        await store.close()
        var received: [LibraryChange] = []
        for await change in changes {
            received.append(change)
        }
        #expect(
            received == [
                LibraryChange(reason: .saved, documentIDs: [song.id]),
                LibraryChange(reason: .saved, documentIDs: [plan.id]),
            ])
    }

    @Test("Ghi lỗi (thư mục mất quyền ghi) vào loadProblems, giữ thay đổi để ghi lại")
    func writeFailureIsReported() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let plans = dir.url.appendingPathComponent("plans")
        try FileManager.default.removeItem(at: plans)
        try Data().write(to: plans)  // "plans" thành tệp thường: không ghi được vào trong.
        let plan = ServicePlan(title: "Buổi nhóm cầu nguyện", date: "2026-12-02")
        store.save(plan)
        await store.flush()
        #expect(store.loadProblems.map(\.kind) == [.writeFailed])
        #expect(store.dirty.contains(DocumentKey(.plan, plan.id)))

        try FileManager.default.removeItem(at: plans)
        try FileManager.default.createDirectory(at: plans, withIntermediateDirectories: true)
        await store.flush()
        #expect(store.loadProblems.isEmpty)
        #expect(fileExists(plans.appendingPathComponent("\(plan.id.uuidString).json")))
        await store.close()
    }
}

import CoreModel
import Foundation
import LibraryIndex
import Testing

@testable import LibraryStore

@Suite("LibraryStore: mẫu mặc định và dựng lại chỉ mục")
@MainActor
struct SettingsTests {
    @Test("Đổi mẫu mặc định: ghi library.json, phát thay đổi, mở lại vẫn giữ")
    func setDefaultThemesPersists() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        var changes = store.changes.makeAsyncIterator()
        let bottom = DefaultThemes.lyricsLowerThirdID
        try await store.setDefaultThemes(presentation: bottom, scripture: DefaultThemes.lyricsCenterID)
        #expect(store.info.defaultThemeID == bottom)
        let change = try #require(await changes.next())
        #expect(change.documentIDs.contains(store.info.id))
        #expect(change.documentIDs.contains(bottom))
        await store.close()

        let reopened = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(reopened.info.defaultThemeID == bottom)
        #expect(reopened.info.defaultScriptureThemeID == DefaultThemes.lyricsCenterID)
        await reopened.close()
    }

    @Test("Dựng lại chỉ mục: tìm kiếm vẫn ra đúng sau khi dựng xong")
    func rebuildIndexKeepsSearchWorking() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        store.save(makeSong(7, title: "Ân Điển Lạ Lùng"))
        await store.waitForIndexing()
        store.rebuildIndex()
        #expect(store.isIndexing)
        await store.waitForIndexing()
        #expect(!store.isIndexing)
        let hits = await store.search("an dien la lung", kinds: [.presentation])
        #expect(hits.count == 1)
        await store.close()
    }
}

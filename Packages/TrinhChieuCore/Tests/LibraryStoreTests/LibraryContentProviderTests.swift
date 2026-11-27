import CoreModel
import Foundation
import Scripture
import Testing

@testable import LibraryStore

@MainActor @Suite("LibraryContentProvider: dựng chuỗi, mẫu, đệm")
struct LibraryContentProviderTests {
    @Test("Bộ trình chiếu: thứ tự hát, mẫu của bộ, không có thì mẫu mặc định thư viện")
    func presentationSequences() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let provider = fixture.provider

        let song = try #require(provider.sequence(for: .presentation(id: fixture.song.id, arrangementID: nil)))
        #expect(song.title == "Chúa Là Đá Muôn Đời")
        #expect(song.slides.map(\.slide.id) == [fixedID(1), fixedID(2), fixedID(3)])
        let chorus = GroupLabel(kind: .chorus)
        #expect(song.slides.map(\.groupLabel) == [GroupLabel(kind: .verse, number: 1), chorus, chorus])
        #expect(song.themeID == DefaultThemes.lyricsCenterID)
        #expect(provider.theme(song.themeID).name == "Lời bài hát giữa màn")

        let videoSource = LiveSource.presentation(id: fixture.videoSong.id, arrangementID: nil)
        let videoSong = try #require(provider.sequence(for: videoSource))
        #expect(videoSong.themeID == fixture.videoTheme.id)
        #expect(provider.sequence(for: .presentation(id: fixedID(999), arrangementID: nil)) == nil)
        await fixture.store.close()
    }

    @Test("Mục chương trình: mẫu và thứ tự hát của mục đè bộ; tiêu đề và mục trỏ tới bộ không có thì nil")
    func planItems() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let store = fixture.store
        let provider = fixture.provider
        var song = fixture.song
        let reversed = Arrangement(id: fixedID(30), name: "Điệp khúc trước", groupIDs: [fixedID(21), fixedID(20)])
        song.arrangements = [reversed]
        store.save(song)
        var plan = fixture.plan
        plan.items.append(
            .presentation(
                PlanPresentationItem(
                    id: fixedID(206), presentationID: song.id, arrangementID: reversed.id,
                    themeID: DefaultThemes.lyricsLowerThirdID)))
        plan.items.append(.presentation(PlanPresentationItem(id: fixedID(207), presentationID: fixedID(999))))
        plan.items.append(.note(PlanNoteItem(id: fixedID(208), text: "Mời Hội Thánh đứng")))
        store.save(plan)
        provider.libraryDidChange(LibraryChange(reason: .saved, documentIDs: [plan.id, song.id]))

        let item = try #require(provider.sequence(for: fixture.item(206)))
        #expect(item.source == fixture.item(206))
        #expect(item.themeID == DefaultThemes.lyricsLowerThirdID)
        #expect(item.slides.map(\.slide.id) == [fixedID(2), fixedID(3), fixedID(1)])
        #expect(provider.sequence(for: fixture.item(202)) == nil)
        #expect(provider.sequence(for: fixture.item(207)) == nil)
        #expect(provider.sequence(for: fixture.item(208)) == nil)
        #expect(provider.sequence(for: .planItem(planID: fixedID(999), itemID: fixedID(201))) == nil)
        #expect(provider.plan(plan.id)?.items.count == 8)
        await fixture.store.close()
    }

    @Test("Kinh Thánh: phân tích lại địa chỉ, tuỳ chọn từ mẫu Kinh Thánh mặc định, tên viết tắt bản dịch")
    func scripture() async throws {
        let dir = try TemporaryDirectory()
        let logSink = InMemoryLogSink()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"),
            log: logSink)
        let provider = fixture.provider
        #expect(fixture.store.info.defaultScriptureThemeID == DefaultThemes.scriptureID)

        let direct = try #require(provider.sequence(for: .scripture(translation: "THU1", reference: "gi 3:16-18")))
        #expect(direct.title == "Giăng 3:16–18 (THU)")
        #expect(direct.themeID == DefaultThemes.scriptureID)
        #expect(direct.slides.count == 2)
        #expect(direct.slides.map(\.indexInGroup) == [0, 1])
        let reference = direct.slides[0].slide.elements.compactMap { element -> String? in
            guard case .text(let text) = element, text.slot == .reference else { return nil }
            return text.text
        }
        #expect(reference == ["Giăng 3:16–17 (THU)"])

        #expect(provider.sequence(for: .scripture(translation: "khac", reference: "Giăng 3:16")) == nil)
        #expect(provider.sequence(for: .scripture(translation: "khac", reference: "Giăng 3:16")) == nil)
        #expect(provider.sequence(for: .scripture(translation: "thu1", reference: "xyz")) == nil)
        #expect(provider.sequence(for: .scripture(translation: "thu1", reference: "Giăng 9:1")) == nil)
        #expect(logSink.entries.count == 3, "mỗi lỗi chỉ ghi log một lần")

        provider.unregisterTranslation(code: "thu1")
        #expect(provider.sequence(for: .scripture(translation: "thu1", reference: "Giăng 3:16")) == nil)
        let translation = try await SampleBible.open(in: try dir.child("kinh-thanh-2"))
        provider.register(translation)
        #expect(provider.sequence(for: .scripture(translation: "thu1", reference: "Giăng 3:16")) != nil)
        await fixture.store.close()
    }

    @Test("Media đơn: một trang nền media, tiêu đề là tên tệp gốc; media không có trong thư viện thì nil")
    func media() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let provider = fixture.provider
        let sequence = try #require(provider.sequence(for: .media(fixture.image)))
        #expect(sequence.title == "nen-anh.jpg")
        #expect(sequence.slides.count == 1)
        #expect(sequence.slides[0].slide.background.mediaID == fixture.image)
        #expect(sequence.slides[0].slide.elements.isEmpty)
        #expect(provider.sequence(for: .media("000000000000")) == nil)
        #expect(provider.mediaURL(fixture.image) != nil)
        #expect(provider.mediaURL("000000000000") == nil)
        await fixture.store.close()
    }

    @Test("Mẫu: id không có thì mẫu mặc định; mẫu mặc định bị xoá thì mẫu mã nhỏ nhất; hết mẫu thì mẫu tối thiểu")
    func themeFallbacks() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let store = fixture.store
        let provider = fixture.provider
        #expect(provider.theme(nil).id == DefaultThemes.lyricsCenterID)
        #expect(provider.theme(fixedID(999)).id == DefaultThemes.lyricsCenterID)
        #expect(provider.theme(DefaultThemes.scriptureID).name == "Kinh Thánh")

        _ = try store.moveToTrash([DefaultThemes.lyricsCenterID])
        #expect(provider.theme(nil).id == fixture.videoTheme.id)
        _ = try store.moveToTrash(Array(store.themes.keys))
        #expect(provider.theme(nil) == LibraryContentProvider.fallbackTheme)
        await fixture.store.close()
    }

    @Test("Đệm theo nguồn; thay đổi chạm id liên quan thì dựng lại, không liên quan thì giữ")
    func cacheInvalidation() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let store = fixture.store
        let provider = fixture.provider
        let source = fixture.item(201)
        let before = try #require(provider.sequence(for: source))
        _ = provider.sequence(for: .media(fixture.image))
        _ = provider.sequence(for: fixture.item(203))
        #expect(provider.cachedSourceCount == 3)

        var song = fixture.song
        song.groups[0].slides[0].elements = [ShowLibraryFixture.body(51, "Lời mới")]
        store.save(song)
        // Chưa báo thay đổi: vẫn trả bản trong đệm.
        #expect(provider.sequence(for: source) == before)

        provider.libraryDidChange(LibraryChange(reason: .saved, documentIDs: [fixedID(999)]))
        #expect(provider.cachedSourceCount == 3)
        provider.libraryDidChange(LibraryChange(reason: .saved, documentIDs: [song.id]))
        #expect(provider.cachedSourceCount == 2)
        let after = try #require(provider.sequence(for: source))
        #expect(after != before)

        provider.libraryDidChange(LibraryChange(reason: .reloaded, mediaIDs: [fixture.image]))
        #expect(provider.cachedSourceCount == 2, "mục 201 và Kinh Thánh còn, media đơn bị xoá đệm")
        provider.libraryDidChange(LibraryChange(reason: .saved, documentIDs: [DefaultThemes.scriptureID]))
        #expect(provider.cachedSourceCount == 1)
        provider.libraryDidChange(LibraryChange(reason: .saved, documentIDs: [fixture.plan.id]))
        #expect(provider.cachedSourceCount == 0)
        await fixture.store.close()
    }

    @Test("startObserving: xoá đệm trước, rồi mới gọi onChange")
    func observingChanges() async throws {
        let dir = try TemporaryDirectory()
        let fixture = try await ShowLibraryFixture.make(
            root: try dir.child("thu-vien"), scratch: try dir.child("nguon"), bibles: try dir.child("kinh-thanh"))
        let provider = fixture.provider
        let source = LiveSource.presentation(id: fixture.song.id, arrangementID: nil)
        _ = provider.sequence(for: source)
        var song = fixture.song
        song.title = "Tên mới"

        let titles = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            provider.startObserving { _ in
                continuation.resume(returning: provider.sequence(for: source)?.title)
                provider.stopObserving()
            }
            fixture.store.save(song)
        }
        #expect(titles == "Tên mới")
        await fixture.store.close()
    }
}

@MainActor @Suite("Mẫu trình bày tạo sẵn")
struct DefaultThemesTests {
    @Test("Ba mẫu đúng đặc tả: tên, khung, kiểu, nền đen, hoà tan 0,35 giây")
    func specValues() throws {
        let themes = try DefaultThemes.load()
        let ids = [DefaultThemes.lyricsCenterID, DefaultThemes.lyricsLowerThirdID, DefaultThemes.scriptureID]
        #expect(themes.map(\.id) == ids)
        #expect(themes.map(\.name) == ["Lời bài hát giữa màn", "Lời bài hát dưới màn", "Kinh Thánh"])
        for theme in themes {
            #expect(theme.canvasSize == .fullHD)
            #expect(theme.background == .color(.black))
            #expect(theme.transition == TransitionSpec(kind: .dissolve, duration: 0.35))
            #expect(theme.schemaVersion == DocumentMigration.currentSchemaVersion)
        }

        let center = themes[0].slots.body
        #expect(center.frame == PixelRect(x: 120, y: 120, width: 1680, height: 840))
        #expect(center.style.fontFamily == "system")
        #expect(center.style.fontWeight == 600)
        #expect(center.style.fontSize == 76)
        #expect(center.style.color == .white)
        #expect(center.style.alignment == .center)
        #expect(center.style.verticalAlignment == .middle)
        #expect(center.style.lineHeight == 1.2)
        #expect(center.style.shadow.radius > 0)
        #expect(center.style.autoFit == AutoFit(mode: .shrink, minScale: 0.6))

        let lower = themes[1]
        #expect(lower.slots.body.frame == PixelRect(x: 120, y: 780, width: 1680, height: 240))
        #expect(lower.slots.body.style.fontSize == 52)
        #expect(lower.slots.body.style.verticalAlignment == .bottom)
        #expect(lower.slots.body.style.box.color == RGBA(red: 0, green: 0, blue: 0, alpha: 153))
        #expect(lower.slots.body.style.box.cornerRadius == 12)
        #expect(lower.slots.body.style.maxLines == 2)
        #expect(lower.lyrics.maxLinesPerSlide == 2)

        let scripture = themes[2]
        #expect(scripture.slots.body.frame == PixelRect(x: 140, y: 120, width: 1640, height: 780))
        #expect(scripture.slots.body.style.fontSize == 60)
        #expect(scripture.slots.body.style.alignment == .left)
        #expect(scripture.slots.reference.frame == PixelRect(x: 140, y: 940, width: 1640, height: 70))
        #expect(scripture.slots.reference.style.fontSize == 40)
        #expect(scripture.slots.reference.style.color == RGBA(red: 255, green: 255, blue: 255, alpha: 179))
        #expect(scripture.slots.reference.style.alignment == .right)
        #expect(scripture.scripture.maxCharactersPerSlide == 220)
    }

    @Test("Thư viện mới: ba mẫu, mẫu bài hát mặc định là \"giữa màn\", mẫu Kinh Thánh mặc định là \"Kinh Thánh\"")
    func newLibraryDefaults() async throws {
        let dir = try TemporaryDirectory()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: FakeClock()))
        #expect(store.themes.count == 3)
        #expect(store.info.defaultThemeID == DefaultThemes.lyricsCenterID)
        #expect(store.info.defaultScriptureThemeID == DefaultThemes.scriptureID)
        await store.close()
    }

    @Test("Cấu hình riêng không có mẫu Kinh Thánh: mẫu đầu làm mặc định cho cả hai")
    func customInitialThemes() async throws {
        let dir = try TemporaryDirectory()
        var configuration = testConfiguration(clock: FakeClock())
        let only = Theme.fallback(id: fixedID(5), name: "Một mẫu")
        configuration.makeInitialThemes = { [only] }
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: configuration)
        #expect(store.info.defaultThemeID == only.id)
        #expect(store.info.defaultScriptureThemeID == only.id)
        #expect(DefaultThemes.make().count == 3)
        await store.close()
    }
}

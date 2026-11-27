import CoreModel
import Foundation
import Testing
import ZIPFoundation

@testable import LibraryStore

@Suite("LibraryStore: gói mang đi")
@MainActor
struct BundleTests {
    /// Thư viện nguồn: một mẫu có nền media, hai bài (một bài dùng mẫu và có ảnh), một video, một chương trình.
    private struct Source {
        var store: LibraryStore
        var plan: ServicePlan
        var theme: Theme
        var songs: [Presentation]
        var image: MediaAssetInfo
        var video: MediaAssetInfo
        var background: MediaAssetInfo
        var unrelated: Presentation
    }

    private func makeSource(_ dir: borrowing TemporaryDirectory, clock: FakeClock) async throws -> Source {
        let store = try await LibraryStore.open(
            at: try dir.child("nguon"), fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let files = try dir.child("tep")
        func media(_ name: String, seed: Int) async throws -> MediaAssetInfo {
            let url = files.appendingPathComponent(name)
            try Data((0..<4_096).map { UInt8(($0 * seed) % 256) }).write(to: url)
            return try await store.importMedia(from: url)
        }
        let image = try await media("thap-gia.png", seed: 3)
        let video = try await media("mo-dau.mp4", seed: 5)
        let background = try await media("nen.jpg", seed: 7)

        var theme = Theme.fallback(name: "Mẫu Chúa Nhật")
        theme.background = .media(background.id)
        store.save(theme)
        var first = makeSong(1, title: "Chúa Là Đá Muôn Đời")
        first.themeID = theme.id
        first.groups[0].slides[0].elements.append(
            .image(ImageElement(frame: PixelRect(x: 0, y: 0, width: 100, height: 100), mediaID: image.id)))
        store.save(first)
        let second = makeSong(2, title: "Ân Điển Lạ Lùng")
        store.save(second)
        let unrelated = makeSong(3, title: "Không nằm trong chương trình")
        store.save(unrelated)
        let plan = ServicePlan(
            title: "Chúa Nhật 30/11/2026", date: "2026-11-30", plannedStart: "09:00",
            items: [
                .header(PlanHeaderItem(title: "Thờ phượng")),
                .presentation(PlanPresentationItem(presentationID: first.id)),
                .presentation(PlanPresentationItem(presentationID: second.id)),
                .scripture(PlanScriptureItem(reference: "Giăng 3:16-18", translation: "vi1925")),
                .media(PlanMediaItem(mediaID: video.id)),
                .note(PlanNoteItem(text: "Mời Hội Thánh đứng")),
            ])
        store.save(plan)
        return Source(
            store: store, plan: plan, theme: theme,
            songs: [try #require(store.presentations[first.id]), try #require(store.presentations[second.id])],
            image: image, video: video, background: background, unrelated: unrelated)
    }

    @Test("Nghiệm thu 5: xuất gói một chương trình rồi nhập vào thư viện trống: đủ tài liệu và media")
    func exportAndImportPlan() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let source = try await makeSource(dir, clock: clock)
        let bundle = try dir.child("xuat").appendingPathComponent("chua-nhat.tcbundle")
        try await source.store.exportBundle(planID: source.plan.id, to: bundle)
        #expect(fileExists(bundle))

        // Gói chỉ chứa thứ chương trình dùng, theo cấu trúc thư viện.
        let archive = try Archive(url: bundle, accessMode: .read)
        let paths = Set(archive.map(\.path))
        #expect(paths.contains("manifest.json"))
        #expect(paths.contains("plans/\(source.plan.id.uuidString).json"))
        #expect(!paths.contains("presentations/\(source.unrelated.id.uuidString).json"))
        #expect(paths.contains("media/\(source.background.id.rawValue).jpg"))
        // manifest, chương trình, 2 bài, 1 mẫu, 3 media (mỗi media một tệp nội dung và một tệp thông tin).
        let expectedCount = 11
        #expect(paths.count == expectedCount)

        let target = try await LibraryStore.open(
            at: try dir.child("dich"), fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let inspection = try await target.inspectBundle(at: bundle)
        #expect(inspection.manifest.kind == .plan)
        #expect(inspection.manifest.rootIDs == [source.plan.id])
        #expect(inspection.manifest.bibleTranslations == ["vi1925"])
        #expect(inspection.missingTranslations == ["vi1925"])
        #expect(inspection.conflicts.isEmpty)
        #expect(inspection.unchangedIDs.isEmpty)
        #expect(inspection.existingMediaIDs.isEmpty)
        #expect(Set(inspection.presentations.map(\.id)) == Set(source.songs.map(\.id)))

        try await target.importBundle(at: bundle, resolutions: [:])
        #expect(target.plans[source.plan.id] == source.plan)
        for song in source.songs {
            #expect(target.presentations[song.id] == song)
        }
        #expect(target.presentations[source.unrelated.id] == nil)
        #expect(target.themes[source.theme.id] == source.theme)
        for info in [source.image, source.video, source.background] {
            #expect(target.media[info.id] == info)
            let url = try #require(target.mediaURL(info.id))
            let original = try #require(source.store.mediaURL(info.id))
            #expect(try Data(contentsOf: url) == Data(contentsOf: original))
        }
        await target.close()

        // Dữ liệu đã nằm trên đĩa: mở lại vẫn đủ.
        let reopened = try await LibraryStore.open(
            at: dir.url.appendingPathComponent("dich"), fileWatcher: NoFileWatching(),
            configuration: testConfiguration(clock: clock))
        #expect(reopened.plans[source.plan.id] == source.plan)
        #expect(reopened.media.count == 3)
        await reopened.close()
        await source.store.close()
    }

    @Test("Nghiệm thu 5: nhập lần hai báo xung đột đúng id; giữ cả hai, thay, bỏ qua làm đúng")
    func secondImportReportsConflicts() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let source = try await makeSource(dir, clock: clock)
        let bundle = dir.url.appendingPathComponent("chua-nhat.tcbundle")
        try await source.store.exportBundle(planID: source.plan.id, to: bundle)
        let target = try await LibraryStore.open(
            at: try dir.child("dich"), fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        try await target.importBundle(at: bundle, resolutions: [:])

        // Nhập lại gói y hệt: không xung đột, mọi tài liệu giống hệt, media đã có.
        let same = try await target.inspectBundle(at: bundle)
        #expect(same.conflicts.isEmpty)
        #expect(same.unchangedIDs == Set([source.plan.id, source.theme.id] + source.songs.map(\.id)))
        #expect(same.existingMediaIDs == [source.image.id, source.video.id, source.background.id])

        // Sửa ở thư viện đích rồi nhập lại: xung đột đúng các id đã sửa.
        var first = try #require(target.presentations[source.songs[0].id])
        first.title = "Chúa Là Đá Muôn Đời (bản Hội Thánh B)"
        clock.advance(by: 60)
        target.save(first)
        var second = try #require(target.presentations[source.songs[1].id])
        second.tags = ["đã sửa"]
        target.save(second)
        var plan = try #require(target.plans[source.plan.id])
        plan.title = "Chúa Nhật 30/11 (đã sửa)"
        target.save(plan)
        let inspection = try await target.inspectBundle(at: bundle)
        #expect(Set(inspection.conflicts.map(\.id)) == [source.songs[0].id, source.songs[1].id, source.plan.id])
        let firstConflict = try #require(inspection.conflicts.first { $0.id == source.songs[0].id })
        #expect(firstConflict.kind == .presentation)
        #expect(firstConflict.bundleTitle == "Chúa Là Đá Muôn Đời")
        #expect(firstConflict.libraryTitle == "Chúa Là Đá Muôn Đời (bản Hội Thánh B)")
        #expect(inspection.unchangedIDs == [source.theme.id])

        // Thiếu cách xử lý: không nhập gì.
        await #expect(throws: LibraryStoreError.self) {
            try await target.importBundle(at: bundle, resolutions: [source.songs[0].id: .skip])
        }
        #expect(target.presentations.count == 2)

        try await target.importBundle(
            at: bundle,
            resolutions: [source.songs[0].id: .keepBoth, source.songs[1].id: .replace, source.plan.id: .keepBoth])
        // Giữ cả hai: bản thư viện còn nguyên, bản trong gói có mã mới và tên thêm "(bản sao)".
        #expect(target.presentations[first.id]?.title == "Chúa Là Đá Muôn Đời (bản Hội Thánh B)")
        let copy = try #require(
            target.presentations.values.first { $0.title == "Chúa Là Đá Muôn Đời (bản sao)" })
        #expect(copy.id != first.id)
        #expect(copy.groups == source.songs[0].groups)
        // Thay: bản trong gói thay bản thư viện; bản cũ nằm trong thùng rác.
        #expect(target.presentations[second.id] == source.songs[1])
        let trash = try FileManager.default.contentsOfDirectory(
            atPath: dir.url.appendingPathComponent("dich/.trash").path)
        #expect(trash.count == 1)
        #expect(trash.allSatisfy { $0.hasPrefix(second.id.uuidString) })
        // Chương trình giữ cả hai: bản sao trỏ tới bản sao của bài đã "giữ cả hai".
        #expect(target.plans[plan.id]?.title == "Chúa Nhật 30/11 (đã sửa)")
        let planCopy = try #require(target.plans.values.first { $0.id != plan.id })
        #expect(planCopy.title == "Chúa Nhật 30/11/2026 (bản sao)")
        let referenced = planCopy.items.compactMap { item -> UUID? in
            if case .presentation(let entry) = item { return entry.presentationID }
            return nil
        }
        #expect(referenced == [copy.id, second.id])
        #expect(target.presentations.count == 3)
        await target.close()
        await source.store.close()
    }

    @Test("Xuất gói bộ trình chiếu kèm mẫu và media; gói hỏng hoặc media sai mã băm bị từ chối")
    func presentationBundleAndValidation() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let source = try await makeSource(dir, clock: clock)
        let bundle = dir.url.appendingPathComponent("bai-hat.tcbundle")
        try await source.store.exportBundle(presentationIDs: [source.songs[0].id], to: bundle)
        let target = try await LibraryStore.open(
            at: try dir.child("dich"), fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let inspection = try await target.inspectBundle(at: bundle)
        #expect(inspection.manifest.kind == .presentation)
        #expect(inspection.plans.isEmpty)
        #expect(inspection.presentations.map(\.id) == [source.songs[0].id])
        #expect(inspection.themes.map(\.id) == [source.theme.id])
        #expect(Set(inspection.media.map(\.id)) == [source.image.id, source.background.id])
        #expect(inspection.missingTranslations.isEmpty)

        let missing = UUID()
        await #expect(throws: LibraryStoreError.documentNotFound(missing)) {
            try await source.store.exportBundle(presentationIDs: [missing], to: bundle)
        }

        let notZip = dir.url.appendingPathComponent("hong.tcbundle")
        try Data("không phải ZIP".utf8).write(to: notZip)
        await #expect(throws: LibraryStoreError.self) { try await target.inspectBundle(at: notZip) }

        // Gói có media bị sửa nội dung: mã băm không khớp, không nhập tệp đó.
        let tampered = dir.url.appendingPathComponent("sua.tcbundle")
        try rewriteBundle(bundle, to: tampered) { path, data in
            if path == "media/\(source.image.id.rawValue).png" {
                data[0] ^= 0xFF
            }
        }
        await #expect(throws: LibraryStoreError.mediaChecksumMismatch(source.image.id)) {
            try await target.importBundle(at: tampered, resolutions: [:])
        }
        #expect(target.mediaURL(source.image.id) == nil)
        await target.close()
        await source.store.close()
    }

    /// Chép gói sang tệp mới, cho phép sửa nội dung từng tệp. Hàm trả về thì tệp ZIP đã đóng.
    private func rewriteBundle(_ source: URL, to destination: URL, edit: (String, inout Data) -> Void) throws {
        let original = try Archive(url: source, accessMode: .read)
        let rebuilt = try Archive(url: destination, accessMode: .create)
        for entry in original {
            var data = Data()
            _ = try original.extract(entry) { data.append($0) }
            edit(entry.path, &data)
            let payload = data
            let provider: Provider = { position, size in
                let start = Int(position)
                return payload.subdata(in: start..<min(start + size, payload.count))
            }
            try rebuilt.addEntry(
                with: entry.path, type: .file, uncompressedSize: Int64(payload.count), provider: provider)
        }
    }
}

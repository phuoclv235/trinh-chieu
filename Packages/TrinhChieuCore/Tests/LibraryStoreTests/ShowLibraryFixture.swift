import CoreModel
import Foundation
import Scripture
import Testing

@testable import LibraryStore

/// Thư viện mẫu cho test nguồn nội dung và cảnh: thư viện mới (3 mẫu tạo sẵn), hai media, một mẫu nền video, hai
/// bài hát, một bản dịch Kinh Thánh thử và một chương trình buổi nhóm.
///
/// - `song` (mẫu mặc định): "Câu 1" gồm trang 1 (ghi chú "Hát chậm"); "Điệp khúc" gồm trang 2 và trang 3 (nền riêng là
///   ảnh `image`, có ảnh `image` nhỏ ở góc).
/// - `videoSong` (mẫu `videoTheme`, nền là video `video`): "Câu 1" gồm trang 11, 12.
/// - Chương trình: 201 `song`, 202 tiêu đề, 203 Kinh Thánh "Giăng 3:16-18" (bản thử), 204 media `image`,
///   205 `videoSong`.
@MainActor struct ShowLibraryFixture {
    let store: LibraryStore
    let provider: LibraryContentProvider
    let image: MediaID
    let video: MediaID
    let videoTheme: Theme
    let song: Presentation
    let videoSong: Presentation
    let plan: ServicePlan

    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Mở thư viện mới ở `root`, nhập media từ `scratch`, ghi bản dịch thử vào `bibles`.
    static func make(root: URL, scratch: URL, bibles: URL, log: any LogSink = NullLogSink()) async throws -> Self {
        let clock = FakeClock(start)
        let store = try await LibraryStore.open(
            at: root, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let imageFile = scratch.appendingPathComponent("nen-anh.jpg")
        try Data("Ảnh nền thử cho T1.5".utf8).write(to: imageFile)
        let videoFile = scratch.appendingPathComponent("nen-video.mp4")
        try Data("Video nền thử cho T1.5".utf8).write(to: videoFile)
        let image = try await store.importMedia(from: imageFile).id
        let video = try await store.importMedia(from: videoFile).id

        var videoTheme = try #require(store.themes[DefaultThemes.lyricsCenterID])
        videoTheme.id = fixedID(300)
        videoTheme.name = "Nền video"
        videoTheme.background = .media(video)
        store.save(videoTheme)

        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let lyrics = "Chúa là đá muôn đời\nCon nương náu nơi Ngài"
        let first = Slide(id: fixedID(1), notes: "Hát chậm", elements: [Self.body(51, lyrics)])
        let second = Slide(id: fixedID(2), elements: [Self.body(52, "Ngợi khen Chúa đời đời")])
        let cornerFrame = PixelRect(x: 1700, y: 40, width: 180, height: 120)
        let corner = ImageElement(id: fixedID(54), frame: cornerFrame, mediaID: image)
        let third = Slide(
            id: fixedID(3), background: .media(image), elements: [Self.body(53, "A-men"), .image(corner)])
        let song = Presentation(
            id: fixedID(100), kind: .song, title: "Chúa Là Đá Muôn Đời", createdAt: created, modifiedAt: created,
            groups: [
                SlideGroup(id: fixedID(20), label: GroupLabel(kind: .verse, number: 1), slides: [first]),
                SlideGroup(id: fixedID(21), label: GroupLabel(kind: .chorus), slides: [second, third]),
            ])
        store.save(song)
        let videoSong = Presentation(
            id: fixedID(101), kind: .song, title: "Ngày Mới", createdAt: created, modifiedAt: created,
            themeID: videoTheme.id,
            groups: [
                SlideGroup(
                    id: fixedID(22), label: GroupLabel(kind: .verse, number: 1),
                    slides: [
                        Slide(id: fixedID(11), elements: [Self.body(61, "Bình minh")]),
                        Slide(id: fixedID(12), elements: [Self.body(62, "Ánh sáng")]),
                    ])
            ])
        store.save(videoSong)
        let plan = ServicePlan(
            id: fixedID(200), title: "Chúa Nhật", date: "2027-01-17",
            items: [
                .presentation(PlanPresentationItem(id: fixedID(201), presentationID: song.id)),
                .header(PlanHeaderItem(id: fixedID(202), title: "Lời Chúa")),
                .scripture(
                    PlanScriptureItem(id: fixedID(203), reference: "Giăng 3:16-18", translation: SampleBible.code)),
                .media(PlanMediaItem(id: fixedID(204), mediaID: image)),
                .presentation(PlanPresentationItem(id: fixedID(205), presentationID: videoSong.id)),
            ])
        store.save(plan)

        let translation = try await SampleBible.open(in: bibles)
        let provider = LibraryContentProvider(store: store, translations: [translation], log: log)
        return ShowLibraryFixture(
            store: store, provider: provider, image: image, video: video, videoTheme: videoTheme,
            song: store.presentations[song.id]!, videoSong: store.presentations[videoSong.id]!, plan: plan)
    }

    /// Phần tử chữ ở ô `body` với mã cố định.
    static func body(_ number: Int, _ text: String) -> Element {
        .text(TextElement(id: fixedID(number), slot: .body, text: text))
    }

    func item(_ number: Int) -> LiveSource {
        .planItem(planID: plan.id, itemID: fixedID(number))
    }
}

/// Bộ điều khiển thật nối thư viện mẫu với bộ dựng cảnh thật; giờ màn hình nhắc theo UTC+7.
@MainActor struct ShowHarness {
    let fixture: ShowLibraryFixture
    let clock = ManualShowClock(now: ShowLibraryFixture.start)
    let sink = LastSceneSink()
    let logSink = InMemoryLogSink()
    let controller: ShowController

    init(fixture: ShowLibraryFixture) {
        self.fixture = fixture
        let resolver = SceneResolver(log: logSink, timeZone: TimeZone(secondsFromGMT: 7 * 3_600)!)
        controller = ShowController(
            provider: fixture.provider, sink: sink, resolver: resolver, log: InMemoryServiceLog(), clock: clock)
    }

    var publication: ScenePublication { sink.outputs.last! }
}

/// So cảnh với tệp JSON mong đợi ở `Fixtures/scenes/<name>.json` (so giá trị sau khi giải mã, bỏ `revision`).
///
/// Chưa có tệp hoặc khác: test hỏng và in JSON thật ra luồng lỗi chuẩn giữa hai dòng "SNAPSHOT <tên> BẮT ĐẦU/KẾT THÚC"
/// để xem lại và chép vào tệp. Đặt biến môi trường `UPDATE_SNAPSHOTS=1` để ghi thẳng tệp (trên máy của bạn).
func expectSnapshot(
    _ publication: ScenePublication, named name: String, sourceLocation: SourceLocation = #_sourceLocation
) throws {
    var actual = publication
    actual.program.revision = 0
    actual.stage.revision = 0
    let data = try DocumentCoding.encode(actual)
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/scenes/\(name).json")
    if ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] == "1" {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return
    }
    let expected = try? DocumentCoding.decode(ScenePublication.self, from: Data(contentsOf: url))
    guard expected != actual else {
        return
    }
    let json = String(decoding: data, as: UTF8.self)
    FileHandle.standardError.write(Data("SNAPSHOT \(name) BẮT ĐẦU\n\(json)\nSNAPSHOT \(name) KẾT THÚC\n".utf8))
    let reason = expected == nil ? "chưa có hoặc không đọc được" : "khác cảnh thật"
    Issue.record("Ảnh chụp \(name).json \(reason); JSON thật ở log lỗi chuẩn.", sourceLocation: sourceLocation)
}

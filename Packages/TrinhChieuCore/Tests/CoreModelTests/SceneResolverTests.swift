import Foundation
import Testing

@testable import CoreModel

/// Thư viện nhỏ cho test bộ dựng cảnh.
///
/// Bộ `song` (mẫu `theme`, khung vẽ 1280x720, chuyển cảnh cắt): đoạn "Câu 1" gồm s1 (chữ có ô mẫu, đè cỡ chữ, ghi
/// chú), s2 (chữ không ô mẫu, chữ hoa), s3 (tắt); đoạn "Điệp khúc" gồm s4 (ảnh, video, khối màu, chữ rỗng), s5 (nền
/// riêng là video `bgVideo`), s6 (ảnh đã mất). Chương trình: `song`, tiêu đề, bộ `empty` (không trang nào bật),
/// media `bgImage`.
@MainActor struct ResolverLibrary {
    static let red = RGBA(red: 255, green: 0, blue: 0)
    let theme: Theme
    let defaultTheme = Theme.fallback(id: fixedID(901), name: "Mẫu mặc định")
    let song: Presentation
    let empty: Presentation
    let plan: ServicePlan
    let photo: MediaID = "aaaaaaaaaaaa"
    let clip: MediaID = "bbbbbbbbbbbb"
    let bgVideo: MediaID = "cccccccccccc"
    let bgImage: MediaID = "dddddddddddd"
    let missing: MediaID = "eeeeeeeeeeee"
    let provider: InMemoryContentProvider

    init() {
        var theme = Theme.fallback(id: fixedID(900), name: "Mẫu thử")
        theme.canvasSize = PixelSize(width: 1280, height: 720)
        theme.transition = .cut
        theme.background = .media(bgVideo)
        self.theme = theme
        let s1 = Slide(
            id: fixedID(1), notes: "Chậm lại", elements: [
                .text(TextElement(slot: .body, text: "Chúa là đá\nmuôn đời", style: TextStyleOverride(fontSize: 90)))
            ])
        let s2 = Slide(
            id: fixedID(2),
            elements: [
                .text(
                    TextElement(
                        frame: PixelRect(x: 10, y: 20, width: 300, height: 40), text: "ha-lê-lu-gia",
                        style: TextStyleOverride(transform: .uppercase)))
            ])
        let s3 = Slide(id: fixedID(3), enabled: false, elements: [.text(TextElement(slot: .body, text: "Tắt"))])
        let s4 = Slide(
            id: fixedID(4),
            elements: [
                .image(ImageElement(frame: PixelRect(x: 0, y: 0, width: 100, height: 100), mediaID: photo)),
                .video(
                    VideoElement(
                        id: fixedID(40), frame: PixelRect(x: 100, y: 0, width: 200, height: 100), mediaID: clip,
                        fit: .fill, loop: true, muted: true)),
                .shape(ShapeElement(frame: PixelRect(x: 0, y: 600, width: 1280, height: 120), fill: Self.red)),
                .text(TextElement(slot: .title, text: "  ")),
            ])
        let s5 = Slide(
            id: fixedID(5), background: .media(bgVideo, loop: false, muted: true),
            elements: [.text(TextElement(slot: .body, text: "Nền riêng"))])
        let s6 = Slide(
            id: fixedID(6),
            elements: [
                .image(ImageElement(frame: PixelRect(x: 0, y: 0, width: 10, height: 10), mediaID: missing)),
                .text(TextElement(slot: .body, text: "Còn chữ")),
            ])
        let verse = SlideGroup(id: fixedID(10), label: GroupLabel(kind: .verse, number: 1), slides: [s1, s2, s3])
        let chorus = SlideGroup(id: fixedID(11), label: GroupLabel(kind: .chorus), slides: [s4, s5, s6])
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        song = Presentation(
            id: fixedID(100), kind: .song, title: "Chúa Là Đá Muôn Đời", createdAt: created, modifiedAt: created,
            themeID: theme.id, groups: [verse, chorus])
        let off = Slide(id: fixedID(7), enabled: false)
        empty = Presentation(
            id: fixedID(101), kind: .generic, title: "Trống", createdAt: created, modifiedAt: created,
            groups: [SlideGroup(id: fixedID(12), label: GroupLabel(kind: .custom), slides: [off])])
        let items: [ServicePlanItem] = [
            .presentation(PlanPresentationItem(id: fixedID(201), presentationID: song.id)),
            .header(PlanHeaderItem(id: fixedID(202), title: "Lời Chúa")),
            .presentation(PlanPresentationItem(id: fixedID(203), presentationID: empty.id)),
            .media(PlanMediaItem(id: fixedID(204), mediaID: bgImage)),
        ]
        plan = ServicePlan(id: fixedID(200), title: "Chúa Nhật", date: "2026-11-29", items: items)
        let urls: [MediaID: URL] = [
            photo: URL(fileURLWithPath: "/thu-vien/media/aaaaaaaaaaaa.png"),
            clip: URL(fileURLWithPath: "/thu-vien/media/bbbbbbbbbbbb.mov"),
            bgVideo: URL(fileURLWithPath: "/thu-vien/media/cccccccccccc.MP4"),
            bgImage: URL(fileURLWithPath: "/thu-vien/media/dddddddddddd.jpg"),
        ]
        provider = InMemoryContentProvider(
            presentations: [song, empty], plans: [plan], themes: [theme], defaultTheme: defaultTheme,
            mediaURLs: urls)
    }

    var songSource: LiveSource { .presentation(id: song.id, arrangementID: nil) }

    func planItem(_ number: Int) -> LiveSource {
        .planItem(planID: plan.id, itemID: fixedID(number))
    }
}

/// Bộ điều khiển thật nối với bộ dựng cảnh thật.
@MainActor struct ResolverHarness {
    let library = ResolverLibrary()
    let sink = RecordingSink()
    let clock = FakeClock()
    let logSink = InMemoryLogSink()
    let resolver: SceneResolver
    let controller: ShowController

    init() {
        resolver = SceneResolver(log: logSink, timeZone: TimeZone(secondsFromGMT: 7 * 3_600)!)
        controller = ShowController(
            provider: library.provider, sink: sink, resolver: resolver, log: InMemoryServiceLog(), clock: clock)
    }

    var program: RenderScene { sink.outputs.last!.program }
    var stage: RenderScene { sink.outputs.last!.stage }

    func layer(_ kind: LayerKind, in scene: RenderScene? = nil) -> RenderLayer? {
        (scene ?? program).layers.first { $0.kind == kind }
    }

    /// Các khối chữ của màn hình nhắc theo khung.
    func stageTexts() -> [PixelRect: String] {
        var result: [PixelRect: String] = [:]
        for layer in stage.layers {
            for case .text(let block, let frame) in layer.items {
                result[frame] = block.string
            }
        }
        return result
    }
}

@MainActor @Suite("SceneResolver: đầu ra chính")
struct SceneResolverProgramTests {
    @Test("Chữ có ô mẫu: khung và kiểu của ô, áp phần đè; khung vẽ và chuyển cảnh của mẫu")
    func slottedText() throws {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let program = harness.program
        #expect(program.canvasSize == PixelSize(width: 1280, height: 720))
        #expect(program.transition == .cut)
        let slide = try #require(harness.layer(.slide))
        #expect(slide.contentID == fixedID(1))
        let body = harness.library.theme.slots.body
        var style = body.style
        style.fontSize = 90
        let block = TextBlock(
            string: "Chúa là đá\nmuôn đời", style: ResolvedTextStyle(style), autoFit: style.autoFit,
            maxLines: style.maxLines)
        #expect(slide.items == [.text(block, frame: body.frame)])
    }

    @Test("Chữ không ô mẫu: khung của phần tử, kiểu body của mẫu, áp chữ hoa (NFC)")
    func freeTextUppercased() throws {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 1))
        let slide = try #require(harness.layer(.slide))
        guard case .text(let block, let frame) = slide.items.first else {
            Issue.record("Thiếu khối chữ")
            return
        }
        #expect(frame == PixelRect(x: 10, y: 20, width: 300, height: 40))
        let expected = "HA-LÊ-LU-GIA".precomposedStringWithCanonicalMapping
        #expect(block.string.unicodeScalars.elementsEqual(expected.unicodeScalars))
        #expect(block.style.fontSize == harness.library.theme.slots.body.style.fontSize)
    }

    @Test("Ảnh, video, khối màu; chữ rỗng không vẽ")
    func mediaAndShapes() throws {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 3))
        let slide = try #require(harness.layer(.slide))
        let wentLiveAt = harness.clock.now
        #expect(slide.items.count == 3)
        let photoFrame = PixelRect(x: 0, y: 0, width: 100, height: 100)
        #expect(slide.items[0] == .image(MediaRef(id: "aaaaaaaaaaaa"), frame: photoFrame, fit: .fit))
        guard case .video(let video, let frame, let fit) = slide.items[1] else {
            Issue.record("Thiếu video")
            return
        }
        #expect(frame == PixelRect(x: 100, y: 0, width: 200, height: 100))
        #expect(fit == .fill)
        #expect(video.loop && video.muted)
        #expect(video.startedAt == wentLiveAt)
        let band = PixelRect(x: 0, y: 600, width: 1280, height: 120)
        #expect(slide.items[2] == .color(ResolverLibrary.red, frame: band))

        // Lên lại cùng trang ở thời điểm khác: video phát lại từ đầu.
        harness.clock.advance(by: 5)
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 3))
        guard case .video(let again, _, _) = try #require(harness.layer(.slide)).items[1] else {
            Issue.record("Thiếu video")
            return
        }
        #expect(again.playbackID != video.playbackID)
    }

    @Test("Nền của mẫu là video: đổi trang cùng nền giữ playbackID; nền riêng mở lần phát mới")
    func backgroundPlaybackContinuity() throws {
        let harness = ResolverHarness()
        let library = harness.library
        harness.controller.send(.goLive(library.songSource, slideIndex: 0))
        let firstAt = harness.clock.now
        let first = try #require(harness.layer(.background))
        #expect(first.contentID == library.theme.id)
        guard case .video(let video, let frame, let fit) = first.items.first else {
            Issue.record("Nền không phải video")
            return
        }
        #expect(frame == PixelRect(x: 0, y: 0, width: 1280, height: 720))
        #expect(fit == .fill)
        #expect(video.loop)
        #expect(!video.muted)
        #expect(video.startedAt == firstAt)

        harness.clock.advance(by: 30)
        harness.controller.send(.next)
        guard case .video(let kept, _, _) = try #require(harness.layer(.background)).items.first else {
            Issue.record("Nền không phải video")
            return
        }
        #expect(kept.playbackID == video.playbackID)
        #expect(kept.startedAt == firstAt)

        harness.clock.advance(by: 30)
        harness.controller.send(.goLive(library.songSource, slideIndex: 4))
        let own = try #require(harness.layer(.background))
        #expect(own.contentID == fixedID(5))
        guard case .video(let fresh, _, _) = own.items.first else {
            Issue.record("Nền không phải video")
            return
        }
        #expect(fresh.playbackID != video.playbackID)
        #expect(fresh.startedAt == harness.clock.now)
        #expect(!fresh.loop)
        #expect(fresh.muted)

        // Tick mỗi giây dựng lại cảnh: vẫn cùng lần phát.
        harness.clock.advance(by: 1)
        harness.clock.fire()
        guard case .video(let ticked, _, _) = try #require(harness.layer(.background)).items.first else {
            Issue.record("Nền không phải video")
            return
        }
        #expect(ticked.playbackID == fresh.playbackID)
    }

    @Test("Media mất: bỏ phần tử, không ném lỗi, ghi log một lần; media có lại thì vẽ lại")
    func missingMediaIsSkipped() throws {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 5))
        let slide = try #require(harness.layer(.slide))
        #expect(slide.items.count == 1)
        guard case .text(let block, _) = slide.items.first else {
            Issue.record("Thiếu khối chữ")
            return
        }
        #expect(block.string == "Còn chữ")
        harness.clock.advance(by: 1)
        harness.clock.fire()
        let warnings = harness.logSink.entries.filter { $0.level == .warning }
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.contains("eeeeeeeeeeee") == true)

        harness.library.provider.mediaURLs[harness.library.missing] = URL(fileURLWithPath: "/thu-vien/e.png")
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 5))
        #expect(try #require(harness.layer(.slide)).items.count == 2)
    }

    @Test("Nền video mất trên đĩa: không có lớp nền, chữ vẫn lên")
    func missingBackgroundMedia() throws {
        let harness = ResolverHarness()
        harness.library.provider.mediaURLs[harness.library.bgVideo] = nil
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        #expect(harness.layer(.background) == nil)
        #expect(harness.layer(.slide) != nil)
    }

    @Test("Media đơn: nền ảnh đặt vừa khung (fit), lớp trang rỗng")
    func singleMediaFits() throws {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.planItem(204), slideIndex: 0))
        let background = try #require(harness.layer(.background))
        let id = harness.library.bgImage
        #expect(background.contentID == id.contentUUID)
        let canvas = harness.library.defaultTheme.canvasSize
        #expect(background.items == [.image(MediaRef(id: id), frame: PixelRect(size: canvas), fit: .fit)])
        #expect(harness.layer(.slide)?.items == [])
    }

    @Test("Nền màu, nền không có, xoá chữ còn nền, xoá hết ra cảnh trống")
    func colorBackgroundAndClearing() throws {
        let harness = ResolverHarness()
        let resolver = SceneResolver()
        let provider = harness.library.provider
        let red = SlideBackground.color(ResolverLibrary.red)
        var state = ShowState(layers: [.background: .background(red, origin: fixedID(77))])
        var scene = resolver.resolve(state: state, provider: provider, now: Date()).program
        let canvas = harness.library.defaultTheme.canvasSize
        let redItem = RenderItem.color(ResolverLibrary.red, frame: PixelRect(size: canvas))
        #expect(scene.layers == [RenderLayer(kind: .background, contentID: fixedID(77), items: [redItem])])
        #expect(scene.transition == harness.library.defaultTheme.transition)

        state.layers[.background] = .background(SlideBackground(kind: .color), origin: fixedID(78))
        scene = resolver.resolve(state: state, provider: provider, now: Date()).program
        #expect(scene.layers.first?.items == [.color(.black, frame: PixelRect(size: canvas))])

        state.layers[.background] = .background(.none, origin: fixedID(79))
        scene = resolver.resolve(state: state, provider: provider, now: Date()).program
        #expect(scene.layers == RenderScene.empty(canvas: canvas).layers)

        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        harness.controller.send(.clearLayer(.slide))
        #expect(harness.program.layers.map(\.kind) == [.background])
        harness.controller.send(.clearAll)
        #expect(harness.program.layers == RenderScene.empty(canvas: canvas).layers)
        #expect(harness.program.transition == harness.library.defaultTheme.transition)
    }

    @Test("Trang đang chiếu không còn trong chuỗi: không vẽ lớp trang")
    func staleSlideIsNotDrawn() {
        let library = ResolverLibrary()
        let live = LivePosition(source: library.songSource, slideIndex: 0, slideID: fixedID(999), wentLiveAt: Date())
        let state = ShowState(live: live, layers: [.slide: .slide(slideID: fixedID(999))])
        let scene = SceneResolver().resolve(state: state, provider: library.provider, now: Date()).program
        #expect(scene.layers == RenderScene.empty(canvas: library.defaultTheme.canvasSize).layers)
    }
}

@MainActor @Suite("SceneResolver: màn hình nhắc")
struct SceneResolverStageTests {
    @Test("Bố cục: tên mục + nhãn đoạn, đồng hồ, trang hiện tại, trang kế, ghi chú")
    func layout() throws {
        let harness = ResolverHarness()
        // 2027-01-15 09:02:03 UTC, tức 16:02:03 giờ Việt Nam.
        harness.clock.now = Date(timeIntervalSince1970: 1_800_003_723)
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let stage = harness.stage
        #expect(stage.canvasSize == .fullHD)
        #expect(stage.layers.map(\.kind) == [.background, .slide, .overlay])
        #expect(stage.layers[0].items == [.color(.black, frame: PixelRect(size: .fullHD))])
        #expect(stage.layers[1].contentID == fixedID(1))
        let texts = harness.stageTexts()
        #expect(texts[StageLayout.Region.title.frame] == "Chúa Là Đá Muôn Đời · Câu 1")
        #expect(texts[StageLayout.Region.clock.frame] == "16:02:03")
        #expect(texts[StageLayout.Region.current.frame] == "Chúa là đá\nmuôn đời")
        #expect(texts[StageLayout.Region.next.frame] == "ha-lê-lu-gia")
        #expect(texts[StageLayout.Region.notes.frame] == "Chậm lại")
        guard case .text(let clock, _) = stage.layers[2].items.first else {
            Issue.record("Thiếu đồng hồ")
            return
        }
        #expect(clock.style.fontFamily == SceneResolver.monospacedDigitFontFamily)
        #expect(clock.style.alignment == .right)
        #expect(clock.maxLines == 1)
    }

    @Test("Trang kế bỏ qua trang tắt; trang kế không có chữ thì ghi rõ; không ghi chú thì không có vùng ghi chú")
    func nextSkipsDisabled() {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 1))
        var texts = harness.stageTexts()
        #expect(texts[StageLayout.Region.next.frame] == "Trang kế không có chữ")
        #expect(texts[StageLayout.Region.notes.frame] == nil)
        #expect(texts[StageLayout.Region.title.frame] == "Chúa Là Đá Muôn Đời · Câu 1")
        harness.controller.send(.next)
        texts = harness.stageTexts()
        #expect(texts[StageLayout.Region.title.frame] == "Chúa Là Đá Muôn Đời · Điệp khúc")
        #expect(texts[StageLayout.Region.current.frame] == nil)
    }

    @Test("Trang cuối của mục: \"Tiếp theo\" là mục kế lên được (bỏ tiêu đề, bỏ mục không có trang bật)")
    func upNextAtEndOfItem() {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.planItem(201), slideIndex: 5))
        #expect(harness.stageTexts()[StageLayout.Region.next.frame] == "Tiếp theo: dddddddddddd")
    }

    @Test("Trang cuối của mục cuối, hoặc nguồn ngoài chương trình: không có vùng trang kế")
    func nothingAfterLastItem() {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.planItem(204), slideIndex: 0))
        #expect(harness.stageTexts()[StageLayout.Region.next.frame] == nil)
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 5))
        #expect(harness.stageTexts()[StageLayout.Region.next.frame] == nil)
    }

    @Test("Không có gì đang chiếu: chỉ đồng hồ và \"Tiếp theo: <mục đang chọn>\"")
    func idle() {
        let harness = ResolverHarness()
        harness.controller.send(.loadPlan(planID: harness.library.plan.id))
        harness.controller.send(.selectItem(harness.library.planItem(201)))
        let stage = harness.sink.previews.last!.stage
        var texts: [PixelRect: String] = [:]
        for layer in stage.layers {
            for case .text(let block, let frame) in layer.items {
                texts[frame] = block.string
            }
        }
        #expect(texts.count == 2)
        #expect(texts[StageLayout.Region.next.frame] == "Tiếp theo: Chúa Là Đá Muôn Đời")
        #expect(texts[StageLayout.Region.clock.frame] != nil)
        #expect(stage.layers[1].contentID == StageLayout.idleContentID)

        let bare = SceneResolver().resolve(state: ShowState(), provider: harness.library.provider, now: Date())
        #expect(bare.stage.layers[1].items.isEmpty)
        #expect(bare.program.layers == RenderScene.empty(canvas: harness.library.defaultTheme.canvasSize).layers)
    }

    @Test("Đồng hồ đổi mỗi giây làm màn hình nhắc xuất lại")
    func clockTicks() {
        let harness = ResolverHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let count = harness.sink.outputs.count
        harness.clock.fire()
        #expect(harness.sink.outputs.count == count)
        harness.clock.advance(by: 1)
        harness.clock.fire()
        #expect(harness.sink.outputs.count == count + 1)
    }

    nonisolated static let labelNames: [(GroupLabel, String)] = [
        (GroupLabel(kind: .verse, number: 2), "Câu 2"),
        (GroupLabel(kind: .chorus), "Điệp khúc"),
        (GroupLabel(kind: .prechorus), "Tiền điệp khúc"),
        (GroupLabel(kind: .bridge, number: 1), "Cầu nối 1"),
        (GroupLabel(kind: .tag), "Lặp cuối"),
        (GroupLabel(kind: .intro), "Dạo đầu"),
        (GroupLabel(kind: .ending), "Kết"),
        (GroupLabel(kind: .custom, custom: " Lời chứng "), "Lời chứng"),
        (GroupLabel(kind: .custom), "Đoạn"),
    ]

    @Test("Tên nhãn đoạn", arguments: Self.labelNames)
    func groupLabelNames(label: GroupLabel, expected: String) {
        #expect(label.displayName == expected)
    }

    @Test("Loại media theo phần mở rộng")
    func mediaKindByExtension() {
        #expect(MediaKind(fileExtension: "MOV") == .video)
        #expect(MediaKind(fileExtension: "heic") == .image)
        #expect(MediaKind(fileExtension: "m4a") == .audio)
        #expect(MediaKind(fileExtension: "pdf") == nil)
    }
}

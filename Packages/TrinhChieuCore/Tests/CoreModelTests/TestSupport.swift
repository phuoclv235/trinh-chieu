import Foundation

@testable import CoreModel

/// Đồng hồ giả: thời gian do test đặt, nhịp do test gọi.
@MainActor final class FakeClock: ShowClock {
    var now: Date
    private var handler: (@MainActor () -> Void)?

    init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.now = now
    }

    var isTicking: Bool { handler != nil }

    func startTicking(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func stopTicking() {
        handler = nil
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    func fire() {
        handler?()
    }
}

/// Nơi nhận cảnh ghi lại mọi lần giao.
@MainActor final class RecordingSink: SceneSink {
    var outputs: [ScenePublication] = []
    var previews: [ScenePublication] = []

    var callCount: Int { outputs.count + previews.count }

    func publishToOutputs(_ publication: ScenePublication) {
        outputs.append(publication)
    }

    func publishToPreview(_ publication: ScenePublication) {
        previews.append(publication)
    }
}

/// Bộ dựng cảnh giả: mỗi lớp trong trạng thái thành một `RenderLayer` rỗng với `contentID` tương ứng.
/// Màn hình nhắc có một khối chữ ghi giây hiện tại khi `stageShowsClock` bật.
struct FakeResolver: SceneResolving {
    var stageShowsClock = true

    @MainActor func resolve(state: ShowState, provider: any ShowContentProvider, now: Date) -> ScenePublication {
        var layers: [RenderLayer] = []
        for kind in LayerKind.allCases {
            switch state.layers[kind] {
            case .background(_, let origin):
                layers.append(RenderLayer(kind: kind, contentID: origin, items: []))
            case .slide(let slideID):
                layers.append(RenderLayer(kind: kind, contentID: slideID, items: []))
            case nil:
                break
            }
        }
        let canvas = provider.theme(nil).canvasSize
        let program = RenderScene(canvasSize: canvas, layers: layers)
        let clockText = stageShowsClock ? "\(Int(now.timeIntervalSince1970))" : ""
        let style = ResolvedTextStyle(TextStyle())
        let block = TextBlock(string: clockText, style: style, autoFit: .none)
        let stageLayer = RenderLayer(
            kind: .slide, contentID: state.live?.slideID ?? RenderScene.emptyContentID,
            items: [.text(block, frame: PixelRect(size: canvas))]
        )
        return ScenePublication(program: program, stage: RenderScene(canvasSize: canvas, layers: [stageLayer]))
    }
}

/// UUID cố định dễ đọc cho test.
func fixedID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", number))!
}

/// Thư viện mẫu cho test điều khiển.
///
/// Bộ `song` (thứ tự hát mặc định A, B): a1, a2, b1, b2 (tắt), b3 (nền riêng màu đỏ).
/// Chương trình: tiêu đề, `song`, ghi chú, mục trỏ tới bộ không tồn tại, `short`, Kinh Thánh, media.
@MainActor struct SampleLibrary {
    let theme = Theme.fallback(id: fixedID(900), name: "Mẫu test")
    let defaultTheme = Theme.fallback(id: fixedID(901), name: "Mẫu mặc định")
    let song: Presentation
    let short: Presentation
    let plan: ServicePlan
    let scripture: SlideSequence
    let media: MediaID = "abcdef012345"
    let provider: InMemoryContentProvider

    static let red = RGBA(red: 255, green: 0, blue: 0)

    init() {
        let slideA1 = Slide(id: fixedID(1), elements: [.text(TextElement(slot: .body, text: "A1"))])
        let slideA2 = Slide(id: fixedID(2), elements: [.text(TextElement(slot: .body, text: "A2"))])
        let slideB1 = Slide(id: fixedID(3), elements: [.text(TextElement(slot: .body, text: "B1"))])
        let slideB2 = Slide(id: fixedID(4), enabled: false, elements: [.text(TextElement(slot: .body, text: "B2"))])
        let slideB3 = Slide(id: fixedID(5), background: .color(SampleLibrary.red))
        let groupA = SlideGroup(id: fixedID(10), label: GroupLabel(kind: .verse, number: 1), slides: [slideA1, slideA2])
        let groupB = SlideGroup(id: fixedID(11), label: GroupLabel(kind: .chorus), slides: [slideB1, slideB2, slideB3])
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        song = Presentation(
            id: fixedID(100), kind: .song, title: "Bài hát", createdAt: created, modifiedAt: created,
            themeID: theme.id, groups: [groupA, groupB]
        )
        let slideS1 = Slide(id: fixedID(20))
        let groupS = SlideGroup(id: fixedID(21), label: GroupLabel(kind: .custom, custom: "Trang"), slides: [slideS1])
        short = Presentation(
            id: fixedID(101), kind: .generic, title: "Ngắn", createdAt: created, modifiedAt: created, groups: [groupS]
        )
        let scriptureSource = LiveSource.scripture(translation: "vi1925", reference: "Giăng 3:16")
        let verses = [Slide(id: fixedID(30)), Slide(id: fixedID(31))].map {
            SequencedSlide(slide: $0, groupID: nil, groupLabel: nil, indexInGroup: 0, presentationID: nil)
        }
        scripture = SlideSequence(source: scriptureSource, title: "Giăng 3:16", slides: verses)
        let verseItem = PlanScriptureItem(
            id: fixedID(206), reference: "Giăng 3:16", translation: "vi1925", themeID: theme.id
        )
        let items: [ServicePlanItem] = [
            .header(PlanHeaderItem(id: fixedID(201), title: "Thờ phượng")),
            .presentation(PlanPresentationItem(id: fixedID(202), presentationID: song.id)),
            .note(PlanNoteItem(id: fixedID(203), text: "Mời Hội Thánh đứng")),
            .presentation(PlanPresentationItem(id: fixedID(204), presentationID: fixedID(999))),
            .presentation(PlanPresentationItem(id: fixedID(205), presentationID: short.id)),
            .scripture(verseItem),
            .media(PlanMediaItem(id: fixedID(207), mediaID: media)),
        ]
        plan = ServicePlan(id: fixedID(200), title: "Chúa Nhật", date: "2026-11-30", items: items)
        provider = InMemoryContentProvider(
            presentations: [song, short], plans: [plan], themes: [theme], defaultTheme: defaultTheme,
            mediaURLs: [media: URL(fileURLWithPath: "/tmp/abcdef012345.mp4")],
            scriptureSequences: [scriptureSource: scripture]
        )
    }

    var songSource: LiveSource { .presentation(id: song.id, arrangementID: nil) }

    func planItem(_ number: Int) -> LiveSource {
        .planItem(planID: plan.id, itemID: fixedID(number))
    }
}

/// Bộ điều khiển kèm các phần giả để test.
@MainActor struct ControllerHarness {
    let library: SampleLibrary
    let sink = RecordingSink()
    let log = InMemoryServiceLog()
    let clock = FakeClock()
    let controller: ShowController

    init(library: SampleLibrary = SampleLibrary(), resolver: FakeResolver = FakeResolver()) {
        self.library = library
        controller = ShowController(provider: library.provider, sink: sink, resolver: resolver, log: log, clock: clock)
    }

    var state: ShowState { controller.state }
}

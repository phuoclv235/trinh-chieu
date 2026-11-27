import Foundation
import Testing

@testable import CoreModel

@MainActor @Suite("ShowController: quy tắc xử lý lệnh")
struct ShowControllerTests {
    // MARK: - goLive

    @Test("goLive: đặt trang đang chiếu, lớp chữ, nền của mẫu khi lớp nền trống, ghi nhật ký")
    func goLiveSetsLiveSlideAndThemeBackground() {
        let harness = ControllerHarness()
        let result = harness.controller.send(.goLive(harness.library.songSource, slideIndex: 1))
        #expect(result == .applied)
        #expect(harness.state.live?.slideIndex == 1)
        #expect(harness.state.live?.slideID == fixedID(2))
        #expect(harness.state.live?.wentLiveAt == harness.clock.now)
        #expect(harness.state.layers[.slide] == .slide(slideID: fixedID(2)))
        let theme = harness.library.theme
        #expect(harness.state.layers[.background] == .background(theme.background, origin: theme.id))
        #expect(harness.sink.outputs.count == 1)
        #expect(harness.sink.previews.count == 1)
        let event = harness.log.events.last
        #expect(event?.type == .goLive)
        #expect(event?.slideID == fixedID(2))
        #expect(event?.presentationID == harness.library.song.id)
        #expect(event?.itemID == nil)
    }

    @Test("goLive: nguồn không tìm thấy thì bỏ qua, không gọi sink")
    func goLiveUnknownSourceIsIgnored() {
        let harness = ControllerHarness()
        let source = LiveSource.presentation(id: fixedID(999), arrangementID: nil)
        #expect(harness.controller.send(.goLive(source, slideIndex: 0)) == .ignored(.notFound))
        #expect(harness.sink.callCount == 0)
        #expect(harness.state.live == nil)
        #expect(harness.log.events.isEmpty)
    }

    @Test("goLive: chỉ số ngoài phạm vi thì bỏ qua", arguments: [-1, 5, 100])
    func goLiveOutOfRangeIsIgnored(index: Int) {
        let harness = ControllerHarness()
        let result = harness.controller.send(.goLive(harness.library.songSource, slideIndex: index))
        #expect(result == .ignored(.notFound))
        #expect(harness.sink.callCount == 0)
    }

    @Test("goLive: mục tiêu đề và ghi chú không lên màn được")
    func goLiveHeaderOrNoteIsIgnored() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.goLive(harness.library.planItem(201), slideIndex: 0)) == .ignored(.notFound))
        #expect(harness.controller.send(.goLive(harness.library.planItem(203), slideIndex: 0)) == .ignored(.notFound))
        #expect(harness.sink.callCount == 0)
    }

    @Test("goLive: trang tắt vẫn lên được khi chọn trực tiếp")
    func goLiveDisabledSlideDirectly() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.goLive(harness.library.songSource, slideIndex: 3)) == .applied)
        #expect(harness.state.live?.slideID == fixedID(4))
    }

    @Test("goLive: trang có nền riêng thay lớp nền")
    func goLiveSlideWithOwnBackgroundReplacesBackground() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 4))
        let expected = LayerState.background(.color(SampleLibrary.red), origin: fixedID(5))
        #expect(harness.state.layers[.background] == expected)
    }

    @Test("goLive: trang không có nền riêng giữ nền đang có")
    func goLiveSlideWithoutBackgroundKeepsBackground() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 4))
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let expected = LayerState.background(.color(SampleLibrary.red), origin: fixedID(5))
        #expect(harness.state.layers[.background] == expected)
        #expect(harness.state.layers[.slide] == .slide(slideID: fixedID(1)))
    }

    @Test("goLive: nguồn không có mẫu riêng dùng mẫu mặc định của thư viện")
    func goLiveUsesDefaultThemeBackground() {
        let harness = ControllerHarness()
        let source = LiveSource.presentation(id: harness.library.short.id, arrangementID: nil)
        harness.controller.send(.goLive(source, slideIndex: 0))
        let theme = harness.library.defaultTheme
        #expect(harness.state.layers[.background] == .background(theme.background, origin: theme.id))
    }

    @Test("goLive: mục chương trình ghi itemID vào nhật ký")
    func goLivePlanItemLogsItemID() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.goLive(harness.library.planItem(202), slideIndex: 0)) == .applied)
        #expect(harness.log.events.last?.itemID == fixedID(202))
        #expect(harness.log.events.last?.presentationID == harness.library.song.id)
    }

    @Test("goLive: media lên màn thành một trang có nền là media đó")
    func goLiveMediaSource() {
        let harness = ControllerHarness()
        let media = harness.library.media
        #expect(harness.controller.send(.goLive(.media(media), slideIndex: 0)) == .applied)
        #expect(harness.state.live?.slideID == media.contentUUID)
        let expected = LayerState.background(.media(media, loop: false), origin: media.contentUUID)
        #expect(harness.state.layers[.background] == expected)
    }

    @Test("goLive: media không còn trên đĩa thì bỏ qua")
    func goLiveMissingMediaIsIgnored() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.goLive(.media("000000000000"), slideIndex: 0)) == .ignored(.notFound))
    }

    // MARK: - next

    @Test("next: không có gì đang chiếu thì bỏ qua")
    func nextWithoutLiveIsIgnored() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.next) == .ignored(.nothingLive))
        #expect(harness.sink.callCount == 0)
    }

    @Test("next: sang trang kế và bỏ qua trang tắt")
    func nextSkipsDisabledSlides() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        #expect(harness.controller.send(.next) == .applied)
        #expect(harness.state.live?.slideIndex == 1)
        harness.controller.send(.next)
        #expect(harness.state.live?.slideIndex == 2)
        harness.controller.send(.next)
        #expect(harness.state.live?.slideIndex == 4)
        #expect(harness.state.live?.slideID == fixedID(5))
    }

    @Test("next: hết trang của bộ trình chiếu (không phải mục chương trình) thì bỏ qua")
    func nextAtEndOfPresentation() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 4))
        let before = harness.sink.callCount
        #expect(harness.controller.send(.next) == .ignored(.atEnd))
        #expect(harness.sink.callCount == before)
    }

    @Test("next: hết trang của mục thì sang mục kế lên màn được, bỏ qua ghi chú và mục không tìm thấy")
    func nextAdvancesToNextPlanItem() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.planItem(202), slideIndex: 4))
        #expect(harness.controller.send(.next) == .applied)
        #expect(harness.state.live?.source == harness.library.planItem(205))
        #expect(harness.state.live?.slideIndex == 0)
        #expect(harness.state.live?.slideID == fixedID(20))
        #expect(harness.log.events.last?.itemID == fixedID(205))
    }

    @Test("next: mục Kinh Thánh rồi mục media nối tiếp nhau")
    func nextWalksThroughScriptureAndMedia() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.planItem(205), slideIndex: 0))
        harness.controller.send(.next)
        #expect(harness.state.live?.source == harness.library.planItem(206))
        harness.controller.send(.next)
        #expect(harness.state.live?.slideID == fixedID(31))
        harness.controller.send(.next)
        #expect(harness.state.live?.source == harness.library.planItem(207))
        #expect(harness.controller.send(.next) == .ignored(.atEnd))
    }

    @Test("next: tắt advanceToNextItem thì dừng ở trang cuối của mục")
    func nextWithoutAdvanceStopsAtEnd() {
        let library = SampleLibrary()
        let sink = RecordingSink()
        let state = ShowState(settings: ShowSettings(advanceToNextItem: false))
        let controller = ShowController(
            provider: library.provider, sink: sink, resolver: FakeResolver(), log: InMemoryServiceLog(),
            clock: FakeClock(), state: state
        )
        controller.send(.goLive(library.planItem(202), slideIndex: 4))
        #expect(controller.send(.next) == .ignored(.atEnd))
        #expect(controller.state.live?.source == library.planItem(202))
    }

    @Test("next: chương trình không còn thì dừng ở trang cuối")
    func nextWhenPlanVanished() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.planItem(202), slideIndex: 4))
        harness.library.provider.plans = [:]
        #expect(harness.controller.send(.next) == .ignored(.notFound))
    }

    @Test("next: mục kế toàn trang tắt thì bỏ qua mục đó")
    func nextSkipsItemWithoutEnabledSlides() {
        let harness = ControllerHarness()
        var short = harness.library.short
        short.groups[0].slides[0].enabled = false
        harness.library.provider.presentations[short.id] = short
        harness.controller.send(.goLive(harness.library.planItem(202), slideIndex: 4))
        harness.controller.send(.next)
        #expect(harness.state.live?.source == harness.library.planItem(206))
    }

    // MARK: - previous

    @Test("previous: về trang trước có enabled, bỏ qua trang tắt")
    func previousSkipsDisabledSlides() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 4))
        #expect(harness.controller.send(.previous) == .applied)
        #expect(harness.state.live?.slideIndex == 2)
    }

    @Test("previous: ở trang đầu thì bỏ qua, không lùi sang mục trước")
    func previousAtStartDoesNotGoToPreviousItem() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.planItem(205), slideIndex: 0))
        let before = harness.sink.callCount
        #expect(harness.controller.send(.previous) == .ignored(.atStart))
        #expect(harness.state.live?.source == harness.library.planItem(205))
        #expect(harness.sink.callCount == before)
    }

    @Test("previous: không có gì đang chiếu thì bỏ qua")
    func previousWithoutLiveIsIgnored() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.previous) == .ignored(.nothingLive))
    }

    @Test("previous: nguồn đang chiếu không còn thì bỏ qua")
    func previousWhenSourceVanished() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 2))
        harness.library.provider.presentations = [:]
        #expect(harness.controller.send(.previous) == .ignored(.notFound))
    }

    // MARK: - clearLayer, clearAll

    @Test("clearLayer(.slide): bỏ trang đang chiếu và lớp chữ, giữ nền")
    func clearSlideLayer() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        #expect(harness.controller.send(.clearLayer(.slide)) == .applied)
        #expect(harness.state.live == nil)
        #expect(harness.state.layers[.slide] == nil)
        #expect(harness.state.layers[.background] != nil)
        #expect(harness.log.events.last?.type == .clearLayer)
        #expect(harness.log.events.last?.layer == .slide)
        #expect(harness.sink.outputs.count == 2)
    }

    @Test("clearLayer(.background): bỏ lớp nền, giữ trang đang chiếu")
    func clearBackgroundLayer() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        #expect(harness.controller.send(.clearLayer(.background)) == .applied)
        #expect(harness.state.layers[.background] == nil)
        #expect(harness.state.live != nil)
        #expect(harness.state.layers[.slide] != nil)
    }

    @Test("clearLayer: lớp đã trống thì bỏ qua, không gọi sink")
    func clearEmptyLayerIsIgnored() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.clearLayer(.overlay)) == .ignored(.nothingLive))
        #expect(harness.controller.send(.clearLayer(.slide)) == .ignored(.nothingLive))
        #expect(harness.sink.callCount == 0)
    }

    @Test("clearAll: bỏ mọi lớp và trang đang chiếu")
    func clearAllRemovesEverything() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        #expect(harness.controller.send(.clearAll) == .applied)
        #expect(harness.state.live == nil)
        #expect(harness.state.layers.isEmpty)
        #expect(harness.log.events.last?.type == .clearAll)
        #expect(harness.controller.send(.clearAll) == .ignored(.nothingLive))
    }

    // MARK: - Đóng băng, tập dượt

    @Test("setFreeze(true): trạng thái vẫn đổi, đầu ra giữ cảnh chính cũ, màn hình nhắc và xem trước cập nhật")
    func freezeHoldsProgramButUpdatesStageAndPreview() throws {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let heldProgram = try #require(harness.sink.outputs.last?.program)
        #expect(harness.controller.send(.setFreeze(true)) == .applied)
        harness.clock.advance(by: 5)
        harness.controller.send(.next)
        #expect(harness.state.isFrozen)
        #expect(harness.state.live?.slideIndex == 1)
        let output = try #require(harness.sink.outputs.last)
        let preview = try #require(harness.sink.previews.last)
        #expect(output.program == heldProgram)
        #expect(output.stage == preview.stage)
        #expect(preview.program.layers.contains { $0.contentID == fixedID(2) })
        #expect(!output.program.layers.contains { $0.contentID == fixedID(2) })
        #expect(harness.log.events.contains { $0.type == .freeze && $0.enabled == true })
    }

    @Test("setFreeze(false): xuất ngay cảnh hiện tại ra đầu ra")
    func unfreezePublishesCurrentScene() throws {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        harness.controller.send(.setFreeze(true))
        harness.controller.send(.next)
        #expect(harness.controller.send(.setFreeze(false)) == .applied)
        let output = try #require(harness.sink.outputs.last)
        #expect(output.program.layers.contains { $0.contentID == fixedID(2) })
        #expect(harness.controller.lastProgramPublished == output.program)
    }

    @Test("Đóng băng khi chưa xuất gì: đầu ra giữ cảnh trống nền đen")
    func freezeBeforeAnyPublicationHoldsEmptyScene() throws {
        let harness = ControllerHarness()
        harness.controller.send(.setFreeze(true))
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let output = try #require(harness.sink.outputs.last)
        var expected = RenderScene.empty(canvas: .fullHD)
        expected.revision = output.program.revision
        #expect(output.program == expected)
    }

    @Test("setRehearsal(true): đầu ra chính giữ nguyên như đóng băng, xem trước vẫn cập nhật")
    func rehearsalBehavesLikeFreezeForOutputs() throws {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let heldProgram = try #require(harness.sink.outputs.last?.program)
        #expect(harness.controller.send(.setRehearsal(true)) == .applied)
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 2))
        #expect(harness.state.isRehearsal)
        #expect(!harness.state.isFrozen)
        #expect(harness.sink.outputs.last?.program == heldProgram)
        #expect(harness.sink.previews.last?.program.layers.contains { $0.contentID == fixedID(3) } == true)
        #expect(harness.log.events.contains { $0.type == .rehearsal && $0.enabled == true })
        harness.controller.send(.setRehearsal(false))
        #expect(harness.sink.outputs.last?.program.layers.contains { $0.contentID == fixedID(3) } == true)
    }

    // MARK: - contentDidChange

    @Test("contentDidChange: trang đang chiếu đổi vị trí thì tìm lại theo slideID")
    func contentChangeFindsSlideByID() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 2))
        var song = harness.library.song
        song.groups[0].slides.remove(at: 0)
        harness.library.provider.presentations[song.id] = song
        let before = harness.sink.callCount
        #expect(harness.controller.send(.contentDidChange(ids: [song.id])) == .applied)
        #expect(harness.state.live?.slideIndex == 1)
        #expect(harness.state.live?.slideID == fixedID(3))
        #expect(harness.sink.callCount == before + 2)
    }

    @Test("contentDidChange: trang đang chiếu bị xoá, chỉ số còn hợp lệ thì giữ chỉ số")
    func contentChangeKeepsIndexWhenSlideRemoved() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 1))
        var song = harness.library.song
        song.groups[0].slides.remove(at: 1)
        harness.library.provider.presentations[song.id] = song
        #expect(harness.controller.send(.contentDidChange(ids: [song.id])) == .applied)
        #expect(harness.state.live?.slideIndex == 1)
        #expect(harness.state.live?.slideID == fixedID(3))
        #expect(harness.state.layers[.slide] == .slide(slideID: fixedID(3)))
    }

    @Test("contentDidChange: trang mới ở chỉ số cũ có nền riêng thì thay lớp nền")
    func contentChangeAppliesNewSlideBackground() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 3))
        var song = harness.library.song
        song.groups[1].slides.remove(at: 1)
        harness.library.provider.presentations[song.id] = song
        harness.controller.send(.contentDidChange(ids: [song.id]))
        #expect(harness.state.live?.slideID == fixedID(5))
        let expected = LayerState.background(.color(SampleLibrary.red), origin: fixedID(5))
        #expect(harness.state.layers[.background] == expected)
    }

    @Test("contentDidChange: mẫu đang dùng đổi nền thì lấy lại nền của mẫu")
    func contentChangeRefreshesThemeBackground() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        var theme = harness.library.theme
        theme.background = .color(RGBA(red: 0, green: 0, blue: 255))
        harness.library.provider.themes[theme.id] = theme
        #expect(harness.controller.send(.contentDidChange(ids: [theme.id])) == .applied)
        #expect(harness.state.layers[.background] == .background(theme.background, origin: theme.id))
    }

    @Test("contentDidChange: trang mất và chỉ số không còn hợp lệ thì xoá lớp chữ")
    func contentChangeClearsSlideWhenIndexInvalid() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 4))
        var song = harness.library.song
        song.groups[1].slides.removeLast()
        harness.library.provider.presentations[song.id] = song
        #expect(harness.controller.send(.contentDidChange(ids: [song.id])) == .applied)
        #expect(harness.state.live == nil)
        #expect(harness.state.layers[.slide] == nil)
    }

    @Test("contentDidChange: nguồn đang chiếu bị xoá thì xoá lớp chữ")
    func contentChangeClearsSlideWhenSourceRemoved() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.planItem(202), slideIndex: 0))
        harness.library.provider.presentations[harness.library.song.id] = nil
        #expect(harness.controller.send(.contentDidChange(ids: [harness.library.song.id])) == .applied)
        #expect(harness.state.live == nil)
        #expect(harness.state.layers[.background] != nil)
    }

    @Test("contentDidChange: nội dung không liên quan hoặc không có gì đang chiếu thì bỏ qua")
    func contentChangeUnrelatedIsIgnored() {
        let harness = ControllerHarness()
        #expect(harness.controller.send(.contentDidChange(ids: [fixedID(100)])) == .ignored(.nothingLive))
        harness.controller.send(.goLive(.media(harness.library.media), slideIndex: 0))
        let before = harness.sink.callCount
        #expect(harness.controller.send(.contentDidChange(ids: [fixedID(100)])) == .ignored(.nothingLive))
        #expect(harness.sink.callCount == before)
        let mediaID = harness.library.media.contentUUID
        #expect(harness.controller.send(.contentDidChange(ids: [mediaID])) == .applied)
    }

    @Test("contentDidChange: nguồn Kinh Thánh chỉ phản ứng với id của trang đang chiếu")
    func contentChangeForScripture() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.planItem(206), slideIndex: 0))
        #expect(harness.controller.send(.contentDidChange(ids: [harness.library.theme.id])) == .applied)
        let scripture = LiveSource.scripture(translation: "vi1925", reference: "Giăng 3:16")
        harness.controller.send(.goLive(scripture, slideIndex: 1))
        #expect(harness.controller.send(.contentDidChange(ids: [fixedID(200)])) == .ignored(.nothingLive))
        #expect(harness.controller.send(.contentDidChange(ids: [fixedID(31)])) == .applied)
    }

    // MARK: - selectItem, loadPlan

    @Test("selectItem: chỉ đổi selected, không đụng đầu ra")
    func selectItemOnlyChangesSelection() {
        let harness = ControllerHarness()
        let source = harness.library.planItem(205)
        #expect(harness.controller.send(.selectItem(source)) == .applied)
        #expect(harness.state.selected == source)
        #expect(harness.state.live == nil)
        #expect(harness.sink.outputs.isEmpty)
        #expect(harness.sink.previews.count == 1)
    }

    @Test("loadPlan: đổi chương trình, bỏ chọn, không đụng đầu ra")
    func loadPlanResetsSelection() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        harness.controller.send(.selectItem(harness.library.planItem(205)))
        let outputs = harness.sink.outputs.count
        #expect(harness.controller.send(.loadPlan(planID: harness.library.plan.id)) == .applied)
        #expect(harness.state.activePlanID == harness.library.plan.id)
        #expect(harness.state.selected == nil)
        #expect(harness.state.live?.slideID == fixedID(1))
        #expect(harness.sink.outputs.count == outputs)
        #expect(harness.controller.send(.loadPlan(planID: nil)) == .applied)
        #expect(harness.state.activePlanID == nil)
    }

    // MARK: - Xuất cảnh

    @Test("revision tăng dần mỗi lần xuất")
    func revisionIncreasesWithEachPublication() {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        harness.controller.send(.next)
        harness.controller.send(.selectItem(harness.library.songSource))
        let revisions = harness.sink.previews.map(\.program.revision)
        #expect(revisions == [1, 2, 3])
        #expect(harness.sink.outputs.map(\.stage.revision) == [1, 2])
    }

    @Test("Nhịp mỗi giây: chỉ xuất khi màn hình nhắc đổi")
    func tickPublishesOnlyWhenStageChanges() {
        let harness = ControllerHarness()
        #expect(harness.clock.isTicking)
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let before = harness.sink.outputs.count
        harness.clock.fire()
        #expect(harness.sink.outputs.count == before)
        harness.clock.advance(by: 1)
        harness.clock.fire()
        #expect(harness.sink.outputs.count == before + 1)
        #expect(harness.sink.previews.count == before + 1)
    }

    @Test("Nhịp mỗi giây: màn hình nhắc không có đồng hồ thì không xuất")
    func tickWithStaticStageDoesNothing() {
        let harness = ControllerHarness(resolver: FakeResolver(stageShowsClock: false))
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        let before = harness.sink.callCount
        harness.clock.advance(by: 3)
        harness.clock.fire()
        #expect(harness.sink.callCount == before)
    }

    @Test("Nhịp mỗi giây khi đóng băng: màn hình nhắc cập nhật, cảnh chính giữ nguyên")
    func tickWhileFrozenKeepsProgram() throws {
        let harness = ControllerHarness()
        harness.controller.send(.goLive(harness.library.songSource, slideIndex: 0))
        harness.controller.send(.setFreeze(true))
        let held = try #require(harness.sink.outputs.last?.program)
        harness.clock.advance(by: 1)
        harness.clock.fire()
        let output = try #require(harness.sink.outputs.last)
        #expect(output.program == held)
        #expect(output.stage.revision > held.revision)
    }
}

@MainActor @Suite("Đồng hồ hệ thống")
struct SystemShowClockTests {
    @Test("Đếm nhịp mỗi giây và dừng được")
    func ticksAndStops() async throws {
        let clock = SystemShowClock()
        #expect(abs(clock.now.timeIntervalSinceNow) < 1)
        let counter = TickCounter()
        clock.startTicking {
            counter.count += 1
        }
        try await Task.sleep(for: .milliseconds(1500))
        clock.stopTicking()
        #expect(counter.count >= 1)
        let counted = counter.count
        try await Task.sleep(for: .milliseconds(1200))
        #expect(counter.count == counted)
    }
}

@MainActor private final class TickCounter {
    var count = 0
}

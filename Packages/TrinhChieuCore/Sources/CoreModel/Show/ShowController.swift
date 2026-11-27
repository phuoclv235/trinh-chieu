import Foundation
import Observation

/// Kết quả xử lý một lệnh.
public enum CommandResult: Sendable, Equatable {
    case applied
    case ignored(IgnoreReason)
}

/// Lý do lệnh bị bỏ qua.
public enum IgnoreReason: Sendable, Equatable {
    case notFound
    case notLiveable
    case atEnd
    case atStart
    case frozen
    case nothingLive
}

/// Lõi điều phối: nhận `ShowCommand`, đổi `ShowState`, dựng cảnh và giao cho đầu ra.
@MainActor @Observable public final class ShowController {
    public private(set) var state: ShowState

    @ObservationIgnored private let provider: any ShowContentProvider
    @ObservationIgnored private let sink: any SceneSink
    @ObservationIgnored private let resolver: any SceneResolving
    @ObservationIgnored private let log: any ServiceLogSink
    @ObservationIgnored private let clock: any ShowClock

    /// Cảnh đầu ra chính của lần xuất cuối ra đầu ra (giữ khi đóng băng hoặc tập dượt).
    @ObservationIgnored public private(set) var lastProgramPublished: RenderScene?
    /// Cảnh màn hình nhắc của lần dựng cuối, chưa đóng số `revision`; dùng để biết nhịp đồng hồ có đổi gì không.
    @ObservationIgnored private var lastResolvedStage: RenderScene?
    @ObservationIgnored private var revision: UInt64 = 0

    public init(
        provider: any ShowContentProvider, sink: any SceneSink, resolver: any SceneResolving,
        log: any ServiceLogSink, clock: any ShowClock, state: ShowState = ShowState()
    ) {
        self.provider = provider
        self.sink = sink
        self.resolver = resolver
        self.log = log
        self.clock = clock
        self.state = state
        clock.startTicking { [weak self] in
            self?.tick()
        }
    }

    /// Xử lý một lệnh. Lệnh `applied` dựng cảnh và giao cho `sink`; lệnh `ignored` không gọi `sink`.
    @discardableResult public func send(_ command: ShowCommand) -> CommandResult {
        let result = apply(command)
        guard result == .applied else {
            return result
        }
        switch command {
        case .loadPlan, .selectItem:
            // Không đụng đầu ra: chỉ ô xem trước cập nhật.
            publishPreviewOnly()
        default:
            publish()
        }
        return result
    }

    /// Đổi thiết lập trình chiếu (Cài đặt > Trực tiếp). Không đụng đầu ra; thiết lập có tác dụng từ lệnh kế tiếp.
    public func updateSettings(_ settings: ShowSettings) {
        guard state.settings != settings else {
            return
        }
        state.settings = settings
    }

    /// Nhịp mỗi giây: dựng lại cảnh và chỉ xuất khi màn hình nhắc đổi (ví dụ đồng hồ).
    public func tick() {
        let publication = resolver.resolve(state: state, provider: provider, now: clock.now)
        guard publication.stage != lastResolvedStage else {
            return
        }
        deliver(publication)
    }

    // MARK: - Xử lý lệnh

    private func apply(_ command: ShowCommand) -> CommandResult {
        switch command {
        case .loadPlan(let planID):
            state.activePlanID = planID
            state.selected = nil
            return .applied
        case .selectItem(let source):
            state.selected = source
            return .applied
        case .goLive(let source, let slideIndex):
            guard let sequence = provider.sequence(for: source) else {
                return .ignored(.notFound)
            }
            guard sequence.slides.indices.contains(slideIndex) else {
                return .ignored(.notFound)
            }
            goLive(sequence, at: slideIndex)
            return .applied
        case .next:
            return next()
        case .previous:
            return previous()
        case .clearLayer(let layer):
            return clearLayer(layer)
        case .clearAll:
            return clearAll()
        case .setFreeze(let enabled):
            state.isFrozen = enabled
            log.record(ServiceLogEvent(at: clock.now, type: .freeze, enabled: enabled))
            return .applied
        case .setRehearsal(let enabled):
            state.isRehearsal = enabled
            log.record(ServiceLogEvent(at: clock.now, type: .rehearsal, enabled: enabled))
            return .applied
        case .contentDidChange(let ids):
            return contentDidChange(ids)
        }
    }

    private func goLive(_ sequence: SlideSequence, at index: Int) {
        let entry = sequence.slides[index]
        let now = clock.now
        state.live = LivePosition(source: sequence.source, slideIndex: index, slideID: entry.slide.id, wentLiveAt: now)
        state.layers[.slide] = .slide(slideID: entry.slide.id)
        updateBackground(for: entry.slide, themeID: sequence.themeID)
        var itemID: UUID?
        if case .planItem(_, let id) = sequence.source {
            itemID = id
        }
        let event = ServiceLogEvent(
            at: now, type: .goLive, itemID: itemID, presentationID: entry.presentationID, slideID: entry.slide.id
        )
        log.record(event)
    }

    /// Trang có nền riêng thì thay lớp nền; không thì giữ nền đang có, lớp nền trống thì dùng nền của mẫu.
    private func updateBackground(for slide: Slide, themeID: UUID?) {
        if slide.background.kind != .none {
            state.layers[.background] = .background(slide.background, origin: slide.id)
        } else if state.layers[.background] == nil {
            let theme = provider.theme(themeID)
            state.layers[.background] = .background(theme.background, origin: theme.id)
        }
    }

    private func next() -> CommandResult {
        guard let live = state.live else {
            return .ignored(.nothingLive)
        }
        guard let sequence = provider.sequence(for: live.source) else {
            return .ignored(.notFound)
        }
        let current = sequence.index(of: live) ?? live.slideIndex
        if let index = sequence.slides.indices.first(where: { $0 > current && sequence.slides[$0].slide.enabled }) {
            goLive(sequence, at: index)
            return .applied
        }
        guard state.settings.advanceToNextItem, case .planItem(let planID, let itemID) = live.source else {
            return .ignored(.atEnd)
        }
        guard let plan = provider.plan(planID), let position = plan.items.firstIndex(where: { $0.id == itemID }) else {
            return .ignored(.atEnd)
        }
        for item in plan.items[(position + 1)...] where item.isLiveable {
            let source = LiveSource.planItem(planID: planID, itemID: item.id)
            guard let nextSequence = provider.sequence(for: source) else {
                continue
            }
            guard let first = nextSequence.slides.indices.first(where: { nextSequence.slides[$0].slide.enabled }) else {
                continue
            }
            goLive(nextSequence, at: first)
            return .applied
        }
        return .ignored(.atEnd)
    }

    private func previous() -> CommandResult {
        guard let live = state.live else {
            return .ignored(.nothingLive)
        }
        guard let sequence = provider.sequence(for: live.source) else {
            return .ignored(.notFound)
        }
        let current = sequence.index(of: live) ?? live.slideIndex
        let candidates = sequence.slides.indices.filter { $0 < current && sequence.slides[$0].slide.enabled }
        guard let index = candidates.last else {
            return .ignored(.atStart)
        }
        goLive(sequence, at: index)
        return .applied
    }

    private func clearLayer(_ layer: LayerKind) -> CommandResult {
        let hadContent = state.layers[layer] != nil || (layer == .slide && state.live != nil)
        guard hadContent else {
            return .ignored(.nothingLive)
        }
        state.layers[layer] = nil
        if layer == .slide {
            state.live = nil
        }
        log.record(ServiceLogEvent(at: clock.now, type: .clearLayer, layer: layer))
        return .applied
    }

    private func clearAll() -> CommandResult {
        guard !state.layers.isEmpty || state.live != nil else {
            return .ignored(.nothingLive)
        }
        state.layers = [:]
        state.live = nil
        log.record(ServiceLogEvent(at: clock.now, type: .clearAll))
        return .applied
    }

    private func contentDidChange(_ ids: Set<UUID>) -> CommandResult {
        guard let live = state.live else {
            return .ignored(.nothingLive)
        }
        let sequence = provider.sequence(for: live.source)
        guard !ids.isDisjoint(with: affectedIDs(of: live, sequence: sequence)) else {
            return .ignored(.nothingLive)
        }
        guard let sequence else {
            removeLiveSlide()
            return .applied
        }
        let index: Int
        if let found = sequence.index(of: live) {
            index = found
        } else if sequence.slides.indices.contains(live.slideIndex) {
            index = live.slideIndex
        } else {
            removeLiveSlide()
            return .applied
        }
        let slide = sequence.slides[index].slide
        state.live?.slideIndex = index
        state.live?.slideID = slide.id
        state.layers[.slide] = .slide(slideID: slide.id)
        if slide.background.kind != .none {
            state.layers[.background] = .background(slide.background, origin: slide.id)
        } else if case .background(_, let origin) = state.layers[.background] {
            // Nền đang lấy từ mẫu thì lấy lại, phòng khi chính mẫu vừa đổi.
            let theme = provider.theme(sequence.themeID)
            if origin == theme.id {
                state.layers[.background] = .background(theme.background, origin: theme.id)
            }
        }
        return .applied
    }

    /// Các id mà một thay đổi nội dung cần chạm vào để ảnh hưởng tới nội dung đang chiếu.
    private func affectedIDs(of live: LivePosition, sequence: SlideSequence?) -> Set<UUID> {
        var ids: Set<UUID> = [live.slideID]
        switch live.source {
        case .planItem(let planID, let itemID):
            ids.formUnion([planID, itemID])
            switch provider.plan(planID)?.items.first(where: { $0.id == itemID }) {
            case .presentation(let entry):
                ids.insert(entry.presentationID)
            case .media(let entry):
                ids.insert(entry.mediaID.contentUUID)
            default:
                break
            }
        case .presentation(let id, _):
            ids.insert(id)
        case .media(let mediaID):
            ids.insert(mediaID.contentUUID)
        case .scripture:
            break
        }
        if let sequence {
            if let themeID = sequence.themeID {
                ids.insert(themeID)
            }
            for entry in sequence.slides {
                if let presentationID = entry.presentationID {
                    ids.insert(presentationID)
                }
            }
        }
        return ids
    }

    private func removeLiveSlide() {
        state.live = nil
        state.layers[.slide] = nil
    }

    // MARK: - Xuất cảnh

    private func publish() {
        let publication = resolver.resolve(state: state, provider: provider, now: clock.now)
        deliver(publication)
    }

    /// Đóng băng hoặc tập dượt: đầu ra giữ `program` của lần xuất cuối, màn hình nhắc và xem trước vẫn cập nhật.
    private func deliver(_ resolved: ScenePublication) {
        lastResolvedStage = resolved.stage
        let publication = stamped(resolved)
        if state.isFrozen || state.isRehearsal {
            let held = lastProgramPublished ?? heldEmptyProgram(canvas: publication.program.canvasSize)
            lastProgramPublished = held
            sink.publishToOutputs(ScenePublication(program: held, stage: publication.stage))
        } else {
            lastProgramPublished = publication.program
            sink.publishToOutputs(publication)
        }
        sink.publishToPreview(publication)
    }

    private func publishPreviewOnly() {
        let resolved = resolver.resolve(state: state, provider: provider, now: clock.now)
        sink.publishToPreview(stamped(resolved))
    }

    private func stamped(_ publication: ScenePublication) -> ScenePublication {
        revision += 1
        var result = publication
        result.program.revision = revision
        result.stage.revision = revision
        return result
    }

    private func heldEmptyProgram(canvas: PixelSize) -> RenderScene {
        var scene = RenderScene.empty(canvas: canvas)
        scene.revision = revision
        return scene
    }
}

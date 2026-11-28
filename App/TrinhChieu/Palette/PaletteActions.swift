import CoreModel
import Foundation
import LibraryIndex
import LibraryStore
import Scripture

/// Việc chỉ khung cửa sổ làm được (đổi chế độ, mở cửa sổ Cài đặt), Bảng lệnh gọi qua đây.
struct PaletteHost {
    let setMode: @MainActor (WorkspaceMode) -> Void
    let openSettings: @MainActor () -> Void
}

/// Kết quả sau khi thực hiện một dòng.
enum PaletteOutcome: Equatable {
    /// Xong, đóng Bảng lệnh.
    case close
    /// Điền chữ vào ô và chờ gõ tiếp (chọn tên sách).
    case fill(String)
    /// Không làm được (chưa có bản dịch, mục đã bị xoá): giữ Bảng lệnh mở.
    case unavailable
}

/// Nối Bảng lệnh với lõi (đặc tả T1.10). Mọi thao tác lên màn đi qua ``AppEnvironment/send(_:)``.
extension AppEnvironment {
    // MARK: - Dữ liệu đưa vào xếp hạng

    /// Các lệnh, tên tiếng Việt; tên tiếng Anh làm tên khác để tìm.
    nonisolated static func paletteCommands() -> [PaletteCommand] {
        typealias Key = String.LocalizationValue
        func command(_ id: PaletteCommandID, _ key: Key, _ en: String, _ keys: String?) -> PaletteCommand {
            PaletteCommand(id: id, title: String(localized: key), keywords: [en], shortcut: keys)
        }
        return [
            command(.clearAll, "Clear all", "clear all", "F1"),
            command(.clearText, "Clear text", "clear text", "F2"),
            command(.clearBackground, "Clear background", "clear background", "F3"),
            command(.toggleRehearsal, "Turn Rehearsal on or off", "rehearsal", "⌘R"),
            command(.toggleFreeze, "Turn Freeze on or off", "freeze", "⇧⌘F"),
            command(.liveMode, "Live mode", "live mode", "⌘1"),
            command(.editorMode, "Editor mode", "editor mode", "⌘2"),
            command(.newSong, "New song", "new song", "⌘N"),
            command(.importFiles, "Import files", "import files", "⌘I"),
            command(.openSettings, "Open Settings", "open settings", "⌘,"),
            command(.identifyScreens, "Show numbers on screens", "identify screens", nil),
        ]
    }

    /// Bản dịch dùng cho Bảng lệnh: bản mặc định trong cài đặt, không thì bản đầu tiên đã mở.
    var paletteTranslation: TranslationInfo? {
        if let preferred = settings.value.defaultTranslation,
            let info = translations.first(where: { $0.code == preferred })
        {
            return info
        }
        return translations.first
    }

    /// Bản dịch và chữ của vài câu đầu cho dòng địa chỉ đầy đủ.
    func paletteScriptureContext(for parse: ParseResult?) -> PaletteScriptureContext? {
        guard let info = paletteTranslation else { return nil }
        var preview: String?
        if case .reference(let reference)? = parse, let translation = bibleTranslation(info.code),
            let verses = try? translation.verses(reference)
        {
            preview = verses.prefix(3).map(\.text).joined(separator: " ")
        }
        return PaletteScriptureContext(
            translationCode: info.code, abbreviation: info.displayAbbreviation, previewText: preview)
    }

    /// Mục chiếu được của chương trình buổi nhóm đang mở.
    func palettePlanItems() -> [PaletteItem] {
        guard let plan = activePlan else { return [] }
        return plan.items.filter(\.isLiveable).map { item in
            let info = PlanItemInfo(item: item, environment: self)
            return PaletteItem(target: .planItem(id: item.id), title: info.title, subtitle: info.subtitle)
        }
    }

    /// Loại bộ trình chiếu của các kết quả tìm (bài hát hay bộ trình chiếu khác).
    func palettePresentationKinds(_ hits: [SearchHit]) -> [String: PresentationKind] {
        guard let library else { return [:] }
        var kinds: [String: PresentationKind] = [:]
        for hit in hits where hit.kind == .presentation {
            if let id = UUID(uuidString: hit.id), let presentation = library.presentations[id] {
                kinds[hit.id] = presentation.kind
            }
        }
        return kinds
    }

    // MARK: - Mở

    /// Mở Bảng lệnh (`⌘K` hoặc bấm ô tìm) và ghi lúc bấm để đo thời gian mở.
    func openCommandPalette() {
        guard !isCommandPalettePresented else { return }
        commandPaletteRequestedAt = .now
        isCommandPalettePresented = true
    }

    /// Làm ấm Bảng lệnh khi thư viện vừa mở: nạp bảng tên sách, chuỗi đã dịch của lệnh, bộ gộp dấu và chạy thử một
    /// lần xếp hạng, để lần `⌘K` đầu tiên sau khi khởi động không chậm hơn các lần sau (đo trên Mac: 60 ms so với
    /// trung vị 36 ms).
    func warmUpCommandPalette() {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let ranker = PaletteRanker()
            let commands = AppEnvironment.paletteCommands()
            for sample in ["", "gi 3 16", "gi", "123", "xoa chu"] {
                let parse = sample.isEmpty ? nil : ranker.parser.parse(sample)
                _ = ranker.rank(
                    query: sample, scriptureParse: parse, scripture: paletteScriptureContext(for: parse), hits: [],
                    commands: commands, planItems: [], recents: settings.value.paletteRecents,
                    commandUsage: settings.value.paletteCommandUsage)
            }
            _ = await library?.search("chua", kinds: [.presentation, .media])
        }
    }

    // MARK: - Thực hiện

    /// `Enter` (`secondary == false`) hoặc `⌘Enter` trên một dòng (bảng hành động của đặc tả T1.10).
    func performPalette(_ row: PaletteRow, secondary: Bool, host: PaletteHost) -> PaletteOutcome {
        if secondary && !row.target.hasSecondaryAction {
            return .unavailable
        }
        let outcome: PaletteOutcome
        switch row.target {
        case .bookCompletion(let text):
            return .fill(text)
        case .command(let id):
            runPaletteCommand(id, host: host)
            settings.value.paletteCommandUsage = PaletteHistory.counting(id, in: settings.value.paletteCommandUsage)
            return .close
        case .scripture(let translation, let reference):
            outcome = performScripture(translation: translation, reference: reference, secondary: secondary)
        case .presentation(let id):
            outcome = performPresentation(id, secondary: secondary)
        case .media(let id):
            outcome = performMedia(id, secondary: secondary)
        case .planItem(let id):
            outcome = performPlanItem(id, secondary: secondary)
        }
        if outcome == .close {
            host.setMode(.live)
            let title = row.detail.map { row.title + " " + $0 } ?? row.title
            let item = PaletteItem(target: row.target, title: title, subtitle: row.subtitle)
            settings.value.paletteRecents = PaletteHistory.recording(item, in: settings.value.paletteRecents)
        }
        return outcome
    }

    private func performScripture(translation: String?, reference: String, secondary: Bool) -> PaletteOutcome {
        guard let translation, show != nil else { return .unavailable }
        if secondary {
            appendToPlan(.scripture(PlanScriptureItem(reference: reference, translation: translation)))
            return .close
        }
        let source = LiveSource.scripture(translation: translation, reference: reference)
        guard let sequence = sequence(for: source), let first = SlideCards.firstEnabled(in: sequence) else {
            return .unavailable
        }
        send(.selectItem(source))
        send(.goLive(source, slideIndex: first))
        return .close
    }

    private func performPresentation(_ id: UUID, secondary: Bool) -> PaletteOutcome {
        guard library?.presentations[id] != nil, show != nil else { return .unavailable }
        if secondary {
            appendToPlan(.presentation(PlanPresentationItem(presentationID: id, arrangementID: nil)))
        } else {
            send(.selectItem(.presentation(id: id, arrangementID: nil)))
        }
        return .close
    }

    private func performMedia(_ id: MediaID, secondary: Bool) -> PaletteOutcome {
        guard let info = library?.media[id], show != nil else { return .unavailable }
        if secondary {
            let duration = info.duration.map { ($0 / 60).rounded(.up) * 60 }
            appendToPlan(.media(PlanMediaItem(mediaID: id, plannedDuration: duration)))
        } else {
            // Chuỗi trang của media là một trang nền: lên màn là thay nền đang chiếu.
            send(.goLive(.media(id), slideIndex: 0))
        }
        return .close
    }

    private func performPlanItem(_ id: UUID, secondary: Bool) -> PaletteOutcome {
        guard let plan = activePlan, let item = plan.items.first(where: { $0.id == id }) else { return .unavailable }
        guard secondary else {
            selectPlanItem(item)
            return .close
        }
        let source = LiveSource.planItem(planID: plan.id, itemID: id)
        guard let sequence = sequence(for: source), let first = SlideCards.firstEnabled(in: sequence) else {
            return .unavailable
        }
        selectPlanItem(item)
        send(.goLive(source, slideIndex: first))
        return .close
    }

    private func runPaletteCommand(_ id: PaletteCommandID, host: PaletteHost) {
        switch id {
        case .clearAll: send(.clearAll)
        case .clearText: send(.clearLayer(.slide))
        case .clearBackground: send(.clearLayer(.background))
        case .toggleRehearsal: send(.setRehearsal(!(show?.state.isRehearsal ?? false)))
        case .toggleFreeze: send(.setFreeze(!(show?.state.isFrozen ?? false)))
        case .liveMode: host.setMode(.live)
        case .editorMode: host.setMode(.editor)
        case .newSong:
            createSong()
            host.setMode(.editor)
        case .importFiles:
            host.setMode(.editor)
            // Hộp chọn tệp mở sau khi Bảng lệnh đã đóng.
            Task { @MainActor [weak self] in
                guard let self else { return }
                EditorImport.choose(self)
            }
        case .openSettings: host.openSettings()
        case .identifyScreens: outputs.identifyScreens()
        }
    }
}

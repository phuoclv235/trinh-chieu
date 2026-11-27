import AppKit
import CoreModel
import Importers
import LibraryStore
import Observation
import RenderEngine
import Scripture
import os

/// Chế độ của cửa sổ chính.
enum WorkspaceMode: String, CaseIterable, Sendable {
    case live
    case editor
}

/// Mọi thành phần sống suốt phiên chạy, tạo đúng thứ tự ở ``start()`` và truyền qua `environment`.
///
/// Thứ tự (đặc tả T1.7 mục 1): lõi dựng hình → thư viện → Kinh Thánh, nguồn nội dung, bộ dựng cảnh, nơi nhận cảnh,
/// lõi điều phối → nối thay đổi thư viện vào lõi điều phối → gắn đầu ra theo cài đặt.
@MainActor @Observable final class AppEnvironment {
    enum Phase: Equatable {
        case starting
        case ready
        /// Máy không có Metal: báo rồi thoát.
        case renderUnavailable(String)
        /// Thư mục thư viện trong cài đặt không còn (ổ ngoài rút ra).
        case libraryMissing(URL)
        /// Mở thư viện lỗi.
        case libraryFailed(URL, String)
    }

    private(set) var phase: Phase = .starting
    let settings: SettingsStore
    let outputs = OutputRouter()
    let warnings = WarningCenter()
    private(set) var frameHealth = FrameHealth()

    private(set) var engine: RenderEngine?
    private(set) var library: LibraryStore?
    private(set) var bible: BibleStore?
    private(set) var content: LibraryProvider?
    private(set) var show: ShowController?
    /// Bản dịch Kinh Thánh đã mở được, theo tên.
    private(set) var translations: [TranslationInfo] = []
    /// Bản dịch đã mở, theo mã viết thường.
    private(set) var openedTranslations: [String: BibleTranslation] = [:]
    /// Tăng mỗi khi thư viện báo nội dung đổi: giao diện đọc số này để dựng lại lưới trang của nguồn đang xem.
    private(set) var contentRevision = 0
    /// Bộ trình chiếu bạn bấm "Soạn" ở chế độ Trực tiếp; chế độ Soạn thảo mở bộ này (T1.9).
    var editingPresentationID: UUID?
    /// Ảnh thu nhỏ của thẻ trang chiếu.
    let thumbnails: SlideThumbnailCache
    /// Chương trình buổi nhóm đang mở ở chế độ Trực tiếp.
    let planEditing = PlanEditing()

    @ObservationIgnored private let mediaLocator: LibraryMediaLocator
    @ObservationIgnored private var sink: AppSceneSink?
    @ObservationIgnored private var clock: SystemShowClock?
    @ObservationIgnored private var statisticsTask: Task<Void, Never>?
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private let log = OSLogSink()
    @ObservationIgnored private let logger = Logger(subsystem: "app.trinhchieu.TrinhChieu", category: "App")

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        let locator = LibraryMediaLocator()
        mediaLocator = locator
        thumbnails = SlideThumbnailCache(mediaLocator: locator)
    }

    // MARK: - Khởi động

    /// Tạo lõi dựng hình rồi mở thư viện theo cài đặt. Gọi một lần khi cửa sổ chính xuất hiện.
    func start() async {
        guard phase == .starting, engine == nil, !Self.isRunningTests else { return }
        applyAppearance()
        do {
            let engine = try RenderEngine(mediaLocator: mediaLocator)
            engine.setAudioOutputDevice(settings.value.audioOutputDeviceID)
            self.engine = engine
            listen(to: engine)
        } catch {
            logger.fault("Không tạo được lõi dựng hình: \(String(describing: error), privacy: .public)")
            phase = .renderUnavailable(String(describing: error))
            return
        }
        let url = settings.value.libraryURL
        if settings.value.libraryPath != nil, !FileManager.default.fileExists(atPath: url.path) {
            phase = .libraryMissing(url)
            return
        }
        await openLibrary(at: url)
    }

    /// Mở (hoặc tạo) thư viện tại `url`, thay thư viện đang mở nếu có. Lưu đường dẫn vào cài đặt khi mở được.
    func openLibrary(at url: URL) async {
        guard let engine else { return }
        await closeLibrary()
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let store = try await LibraryStore.open(
                at: url, fileWatcher: FSEventsWatcher(), configuration: LibraryStoreConfiguration(log: log))
            let bible = BibleStore(directory: url.appendingPathComponent("bibles", isDirectory: true))
            let content = LibraryProvider(store: store, log: log)
            let sink = AppSceneSink(engine: engine)
            let clock = SystemShowClock()
            let show = ShowController(
                provider: content, sink: sink, resolver: SceneResolver(log: log), log: store, clock: clock,
                state: ShowState(settings: ShowSettings(advanceToNextItem: settings.value.advanceToNextItem)))
            content.startObserving { [weak self, weak show] change in
                self?.mediaLocator.update(from: self?.library)
                show?.send(.contentDidChange(ids: change.documentIDs))
                self?.contentRevision &+= 1
                self?.syncActivePlan()
            }
            library = store
            self.bible = bible
            self.content = content
            self.sink = sink
            self.clock = clock
            self.show = show
            mediaLocator.update(from: store)
            settings.value.libraryPath = url == AppSettings.defaultLibraryURL ? nil : url.path
            await loadTranslations()
            // Giao cảnh đầu tiên (nền đen của mẫu) để đầu ra vừa gắn có hình ngay.
            show.tick()
            phase = .ready
            outputs.start(engine: engine) { [weak self] in self?.settings.value.outputAssignments ?? [] }
            logger.info("Đã mở thư viện \(url.path, privacy: .private)")
        } catch {
            logger.error("Mở thư viện lỗi: \(String(describing: error), privacy: .public)")
            phase = .libraryFailed(url, (error as? LibraryStoreError)?.message ?? error.localizedDescription)
        }
    }

    /// Ghi nốt và đóng thư viện đang mở. Đầu ra vẫn gắn, giữ khung cuối cho tới cảnh kế tiếp.
    private func closeLibrary() async {
        guard let library else { return }
        content?.stopObserving()
        clock?.stopTicking()
        await library.close()
        self.library = nil
        content = nil
        show = nil
        sink = nil
        clock = nil
        bible = nil
        translations = []
        openedTranslations = [:]
        editingPresentationID = nil
        planEditing.reset()
        thumbnails.removeAll()
        mediaLocator.update(from: nil)
    }

    /// Đọc lại danh sách bản dịch Kinh Thánh và đăng ký các bản mở được cho nguồn nội dung.
    func loadTranslations() async {
        guard let bible, let content else { return }
        let infos = (try? await bible.translations()) ?? []
        var opened: [TranslationInfo] = []
        var byCode: [String: BibleTranslation] = [:]
        for info in infos {
            do {
                let translation = try await bible.open(info.code)
                content.register(translation)
                opened.append(translation.info)
                byCode[translation.info.code.lowercased()] = translation
            } catch {
                logger.error("Không mở được bản dịch \(info.code, privacy: .public): \(String(describing: error))")
            }
        }
        translations = opened
        openedTranslations = byCode
        let current = settings.value.defaultTranslation
        if !opened.contains(where: { $0.code == current }) {
            settings.value.defaultTranslation = opened.first?.code
        }
    }

    private func listen(to engine: RenderEngine) {
        let stream = engine.statistics
        statisticsTask = Task { [weak self] in
            for await statistics in stream {
                guard let self else { return }
                self.frameHealth.record(statistics)
                self.warnings.ingest(statistics.warnings)
            }
        }
    }

    /// Gói test chạy bên trong ứng dụng: không tạo thư viện hay đầu ra thật trên máy chạy test.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - Thao tác

    /// Gửi lệnh trình chiếu. Giao diện không gọi thẳng lõi dựng hình.
    @discardableResult func send(_ command: ShowCommand) -> CommandResult? {
        show?.send(command)
    }

    /// Đổi cài đặt "Hết trang thì sang mục kế".
    func setAdvanceToNextItem(_ enabled: Bool) {
        settings.value.advanceToNextItem = enabled
        show?.updateSettings(ShowSettings(advanceToNextItem: enabled))
    }

    /// Gán vai cho một màn rồi gắn lại đầu ra.
    func assign(_ role: OutputRole?, to display: DisplayDescriptor) {
        settings.value.assign(role, toDisplay: display.uuid, name: display.name)
        outputs.refresh()
        warnings.pruneDismissed(outputs: outputs)
    }

    func setAudioOutputDevice(_ uniqueID: String?) {
        settings.value.audioOutputDeviceID = uniqueID
        engine?.setAudioOutputDevice(uniqueID)
    }

    func setAppearance(_ appearance: AppearancePreference) {
        settings.value.appearance = appearance
        applyAppearance()
    }

    private func applyAppearance() {
        switch settings.value.appearance {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
    }

    /// Đầu ra chính đang gắn và đang có nội dung: thoát lúc này sẽ làm mất hình.
    var isShowingOnProgram: Bool {
        guard outputs.attached[.program] != nil, let scene = show?.lastProgramPublished else { return false }
        return scene.layers.contains { !$0.items.isEmpty }
    }

    /// Thư viện chưa có bộ trình chiếu và chương trình nào.
    var isLibraryEmpty: Bool {
        guard let library else { return false }
        return library.presentations.isEmpty && library.plans.isEmpty
    }

    /// Ghi mọi thứ xuống đĩa và dừng đầu ra (khi thoát).
    func shutdown() async {
        logger.info("Thoát Hệ thống: ghi thư viện và nhật ký buổi nhóm")
        await library?.flush()
        await closeLibrary()
        outputs.stop()
        statisticsTask?.cancel()
        engine?.shutdown()
    }

    // MARK: - Nhập

    /// Nhập tệp lời bài hát (văn bản, OpenLyrics) vào thư viện. Trả câu tóm tắt cho bạn.
    func importLyrics(from urls: [URL]) async -> String {
        guard let library else { return "" }
        let report = await ImportRegistry.standard.importFiles(at: urls)
        for presentation in report.presentations {
            library.save(presentation)
        }
        return report.summary
    }

    /// Nhập một bản dịch Kinh Thánh (OSIS, Zefania, USFM). Mã lấy từ tên tệp; giấy phép ghi "chỉ dùng nội bộ" cho tới
    /// khi bạn xác minh.
    func importBible(from urls: [URL]) async throws -> TranslationInfo {
        guard let bible, let first = urls.first else { throw ImportError.empty(filename: "") }
        let files = try urls.map { (data: try Data(contentsOf: $0), filename: $0.lastPathComponent) }
        let outcome = try BibleImportRegistry.standard.importBible(files: files)
        let code = Self.translationCode(from: first.deletingPathExtension().lastPathComponent)
        try await outcome.write(to: bible, code: code, license: BibleLicense.internalUseOnly)
        await loadTranslations()
        return translations.first { $0.code == code } ?? outcome.translationInfo(code: code, license: "")
    }

    /// "Bản Truyền Thống 1925.xml" → "ban-truyen-thong-1925".
    nonisolated static func translationCode(from filename: String) -> String {
        let folded = filename.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "vi"))
        let parts = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let code = parts.joined(separator: "-")
        return code.isEmpty ? "ban-dich" : String(code.prefix(40))
    }
}

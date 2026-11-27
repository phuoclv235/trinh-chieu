import CoreModel
import Foundation
import LibraryIndex
import Observation

/// Thư viện trên đĩa: nguồn sự thật duy nhất (`docs/dinh-dang-tep.md`).
///
/// Giữ toàn bộ tài liệu trong bộ nhớ để `ShowController` đọc đồng bộ trên luồng chính. Đọc, ghi, băm, nén chạy ngoài
/// luồng chính. Mỗi lần lưu cập nhật bộ nhớ và chỉ mục ngay, còn ghi đĩa hoãn 1 giây theo từng tài liệu; lần lưu mới
/// huỷ lần ghi hoãn trước của cùng tài liệu. Ghi luôn nguyên tử (`.tmp` rồi đổi tên).
@MainActor @Observable public final class LibraryStore {
    /// Thư mục gốc của thư viện.
    public let root: URL
    public internal(set) var info: LibraryInfo
    public internal(set) var presentations: [UUID: Presentation]
    public internal(set) var themes: [UUID: Theme]
    public internal(set) var plans: [UUID: ServicePlan]
    public internal(set) var media: [MediaID: MediaAssetInfo]
    /// Tệp hỏng, tệp từ phiên bản mới hơn, xung đột đồng bộ, lỗi ghi. Hiện trên giao diện.
    public internal(set) var loadProblems: [LoadProblem]
    /// `true` khi chỉ mục đang được dựng hoặc đồng bộ ở nền; tìm kiếm vẫn chạy, kết quả có thể chưa đủ.
    public internal(set) var isIndexing = false

    @ObservationIgnored let layout: LibraryLayout
    @ObservationIgnored let configuration: LibraryStoreConfiguration
    @ObservationIgnored let index: LibraryIndex
    @ObservationIgnored let gate = WriteGate()
    @ObservationIgnored let fileWatcher: any FileWatching

    /// Tài liệu có thay đổi chưa ghi xuống đĩa.
    @ObservationIgnored var dirty: Set<DocumentKey> = []
    /// Lần ghi đang hoãn, theo tài liệu.
    @ObservationIgnored var pendingWrites: [DocumentKey: Task<Void, Never>] = [:]
    /// Lần ghi đang chạy ngoài luồng chính, chờ trong `flush()`.
    @ObservationIgnored var inFlightWrites: [UUID: Task<Void, Never>] = [:]
    /// Số lần ghi đang chạy theo đường dẫn.
    @ObservationIgnored var inFlightPaths: [String: Int] = [:]
    /// Dấu vân tay nội dung trên đĩa mà Hệ thống biết (đọc lúc mở hoặc tự ghi).
    @ObservationIgnored var fingerprints: [String: FileFingerprint]
    /// Vài lần ghi gần nhất theo đường dẫn: sự kiện theo dõi đến trễ của chính các lần ghi này không bị coi là
    /// thay đổi ngoài Hệ thống.
    @ObservationIgnored var recentWrites: [String: [FileFingerprint]] = [:]
    @ObservationIgnored var continuations: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]
    /// Chuỗi việc cập nhật chỉ mục, chạy tuần tự theo thứ tự gửi.
    @ObservationIgnored var indexChain: Task<Void, Never>?
    @ObservationIgnored var watchTask: Task<Void, Never>?
    @ObservationIgnored var processedFileEvents = 0
    @ObservationIgnored var fileEventWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    @ObservationIgnored var serviceLog: ServiceLogState?
    @ObservationIgnored var serviceLogTask: Task<Void, Never>?

    private init(
        layout: LibraryLayout, snapshot: LibraryLoader.Snapshot, index: LibraryIndex, fileWatcher: any FileWatching,
        configuration: LibraryStoreConfiguration
    ) {
        self.root = layout.root
        self.layout = layout
        self.configuration = configuration
        self.index = index
        self.fileWatcher = fileWatcher
        self.info = snapshot.info
        self.presentations = snapshot.presentations
        self.themes = snapshot.themes
        self.plans = snapshot.plans
        self.media = snapshot.media
        self.loadProblems = snapshot.problems
        self.fingerprints = snapshot.fingerprints
    }

    /// Mở thư viện tại `root`; thư mục trống thì tạo cấu trúc mới với mẫu tạo sẵn.
    ///
    /// Tệp lỗi đưa vào ``loadProblems``, không chặn việc mở. Chỉ mục được đối chiếu và cập nhật ở nền
    /// (``isIndexing``); tìm kiếm dùng được ngay và đủ dần.
    public static func open(
        at root: URL, fileWatcher: any FileWatching, configuration: LibraryStoreConfiguration = .init()
    ) async throws -> LibraryStore {
        let layout = LibraryLayout(root: root)
        let snapshot = try await Task.detached {
            try await LibraryLoader.load(layout, configuration: configuration)
        }
        .value
        let index = try await Task.detached {
            try LibraryIndex(databaseURL: layout.url(LibraryLayout.indexPath))
        }
        .value
        let store = LibraryStore(
            layout: layout, snapshot: snapshot, index: index, fileWatcher: fileWatcher, configuration: configuration)
        store.startIndexSynchronization()
        store.startWatching()
        return store
    }

    // MARK: - Lưu

    /// Lưu bộ trình chiếu: cập nhật bộ nhớ và chỉ mục ngay, đặt `modifiedAt` là bây giờ, ghi đĩa sau 1 giây.
    public func save(_ presentation: Presentation) {
        var presentation = presentation
        presentation.modifiedAt = configuration.now().wholeSeconds
        presentation.createdAt = presentation.createdAt.wholeSeconds
        presentations[presentation.id] = presentation
        didChange(DocumentKey(.presentation, presentation.id), entry: IndexEntries.entry(for: presentation))
    }

    /// Lưu mẫu trình bày: cập nhật bộ nhớ và chỉ mục ngay, ghi đĩa sau 1 giây.
    public func save(_ theme: Theme) {
        themes[theme.id] = theme
        didChange(DocumentKey(.theme, theme.id), entry: IndexEntries.entry(for: theme))
    }

    /// Lưu chương trình buổi nhóm: cập nhật bộ nhớ và chỉ mục ngay, ghi đĩa sau 1 giây.
    public func save(_ plan: ServicePlan) {
        plans[plan.id] = plan
        didChange(DocumentKey(.plan, plan.id), entry: IndexEntries.entry(for: plan))
    }

    private func didChange(_ key: DocumentKey, entry: IndexEntry) {
        scheduleWrite(key)
        enqueueIndex { try await $0.upsert([entry]) }
        emit(LibraryChange(reason: .saved, documentIDs: [key.id]))
    }

    /// Ghi ngay mọi thay đổi đang hoãn (tài liệu và nhật ký buổi nhóm) và chờ ghi xong. Gọi khi thoát ứng dụng.
    public func flush() async {
        for task in pendingWrites.values {
            task.cancel()
        }
        pendingWrites.removeAll()
        for key in dirty.sorted(by: { $0.relativePath < $1.relativePath }) {
            writeNow(key)
        }
        writeServiceLogNow()
        while let (id, task) = inFlightWrites.first {
            await task.value
            inFlightWrites[id] = nil
        }
    }

    /// Ghi mọi thứ, ngừng theo dõi thư mục, chờ chỉ mục xong và đóng các luồng ``changes``.
    public func close() async {
        await flush()
        watchTask?.cancel()
        watchTask = nil
        serviceLogTask?.cancel()
        serviceLogTask = nil
        await waitForIndexing()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    // MARK: - Thay đổi và vấn đề

    /// Mỗi lần đọc trả một luồng mới nhận mọi thay đổi từ lúc đó (cho `ShowController.contentDidChange` và
    /// giao diện). Luồng kết thúc khi ``close()``.
    public var changes: AsyncStream<LibraryChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: LibraryChange.self)
        let key = UUID()
        continuations[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.continuations[key] = nil
            }
        }
        return stream
    }

    func emit(_ change: LibraryChange) {
        for continuation in continuations.values {
            continuation.yield(change)
        }
    }

    /// Bỏ một vấn đề khỏi danh sách sau khi bạn đã xem.
    public func dismissProblem(_ id: LoadProblem.ID) {
        loadProblems.removeAll { $0.id == id }
    }

    func report(_ problem: LoadProblem) {
        loadProblems.append(problem)
        configuration.log.log(.warning, problem.message, category: "LibraryStore")
    }

    func clearProblems(at path: String, kinds: Set<LoadProblem.Kind>) {
        loadProblems.removeAll { $0.relativePath == path && kinds.contains($0.kind) }
    }

    // MARK: - Ghi đĩa

    func scheduleWrite(_ key: DocumentKey) {
        dirty.insert(key)
        pendingWrites[key]?.cancel()
        let delay = configuration.writeDelay
        pendingWrites[key] = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.writeNow(key)
        }
    }

    /// Mã hoá bản trong bộ nhớ và ghi ngoài luồng chính. Không còn trong bộ nhớ (đã xoá) thì bỏ.
    func writeNow(_ key: DocumentKey) {
        pendingWrites[key]?.cancel()
        pendingWrites[key] = nil
        guard dirty.remove(key) != nil else { return }
        let data: Data
        do {
            guard let encoded = try encodeDocument(key) else { return }
            data = encoded
        } catch {
            reportWriteFailure(key.relativePath, error: error)
            return
        }
        writeData(data, to: key.relativePath) { [weak self] in
            _ = self?.dirty.insert(key)
        }
    }

    func encodeDocument(_ key: DocumentKey) throws -> Data? {
        switch key.kind {
        case .presentation:
            return try presentations[key.id].map { try DocumentCoding.encode($0) }
        case .theme:
            return try themes[key.id].map { try DocumentCoding.encode($0) }
        case .plan:
            return try plans[key.id].map { try DocumentCoding.encode($0) }
        }
    }

    /// Ghi `data` vào `path` ngoài luồng chính, theo thứ tự thế hệ của ``WriteGate``.
    /// `onFailure` chạy trên luồng chính khi ghi lỗi (ví dụ đánh dấu lại tài liệu chưa ghi).
    func writeData(_ data: Data, to path: String, onFailure: @escaping @MainActor () -> Void = {}) {
        let generation = gate.reserve(path)
        remember(FileFingerprint(data), at: path)
        inFlightPaths[path, default: 0] += 1
        let url = layout.url(path)
        let gate = self.gate
        let writer = Task.detached { () -> (any Error)? in
            do {
                _ = try gate.perform(path, generation: generation) {
                    try AtomicFile.write(data, to: url)
                }
                return nil
            } catch {
                return error
            }
        }
        let id = UUID()
        inFlightWrites[id] = Task { [weak self] in
            let failure = await writer.value
            guard let self else { return }
            self.inFlightWrites[id] = nil
            self.inFlightPaths[path, default: 1] -= 1
            if self.inFlightPaths[path] == 0 {
                self.inFlightPaths[path] = nil
            }
            if let failure {
                self.reportWriteFailure(path, error: failure)
                onFailure()
            } else {
                self.clearProblems(at: path, kinds: [.writeFailed])
            }
        }
    }

    /// Ghi ngay và chờ ghi xong; lỗi thì ném ra. Dùng cho media và gói mang đi.
    func writeDataNow(_ data: Data, to path: String) async throws {
        let generation = gate.reserve(path)
        remember(FileFingerprint(data), at: path)
        let url = layout.url(path)
        let gate = self.gate
        try await Task.detached {
            _ = try gate.perform(path, generation: generation) {
                try AtomicFile.write(data, to: url)
            }
        }
        .value
    }

    /// Ghi nhận nội dung Hệ thống vừa ghi xuống `path`.
    func remember(_ fingerprint: FileFingerprint, at path: String) {
        fingerprints[path] = fingerprint
        var recent = recentWrites[path] ?? []
        recent.append(fingerprint)
        recentWrites[path] = Array(recent.suffix(4))
    }

    func reportWriteFailure(_ path: String, error: any Error) {
        clearProblems(at: path, kinds: [.writeFailed])
        let message = LibraryStoreError.writeFailed(path: path, reason: String(describing: error)).message
        report(LoadProblem(kind: .writeFailed, relativePath: path, message: message, occurredAt: configuration.now()))
    }

    /// Tài liệu theo mã, bất kể loại.
    func documentKind(of id: UUID) -> LibraryDocumentKind? {
        if presentations[id] != nil {
            return .presentation
        }
        if themes[id] != nil {
            return .theme
        }
        if plans[id] != nil {
            return .plan
        }
        return nil
    }
}

/// Khoá một tài liệu: loại và mã.
struct DocumentKey: Hashable, Sendable {
    var kind: LibraryDocumentKind
    var id: UUID

    init(_ kind: LibraryDocumentKind, _ id: UUID) {
        self.kind = kind
        self.id = id
    }

    var relativePath: String {
        LibraryLayout.documentPath(kind, id)
    }
}

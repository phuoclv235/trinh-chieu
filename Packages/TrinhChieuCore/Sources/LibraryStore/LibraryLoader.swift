import CoreModel
import Foundation

/// Đọc toàn bộ thư mục thư viện ngoài luồng chính (quy tắc 1 của T1.3).
enum LibraryLoader {
    struct Snapshot: Sendable {
        var info: LibraryInfo
        var presentations: [UUID: Presentation] = [:]
        var themes: [UUID: Theme] = [:]
        var plans: [UUID: ServicePlan] = [:]
        var media: [MediaID: MediaAssetInfo] = [:]
        var fingerprints: [String: FileFingerprint] = [:]
        var problems: [LoadProblem] = []
    }

    private enum Outcome: Sendable {
        case presentation(Presentation, String, FileFingerprint)
        case theme(Theme, String, FileFingerprint)
        case plan(ServicePlan, String, FileFingerprint)
        case media(MediaAssetInfo, String, FileFingerprint)
        case problem(LoadProblem)
    }

    private struct Job: Sendable {
        enum Target: Sendable {
            case document(LibraryDocumentKind, UUID)
            case media(MediaID)
        }

        var target: Target
        var relativePath: String
    }

    static func load(_ layout: LibraryLayout, configuration: LibraryStoreConfiguration) async throws -> Snapshot {
        let manager = FileManager.default
        for directory in layout.requiredDirectories {
            try manager.createDirectory(at: layout.url(directory), withIntermediateDirectories: true)
        }
        removeTemporaryFiles(layout)
        purgeTrash(layout, configuration: configuration)

        let now = configuration.now()
        var problems: [LoadProblem] = []
        let jobs = makeJobs(layout, problems: &problems, now: now)

        var snapshot = Snapshot(info: LibraryInfo(createdAt: now.wholeSeconds))
        snapshot.problems = problems
        let outcomes = await withTaskGroup(of: Outcome.self, returning: [Outcome].self) { group in
            for job in jobs {
                group.addTask { loadJob(job, layout: layout, configuration: configuration) }
            }
            var collected: [Outcome] = []
            collected.reserveCapacity(jobs.count)
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }
        for outcome in outcomes {
            switch outcome {
            case .presentation(let value, let path, let fingerprint):
                snapshot.presentations[value.id] = value
                snapshot.fingerprints[path] = fingerprint
            case .theme(let value, let path, let fingerprint):
                snapshot.themes[value.id] = value
                snapshot.fingerprints[path] = fingerprint
            case .plan(let value, let path, let fingerprint):
                snapshot.plans[value.id] = value
                snapshot.fingerprints[path] = fingerprint
            case .media(let value, let path, let fingerprint):
                snapshot.media[value.id] = value
                snapshot.fingerprints[path] = fingerprint
            case .problem(let problem):
                snapshot.problems.append(problem)
            }
        }
        try loadLibraryInfo(into: &snapshot, layout: layout, configuration: configuration)
        snapshot.problems.sort { $0.relativePath < $1.relativePath }
        return snapshot
    }

    // MARK: - Từng tệp

    private static func makeJobs(_ layout: LibraryLayout, problems: inout [LoadProblem], now: Date) -> [Job] {
        var jobs: [Job] = []
        for kind in LibraryDocumentKind.allCases {
            for name in fileNames(in: layout.url(kind.directoryName)) {
                let path = "\(kind.directoryName)/\(name)"
                if let id = LibraryLayout.documentID(fileName: name) {
                    jobs.append(Job(target: .document(kind, id), relativePath: path))
                } else if name.contains(".conflict-"), name.hasSuffix(".json") {
                    problems.append(conflictProblem(relativePath: path, now: now))
                }
            }
        }
        for name in fileNames(in: layout.url(LibraryLayout.mediaDirectory)) {
            if let id = LibraryLayout.mediaID(infoFileName: name) {
                jobs.append(Job(target: .media(id), relativePath: "\(LibraryLayout.mediaDirectory)/\(name)"))
            }
        }
        return jobs
    }

    static func conflictProblem(relativePath: String, now: Date) -> LoadProblem {
        let message =
            "Tệp \(relativePath) là bản trên đĩa bị đổi ngoài Hệ thống khi bạn còn thay đổi chưa ghi. "
            + "Hệ thống giữ bản của bạn; mở tệp này nếu cần lấy lại nội dung."
        return LoadProblem(kind: .syncConflict, relativePath: relativePath, message: message, occurredAt: now)
    }

    private static func loadJob(_ job: Job, layout: LibraryLayout, configuration: LibraryStoreConfiguration)
        -> Outcome
    {
        let now = configuration.now()
        let path = job.relativePath
        do {
            switch job.target {
            case .document(let kind, let id):
                switch kind {
                case .presentation:
                    let loaded = try readDocument(Presentation.self, path, kind, layout, configuration)
                    guard loaded.value.id == id else { return idMismatch(path, now: now) }
                    return .presentation(loaded.value, path, loaded.fingerprint)
                case .theme:
                    let loaded = try readDocument(Theme.self, path, kind, layout, configuration)
                    guard loaded.value.id == id else { return idMismatch(path, now: now) }
                    return .theme(loaded.value, path, loaded.fingerprint)
                case .plan:
                    let loaded = try readDocument(ServicePlan.self, path, kind, layout, configuration)
                    guard loaded.value.id == id else { return idMismatch(path, now: now) }
                    return .plan(loaded.value, path, loaded.fingerprint)
                }
            case .media(let id):
                let loaded = try readFile(MediaAssetInfo.self, path, .media, layout, configuration)
                guard loaded.value.id == id else { return idMismatch(path, now: now) }
                return .media(loaded.value, path, loaded.fingerprint)
            }
        } catch {
            return .problem(DocumentDecoding.problem(for: error, relativePath: path, at: now))
        }
    }

    private static func readDocument<Value: VersionedDocument>(
        _ type: Value.Type, _ path: String, _ kind: LibraryDocumentKind, _ layout: LibraryLayout,
        _ configuration: LibraryStoreConfiguration
    ) throws -> (value: Value, fingerprint: FileFingerprint) {
        try readFile(type, path, kind.documentKind, layout, configuration)
    }

    /// Đọc, chuyển đổi nếu cần (ghi `.bak` trước khi ghi đè), giải mã.
    static func readFile<Value: VersionedDocument>(
        _ type: Value.Type, _ path: String, _ kind: DocumentKind, _ layout: LibraryLayout,
        _ configuration: LibraryStoreConfiguration
    ) throws -> (value: Value, fingerprint: FileFingerprint) {
        let url = layout.url(path)
        let data = try Data(contentsOf: url)
        let decoded = try DocumentDecoding.decode(type, from: data, kind: kind, migrate: configuration.migrate)
        guard decoded.migratedFrom != nil else {
            return (decoded.value, FileFingerprint(data))
        }
        try writeBackup(of: data, for: url, now: configuration.now())
        try AtomicFile.write(decoded.data, to: url)
        configuration.log.log(.info, "Đã chuyển đổi \(path) lên định dạng hiện tại", category: "LibraryStore")
        return (decoded.value, FileFingerprint(decoded.data))
    }

    /// Bản sao tệp cũ trước khi chuyển đổi: `<tên>.bak`; nếu đã có thì `<tên>.<thời điểm>.bak`.
    static func writeBackup(of data: Data, for url: URL, now: Date) throws {
        let directory = url.deletingLastPathComponent()
        var backup = directory.appendingPathComponent(url.lastPathComponent + ".bak")
        if FileManager.default.fileExists(atPath: backup.path) {
            let stamp = FileTimestamp.string(from: now)
            backup = directory.appendingPathComponent(url.lastPathComponent + ".\(stamp).bak")
        }
        try AtomicFile.write(data, to: backup)
    }

    private static func idMismatch(_ path: String, now: Date) -> Outcome {
        let message = "Tệp \(path) có mã bên trong không khớp tên tệp nên Hệ thống bỏ qua."
        return .problem(LoadProblem(kind: .idMismatch, relativePath: path, message: message, occurredAt: now))
    }

    // MARK: - library.json

    private static func loadLibraryInfo(
        into snapshot: inout Snapshot, layout: LibraryLayout, configuration: LibraryStoreConfiguration
    ) throws {
        let path = LibraryLayout.libraryFileName
        let now = configuration.now()
        if FileManager.default.fileExists(atPath: layout.url(path).path) {
            do {
                snapshot.info = try readFile(LibraryInfo.self, path, .library, layout, configuration).value
                return
            } catch {
                // Không ghi đè library.json hỏng: dùng thông tin tạm trong bộ nhớ, báo để bạn xử lý.
                snapshot.problems.append(DocumentDecoding.problem(for: error, relativePath: path, at: now))
                snapshot.info = LibraryInfo(createdAt: now.wholeSeconds)
                return
            }
        }
        // Thư viện mới (hoặc mất library.json): tạo thông tin, thêm mẫu tạo sẵn nếu chưa có mẫu nào.
        var info = LibraryInfo(createdAt: now.wholeSeconds)
        if snapshot.themes.isEmpty {
            let themes = configuration.makeInitialThemes()
            for theme in themes {
                let themePath = LibraryLayout.documentPath(.theme, theme.id)
                let data = try DocumentCoding.encode(theme)
                try AtomicFile.write(data, to: layout.url(themePath))
                snapshot.themes[theme.id] = theme
                snapshot.fingerprints[themePath] = FileFingerprint(data)
            }
            info.defaultThemeID = themes.first?.id
            let scripture = themes.first { $0.id == DefaultThemes.scriptureID }
            info.defaultScriptureThemeID = scripture?.id ?? themes.first?.id
        }
        let data = try DocumentCoding.encode(info)
        try AtomicFile.write(data, to: layout.url(path))
        snapshot.info = info
    }

    // MARK: - Dọn dẹp

    static func fileNames(in directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    /// Xoá tệp `.tmp` còn sót do lần ghi bị ngắt; tệp gốc chưa bị đụng tới nên vẫn nguyên vẹn.
    private static func removeTemporaryFiles(_ layout: LibraryLayout) {
        let others = [LibraryLayout.mediaDirectory, LibraryLayout.logsDirectory, LibraryLayout.trashDirectory]
        let directories = [""] + LibraryDocumentKind.allCases.map(\.directoryName) + others
        for directory in directories {
            let url = directory.isEmpty ? layout.root : layout.url(directory)
            for name in fileNames(in: url) where name.hasSuffix(".tmp") {
                try? FileManager.default.removeItem(at: url.appendingPathComponent(name))
            }
        }
    }

    /// Xoá hẳn tệp trong `.trash/` cũ hơn thời gian giữ (mặc định 30 ngày).
    private static func purgeTrash(_ layout: LibraryLayout, configuration: LibraryStoreConfiguration) {
        let directory = layout.url(LibraryLayout.trashDirectory)
        let cutoff = configuration.now().addingTimeInterval(-configuration.trashRetention)
        for name in fileNames(in: directory) {
            let url = directory.appendingPathComponent(name)
            let deletedAt = TrashNaming.deletedAt(fileName: name) ?? modificationDate(of: url)
            if let deletedAt, deletedAt < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}

/// Tên tệp trong thùng rác: `<uuid>.<thời điểm>.json`, thêm `-<n>` sau thời điểm nếu trùng.
enum TrashNaming {
    static func fileName(id: UUID, deletedAt: Date, attempt: Int) -> String {
        let stamp = FileTimestamp.string(from: deletedAt)
        return attempt == 0 ? "\(id.uuidString).\(stamp).json" : "\(id.uuidString).\(stamp)-\(attempt).json"
    }

    static func deletedAt(fileName: String) -> Date? {
        let parts = fileName.split(separator: ".")
        guard parts.count == 3, parts[2] == "json", UUID(uuidString: String(parts[0])) != nil else { return nil }
        let stamp = parts[1].split(separator: "-").first.map(String.init) ?? ""
        return FileTimestamp.date(from: stamp)
    }
}

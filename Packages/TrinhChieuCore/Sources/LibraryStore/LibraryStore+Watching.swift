import CoreModel
import Foundation

/// Tệp trong thư viện mà việc theo dõi thay đổi quan tâm.
enum WatchedFile: Hashable, Sendable {
    case document(DocumentKey)
    case mediaInfo(MediaID)
    /// Thư mục cần quét lại: một loại tài liệu, hoặc `nil` là thư mục media.
    case directory(LibraryDocumentKind?)
}

extension LibraryStore {
    func startWatching() {
        let stream = fileWatcher.changes(in: root)
        watchTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
                self.processedFileEvents += 1
                self.resumeFileEventWaiters()
            }
        }
    }

    /// Chờ tới khi đã xử lý xong `count` sự kiện từ lúc mở thư viện. Dùng cho test.
    func waitForFileEvents(count: Int) async {
        guard processedFileEvents < count else { return }
        await withCheckedContinuation { continuation in
            fileEventWaiters.append((count, continuation))
        }
    }

    private func resumeFileEventWaiters() {
        let ready = fileEventWaiters.filter { $0.count <= processedFileEvents }
        fileEventWaiters.removeAll { $0.count <= processedFileEvents }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }

    // MARK: - Xử lý sự kiện

    func handle(_ event: FileChangeEvent) async {
        var targets: [WatchedFile] = []
        if event.rescanAll {
            targets = LibraryDocumentKind.allCases.map { WatchedFile.directory($0) } + [WatchedFile.directory(nil)]
        } else {
            for url in event.urls {
                if let target = classify(url), !targets.contains(target) {
                    targets.append(target)
                }
            }
        }
        for target in targets {
            switch target {
            case .document(let key):
                await refreshDocument(key)
            case .mediaInfo(let id):
                await refreshMediaInfo(id)
            case .directory(let kind):
                await rescan(kind)
            }
        }
    }

    /// Phân loại đường dẫn theo cấu trúc thư viện. Tệp tạm, `.bak`, `.conflict-`, thùng rác, bộ đệm: bỏ qua.
    func classify(_ url: URL) -> WatchedFile? {
        let rootComponents = Self.pathComponents(root)
        let components = Self.pathComponents(url)
        guard components.count > rootComponents.count, Array(components.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        let relative = Array(components.dropFirst(rootComponents.count))
        let directory = relative[0]
        let kind = LibraryDocumentKind.allCases.first { $0.directoryName == directory }
        guard kind != nil || directory == LibraryLayout.mediaDirectory else { return nil }
        guard relative.count == 2 else {
            return relative.count == 1 ? .directory(kind) : nil
        }
        if let kind {
            return LibraryLayout.documentID(fileName: relative[1]).map { .document(DocumentKey(kind, $0)) }
        }
        return LibraryLayout.mediaID(infoFileName: relative[1]).map { .mediaInfo($0) }
    }

    /// Thành phần đường dẫn sau khi giải liên kết mềm (trên Mac `/var` là `/private/var`). Giải ở thư mục cha vì
    /// tệp vừa bị xoá không còn để giải.
    private static func pathComponents(_ url: URL) -> [String] {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(standardized.lastPathComponent).pathComponents
    }

    /// Đọc tệp ngoài luồng chính; `nil` nếu tệp không còn.
    private func readData(_ path: String) async -> Data? {
        let url = layout.url(path)
        return await Task.detached { try? Data(contentsOf: url) }.value
    }

    /// Một tệp tài liệu đổi trên đĩa (quy tắc 4 của T1.3).
    ///
    /// - Nội dung trùng bản Hệ thống biết (do chính Hệ thống ghi) hoặc trùng bản trong bộ nhớ: bỏ qua.
    /// - Tài liệu không có thay đổi chưa ghi: nạp lại, cập nhật chỉ mục, phát ``LibraryChange``.
    /// - Tài liệu đang có thay đổi chưa ghi: giữ bản trong bộ nhớ, ghi bản đĩa thành
    ///   `<uuid>.conflict-<thời điểm>.json`, báo trong ``loadProblems``, rồi ghi lại bản trong bộ nhớ.
    func refreshDocument(_ key: DocumentKey) async {
        let path = key.relativePath
        guard let data = await readData(path) else {
            documentRemovedExternally(key)
            return
        }
        let fingerprint = FileFingerprint(data)
        guard !isKnownContent(fingerprint, at: path) else { return }
        let now = configuration.now()
        var changed = false
        do {
            switch key.kind {
            case .presentation:
                let decoded = try decode(Presentation.self, data, kind: key.kind)
                guard decoded.id == key.id else { return }
                if presentations[key.id] != decoded {
                    guard !hasUnsavedChanges(key) else { return keepConflict(key, data: data, now: now) }
                    presentations[key.id] = decoded
                    indexUpsert([IndexEntries.entry(for: decoded)])
                    changed = true
                }
            case .theme:
                let decoded = try decode(Theme.self, data, kind: key.kind)
                guard decoded.id == key.id else { return }
                if themes[key.id] != decoded {
                    guard !hasUnsavedChanges(key) else { return keepConflict(key, data: data, now: now) }
                    themes[key.id] = decoded
                    indexUpsert([IndexEntries.entry(for: decoded)])
                    changed = true
                }
            case .plan:
                let decoded = try decode(ServicePlan.self, data, kind: key.kind)
                guard decoded.id == key.id else { return }
                if plans[key.id] != decoded {
                    guard !hasUnsavedChanges(key) else { return keepConflict(key, data: data, now: now) }
                    plans[key.id] = decoded
                    indexUpsert([IndexEntries.entry(for: decoded)])
                    changed = true
                }
            }
        } catch {
            clearProblems(at: path, kinds: [.unreadable, .newerSchema])
            report(DocumentDecoding.problem(for: error, relativePath: path, at: now))
            return
        }
        fingerprints[path] = fingerprint
        clearProblems(at: path, kinds: [.unreadable, .newerSchema])
        if changed {
            emit(LibraryChange(reason: .reloaded, documentIDs: [key.id]))
        }
    }

    /// Nội dung trùng bản Hệ thống đã đọc hoặc vừa tự ghi.
    func isKnownContent(_ fingerprint: FileFingerprint, at path: String) -> Bool {
        fingerprints[path] == fingerprint || recentWrites[path]?.contains(fingerprint) == true
    }

    private func decode<Value: VersionedDocument>(_ type: Value.Type, _ data: Data, kind: LibraryDocumentKind) throws
        -> Value
    {
        try DocumentDecoding.decode(type, from: data, kind: kind.documentKind, migrate: configuration.migrate).value
    }

    func hasUnsavedChanges(_ key: DocumentKey) -> Bool {
        dirty.contains(key) || inFlightPaths[key.relativePath] != nil
    }

    private func keepConflict(_ key: DocumentKey, data: Data, now: Date) {
        let directory = key.kind.directoryName
        var name = "\(key.id.uuidString).conflict-\(FileTimestamp.string(from: now)).json"
        var attempt = 1
        while FileManager.default.fileExists(atPath: layout.url("\(directory)/\(name)").path) {
            name = "\(key.id.uuidString).conflict-\(FileTimestamp.string(from: now))-\(attempt).json"
            attempt += 1
        }
        let conflictPath = "\(directory)/\(name)"
        do {
            try AtomicFile.write(data, to: layout.url(conflictPath))
        } catch {
            reportWriteFailure(conflictPath, error: error)
        }
        report(LibraryLoader.conflictProblem(relativePath: conflictPath, now: now))
        // Bản trong bộ nhớ thắng: ghi lại để thay bản đĩa vừa bị đổi.
        scheduleWrite(key)
    }

    private func documentRemovedExternally(_ key: DocumentKey) {
        let path = key.relativePath
        guard fingerprints[path] != nil || documentKind(of: key.id) != nil else { return }
        fingerprints[path] = nil
        if hasUnsavedChanges(key) {
            // Còn thay đổi chưa ghi: giữ bản trong bộ nhớ, ghi lại tệp.
            scheduleWrite(key)
            return
        }
        switch key.kind {
        case .presentation:
            presentations[key.id] = nil
        case .theme:
            themes[key.id] = nil
        case .plan:
            plans[key.id] = nil
        }
        indexRemove([key.id.uuidString])
        emit(LibraryChange(reason: .removedExternally, documentIDs: [key.id]))
    }

    func refreshMediaInfo(_ id: MediaID) async {
        let path = LibraryLayout.mediaInfoPath(id)
        guard let data = await readData(path) else {
            guard media[id] != nil else { return }
            media[id] = nil
            fingerprints[path] = nil
            indexRemove([id.rawValue])
            emit(LibraryChange(reason: .removedExternally, mediaIDs: [id]))
            return
        }
        let fingerprint = FileFingerprint(data)
        guard !isKnownContent(fingerprint, at: path) else { return }
        let now = configuration.now()
        do {
            let decoded = try DocumentDecoding.decode(
                MediaAssetInfo.self, from: data, kind: .media, migrate: configuration.migrate
            )
            .value
            guard decoded.id == id else { return }
            fingerprints[path] = fingerprint
            clearProblems(at: path, kinds: [.unreadable, .newerSchema])
            guard media[id] != decoded else { return }
            media[id] = decoded
            indexUpsert([IndexEntries.entry(for: decoded)])
            emit(LibraryChange(reason: .reloaded, mediaIDs: [id]))
        } catch {
            clearProblems(at: path, kinds: [.unreadable, .newerSchema])
            report(DocumentDecoding.problem(for: error, relativePath: path, at: now))
        }
    }

    /// Quét lại một thư mục: mọi tệp có trên đĩa, cộng mọi tài liệu trong bộ nhớ mà tệp đã mất.
    func rescan(_ kind: LibraryDocumentKind?) async {
        if let kind {
            let directory = layout.url(kind.directoryName)
            let names = await Task.detached { LibraryLoader.fileNames(in: directory) }.value
            var ids = Set(names.compactMap(LibraryLayout.documentID(fileName:)))
            switch kind {
            case .presentation:
                ids.formUnion(presentations.keys)
            case .theme:
                ids.formUnion(themes.keys)
            case .plan:
                ids.formUnion(plans.keys)
            }
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                await refreshDocument(DocumentKey(kind, id))
            }
        } else {
            let directory = layout.url(LibraryLayout.mediaDirectory)
            let names = await Task.detached { LibraryLoader.fileNames(in: directory) }.value
            var ids = Set(names.compactMap(LibraryLayout.mediaID(infoFileName:)))
            ids.formUnion(media.keys)
            for id in ids.sorted() {
                await refreshMediaInfo(id)
            }
        }
    }
}

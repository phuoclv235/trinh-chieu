import CoreModel
import Foundation

extension LibraryStore {
    /// Chuyển tài liệu vào thùng rác (`.trash/<uuid>.<thời điểm>.json`), kể cả thay đổi chưa ghi.
    ///
    /// Mã không có trong thư viện thì bỏ qua. Xoá bộ trình chiếu đang nằm trong chương trình vẫn xoá; mục trong
    /// chương trình hiện "Không tìm thấy" (chương trình không bị sửa). Lỗi giữa chừng thì hoàn lại các tài liệu đã
    /// chuyển và ném lỗi.
    public func moveToTrash(_ ids: [UUID]) throws -> TrashTicket {
        var entries: [TrashTicket.Entry] = []
        do {
            for id in ids {
                guard let kind = documentKind(of: id), !entries.contains(where: { $0.id == id }) else { continue }
                entries.append(try trashDocument(DocumentKey(kind, id)))
            }
        } catch {
            if !entries.isEmpty {
                try? restore(TrashTicket(entries: entries))
            }
            throw error
        }
        guard !entries.isEmpty else { return TrashTicket(entries: []) }
        indexRemove(entries.map(\.id.uuidString))
        emit(LibraryChange(reason: .removed, documentIDs: Set(entries.map(\.id))))
        return TrashTicket(entries: entries)
    }

    private func trashDocument(_ key: DocumentKey) throws -> TrashTicket.Entry {
        guard let data = try encodeDocument(key) else { throw LibraryStoreError.documentNotFound(key.id) }
        let deletedAt = configuration.now()
        let path = key.relativePath
        let trashDirectory = layout.url(LibraryLayout.trashDirectory)
        var attempt = 0
        var name = TrashNaming.fileName(id: key.id, deletedAt: deletedAt, attempt: attempt)
        while FileManager.default.fileExists(atPath: trashDirectory.appendingPathComponent(name).path) {
            attempt += 1
            name = TrashNaming.fileName(id: key.id, deletedAt: deletedAt, attempt: attempt)
        }
        let trashURL = trashDirectory.appendingPathComponent(name)
        let url = layout.url(path)
        // Khoá ghi: lần ghi đang chờ của tài liệu này bị làm cũ, không dựng lại tệp vừa xoá.
        try gate.invalidate(path) {
            try AtomicFile.write(data, to: trashURL)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        pendingWrites[key]?.cancel()
        pendingWrites[key] = nil
        dirty.remove(key)
        fingerprints[path] = nil
        switch key.kind {
        case .presentation:
            presentations[key.id] = nil
        case .theme:
            themes[key.id] = nil
        case .plan:
            plans[key.id] = nil
        }
        return TrashTicket.Entry(id: key.id, kind: key.kind, trashFileName: name, deletedAt: deletedAt)
    }

    /// Hoàn tác xoá: đưa tài liệu trong phiếu về chỗ cũ và vào lại bộ nhớ, chỉ mục.
    ///
    /// Ném ``LibraryStoreError/trashItemMissing(_:)`` nếu tệp đã bị dọn khỏi thùng rác,
    /// ``LibraryStoreError/restoreConflict(_:)`` nếu thư viện đã có tài liệu cùng mã. Các tài liệu khác trong phiếu
    /// vẫn được khôi phục.
    public func restore(_ ticket: TrashTicket) throws {
        var restored: Set<UUID> = []
        var firstError: (any Error)?
        for entry in ticket.entries {
            do {
                try restoreEntry(entry)
                restored.insert(entry.id)
            } catch {
                firstError = firstError ?? error
            }
        }
        if !restored.isEmpty {
            emit(LibraryChange(reason: .restored, documentIDs: restored))
        }
        if let firstError {
            throw firstError
        }
    }

    private func restoreEntry(_ entry: TrashTicket.Entry) throws {
        guard documentKind(of: entry.id) == nil else { throw LibraryStoreError.restoreConflict(entry.id) }
        let key = DocumentKey(entry.kind, entry.id)
        let path = key.relativePath
        let url = layout.url(path)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryStoreError.restoreConflict(entry.id)
        }
        let trashURL = layout.url(LibraryLayout.trashDirectory).appendingPathComponent(entry.trashFileName)
        guard let data = try? Data(contentsOf: trashURL) else { throw LibraryStoreError.trashItemMissing(entry.id) }
        let kind = entry.kind.documentKind
        let migrate = configuration.migrate
        switch entry.kind {
        case .presentation:
            let decoded = try DocumentDecoding.decode(Presentation.self, from: data, kind: kind, migrate: migrate)
            try moveBack(trashURL, decoded.data, to: url, path: path)
            presentations[entry.id] = decoded.value
            indexUpsert([IndexEntries.entry(for: decoded.value)])
        case .theme:
            let decoded = try DocumentDecoding.decode(Theme.self, from: data, kind: kind, migrate: migrate)
            try moveBack(trashURL, decoded.data, to: url, path: path)
            themes[entry.id] = decoded.value
            indexUpsert([IndexEntries.entry(for: decoded.value)])
        case .plan:
            let decoded = try DocumentDecoding.decode(ServicePlan.self, from: data, kind: kind, migrate: migrate)
            try moveBack(trashURL, decoded.data, to: url, path: path)
            plans[entry.id] = decoded.value
            indexUpsert([IndexEntries.entry(for: decoded.value)])
        }
    }

    private func moveBack(_ trashURL: URL, _ data: Data, to url: URL, path: String) throws {
        try gate.invalidate(path) {
            try AtomicFile.write(data, to: url)
            try? FileManager.default.removeItem(at: trashURL)
        }
        remember(FileFingerprint(data), at: path)
    }
}

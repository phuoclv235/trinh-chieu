import CoreModel
import Foundation
import LibraryIndex

/// Dựng mục chỉ mục từ tài liệu (quy tắc 3 của T1.3).
enum IndexEntries {
    /// Bộ trình chiếu: thân là toàn bộ chữ các trang; phụ đề bắt đầu bằng số thánh ca (để gõ số ra đúng bài),
    /// sau đó là tác giả.
    static func entry(for presentation: Presentation) -> IndexEntry {
        var subtitleParts: [String] = []
        if let number = presentation.song?.number?.trimmingCharacters(in: .whitespaces), !number.isEmpty {
            subtitleParts.append(number)
        }
        let authors = presentation.song?.authors.filter { !$0.isEmpty } ?? []
        if !authors.isEmpty {
            subtitleParts.append(authors.joined(separator: ", "))
        }
        var lines: [String] = []
        for group in presentation.groups {
            for slide in group.slides {
                for element in slide.elements {
                    if case .text(let text) = element, !text.text.isEmpty {
                        lines.append(text.text)
                    }
                }
            }
        }
        return IndexEntry(
            id: presentation.id.uuidString, kind: .presentation, title: presentation.title,
            subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
            body: lines.isEmpty ? nil : lines.joined(separator: "\n"),
            path: LibraryLayout.documentPath(.presentation, presentation.id), modifiedAt: presentation.modifiedAt)
    }

    static func entry(for theme: Theme) -> IndexEntry {
        IndexEntry(
            id: theme.id.uuidString, kind: .theme, title: theme.name,
            path: LibraryLayout.documentPath(.theme, theme.id))
    }

    static func entry(for plan: ServicePlan) -> IndexEntry {
        IndexEntry(
            id: plan.id.uuidString, kind: .plan, title: plan.title, subtitle: plan.date,
            path: LibraryLayout.documentPath(.plan, plan.id))
    }

    static func entry(for media: MediaAssetInfo) -> IndexEntry {
        IndexEntry(
            id: media.id.rawValue, kind: .media, title: media.originalName,
            body: media.tags.isEmpty ? nil : media.tags.joined(separator: " "),
            path: LibraryLayout.mediaInfoPath(media.id))
    }
}

extension LibraryStore {
    /// Số mục ghi vào chỉ mục mỗi lần khi dựng ở nền, để tìm kiếm chen vào giữa và ra kết quả dần.
    static let indexBatchSize = 250

    /// Tìm trong thư viện, có dấu hay không dấu đều được. Lỗi chỉ mục thì ghi log và trả rỗng.
    public func search(_ query: String, kinds: Set<IndexKind>) async -> [SearchHit] {
        do {
            return try await index.search(query, kinds: kinds)
        } catch {
            configuration.log.log(.error, "Tìm kiếm lỗi: \(error)", category: "LibraryStore")
            return []
        }
    }

    /// Chờ mọi việc cập nhật chỉ mục đã gửi chạy xong.
    public func waitForIndexing() async {
        while let chain = indexChain {
            await chain.value
            if indexChain == chain {
                indexChain = nil
            }
        }
    }

    /// Gửi một việc cập nhật chỉ mục; các việc chạy tuần tự theo thứ tự gửi.
    func enqueueIndex(_ operation: @escaping @Sendable (LibraryIndex) async throws -> Void) {
        let previous = indexChain
        let index = self.index
        let log = configuration.log
        indexChain = Task {
            await previous?.value
            do {
                try await operation(index)
            } catch {
                log.log(.error, "Cập nhật chỉ mục lỗi: \(error)", category: "LibraryStore")
            }
        }
    }

    func indexUpsert(_ entries: [IndexEntry]) {
        guard !entries.isEmpty else { return }
        enqueueIndex { try await $0.upsert(entries) }
    }

    func indexRemove(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        enqueueIndex { try await $0.remove(ids: ids) }
    }

    /// Đối chiếu chỉ mục với thư viện vừa mở: bộ trình chiếu so `modifiedAt`, chỉ ghi phần chênh; mẫu, chương
    /// trình, media (ít) ghi lại toàn bộ; mục không còn tệp thì xoá. Chỉ mục trống thì đây là dựng toàn bộ.
    func startIndexSynchronization() {
        let presentations = Array(presentations.values)
        let others =
            themes.values.map(IndexEntries.entry(for:)) + plans.values.map(IndexEntries.entry(for:))
            + media.values.map(IndexEntries.entry(for:))
        let batchSize = Self.indexBatchSize
        isIndexing = true
        enqueueIndex { index in
            let stored = try await index.modificationStamps(kind: .presentation)
            var changed: [IndexEntry] = []
            var current = Set<String>()
            for presentation in presentations {
                let id = presentation.id.uuidString
                current.insert(id)
                if stored[id] != LibraryIndex.modificationStamp(presentation.modifiedAt) {
                    changed.append(IndexEntries.entry(for: presentation))
                }
            }
            var stale = stored.keys.filter { !current.contains($0) }
            for kind in [IndexKind.theme, .plan, .media] {
                let ids = Set(others.filter { $0.kind == kind }.map(\.id))
                stale += try await index.modificationStamps(kind: kind).keys.filter { !ids.contains($0) }
            }
            try await index.remove(ids: stale)
            try await index.upsert(others)
            var start = 0
            while start < changed.count {
                let end = min(start + batchSize, changed.count)
                try await index.upsert(Array(changed[start..<end]))
                start = end
            }
        }
        // Tắt cờ ngay trong chuỗi việc chỉ mục, để `waitForIndexing()` trả về thì `isIndexing` đã là `false`
        // (trước đây cờ tắt trong một Task riêng, chạy đua với `waitForIndexing()`).
        let chain = indexChain
        indexChain = Task { [weak self] in
            await chain?.value
            self?.isIndexing = false
        }
    }
}

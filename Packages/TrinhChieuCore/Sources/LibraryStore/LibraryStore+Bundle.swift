import CoreModel
import Foundation

extension LibraryStore {
    /// Tài liệu và media một gói cần chứa.
    private struct BundleSelection {
        var plans: [ServicePlan] = []
        var presentations: [Presentation] = []
        var themes: [Theme] = []
        var media: [MediaAssetInfo] = []
        var translations: Set<String> = []
    }

    // MARK: - Xuất

    /// Xuất gói mang đi cho một chương trình: chương trình, mọi bộ trình chiếu nó dùng, mọi mẫu trình bày và media
    /// được tham chiếu. Không gói bản dịch Kinh Thánh (chỉ ghi mã bản dịch vào `manifest.json`).
    public func exportBundle(planID: UUID, to destination: URL) async throws {
        guard let plan = plans[planID] else { throw LibraryStoreError.documentNotFound(planID) }
        var presentationIDs: [UUID] = []
        var themeIDs: [UUID] = []
        var mediaIDs: [MediaID] = []
        var translations: Set<String> = []
        for item in plan.items {
            switch item {
            case .presentation(let entry):
                presentationIDs.append(entry.presentationID)
                themeIDs.append(contentsOf: entry.themeID.map { [$0] } ?? [])
            case .scripture(let entry):
                translations.insert(entry.translation)
                themeIDs.append(contentsOf: entry.themeID.map { [$0] } ?? [])
            case .media(let entry):
                mediaIDs.append(entry.mediaID)
            case .header, .note:
                break
            }
        }
        var selection = collect(presentationIDs: presentationIDs, themeIDs: themeIDs, mediaIDs: mediaIDs)
        selection.plans = [plan]
        selection.translations = translations
        try await writeBundle(selection, kind: .plan, rootIDs: [planID], to: destination)
    }

    /// Xuất gói mang đi cho các bộ trình chiếu, kèm mẫu trình bày và media chúng dùng.
    public func exportBundle(presentationIDs: [UUID], to destination: URL) async throws {
        for id in presentationIDs where presentations[id] == nil {
            throw LibraryStoreError.documentNotFound(id)
        }
        let selection = collect(presentationIDs: presentationIDs, themeIDs: [], mediaIDs: [])
        try await writeBundle(selection, kind: .presentation, rootIDs: presentationIDs, to: destination)
    }

    /// Gom bộ trình chiếu, mẫu và media được tham chiếu. Mã không còn trong thư viện thì bỏ qua (mục chương trình
    /// tương ứng hiện "Không tìm thấy" ở máy nhận như ở máy này).
    private func collect(presentationIDs: [UUID], themeIDs: [UUID], mediaIDs: [MediaID]) -> BundleSelection {
        var selection = BundleSelection()
        var seenPresentations: Set<UUID> = []
        var themeOrder: [UUID] = themeIDs
        var mediaOrder: [MediaID] = mediaIDs
        for id in presentationIDs where seenPresentations.insert(id).inserted {
            guard let presentation = presentations[id] else { continue }
            selection.presentations.append(presentation)
            themeOrder.append(contentsOf: presentation.themeID.map { [$0] } ?? [])
            mediaOrder.append(contentsOf: Self.mediaReferences(in: presentation))
        }
        var seenThemes: Set<UUID> = []
        for id in themeOrder where seenThemes.insert(id).inserted {
            guard let theme = themes[id] else { continue }
            selection.themes.append(theme)
            mediaOrder.append(contentsOf: theme.background.mediaID.map { [$0] } ?? [])
        }
        var seenMedia: Set<MediaID> = []
        for id in mediaOrder where seenMedia.insert(id).inserted {
            if let info = media[id] {
                selection.media.append(info)
            }
        }
        return selection
    }

    /// Mọi media một bộ trình chiếu dùng: nền trang, ảnh, video.
    static func mediaReferences(in presentation: Presentation) -> [MediaID] {
        var ids: [MediaID] = []
        for group in presentation.groups {
            for slide in group.slides {
                if let id = slide.background.mediaID, slide.background.kind == .media {
                    ids.append(id)
                }
                for element in slide.elements {
                    switch element {
                    case .image(let image):
                        ids.append(image.mediaID)
                    case .video(let video):
                        ids.append(video.mediaID)
                    case .text, .shape:
                        break
                    }
                }
            }
        }
        return ids
    }

    private func writeBundle(
        _ selection: BundleSelection, kind: PortableBundleKind, rootIDs: [UUID], to destination: URL
    ) async throws {
        var documents: [String: Data] = [:]
        for plan in selection.plans {
            documents[LibraryLayout.documentPath(.plan, plan.id)] = try DocumentCoding.encode(plan)
        }
        for presentation in selection.presentations {
            let path = LibraryLayout.documentPath(.presentation, presentation.id)
            documents[path] = try DocumentCoding.encode(presentation)
        }
        for theme in selection.themes {
            documents[LibraryLayout.documentPath(.theme, theme.id)] = try DocumentCoding.encode(theme)
        }
        var mediaFiles: [PortableBundleArchive.MediaFile] = []
        for info in selection.media {
            if info.origin.kind == .copied {
                let path = LibraryLayout.mediaFilePath(info.id, fileExtension: info.fileExtension)
                guard mediaFileExists(info) else { throw LibraryStoreError.mediaFileMissing(info.id) }
                mediaFiles.append(PortableBundleArchive.MediaFile(path: path, source: layout.url(path)))
            }
            documents[LibraryLayout.mediaInfoPath(info.id)] = try DocumentCoding.encode(info)
        }
        let manifest = PortableBundleManifest(
            kind: kind, createdAt: configuration.now().wholeSeconds, rootIDs: rootIDs,
            files: (Array(documents.keys) + mediaFiles.map(\.path)).sorted(),
            bibleTranslations: selection.translations.sorted())
        try await Task.detached {
            try PortableBundleArchive.write(
                manifest: manifest, documents: documents, mediaFiles: mediaFiles, to: destination)
        }
        .value
    }

    // MARK: - Mở

    /// Liệt kê nội dung gói và đối chiếu với thư viện: tài liệu trùng mã khác nội dung (cần chọn cách xử lý),
    /// trùng mã giống hệt (bỏ qua), media đã có, bản dịch Kinh Thánh còn thiếu.
    public func inspectBundle(at url: URL) async throws -> BundleInspection {
        let contents = try await readBundle(at: url)
        return inspection(of: contents)
    }

    private func readBundle(at url: URL) async throws -> PortableBundleArchive.Contents {
        let migrate = configuration.migrate
        return try await Task.detached { try PortableBundleArchive.read(from: url, migrate: migrate) }.value
    }

    private func inspection(of contents: PortableBundleArchive.Contents) -> BundleInspection {
        var conflicts: [BundleConflict] = []
        var unchanged: Set<UUID> = []
        func compare(_ id: UUID, kind: LibraryDocumentKind, same: Bool?, bundleTitle: String, libraryTitle: String?) {
            guard let same, let libraryTitle else { return }
            if same {
                unchanged.insert(id)
            } else {
                conflicts.append(
                    BundleConflict(id: id, kind: kind, bundleTitle: bundleTitle, libraryTitle: libraryTitle))
            }
        }
        for plan in contents.plans {
            let existing = plans[plan.id]
            compare(
                plan.id, kind: .plan, same: existing.map { $0 == plan }, bundleTitle: plan.title,
                libraryTitle: existing?.title)
        }
        for presentation in contents.presentations {
            let existing = presentations[presentation.id]
            compare(
                presentation.id, kind: .presentation, same: existing.map { $0 == presentation },
                bundleTitle: presentation.title, libraryTitle: existing?.title)
        }
        for theme in contents.themes {
            let existing = themes[theme.id]
            compare(
                theme.id, kind: .theme, same: existing.map { $0 == theme }, bundleTitle: theme.name,
                libraryTitle: existing?.name)
        }
        let existingMedia = Set(contents.media.map(\.id).filter { id in media[id].map { mediaIsUsable($0) } ?? false })
        let missing = contents.manifest.bibleTranslations.filter { code in
            !LibraryLayout.isValidTranslationCode(code)
                || !FileManager.default.fileExists(atPath: layout.url(LibraryLayout.biblePath(translation: code)).path)
        }
        return BundleInspection(
            manifest: contents.manifest, plans: contents.plans, presentations: contents.presentations,
            themes: contents.themes, media: contents.media, conflicts: conflicts, unchangedIDs: unchanged,
            existingMediaIDs: existingMedia, missingTranslations: missing)
    }

    private func mediaIsUsable(_ info: MediaAssetInfo) -> Bool {
        info.origin.kind == .linked || mediaFileExists(info)
    }

    /// Nhập gói vào thư viện. Media đã có (cùng SHA-256) bị bỏ qua; tài liệu trùng mã giống hệt bị bỏ qua; tài liệu
    /// trùng mã khác nội dung làm theo `resolutions` (thiếu thì ném ``LibraryStoreError/unresolvedConflicts(_:)``,
    /// chưa nhập gì).
    ///
    /// "Giữ cả hai" cấp mã mới cho bản trong gói và sửa mọi tham chiếu tới nó trong gói (chương trình trỏ tới bộ
    /// trình chiếu, bộ trình chiếu trỏ tới mẫu). "Thay bản trong thư viện" chuyển bản cũ vào thùng rác trước.
    public func importBundle(at url: URL, resolutions: [UUID: ConflictResolution]) async throws {
        let contents = try await readBundle(at: url)
        let inspection = inspection(of: contents)
        let unresolved = inspection.conflicts.map(\.id).filter { resolutions[$0] == nil }
        guard unresolved.isEmpty else { throw LibraryStoreError.unresolvedConflicts(unresolved) }

        var remap: [UUID: UUID] = [:]
        var replaced: [UUID] = []
        for conflict in inspection.conflicts {
            switch resolutions[conflict.id] {
            case .keepBoth:
                remap[conflict.id] = UUID()
            case .replace:
                replaced.append(conflict.id)
            case .skip, nil:
                break
            }
        }
        let skipped = inspection.unchangedIDs.union(
            inspection.conflicts.filter { resolutions[$0.id] == .skip }.map(\.id))

        try await importBundleMedia(contents, existing: inspection.existingMediaIDs, bundleURL: url)
        if !replaced.isEmpty {
            _ = try moveToTrash(replaced)
        }

        let copySuffix = " (bản sao)"
        var imported: Set<UUID> = []
        for var theme in contents.themes where !skipped.contains(theme.id) {
            if let newID = remap[theme.id] {
                theme.id = newID
                theme.name += copySuffix
            }
            try await importDocument(DocumentKey(.theme, theme.id), data: DocumentCoding.encode(theme))
            themes[theme.id] = theme
            indexUpsert([IndexEntries.entry(for: theme)])
            imported.insert(theme.id)
        }
        for var presentation in contents.presentations where !skipped.contains(presentation.id) {
            if let newID = remap[presentation.id] {
                presentation.id = newID
                presentation.title += copySuffix
            }
            if let themeID = presentation.themeID, let newID = remap[themeID] {
                presentation.themeID = newID
            }
            let key = DocumentKey(.presentation, presentation.id)
            try await importDocument(key, data: DocumentCoding.encode(presentation))
            presentations[presentation.id] = presentation
            indexUpsert([IndexEntries.entry(for: presentation)])
            imported.insert(presentation.id)
        }
        for var plan in contents.plans where !skipped.contains(plan.id) {
            if let newID = remap[plan.id] {
                plan.id = newID
                plan.title += copySuffix
            }
            plan.items = plan.items.map { Self.remapReferences(in: $0, using: remap) }
            try await importDocument(DocumentKey(.plan, plan.id), data: DocumentCoding.encode(plan))
            plans[plan.id] = plan
            indexUpsert([IndexEntries.entry(for: plan)])
            imported.insert(plan.id)
        }
        if !imported.isEmpty {
            emit(LibraryChange(reason: .imported, documentIDs: imported))
        }
    }

    private func importDocument(_ key: DocumentKey, data: Data) async throws {
        pendingWrites[key]?.cancel()
        pendingWrites[key] = nil
        dirty.remove(key)
        try await writeDataNow(data, to: key.relativePath)
    }

    private func importBundleMedia(
        _ contents: PortableBundleArchive.Contents, existing: Set<MediaID>, bundleURL: URL
    ) async throws {
        for info in contents.media where !existing.contains(info.id) {
            if info.origin.kind == .copied, let entryPath = contents.mediaEntries[info.id] {
                let destination = layout.url(LibraryLayout.mediaFilePath(info.id, fileExtension: info.fileExtension))
                let temporary = layout.url(LibraryLayout.mediaDirectory)
                    .appendingPathComponent(".import-\(UUID().uuidString).tmp")
                let id = info.id
                try await Task.detached {
                    try PortableBundleArchive.extractMedia(id, path: entryPath, from: bundleURL, to: temporary)
                    try AtomicFile.rename(temporary, to: destination)
                }
                .value
            }
            try await addMediaInfo(info)
        }
    }

    private static func remapReferences(in item: ServicePlanItem, using remap: [UUID: UUID]) -> ServicePlanItem {
        switch item {
        case .presentation(var entry):
            entry.presentationID = remap[entry.presentationID] ?? entry.presentationID
            entry.themeID = entry.themeID.map { remap[$0] ?? $0 }
            return .presentation(entry)
        case .scripture(var entry):
            entry.themeID = entry.themeID.map { remap[$0] ?? $0 }
            return .scripture(entry)
        case .header, .media, .note:
            return item
        }
    }
}

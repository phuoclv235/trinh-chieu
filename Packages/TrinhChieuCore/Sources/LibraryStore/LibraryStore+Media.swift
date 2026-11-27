import CoreModel
import Foundation

extension MediaKind {
    /// Loại media theo phần mở rộng (chữ thường). `nil` là loại Hệ thống chưa nhận.
    init?(fileExtension: String) {
        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp":
            self = .image
        case "mp4", "mov", "m4v":
            self = .video
        case "mp3", "m4a", "aac", "wav", "aif", "aiff":
            self = .audio
        default:
            return nil
        }
    }
}

extension LibraryStore {
    /// Nhập một tệp media: băm SHA-256 theo luồng trong lúc chép vào `media/<12 ký tự hex đầu>.<đuôi viết thường>`,
    /// ghi `media/<mã>.json`. Nội dung đã có trong thư viện thì trả bản có sẵn, không chép lần hai.
    ///
    /// Kích thước điểm ảnh, thời lượng, ảnh thu nhỏ do `MediaImport` (phía Mac) điền sau.
    public func importMedia(from url: URL) async throws -> MediaAssetInfo {
        let fileExtension = url.pathExtension.lowercased()
        guard LibraryLayout.isValidFileExtension(fileExtension), let kind = MediaKind(fileExtension: fileExtension)
        else {
            throw LibraryStoreError.unsupportedMediaType(fileExtension)
        }
        let mediaDirectory = layout.url(LibraryLayout.mediaDirectory)
        let temporary = mediaDirectory.appendingPathComponent(".import-\(UUID().uuidString).tmp")
        let digest = try await Task.detached { () throws -> (hex: String, byteCount: Int) in
            do {
                return try MediaHasher.sha256(of: url, copyingTo: temporary)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }
        .value
        let id = MediaID(String(digest.hex.prefix(12)))
        if let existing = media[id], existing.origin.kind == .linked || mediaFileExists(existing) {
            try? FileManager.default.removeItem(at: temporary)
            return existing
        }
        let destination = layout.url(LibraryLayout.mediaFilePath(id, fileExtension: fileExtension))
        do {
            try AtomicFile.rename(temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let info = MediaAssetInfo(
            id: id, kind: kind, originalName: url.lastPathComponent, fileExtension: fileExtension,
            byteCount: digest.byteCount, importedAt: configuration.now().wholeSeconds, origin: .copied)
        try await addMediaInfo(info)
        return info
    }

    /// Cập nhật thông tin một media đã có (kích thước điểm ảnh, thời lượng do `MediaProbe` đọc được, thẻ). Không đổi
    /// được mã, loại, đuôi tệp hay nguồn: các trường đó giữ như bản trong thư viện.
    public func updateMediaInfo(_ info: MediaAssetInfo) async throws {
        guard let existing = media[info.id] else { throw LibraryStoreError.mediaNotFound(info.id) }
        var updated = info
        updated.kind = existing.kind
        updated.fileExtension = existing.fileExtension
        updated.origin = existing.origin
        updated.importedAt = existing.importedAt
        guard updated != existing else { return }
        try await addMediaInfo(updated)
    }

    /// Ghi `media/<mã>.json`, cập nhật bộ nhớ, chỉ mục và phát thay đổi.
    func addMediaInfo(_ info: MediaAssetInfo) async throws {
        try await writeDataNow(try DocumentCoding.encode(info), to: LibraryLayout.mediaInfoPath(info.id))
        media[info.id] = info
        indexUpsert([IndexEntries.entry(for: info)])
        emit(LibraryChange(reason: .mediaAdded, mediaIDs: [info.id]))
    }

    /// Đường dẫn tệp để phát media. Media chép: `media/<mã>.<đuôi>`; media liên kết: bản tải về trong
    /// `.cache/media/`. `nil` là media không có trong thư viện hoặc tệp không còn trên đĩa.
    public func mediaURL(_ id: MediaID) -> URL? {
        guard let info = media[id] else { return nil }
        let url = layout.url(Self.storedPath(of: info))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Đường dẫn tương đối của tệp nội dung media.
    static func storedPath(of info: MediaAssetInfo) -> String {
        switch info.origin.kind {
        case .copied:
            return LibraryLayout.mediaFilePath(info.id, fileExtension: info.fileExtension)
        case .linked:
            return LibraryLayout.cachedMediaPath(info.id, fileExtension: info.fileExtension)
        }
    }

    func mediaFileExists(_ info: MediaAssetInfo) -> Bool {
        FileManager.default.fileExists(atPath: layout.url(Self.storedPath(of: info)).path)
    }
}

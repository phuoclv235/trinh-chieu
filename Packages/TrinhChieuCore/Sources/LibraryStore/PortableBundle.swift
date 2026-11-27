import CoreModel
import Foundation
import ZIPFoundation

/// Đọc ghi tệp ZIP của gói mang đi (`.tcbundle`, `docs/dinh-dang-tep.md` mục 7). Chạy ngoài luồng chính.
enum PortableBundleArchive {
    static let manifestPath = "manifest.json"
    /// Giới hạn kích thước một tệp JSON trong gói, chặn gói hỏng hoặc gói độc giải nén ra quá lớn.
    static let maxDocumentSize: UInt64 = 64 << 20

    /// Tệp media đưa vào gói.
    struct MediaFile: Sendable {
        var path: String
        var source: URL
    }

    /// Ghi gói vào `destination` (qua tệp tạm rồi đổi tên, đè tệp cũ nếu có).
    static func write(
        manifest: PortableBundleManifest, documents: [String: Data], mediaFiles: [MediaFile], to destination: URL
    ) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try writeArchive(manifest: manifest, documents: documents, mediaFiles: mediaFiles, to: temporary)
            try AtomicFile.rename(temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Ghi tệp ZIP; `Archive` được giải phóng (đóng tệp, đẩy hết dữ liệu xuống đĩa) khi hàm trả về.
    private static func writeArchive(
        manifest: PortableBundleManifest, documents: [String: Data], mediaFiles: [MediaFile], to url: URL
    ) throws {
        let archive = try Archive(url: url, accessMode: .create)
        try addData(DocumentCoding.encode(manifest), path: manifestPath, to: archive)
        for path in documents.keys.sorted() {
            if let data = documents[path] {
                try addData(data, path: path, to: archive)
            }
        }
        for file in mediaFiles.sorted(by: { $0.path < $1.path }) {
            // Media đã nén sẵn (JPEG, H.264): lưu nguyên, không nén lại.
            try archive.addEntry(with: file.path, fileURL: file.source, compressionMethod: .none)
        }
    }

    private static func addData(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(
            with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            return data.subdata(in: start..<min(start + size, data.count))
        }
    }

    /// Nội dung đọc từ gói, chưa đối chiếu với thư viện.
    struct Contents: Sendable {
        var manifest: PortableBundleManifest
        var plans: [ServicePlan] = []
        var presentations: [Presentation] = []
        var themes: [Theme] = []
        var media: [MediaAssetInfo] = []
        /// Đường dẫn tệp nội dung media trong gói, theo mã.
        var mediaEntries: [MediaID: String] = [:]
    }

    /// Đọc `manifest.json` và mọi tài liệu gói liệt kê. Chỉ đọc đường dẫn đúng cấu trúc thư viện; tệp ngoài cấu
    /// trúc bị bỏ qua, nên gói không thể ghi ra ngoài thư viện.
    static func read(
        from url: URL, migrate: @Sendable (Data, DocumentKind) throws -> (Data, migratedFrom: Int?)
    ) throws -> Contents {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw LibraryStoreError.invalidBundle("không mở được tệp ZIP.")
        }
        guard let manifestEntry = archive[manifestPath] else {
            throw LibraryStoreError.invalidBundle("thiếu manifest.json.")
        }
        let manifestData = try readEntry(manifestEntry, in: archive)
        let manifest: PortableBundleManifest
        do {
            manifest = try DocumentDecoding.decode(
                PortableBundleManifest.self, from: manifestData, kind: .library, migrate: migrate
            )
            .value
        } catch DocumentError.newerSchema(let found, let supported) {
            throw LibraryStoreError.newerBundle(found: found, supported: supported)
        } catch {
            throw LibraryStoreError.invalidBundle("manifest.json không đọc được.")
        }
        var contents = Contents(manifest: manifest)
        for path in Set(manifest.files).sorted() {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { continue }
            let (directory, name) = (parts[0], parts[1])
            if let kind = LibraryDocumentKind.allCases.first(where: { $0.directoryName == directory }) {
                guard let id = LibraryLayout.documentID(fileName: name) else { continue }
                let data = try readListedEntry(path, in: archive)
                do {
                    switch kind {
                    case .presentation:
                        let value = try decode(Presentation.self, data, kind, migrate)
                        guard value.id == id else { throw LibraryStoreError.invalidBundle("\(path) sai mã.") }
                        contents.presentations.append(value)
                    case .theme:
                        let value = try decode(Theme.self, data, kind, migrate)
                        guard value.id == id else { throw LibraryStoreError.invalidBundle("\(path) sai mã.") }
                        contents.themes.append(value)
                    case .plan:
                        let value = try decode(ServicePlan.self, data, kind, migrate)
                        guard value.id == id else { throw LibraryStoreError.invalidBundle("\(path) sai mã.") }
                        contents.plans.append(value)
                    }
                } catch let error as LibraryStoreError {
                    throw error
                } catch {
                    throw LibraryStoreError.invalidBundle("\(path): \(error)")
                }
            } else if directory == LibraryLayout.mediaDirectory {
                if let id = LibraryLayout.mediaID(infoFileName: name) {
                    let data = try readListedEntry(path, in: archive)
                    let info: MediaAssetInfo
                    do {
                        info = try DocumentDecoding.decode(
                            MediaAssetInfo.self, from: data, kind: .media, migrate: migrate
                        )
                        .value
                    } catch {
                        throw LibraryStoreError.invalidBundle("\(path): \(error)")
                    }
                    guard info.id == id, LibraryLayout.isValidFileExtension(info.fileExtension) else {
                        throw LibraryStoreError.invalidBundle("\(path) sai mã hoặc phần mở rộng.")
                    }
                    contents.media.append(info)
                } else {
                    let pieces = name.split(separator: ".").map(String.init)
                    if pieces.count == 2, LibraryLayout.isValidMediaID(pieces[0]) {
                        contents.mediaEntries[MediaID(pieces[0])] = path
                    }
                }
            }
        }
        for info in contents.media where info.origin.kind == .copied {
            let expected = LibraryLayout.mediaFilePath(info.id, fileExtension: info.fileExtension)
            guard contents.mediaEntries[info.id] == expected, archive[expected] != nil else {
                throw LibraryStoreError.invalidBundle("thiếu tệp media \(expected).")
            }
        }
        contents.plans.sort { $0.id.uuidString < $1.id.uuidString }
        contents.presentations.sort { $0.id.uuidString < $1.id.uuidString }
        contents.themes.sort { $0.id.uuidString < $1.id.uuidString }
        contents.media.sort { $0.id < $1.id }
        return contents
    }

    private static func decode<Value: VersionedDocument>(
        _ type: Value.Type, _ data: Data, _ kind: LibraryDocumentKind,
        _ migrate: @Sendable (Data, DocumentKind) throws -> (Data, migratedFrom: Int?)
    ) throws -> Value {
        try DocumentDecoding.decode(type, from: data, kind: kind.documentKind, migrate: migrate).value
    }

    private static func readListedEntry(_ path: String, in archive: Archive) throws -> Data {
        guard let entry = archive[path] else {
            throw LibraryStoreError.invalidBundle("thiếu tệp \(path).")
        }
        return try readEntry(entry, in: archive)
    }

    private static func readEntry(_ entry: Entry, in archive: Archive) throws -> Data {
        guard entry.type == .file, entry.uncompressedSize <= maxDocumentSize else {
            throw LibraryStoreError.invalidBundle("tệp \(entry.path) quá lớn hoặc không phải tệp.")
        }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
                if UInt64(data.count) > maxDocumentSize {
                    throw LibraryStoreError.invalidBundle("tệp \(entry.path) quá lớn.")
                }
            }
        } catch let error as LibraryStoreError {
            throw error
        } catch {
            throw LibraryStoreError.invalidBundle("tệp \(entry.path) bị hỏng.")
        }
        return data
    }

    /// Giải nén một tệp media ra `destination` rồi kiểm SHA-256 khớp mã media; sai thì xoá và ném lỗi.
    static func extractMedia(_ id: MediaID, path: String, from url: URL, to destination: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw LibraryStoreError.invalidBundle("không mở được tệp ZIP.")
        }
        guard let entry = archive[path], entry.type == .file else {
            throw LibraryStoreError.invalidBundle("thiếu tệp media \(path).")
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            _ = try archive.extract(entry, to: destination)
            let digest = try MediaHasher.sha256(of: destination)
            guard digest.hex.hasPrefix(id.rawValue) else {
                throw LibraryStoreError.mediaChecksumMismatch(id)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if let error = error as? LibraryStoreError {
                throw error
            }
            throw LibraryStoreError.invalidBundle("tệp media \(path) bị hỏng.")
        }
    }
}

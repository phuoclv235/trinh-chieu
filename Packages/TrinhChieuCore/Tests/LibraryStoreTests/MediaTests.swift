import CoreModel
import Foundation
import Testing

@testable import LibraryStore

@Suite("LibraryStore: media và SHA-256")
@MainActor
struct MediaTests {
    @Test("SHA-256 viết tay khớp vectơ chuẩn, kể cả khi nạp theo khối lẻ")
    func sha256Vectors() {
        func digest(_ bytes: [UInt8], chunk: Int) -> String {
            var hasher = StreamingSHA256()
            var start = 0
            while start < bytes.count {
                let end = min(start + chunk, bytes.count)
                bytes[start..<end].withUnsafeBytes { hasher.update($0) }
                start = end
            }
            return MediaHasher.hex(hasher.finalize())
        }
        #expect(digest([], chunk: 1) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let abcDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(digest(Array("abc".utf8), chunk: 1) == abcDigest)
        let twoBlocks = Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
        let twoBlocksDigest = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        #expect(digest(twoBlocks, chunk: 64) == twoBlocksDigest)
        #expect(digest(twoBlocks, chunk: 7) == twoBlocksDigest)
        let long = (0..<10_000).map { UInt8($0 % 251) }
        let longDigest = "0cd0bf930677960951dda8588edcb6b293c0c3b26ef3ba72cddff4ddfc6822c7"
        for chunk in [1, 63, 64, 65, 1_000, 10_000] {
            #expect(digest(long, chunk: chunk) == longDigest, "khối \(chunk)")
        }
    }

    @Test("Bộ băm media (CryptoKit trên Mac, bản viết tay trên Linux) cho cùng kết quả khi chép tệp")
    func mediaHasherCopies() throws {
        let dir = try TemporaryDirectory()
        let source = dir.url.appendingPathComponent("nguon.bin")
        let bytes = Data((0..<10_000).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        let copy = dir.url.appendingPathComponent("ban-chep.bin")
        let result = try MediaHasher.sha256(of: source, copyingTo: copy)
        #expect(result.hex == "0cd0bf930677960951dda8588edcb6b293c0c3b26ef3ba72cddff4ddfc6822c7")
        #expect(result.byteCount == 10_000)
        #expect(try Data(contentsOf: copy) == bytes)
    }

    @Test("Nhập media: tên theo 12 ký tự hex đầu của SHA-256 và đuôi viết thường; trùng nội dung trả bản có sẵn")
    func importsAndDeduplicates() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let library = try dir.child("thu-vien")
        let store = try await LibraryStore.open(
            at: library, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let source = try dir.child("nguon").appendingPathComponent("Nền Giáng Sinh.JPG")
        let bytes = Data((0..<10_000).map { UInt8($0 % 251) })
        try bytes.write(to: source)

        let info = try await store.importMedia(from: source)
        #expect(info.id == MediaID("0cd0bf930677"))
        #expect(info.kind == .image)
        #expect(info.fileExtension == "jpg")
        #expect(info.originalName == "Nền Giáng Sinh.JPG")
        #expect(info.byteCount == 10_000)
        #expect(info.origin == .copied)
        #expect(info.importedAt == clock.now.wholeSeconds)
        let stored = library.appendingPathComponent("media/0cd0bf930677.jpg")
        #expect(store.mediaURL(info.id)?.path == stored.standardizedFileURL.path)
        #expect(try Data(contentsOf: stored) == bytes)
        #expect(fileExists(library.appendingPathComponent("media/0cd0bf930677.json")))

        let duplicate = dir.url.appendingPathComponent("ban-sao.jpeg")
        try bytes.write(to: duplicate)
        clock.advance(by: 60)
        let again = try await store.importMedia(from: duplicate)
        #expect(again == info)
        let mediaDirectory = library.appendingPathComponent("media")
        let mediaFiles = try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path)
        #expect(mediaFiles.sorted() == ["0cd0bf930677.jpg", "0cd0bf930677.json"])

        await store.waitForIndexing()
        #expect(await store.search("giang sinh", kinds: [.media]).map(\.id) == ["0cd0bf930677"])
        await store.close()

        let reopened = try await LibraryStore.open(
            at: library, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(reopened.media[info.id] == info)
        await reopened.close()
    }

    @Test("Loại tệp không nhận làm media thì báo lỗi, không chép gì")
    func rejectsUnsupportedType() async throws {
        let dir = try TemporaryDirectory()
        let library = try dir.child("thu-vien")
        let store = try await LibraryStore.open(
            at: library, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: FakeClock()))
        let source = dir.url.appendingPathComponent("bai-giang.docx")
        try Data("x".utf8).write(to: source)
        await #expect(throws: LibraryStoreError.unsupportedMediaType("docx")) {
            try await store.importMedia(from: source)
        }
        let mediaPath = library.appendingPathComponent("media").path
        #expect(try FileManager.default.contentsOfDirectory(atPath: mediaPath).isEmpty)
        await store.close()
    }

    @Test("Media liên kết đọc được; mediaURL trả bản trong .cache/media nếu có, không thì nil")
    func linkedMedia() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let linked = MediaAssetInfo(
            id: MediaID("l-0123456789"), kind: .video, originalName: "Bài giảng.mp4", fileExtension: "mp4",
            importedAt: clock.now.wholeSeconds,
            origin: MediaOrigin(kind: .linked, url: "https://nas.local/d/abc/Bai-giang.mp4", provider: "slate"))
        try writeDocument(linked, to: dir.url, path: "media/l-0123456789.json")
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        #expect(store.media[linked.id] == linked)
        #expect(store.loadProblems.isEmpty)
        #expect(store.mediaURL(linked.id) == nil)
        let cached = dir.url.appendingPathComponent(".cache/media/l-0123456789.mp4")
        try FileManager.default.createDirectory(
            at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("video".utf8).write(to: cached)
        #expect(store.mediaURL(linked.id)?.path == cached.standardizedFileURL.path)
        #expect(store.mediaURL(MediaID("aaaaaaaaaaaa")) == nil)
        await store.close()
    }

    @Test("Mã media và tên tệp hợp lệ")
    func mediaNaming() {
        #expect(LibraryLayout.isValidMediaID("0cd0bf930677"))
        #expect(LibraryLayout.isValidMediaID("l-0123456789"))
        #expect(!LibraryLayout.isValidMediaID("0CD0BF930677"))
        #expect(!LibraryLayout.isValidMediaID("../../etc"))
        #expect(!LibraryLayout.isValidFileExtension("j/g"))
        #expect(LibraryLayout.isValidTranslationCode("vi1925"))
        #expect(!LibraryLayout.isValidTranslationCode("../x"))
    }
}

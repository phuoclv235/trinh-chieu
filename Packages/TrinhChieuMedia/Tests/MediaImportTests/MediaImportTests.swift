import CoreGraphics
import CoreModel
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MediaImport

/// Thư mục tạm riêng cho từng test, xoá khi xong.
struct TemporaryDirectory: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Ghi số đo ra luồng lỗi chuẩn để thấy trong log CI (test không dùng `print`).
func reportMeasurement(_ line: String) {
    FileHandle.standardError.write(Data("ĐO HIỆU NĂNG: \(line)\n".utf8))
}

/// Tạo PDF `pages` trang khổ `size` điểm, mỗi trang vài khối màu và một khung viền.
func makePDF(at url: URL, pages: Int, size: CGSize = CGSize(width: 612, height: 792)) throws {
    var mediaBox = CGRect(origin: .zero, size: size)
    let context = try #require(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
    for page in 0..<pages {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: size.width - 80, height: 120 + CGFloat(page) * 10))
        context.setStrokeColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.setLineWidth(4)
        context.stroke(CGRect(x: 20, y: 20, width: size.width - 40, height: size.height - 40))
        context.endPDFPage()
    }
    context.closePDF()
}

/// Kích thước và màu điểm ảnh góc trên trái của một tệp ảnh.
func imageInfo(_ url: URL) throws -> (width: Int, height: Int, hasAlpha: Bool) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let alpha = image.alphaInfo
    let hasAlpha = !(alpha == .none || alpha == .noneSkipLast || alpha == .noneSkipFirst)
    return (image.width, image.height, hasAlpha)
}

@Suite("MediaImport: PDF")
struct PDFImporterTests {
    @Test("Trang dọc khổ Letter vừa khung 1920x1080, giữ tỉ lệ; trang ngang khổ 16:9 phủ đúng khung")
    func pixelSizes() {
        let importer = PDFImporter()
        let portrait = importer.pixelSize(forPageSize: CGSize(width: 612, height: 792))
        #expect(portrait.width == 835 && portrait.height == 1080)
        let wide = importer.pixelSize(forPageSize: CGSize(width: 960, height: 540))
        #expect(wide.width == 1920 && wide.height == 1080)
        let tall = importer.pixelSize(forPageSize: CGSize(width: 4000, height: 1000))
        #expect(tall.width == 1920 && tall.height == 480)
    }

    @Test("PDF 10 trang: mỗi trang một ảnh PNG nền trắng, mỗi trang một trang chiếu; dưới 5 giây")
    func importsTenPages() async throws {
        let dir = try TemporaryDirectory()
        let pdf = dir.url.appendingPathComponent("Bài giảng Chúa Nhật.pdf")
        try makePDF(at: pdf, pages: 10)
        let collected = ImportedFiles()

        let start = Date()
        let result = try await PDFImporter().importPDF(
            at: pdf, workDirectory: dir.url, now: Date(timeIntervalSince1970: 1_800_000_000)
        ) { url in
            try collected.add(url)
        }
        let elapsed = Date().timeIntervalSince(start)
        reportMeasurement(String(format: "PDF 10 trang nhập trong %.2f s (ngưỡng 5 s)", elapsed))
        #expect(elapsed < 5)

        let infos = collected.infos
        #expect(infos.count == 10)
        for info in infos {
            #expect(info.width == 835 && info.height == 1080)
            #expect(info.cornerIsWhite)
        }
        let presentation = result.presentation
        #expect(presentation.kind == .generic)
        #expect(presentation.title == "Bài giảng Chúa Nhật")
        #expect(presentation.song == nil)
        #expect(presentation.groups.count == 1)
        let slides = presentation.groups[0].slides
        #expect(slides.count == 10)
        #expect(result.media.map(\.id) == (0..<10).map { MediaID("trang\($0)") })
        for (index, slide) in slides.enumerated() {
            guard case .image(let image) = slide.elements.first else {
                Issue.record("Trang \(index + 1) không có phần tử ảnh")
                continue
            }
            #expect(image.mediaID == MediaID("trang\(index)"))
            #expect(image.fit == .fit)
            #expect(image.frame == PixelRect(x: 0, y: 0, width: 1920, height: 1080))
        }
        // Ảnh tạm đã được dọn.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(leftovers == ["Bài giảng Chúa Nhật.pdf"])
    }

    @Test("Tệp hỏng: lỗi tiếng Việt có tên tệp, không gọi nhập media")
    func corruptFile() async throws {
        let dir = try TemporaryDirectory()
        let pdf = dir.url.appendingPathComponent("hỏng.pdf")
        try Data("Đây là văn bản, không phải PDF.".utf8).write(to: pdf)
        do {
            _ = try await PDFImporter().importPDF(at: pdf, workDirectory: dir.url) { _ in
                Issue.record("Không được gọi nhập media")
                throw CancellationError()
            }
            Issue.record("Phải báo lỗi")
        } catch let error as PDFImportError {
            #expect([.unreadable(filename: "hỏng.pdf"), .empty(filename: "hỏng.pdf")].contains(error))
            #expect(error.message.contains("hỏng.pdf"))
        }
    }
}

/// Giả lập `LibraryStore.importMedia`: đọc ảnh vừa dựng, trả mã media theo thứ tự.
final class ImportedFiles: @unchecked Sendable {
    struct Info {
        var width: Int
        var height: Int
        var cornerIsWhite: Bool
    }

    private let lock = NSLock()
    private var stored: [Info] = []

    var infos: [Info] {
        lock.withLock { stored }
    }

    func add(_ url: URL) throws -> MediaAssetInfo {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let info = Info(width: image.width, height: image.height, cornerIsWhite: Self.topLeftIsWhite(image))
        let index = lock.withLock {
            stored.append(info)
            return stored.count - 1
        }
        return MediaAssetInfo(
            id: MediaID("trang\(index)"), kind: .image, originalName: url.lastPathComponent, fileExtension: "png",
            importedAt: Date(timeIntervalSince1970: 0))
    }

    static func topLeftIsWhite(_ image: CGImage) -> Bool {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return false }
        // Vẽ sao cho điểm ảnh trên trái của ảnh rơi vào ô 1x1.
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        guard let data = context.data else { return false }
        let pixel = data.bindMemory(to: UInt8.self, capacity: 4)
        return pixel[0] > 250 && pixel[1] > 250 && pixel[2] > 250
    }
}

@Suite("MediaImport: bộ trình chiếu từ ảnh")
struct MediaSlidesTests {
    func media(_ id: String, name: String) -> MediaAssetInfo {
        MediaAssetInfo(
            id: MediaID(id), kind: .image, originalName: name, fileExtension: "jpg",
            importedAt: Date(timeIntervalSince1970: 0))
    }

    @Test("Nhiều ảnh: tạo một bộ trình chiếu mỗi ảnh một trang; chọn chỉ thêm vào Media thì không tạo")
    func imagesToPresentation() throws {
        let images = [media("aaaaaaaaaaaa", name: "Nền 1.jpg"), media("bbbbbbbbbbbb", name: "Nền 2.jpg")]
        let presentation = try #require(MediaSlides.presentation(fromImages: images, mode: .presentation))
        #expect(presentation.title == "Ảnh (2)")
        #expect(presentation.kind == .generic)
        #expect(presentation.groups.first?.slides.count == 2)
        #expect(presentation.orderedGroups().count == 1)
        #expect(MediaSlides.presentation(fromImages: images, mode: .mediaOnly) == nil)
        let single = try #require(MediaSlides.presentation(fromImages: [images[0]], mode: .presentation))
        #expect(single.title == "Nền 1")
    }
}

@Suite("MediaImport: MediaProbe")
struct MediaProbeTests {
    /// Ghi ảnh PNG có kênh trong suốt, kích thước `width` x `height`.
    func writeTransparentPNG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test("Ảnh PNG trong suốt: kích thước, có alpha, phát được; ảnh thu nhỏ cạnh dài 320 px")
    func probesImage() async throws {
        let dir = try TemporaryDirectory()
        let png = dir.url.appendingPathComponent("loi-bai-hat.png")
        try writeTransparentPNG(to: png, width: 1600, height: 900)
        let result = await MediaProbe.probe(url: png, kind: .image)
        #expect(result.pixelSize == PixelSize(width: 1600, height: 900))
        #expect(result.hasAlpha)
        #expect(result.playable)
        #expect(result.duration == nil)
        #expect(result.codec == UTType.png.identifier)

        let thumbnail = MediaProbe.thumbnailURL(libraryRoot: dir.url, id: MediaID("abcdefabcdef"))
        #expect(thumbnail.path.hasSuffix(".cache/thumbs/abcdefabcdef.jpg"))
        #expect(await MediaProbe.makeThumbnail(for: png, kind: .image, to: thumbnail))
        let info = try imageInfo(thumbnail)
        #expect(info.width == 320 && info.height == 180)
        #expect(!info.hasAlpha)

        let applied = MediaProbe.apply(
            result,
            to: MediaAssetInfo(
                id: "abcdefabcdef", kind: .image, originalName: "loi-bai-hat.png", fileExtension: "png",
                importedAt: Date(timeIntervalSince1970: 0)))
        #expect(applied.pixelSize == PixelSize(width: 1600, height: 900))
    }

    @Test("Video AVFoundation không đọc được: vẫn trả kết quả, đánh dấu không phát được, không có ảnh thu nhỏ")
    func unplayableVideo() async throws {
        let dir = try TemporaryDirectory()
        let video = dir.url.appendingPathComponent("hong.mp4")
        try Data((0..<4_096).map { UInt8($0 % 7) }).write(to: video)
        let result = await MediaProbe.probe(url: video, kind: .video)
        #expect(!result.playable)
        let thumbnail = dir.url.appendingPathComponent("thumb.jpg")
        #expect(!(await MediaProbe.makeThumbnail(for: video, kind: .video, to: thumbnail)))
    }

    @Test("FourCC dạng chữ")
    func fourCharacterCodes() {
        #expect(MediaProbe.fourCharacterCode(0x6176_6331) == "avc1")
        #expect(MediaProbe.fourCharacterCode(0x6170_3468) == "ap4h")
    }
}

import CoreGraphics
import CoreModel
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Lỗi nhập PDF. Thông báo tiếng Việt có tên tệp.
public enum PDFImportError: Error, Sendable, Equatable, LocalizedError, CustomStringConvertible {
    case unreadable(filename: String)
    case locked(filename: String)
    case empty(filename: String)
    case renderFailed(filename: String, page: Int)

    public var message: String {
        switch self {
        case .unreadable(let filename):
            return "Hệ thống không đọc được tệp \(filename): tệp không phải PDF hoặc đã hỏng."
        case .locked(let filename):
            return "Tệp \(filename) có mật khẩu; bạn mở khoá tệp rồi nhập lại."
        case .empty(let filename):
            return "Tệp \(filename) không có trang nào."
        case .renderFailed(let filename, let page):
            return "Hệ thống không dựng được trang \(page) của tệp \(filename)."
        }
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}

/// Kết quả nhập một tệp PDF.
public struct PDFImportResult: Sendable {
    /// Bộ trình chiếu `generic`, mỗi trang PDF một trang chiếu.
    public var presentation: Presentation
    /// Media ảnh của từng trang, theo thứ tự trang.
    public var media: [MediaAssetInfo]

    public init(presentation: Presentation, media: [MediaAssetInfo]) {
        self.presentation = presentation
        self.media = media
    }
}

/// Nhập PDF: mỗi trang dựng thành ảnh PNG vừa khung vẽ (giữ tỉ lệ, nền trắng), nhập ảnh vào thư viện, tạo một bộ
/// trình chiếu mỗi trang một trang chiếu. Dựng bằng CoreGraphics, chạy được ngoài luồng chính.
public struct PDFImporter: Sendable {
    public var canvasSize: PixelSize

    public init(canvasSize: PixelSize = .fullHD) {
        self.canvasSize = canvasSize
    }

    /// Dựng từng trang thành `trang-001.png`, `trang-002.png`... trong `directory` (tạo nếu chưa có).
    public func renderPages(of url: URL, into directory: URL) throws -> [URL] {
        let filename = url.lastPathComponent
        guard let document = CGPDFDocument(url as CFURL) else { throw PDFImportError.unreadable(filename: filename) }
        guard document.isUnlocked || document.unlockWithPassword("") else {
            throw PDFImportError.locked(filename: filename)
        }
        guard document.numberOfPages > 0 else { throw PDFImportError.empty(filename: filename) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var outputs: [URL] = []
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number), let image = render(page) else {
                throw PDFImportError.renderFailed(filename: filename, page: number)
            }
            let output = directory.appendingPathComponent(String(format: "trang-%03d.png", number))
            guard Self.writePNG(image, to: output) else {
                throw PDFImportError.renderFailed(filename: filename, page: number)
            }
            outputs.append(output)
        }
        return outputs
    }

    /// Nhập cả tệp: dựng trang vào `workDirectory`, gọi `importMedia` cho từng ảnh (thường là
    /// `LibraryStore.importMedia(from:)`), rồi dựng bộ trình chiếu tên là tên tệp. Ảnh tạm được xoá khi xong.
    public func importPDF(
        at url: URL, workDirectory: URL, now: Date = Date(),
        importMedia: @Sendable (URL) async throws -> MediaAssetInfo
    ) async throws -> PDFImportResult {
        let pagesDirectory = workDirectory.appendingPathComponent("pdf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: pagesDirectory) }
        let pages = try renderPages(of: url, into: pagesDirectory)
        var media: [MediaAssetInfo] = []
        for page in pages {
            media.append(try await importMedia(page))
        }
        let title = url.deletingPathExtension().lastPathComponent
        let presentation = MediaSlides.presentation(
            title: title, mediaIDs: media.map(\.id), groupName: "PDF", canvasSize: canvasSize, now: now
        )
        return PDFImportResult(presentation: presentation, media: media)
    }

    /// Kích thước ảnh (điểm ảnh) của một trang có kích thước hiển thị `pageSize` (đã xoay): vừa khung vẽ, giữ tỉ lệ.
    public func pixelSize(forPageSize pageSize: CGSize) -> (width: Int, height: Int) {
        guard pageSize.width > 0, pageSize.height > 0 else { return (1, 1) }
        let scale = min(canvasSize.width / pageSize.width, canvasSize.height / pageSize.height)
        let width = max(1, Int((pageSize.width * scale).rounded()))
        let height = max(1, Int((pageSize.height * scale).rounded()))
        return (width, height)
    }

    // MARK: - Nội bộ

    func render(_ page: CGPDFPage) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let rotation = ((Int(page.rotationAngle) % 360) + 360) % 360
        let turned = rotation == 90 || rotation == 270
        let shown = CGSize(width: turned ? box.height : box.width, height: turned ? box.width : box.height)
        let size = pixelSize(forPageSize: shown)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.scaleBy(x: CGFloat(size.width) / shown.width, y: CGFloat(size.height) / shown.height)
        // Xoay theo /Rotate của trang (chiều kim đồng hồ khi hiển thị), gốc toạ độ CoreGraphics ở góc dưới trái.
        switch rotation {
        case 90:
            context.translateBy(x: 0, y: box.width)
            context.rotate(by: -.pi / 2)
        case 180:
            context.translateBy(x: box.width, y: box.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: box.height, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.translateBy(x: -box.minX, y: -box.minY)
        context.clip(to: box)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        let type = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

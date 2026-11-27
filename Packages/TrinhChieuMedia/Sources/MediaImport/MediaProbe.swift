import AVFoundation
import CoreGraphics
import CoreMedia
import CoreModel
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Thông tin đọc được từ một tệp media.
public struct MediaProbeResult: Sendable, Hashable {
    /// Kích thước điểm ảnh đã tính hướng xoay (ảnh: EXIF; video: `preferredTransform`).
    public var pixelSize: PixelSize?
    /// Thời lượng (giây) của video, âm thanh.
    public var duration: Double?
    /// Mã nén: FourCC của video, âm thanh (`avc1`, `hvc1`, `ap4h`, `aac `) hoặc kiểu tệp ảnh (`public.png`).
    public var codec: String?
    /// Có kênh trong suốt (PNG, HEVC có alpha, ProRes 4444).
    public var hasAlpha: Bool
    /// Có rãnh âm thanh.
    public var hasAudio: Bool
    /// AVFoundation phát được (ảnh: đọc được). `false` thì vẫn nhập, giao diện hiện cảnh báo.
    public var playable: Bool

    public init(
        pixelSize: PixelSize? = nil, duration: Double? = nil, codec: String? = nil, hasAlpha: Bool = false,
        hasAudio: Bool = false, playable: Bool
    ) {
        self.pixelSize = pixelSize
        self.duration = duration
        self.codec = codec
        self.hasAlpha = hasAlpha
        self.hasAudio = hasAudio
        self.playable = playable
    }

    /// Không đọc được gì: tệp hỏng hoặc định dạng AVFoundation không hỗ trợ.
    public static let unreadable = MediaProbeResult(playable: false)
}

/// Đọc thông tin media và tạo ảnh thu nhỏ.
///
/// `MediaAssetInfo` (định dạng tệp `media/<id>.json`) hiện chỉ có `pixelSize` và `duration`; `codec`, `hasAlpha`,
/// `hasAudio`, `playable` nằm trong ``MediaProbeResult`` để giao diện dùng ngay, chưa ghi xuống tệp.
public enum MediaProbe {
    /// Cạnh dài nhất của ảnh thu nhỏ.
    public static let thumbnailMaxPixelSize = 320

    /// Đọc thông tin. Không ném lỗi: tệp hỏng hoặc không phát được cho kết quả `playable == false`.
    public static func probe(url: URL, kind: MediaKind) async -> MediaProbeResult {
        switch kind {
        case .image:
            return probeImage(url)
        case .video, .audio:
            do {
                return try await probeAudiovisual(url)
            } catch {
                return .unreadable
            }
        }
    }

    /// Ghi kích thước, thời lượng vào thông tin media.
    public static func apply(_ result: MediaProbeResult, to info: MediaAssetInfo) -> MediaAssetInfo {
        var updated = info
        if let pixelSize = result.pixelSize { updated.pixelSize = pixelSize }
        if let duration = result.duration { updated.duration = duration }
        return updated
    }

    /// `.cache/thumbs/<mã>.jpg` trong thư mục thư viện.
    public static func thumbnailURL(libraryRoot: URL, id: MediaID) -> URL {
        libraryRoot.appendingPathComponent(".cache/thumbs", isDirectory: true)
            .appendingPathComponent(id.rawValue + ".jpg")
    }

    /// Tạo ảnh thu nhỏ JPEG cạnh dài tối đa 320 px. Video lấy khung ở giây thứ 1 (hoặc 1/10 thời lượng nếu ngắn
    /// hơn). Trả `false` khi không tạo được (âm thanh, tệp hỏng, video không giải mã được).
    @discardableResult
    public static func makeThumbnail(for url: URL, kind: MediaKind, to destination: URL) async -> Bool {
        let image: CGImage?
        switch kind {
        case .image:
            image = imageThumbnail(url)
        case .video:
            image = await videoThumbnail(url)
        case .audio:
            image = nil
        }
        guard let image else { return false }
        return writeJPEG(image, to: destination)
    }

    // MARK: - Ảnh

    static func probeImage(_ url: URL) -> MediaProbeResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return .unreadable }
        var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue
        var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        // Hướng EXIF 5 đến 8: ảnh xoay 90 độ khi hiển thị.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation >= 5 { swap(&width, &height) }
        var pixelSize: PixelSize?
        if let width, let height { pixelSize = PixelSize(width: width, height: height) }
        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) ?? false
        let codec = CGImageSourceGetType(source).map { $0 as String }
        return MediaProbeResult(pixelSize: pixelSize, codec: codec, hasAlpha: hasAlpha, playable: true)
    }

    static func imageThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Video, âm thanh

    static func probeAudiovisual(_ url: URL) async throws -> MediaProbeResult {
        let asset = AVURLAsset(url: url)
        let (duration, assetPlayable) = try await asset.load(.duration, .isPlayable)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var result = MediaProbeResult(hasAudio: !audioTracks.isEmpty, playable: assetPlayable)
        if duration.isNumeric, duration.seconds > 0 {
            result.duration = duration.seconds
        }
        if let track = videoTracks.first {
            let (naturalSize, transform, formats, trackPlayable) = try await track.load(
                .naturalSize, .preferredTransform, .formatDescriptions, .isPlayable)
            let shown = naturalSize.applying(transform)
            result.pixelSize = PixelSize(width: abs(shown.width), height: abs(shown.height))
            if let format = formats.first {
                result.codec = fourCharacterCode(CMFormatDescriptionGetMediaSubType(format))
                result.hasAlpha = containsAlpha(format)
            }
            result.playable = assetPlayable && trackPlayable
        } else if let track = audioTracks.first {
            let formats = try await track.load(.formatDescriptions)
            result.codec = formats.first.map { fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) }
        }
        return result
    }

    static func videoThumbnail(_ url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let edge = CGFloat(thumbnailMaxPixelSize)
        generator.maximumSize = CGSize(width: edge, height: edge)
        var seconds = 1.0
        if let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 {
            seconds = min(1.0, duration.seconds / 10)
        }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    /// Định dạng có kênh trong suốt: cờ `ContainsAlphaChannel` (HEVC có alpha) hoặc độ sâu 32 bit (ProRes 4444).
    static func containsAlpha(_ format: CMFormatDescription) -> Bool {
        let alphaKey = kCMFormatDescriptionExtension_ContainsAlphaChannel
        if let flag = CMFormatDescriptionGetExtension(format, extensionKey: alphaKey) as? Bool, flag {
            return true
        }
        let depthKey = kCMFormatDescriptionExtension_Depth
        if let depth = CMFormatDescriptionGetExtension(format, extensionKey: depthKey) as? Int, depth == 32 {
            return true
        }
        return false
    }

    /// FourCC dạng chữ: `0x61766331` → `avc1`.
    static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        let characters = bytes.map { byte -> Character in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "?"
        }
        return String(characters)
    }

    // MARK: - Ghi JPEG

    /// Ghi JPEG chất lượng 0,8. Ảnh có kênh trong suốt được lót nền xám tối để chữ trắng trên nền trong vẫn thấy.
    static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return false }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flattened = context.makeImage() else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return false
        }
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return false }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, flattened, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}

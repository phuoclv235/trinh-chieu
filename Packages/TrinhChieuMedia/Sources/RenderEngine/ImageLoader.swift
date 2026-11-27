import CoreGraphics
import CoreModel
import Foundation
import ImageIO

/// Giải mã ảnh bằng `CGImageSource` ở đúng kích thước cần vẽ, không giải mã cả ảnh gốc.
enum ImageLoader {
    /// Kích thước điểm ảnh của ảnh gốc (đã xoay theo EXIF), đọc từ phần đầu tệp.
    static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double,
            width > 0, height > 0
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        // Hướng 5 đến 8 là xoay 90 độ: đổi chỗ rộng và cao.
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Cạnh dài (điểm ảnh) cần giải mã để vẽ ảnh vào khung `frame` theo cách đặt `fit`.
    static func decodeLongEdge(imageSize: CGSize, frame: CGSize, fit: ContentFit) -> Int {
        let scale: CGFloat
        switch fit {
        case .fit:
            scale = min(frame.width / imageSize.width, frame.height / imageSize.height)
        case .fill:
            scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        case .stretch:
            scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        }
        let longEdge = max(imageSize.width, imageSize.height) * min(1, scale)
        return max(1, Int(longEdge.rounded(.up)))
    }

    /// Giải mã ảnh ở `url` cho khung `frame` (điểm ảnh đầu ra). `nil` khi tệp mất hoặc hỏng.
    static func load(url: URL, frame: CGSize, fit: ContentFit) -> BGRABitmap? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
            let size = pixelSize(of: source)
        else { return nil }
        let longEdge = decodeLongEdge(imageSize: size, frame: frame, fit: fit)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return bitmap(from: image)
    }

    /// Chép `CGImage` sang ảnh BGRA đã nhân sẵn alpha trong không gian sRGB.
    static func bitmap(from image: CGImage) -> BGRABitmap {
        BGRABitmap.draw(width: image.width, height: image.height) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }
}

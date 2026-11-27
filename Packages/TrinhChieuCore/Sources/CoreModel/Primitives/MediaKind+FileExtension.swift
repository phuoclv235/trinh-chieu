import Foundation

extension MediaKind {
    /// Loại media theo phần mở rộng (không phân biệt hoa thường). `nil` là loại Hệ thống chưa nhận.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
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

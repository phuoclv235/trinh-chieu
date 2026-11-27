import CoreModel
import Foundation

/// Cách nhập nhiều ảnh một lúc.
public enum ImageImportMode: String, Sendable, Hashable, CaseIterable {
    /// "Tạo một bộ trình chiếu từ các ảnh": mỗi ảnh một trang.
    case presentation
    /// "Chỉ thêm vào Media".
    case mediaOnly
}

/// Dựng bộ trình chiếu từ các media đã nhập (trang PDF, ảnh).
public enum MediaSlides {
    /// Bộ trình chiếu `generic`, một đoạn có nhãn `groupName`, mỗi media một trang chiếu có một phần tử ảnh `fit`
    /// phủ toàn khung vẽ, nền đen. Không có thứ tự hát (trình chiếu theo thứ tự trang).
    public static func presentation(
        title: String, mediaIDs: [MediaID], groupName: String, canvasSize: PixelSize = .fullHD, now: Date = Date()
    ) -> Presentation {
        let frame = PixelRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
        let slides = mediaIDs.map { id in
            Slide(background: .color(.black), elements: [.image(ImageElement(frame: frame, mediaID: id, fit: .fit))])
        }
        let group = SlideGroup(label: GroupLabel(kind: .custom, custom: groupName), slides: slides)
        return Presentation(kind: .generic, title: title, createdAt: now, modifiedAt: now, groups: [group])
    }

    /// Bộ trình chiếu từ nhiều ảnh, hoặc `nil` khi chọn "Chỉ thêm vào Media". Tên bộ là tên ảnh đầu tiên khi chỉ có
    /// một ảnh, còn lại là "Ảnh (n)".
    public static func presentation(
        fromImages media: [MediaAssetInfo], mode: ImageImportMode, now: Date = Date()
    ) -> Presentation? {
        guard mode == .presentation, !media.isEmpty else { return nil }
        let title: String
        if media.count == 1 {
            title = (media[0].originalName as NSString).deletingPathExtension
        } else {
            title = "Ảnh (\(media.count))"
        }
        return presentation(title: title, mediaIDs: media.map(\.id), groupName: "Ảnh", now: now)
    }
}

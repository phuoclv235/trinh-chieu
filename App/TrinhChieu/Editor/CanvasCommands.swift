import CoreModel
import Foundation
import LibraryStore

/// Loại phần tử thêm từ thanh công cụ.
enum NewElementKind {
    case text
    case image(MediaID)
    case video(MediaID)
    case rectangle
}

/// Thao tác của khung vẽ và bảng thuộc tính trên trang đang chọn. Mỗi thao tác là một bước hoàn tác.
extension AppEnvironment {
    /// Trang đang chọn của bộ đang soạn.
    var editingSlide: Slide? {
        guard let id = presentationEditing.selectedSlideID else { return nil }
        return editingPresentation?.slide(id)
    }

    /// Phần tử đang chọn trên khung vẽ (còn tồn tại trên trang đang chọn).
    var editingElement: Element? {
        guard let id = presentationEditing.selectedElementID else { return nil }
        return editingSlide?.elements.first { $0.id == id }
    }

    /// Sửa trang đang chọn.
    func editSlide(_ actionName: String, coalescingKey: String? = nil, _ change: (inout Slide) -> Void) {
        guard let slideID = presentationEditing.selectedSlideID else { return }
        editPresentation(actionName, coalescingKey: coalescingKey) { $0.updateSlide(slideID, change) }
    }

    /// Sửa phần tử đang chọn.
    func editElement(_ actionName: String, coalescingKey: String? = nil, _ change: (inout Element) -> Void) {
        guard let elementID = presentationEditing.selectedElementID else { return }
        editSlide(actionName, coalescingKey: coalescingKey) { slide in
            guard let index = slide.elementIndex(elementID) else { return }
            change(&slide.elements[index])
        }
    }

    /// Sửa phần tử chữ đang chọn (bỏ qua khi phần tử không phải chữ).
    func editTextElement(_ actionName: String, coalescingKey: String? = nil, _ change: (inout TextElement) -> Void) {
        editElement(actionName, coalescingKey: coalescingKey) { element in
            guard case .text(var text) = element else { return }
            change(&text)
            element = .text(text)
        }
    }

    func setElementFrame(_ elementID: UUID, _ frame: PixelRect, coalescingKey: String?) {
        editSlide(String(localized: "Move element"), coalescingKey: coalescingKey) { $0.setFrame(frame, of: elementID) }
    }

    /// Sửa chữ của phần tử, trên trang đang chứa nó (có thể không còn là trang đang chọn khi vừa đổi trang).
    func setElementText(_ elementID: UUID, _ text: String) {
        let slides = editingPresentation?.groups.flatMap(\.slides) ?? []
        guard let slideID = slides.first(where: { $0.elementIndex(elementID) != nil })?.id else { return }
        editPresentation(String(localized: "Edit text")) { presentation in
            presentation.updateSlide(slideID) { slide in
                guard let index = slide.elementIndex(elementID), case .text(var element) = slide.elements[index] else {
                    return
                }
                element.text = text
                slide.elements[index] = .text(element)
            }
        }
    }

    func deleteElement(_ elementID: UUID) {
        editSlide(String(localized: "Delete element")) { $0.removeElement(elementID) }
        if presentationEditing.selectedElementID == elementID {
            presentationEditing.selectedElementID = nil
        }
    }

    func bringElementForward(_ elementID: UUID) {
        editSlide(String(localized: "Bring forward")) { $0.bringForward(elementID) }
    }

    func sendElementBackward(_ elementID: UUID) {
        editSlide(String(localized: "Send backward")) { $0.sendBackward(elementID) }
    }

    /// "Tách khỏi mẫu": phần tử chữ gắn ô mẫu thành phần tử tự do, giữ nguyên hình đang thấy.
    func detachElement(_ elementID: UUID) {
        guard let theme = editingTheme else { return }
        editSlide(String(localized: "Detach from theme")) { $0.detachFromTheme(elementID, theme: theme) }
    }

    /// Tách trang đang chọn tại dòng `line` của chữ chính (menu "Tách trang tại con trỏ").
    func splitSelectedSlide(atLine line: Int) {
        guard let slideID = presentationEditing.selectedSlideID else { return }
        var newID: UUID?
        editPresentation(String(localized: "Split slide")) { newID = $0.splitSlide(slideID, atLine: line) }
        if let newID {
            presentationEditing.selectedSlideID = newID
        }
    }

    /// Thêm phần tử vào trang đang chọn, giữa khung vẽ (hoặc tại `point`), rồi chọn nó.
    /// `slideID` khi phải thêm vào một trang đã biết trước (thả tệp: trang có thể đổi trong lúc chờ nhập).
    func addElement(_ kind: NewElementKind, at point: PixelPoint? = nil, onSlide slideID: UUID? = nil) {
        guard let slideID = slideID ?? presentationEditing.selectedSlideID, editingPresentation?.slide(slideID) != nil
        else { return }
        let canvas = editingTheme?.canvasSize ?? .fullHD
        let element: Element
        switch kind {
        case .text:
            let size = PixelSize(width: canvas.width * 0.6, height: canvas.height * 0.2)
            let frame = Self.frame(size: size, canvas: canvas, at: point)
            element = .text(TextElement(frame: frame, text: String(localized: "Text")))
        case .rectangle:
            let size = PixelSize(width: canvas.width * 0.3, height: canvas.height * 0.3)
            let frame = Self.frame(size: size, canvas: canvas, at: point)
            element = .shape(ShapeElement(frame: frame, fill: RGBA(red: 0x1A, green: 0x1C, blue: 0x22)))
        case .image(let id):
            let frame = Self.frame(size: mediaSize(id, canvas: canvas), canvas: canvas, at: point)
            element = .image(ImageElement(frame: frame, mediaID: id))
        case .video(let id):
            let frame = Self.frame(size: mediaSize(id, canvas: canvas), canvas: canvas, at: point)
            element = .video(VideoElement(frame: frame, mediaID: id, loop: true, muted: true))
        }
        editPresentation(String(localized: "Add element")) { presentation in
            presentation.updateSlide(slideID) { $0.elements.append(element) }
        }
        if presentationEditing.selectedSlideID == slideID {
            presentationEditing.selectedElementID = element.id
        }
    }

    /// Nhập tệp ảnh hoặc video (kéo vào khung vẽ, "Chọn tệp…") rồi thêm thành phần tử.
    func addMediaElements(from urls: [URL], at point: PixelPoint?) async {
        guard let library, let slideID = presentationEditing.selectedSlideID else { return }
        var failures: [EditorImportReport.Row] = []
        for url in urls {
            do {
                let info = try await library.importMedia(from: url)
                switch info.kind {
                case .image: addElement(.image(info.id), at: point, onSlide: slideID)
                case .video: addElement(.video(info.id), at: point, onSlide: slideID)
                case .audio:
                    let message = String(localized: "Audio files cannot be placed on a slide.")
                    failures.append(.init(filename: url.lastPathComponent, status: .failure, message: message))
                }
            } catch {
                let message = (error as? LibraryStoreError)?.message ?? error.localizedDescription
                failures.append(.init(filename: url.lastPathComponent, status: .failure, message: message))
            }
        }
        if !failures.isEmpty {
            presentationEditing.importReport = EditorImportReport(rows: failures)
        }
    }

    /// Media trong thư viện theo loại, mới nhập trước.
    func libraryMedia(_ kind: MediaKind) -> [MediaAssetInfo] {
        (library?.media.values.filter { $0.kind == kind } ?? []).sorted { $0.importedAt > $1.importedAt }
    }

    /// Cỡ phần tử media: kích thước điểm ảnh, thu cho vừa một nửa khung vẽ.
    private func mediaSize(_ id: MediaID, canvas: PixelSize) -> PixelSize {
        let natural = library?.media[id]?.pixelSize ?? PixelSize(width: canvas.width / 2, height: canvas.height / 2)
        guard natural.width > 0, natural.height > 0 else { return PixelSize(width: 640, height: 360) }
        let scale = min(1, canvas.width * 0.5 / natural.width, canvas.height * 0.5 / natural.height)
        return PixelSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
    }

    /// Khung cỡ `size` đặt giữa khung vẽ, hoặc tâm tại `point`.
    private static func frame(size: PixelSize, canvas: PixelSize, at point: PixelPoint?) -> PixelRect {
        let center = point ?? PixelPoint(x: canvas.width / 2, y: canvas.height / 2)
        let origin = PixelPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        return CanvasSnapping.rounded(PixelRect(x: origin.x, y: origin.y, width: size.width, height: size.height))
    }
}

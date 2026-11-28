import CoreGraphics
import CoreModel
import SwiftUI

/// Vùng giữa của trình soạn: trang đang chọn dựng bằng `RenderEngine.renderOffscreen` vừa khung, dựng lại có hoãn
/// 50 ms khi trang đổi. `CanvasView` vẽ ảnh dựng, viền vùng an toàn 5% và nhận chọn, kéo, đổi cỡ phần tử; khi đang
/// kéo, ảnh dựng theo khung tạm (chưa lưu), không hoãn, để chữ chạy theo chuột. Khi sửa chữ tại chỗ, ảnh dựng giấu
/// chữ của phần tử đang sửa để ô gõ không chồng lên chữ cũ.
struct EditorStage: View {
    let presentation: Presentation
    @Environment(AppEnvironment.self) private var environment
    @State private var image: CGImage?
    /// Khung đang kéo, chưa lưu: chỉ để dựng thử.
    @State private var draft: (id: UUID, rect: PixelRect)?
    /// Phần tử chữ đang sửa tại chỗ: dựng thử không có chữ của nó.
    @State private var editingTextID: UUID?
    /// Số thứ tự lần dựng: khi kéo, nhận ảnh của lần dựng mới hơn ảnh đang hiện dù lượt đó đã bị huỷ.
    @State private var renders = RenderCounter()

    var body: some View {
        let editing = environment.presentationEditing
        let saved = editing.selectedSlideID.flatMap { presentation.slide($0) }
        let selected = previewSlide(saved)
        let theme = environment.editingTheme
        let canvas = theme?.canvasSize ?? .fullHD
        GeometryReader { proxy in
            let size = fitted(canvas: canvas, in: proxy.size)
            ZStack {
                CanvasView(
                    slide: saved, theme: theme ?? Theme.fallback(), image: image,
                    selectedElementID: editing.selectedElementID, callbacks: callbacks)
                if selected == nil {
                    Text("Choose a slide on the left")
                        .font(Typography.body)
                        .foregroundStyle(Palette.text3)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(Rectangle().strokeBorder(Palette.lineStrong, lineWidth: 1).allowsHitTesting(false))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: RenderKey(slide: selected, theme: theme, width: Int(size.width))) {
                await render(selected, width: size.width, canvas: canvas, live: draft != nil)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 32, bottom: 20, trailing: 32))
        .background(Palette.bgStage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Canvas"))
    }

    /// Trang dựng thử: trang đã lưu, thay khung đang kéo nếu có, bỏ chữ của ô đang sửa tại chỗ.
    private func previewSlide(_ slide: Slide?) -> Slide? {
        guard var slide else { return nil }
        if let draft {
            slide.setFrame(draft.rect, of: draft.id)
        }
        if let editingTextID,
            let index = slide.elements.firstIndex(where: { $0.id == editingTextID }),
            case .text(var text) = slide.elements[index]
        {
            text.text = ""
            slide.elements[index] = .text(text)
        }
        return slide
    }

    private var callbacks: CanvasView.Callbacks {
        let environment = environment
        return CanvasView.Callbacks(
            select: { environment.presentationEditing.selectedElementID = $0 },
            commitFrame: { id, rect, coalescing in
                environment.setElementFrame(id, rect, coalescingKey: coalescing)
                draft = nil
            },
            previewFrame: { id, rect in draft = rect.map { (id, $0) } },
            commitText: { id, text in environment.setElementText(id, text) },
            editingText: { editingTextID = $0 },
            splitAtLine: { environment.splitSelectedSlide(atLine: $0) },
            delete: { environment.deleteElement($0) },
            bringForward: { environment.bringElementForward($0) },
            sendBackward: { environment.sendElementBackward($0) },
            detach: { environment.detachElement($0) },
            dropFiles: { urls, point in Task { await environment.addMediaElements(from: urls, at: point) } },
            addText: { environment.addElement(.text) })
    }

    /// Kích thước khung vẽ vừa vùng hiện có, giữ tỉ lệ của mẫu.
    private func fitted(canvas: PixelSize, in available: CGSize) -> CGSize {
        let width = CGFloat(canvas.width)
        let height = CGFloat(canvas.height)
        guard width > 0, height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / width, available.height / height)
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    /// `live`: đang kéo, dựng ngay không hoãn. Chuột đổi khung liên tục nên lượt dựng nào cũng bị huỷ trước khi
    /// xong; vẫn nhận ảnh nếu nó mới hơn ảnh đang hiện, để chữ chạy theo chuột thay vì đứng yên tới lúc thả.
    private func render(_ slide: Slide?, width: CGFloat, canvas: PixelSize, live: Bool) async {
        guard let slide, width > 0 else {
            image = nil
            return
        }
        let ticket = renders.next()
        if !live {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
        }
        guard let provider = environment.editorContent(), let index = provider.sequence.index(ofSlide: slide.id)
        else {
            image = nil
            return
        }
        // Dựng ở độ phân giải màn Retina của khung, tối đa bằng khung vẽ của mẫu.
        let shown = Double(width)
        let scale = min(2, canvas.width / max(1, shown))
        let pixelWidth = (shown * max(1, scale)).rounded()
        let pixelHeight = (pixelWidth * canvas.height / canvas.width).rounded()
        let rendered = await environment.thumbnails.renderLarge(
            slide, at: index, in: provider.sequence, provider: provider,
            size: PixelSize(width: pixelWidth, height: pixelHeight))
        guard !Task.isCancelled || live, renders.accept(ticket) else { return }
        // Dựng hỏng thì để khung đen, không giữ ảnh của trang trước.
        image = rendered
    }
}

/// Khoá dựng lại: trang (cả nội dung), mẫu, bề rộng khung.
private struct RenderKey: Hashable {
    let slide: Slide?
    let theme: Theme?
    let width: Int
}

/// Đếm lần dựng của khung vẽ; chỉ nhận ảnh mới hơn ảnh đang hiện.
@MainActor
private final class RenderCounter {
    private var issued = 0
    private var shown = 0

    func next() -> Int {
        issued += 1
        return issued
    }

    func accept(_ ticket: Int) -> Bool {
        guard ticket > shown else { return false }
        shown = ticket
        return true
    }
}

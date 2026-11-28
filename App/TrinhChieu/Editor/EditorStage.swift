import CoreGraphics
import CoreModel
import SwiftUI

/// Vùng giữa của trình soạn: trang đang chọn dựng bằng `RenderEngine.renderOffscreen` vừa khung, có viền vùng an
/// toàn 5%. Dựng lại có hoãn 50 ms khi trang đổi. Khung vẽ có chọn, kéo, đổi cỡ phần tử làm ở PR 2 của T1.9.
struct EditorStage: View {
    let presentation: Presentation
    @Environment(AppEnvironment.self) private var environment
    @State private var image: CGImage?

    var body: some View {
        let selected = environment.presentationEditing.selectedSlideID.flatMap { presentation.slide($0) }
        let theme = environment.editingTheme
        let canvas = theme?.canvasSize ?? .fullHD
        GeometryReader { proxy in
            let size = fitted(canvas: canvas, in: proxy.size)
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color.black
                }
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .padding(.horizontal, size.width * 0.05)
                    .padding(.vertical, size.height * 0.05)
                    .accessibilityHidden(true)
                if selected == nil {
                    Text("Choose a slide on the left")
                        .font(Typography.body)
                        .foregroundStyle(Palette.text3)
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(Rectangle().strokeBorder(Palette.lineStrong, lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: RenderKey(slide: selected, theme: theme, width: Int(size.width))) {
                await render(selected, width: size.width, canvas: canvas)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 32, bottom: 20, trailing: 32))
        .background(Palette.bgStage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Canvas"))
    }

    /// Kích thước khung vẽ vừa vùng hiện có, giữ tỉ lệ của mẫu.
    private func fitted(canvas: PixelSize, in available: CGSize) -> CGSize {
        let width = CGFloat(canvas.width)
        let height = CGFloat(canvas.height)
        guard width > 0, height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / width, available.height / height)
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    private func render(_ slide: Slide?, width: CGFloat, canvas: PixelSize) async {
        guard let slide, width > 0 else {
            image = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled, let provider = environment.editorContent(),
            let index = provider.sequence.index(ofSlide: slide.id)
        else { return }
        // Dựng ở độ phân giải màn Retina của khung, tối đa bằng khung vẽ của mẫu.
        let shown = Double(width)
        let scale = min(2, canvas.width / max(1, shown))
        let pixelWidth = (shown * max(1, scale)).rounded()
        let pixelHeight = (pixelWidth * canvas.height / canvas.width).rounded()
        let rendered = await environment.thumbnails.renderLarge(
            slide, at: index, in: provider.sequence, provider: provider,
            size: PixelSize(width: pixelWidth, height: pixelHeight))
        guard !Task.isCancelled else { return }
        if let rendered {
            image = rendered
        }
    }
}

/// Khoá dựng lại: trang (cả nội dung), mẫu, bề rộng khung.
private struct RenderKey: Hashable {
    let slide: Slide?
    let theme: Theme?
    let width: Int
}

import AppKit
import RenderEngine
import SwiftUI

/// Gắn lớp xem trước của lõi dựng hình (`RenderEngine.previewLayer`) vào cây lớp của giao diện.
///
/// Lớp này kiêm "lớp giữ nhịp" cho màn điều khiển (`docs/kien-truc.md` mục 4.1): vẽ đều 15 khung/giây để bộ ghép hình
/// không làm lỡ nhịp đầu ra trên màn khác. Một lớp chỉ nằm ở một chỗ; gắn vào chỗ mới thì tự rời chỗ cũ.
struct OutputPreview: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.host(layer)
        return view
    }

    func updateNSView(_ view: PreviewHostView, context: Context) {
        view.host(layer)
    }

    static func dismantleNSView(_ view: PreviewHostView, coordinator: ()) {
        view.releaseHostedLayer()
    }
}

final class PreviewHostView: NSView {
    private var hosted: CALayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    func host(_ preview: CALayer) {
        guard hosted !== preview || preview.superlayer !== layer else { return }
        if let previous = hosted, previous !== preview, previous.superlayer === layer {
            previous.removeFromSuperlayer()
        }
        hosted = preview
        layer?.addSublayer(preview)
        needsLayout = true
    }

    /// Chỉ gỡ khi lớp còn nằm ở đây (chỗ mới có thể đã nhận lớp trước khi chỗ cũ bị huỷ).
    func releaseHostedLayer() {
        if let hosted, hosted.superlayer === layer {
            hosted.removeFromSuperlayer()
        }
        hosted = nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted?.frame = bounds
        CATransaction.commit()
    }
}

/// Một khối xem trước trong cột phải: đèn, tên vai, màn đang gán, hình 16:9.
struct OutputPreviewCard: View {
    let role: OutputRole
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Lamp(style: isReceiving ? .breathing(Palette.accent) : .idle)
                Text(verbatim: role.localizedName)
                    .font(Typography.bodyStrong)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text(verbatim: screenDescription)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(Text(verbatim: screenDescription))
            }
            if let engine = environment.engine {
                OutputPreview(layer: engine.previewLayer(for: role))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.lineStrong, lineWidth: 1)
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: role.localizedName))
            }
        }
        .padding(16)
    }

    private var isReceiving: Bool {
        environment.outputs.attached[role] != nil
    }

    private var screenDescription: String {
        if let display = environment.outputs.attached[role] {
            return "\(display.name) · \(display.pixelWidth)×\(display.pixelHeight)"
        }
        if environment.outputs.missing.contains(where: { $0.role == role }) {
            return String(localized: "Screen disconnected")
        }
        if environment.outputs.blocked.contains(where: { $0.role == role }) {
            return String(localized: "Waiting for main window to move")
        }
        return String(localized: "No screen assigned")
    }
}

/// Bản xem trước 64x36 ở góc dưới phải khi cột phải ẩn hoặc ở chế độ Soạn thảo: lớp giữ nhịp không bao giờ biến mất.
struct MiniOutputPreview: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let engine = environment.engine {
            OutputPreview(layer: engine.previewLayer(for: .program))
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineStrong, lineWidth: 1))
                .help(Text(verbatim: OutputRole.program.localizedName))
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: OutputRole.program.localizedName))
                .padding(12)
        }
    }
}

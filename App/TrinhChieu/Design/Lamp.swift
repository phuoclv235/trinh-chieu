import AppKit
import SwiftUI

/// Đèn trạng thái 7 px. Đèn "thở" (quầng sáng nhịp 2,6 giây) chạy bằng Core Animation trong tiến trình vẽ của
/// hệ điều hành, không bắt SwiftUI vẽ lại mỗi khung: cửa sổ điều khiển gần như không tốn CPU khi đứng yên.
struct Lamp: View {
    enum Style: Equatable {
        /// Tắt: chấm xám mờ.
        case off
        /// Rỗng: vòng viền, chưa có nội dung.
        case idle
        /// Sáng, không thở.
        case steady(Color)
        /// Sáng và thở (chỉ ở chỗ đang hoạt động).
        case breathing(Color)
    }

    var style: Style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LampRepresentable(style: style, reduceMotion: reduceMotion)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

private struct LampRepresentable: NSViewRepresentable {
    var style: Lamp.Style
    var reduceMotion: Bool

    func makeNSView(context: Context) -> LampView {
        LampView()
    }

    func updateNSView(_ view: LampView, context: Context) {
        view.configure(style: style, reduceMotion: reduceMotion)
    }
}

final class LampView: NSView {
    private var style: Lamp.Style = .off
    private var reduceMotion = false
    private static let breathKey = "breath"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override var wantsUpdateLayer: Bool { true }

    func configure(style: Lamp.Style, reduceMotion: Bool) {
        guard style != self.style || reduceMotion != self.reduceMotion else { return }
        self.style = style
        self.reduceMotion = reduceMotion
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = bounds.width / 2
        layer.masksToBounds = false
        layer.borderWidth = 0
        layer.shadowOffset = .zero
        layer.shadowRadius = 0
        layer.shadowOpacity = 0
        layer.removeAnimation(forKey: Self.breathKey)
        var resolved: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case .off:
                layer.backgroundColor = NSColor(Palette.text3).withAlphaComponent(0.6).cgColor
            case .idle:
                layer.backgroundColor = NSColor.clear.cgColor
                layer.borderWidth = 1
                layer.borderColor = NSColor(Palette.text3).cgColor
            case .steady(let color), .breathing(let color):
                let cg = NSColor(color).cgColor
                layer.backgroundColor = cg
                resolved = cg
            }
        }
        guard case .breathing = style, !reduceMotion, let resolved else {
            if case .breathing = style, let resolved {
                // Giảm chuyển động: giữ quầng tĩnh.
                layer.shadowColor = resolved
                layer.shadowRadius = 2.5
                layer.shadowOpacity = 0.35
            }
            return
        }
        layer.shadowColor = resolved
        layer.shadowRadius = 3
        let animation = CAKeyframeAnimation(keyPath: "shadowOpacity")
        animation.values = [0, 0.55, 0]
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = Motion.breath
        animation.repeatCount = .infinity
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        layer.add(animation, forKey: Self.breathKey)
    }
}

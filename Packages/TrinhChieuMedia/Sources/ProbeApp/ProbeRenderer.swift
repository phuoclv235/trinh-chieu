import CoreGraphics
import Metal
import QuartzCore
import RenderEngine

/// Cảnh của bản thử: chỉ có lời đang hiện. Nền, khung phụ và logo cố định.
struct ProbeScene: Sendable, Equatable {
    var text: String
}

/// Bố cục cố định trên khung vẽ 1920x1080.
enum ProbeLayout {
    static let canvas = CGSize(width: 1920, height: 1080)
    static let background = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    static let pictureInPicture = CGRect(x: 1380, y: 60, width: 480, height: 270)
    static let logo = CGRect(x: 60, y: 900, width: 120, height: 120)
    static let textBox = CGRect(x: 120, y: 330, width: 1680, height: 640)
    static let textStyle = TextStyle(
        fontSize: 72,
        fillColor: SIMD4(1, 1, 1, 1),
        strokeColor: SIMD4(0, 0, 0, 1),
        strokeWidthPercent: 4,
        lineHeightMultiple: 1.1
    )

    /// Các lời đổi vòng. Có dấu chồng ở dòng trên cùng ("Ẩn", "Người", "Ở") để kiểm việc cắt dấu.
    static let phrases = [
        [
            "Ngợi khen Chúa, Đấng Toàn Năng,",
            "Vua của muôn vua,",
            "Chúa của muôn chúa,",
            "Người đáng được tôn vinh",
        ]
        .joined(separator: "\n"),
        [
            "Người là Đấng Chăn Chiên lành,",
            "dẫn tôi đi trong đồng cỏ xanh tươi,",
            "bên mé nước bình tịnh,",
            "bổ lại linh hồn tôi",
        ]
        .joined(separator: "\n"),
        [
            "Ẩn náu nơi Đấng Chí Cao,",
            "Ở dưới bóng Đấng Toàn Năng,",
            "Tôi nói về Đức Giê-hô-va rằng:",
            "Ngài là nơi nương náu tôi",
        ]
        .joined(separator: "\n"),
        [
            "Hãy hát mừng Đức Giê-hô-va,",
            "hỡi cả trái đất,",
            "Hãy hầu việc Ngài cách vui mừng,",
            "hát xướng mà đến trước mặt Ngài",
        ]
        .joined(separator: "\n"),
    ]

    static func textKey(_ text: String, layout: CanvasLayout) -> TextKey {
        let pixels = layout.pixelSize(textBox.size)
        return TextKey(
            text: text,
            style: textStyle,
            width: pixels.width,
            height: pixels.height,
            scale: layout.scale
        )
    }
}

/// Vẽ cảnh thử cho một đầu ra. Chỉ chạy trên luồng vẽ của đầu ra đó.
final class ProbeRenderer: FrameRenderer, @unchecked Sendable {
    private let compositor: Compositor
    private let textCache: TextTextureCache
    private let mailbox: SceneMailbox<ProbeScene>
    private let background: VideoTap
    private let pictureInPicture: VideoTap?
    private let logo: any MTLTexture
    private let dissolveDuration: Double
    private let nominalPeriod: Double

    private var shownRevision: UInt64 = 0
    private var currentText: TextKey?
    private var previousText: TextKey?
    private var transitionStart: CFTimeInterval?

    init(
        compositor: Compositor,
        textCache: TextTextureCache,
        mailbox: SceneMailbox<ProbeScene>,
        background: VideoTap,
        pictureInPicture: VideoTap?,
        logo: any MTLTexture,
        dissolveDuration: Double,
        nominalPeriod: Double
    ) {
        self.compositor = compositor
        self.textCache = textCache
        self.mailbox = mailbox
        self.background = background
        self.pictureInPicture = pictureInPicture
        self.logo = logo
        self.dissolveDuration = dissolveDuration
        self.nominalPeriod = nominalPeriod
    }

    func encodeFrame(_ frame: FrameContext) -> FrameOutcome {
        let layout = CanvasLayout(canvasSize: ProbeLayout.canvas, targetSize: frame.targetSize)
        let encoder = frame.encoder
        let target = frame.targetSize
        var retained: [AnyObject] = []

        if let video = background.frame(forHostTime: frame.targetPresentationTime) {
            compositor.drawQuad(
                encoder,
                texture: video.texture,
                rect: layout.pixelRect(ProbeLayout.background),
                targetSize: target,
                fit: .fill
            )
            retained.append(video.retain)
        }
        if let pictureInPicture, let video = pictureInPicture.frame(forHostTime: frame.targetPresentationTime) {
            compositor.drawQuad(
                encoder,
                texture: video.texture,
                rect: layout.pixelRect(ProbeLayout.pictureInPicture),
                targetSize: target,
                fit: .fill
            )
            retained.append(video.retain)
        }
        compositor.drawQuad(
            encoder,
            texture: logo,
            rect: layout.pixelRect(ProbeLayout.logo),
            targetSize: target,
            opacity: 0.9
        )

        let newScenePostedAt = advanceScene(layout: layout, time: frame.targetPresentationTime)
        drawText(encoder, layout: layout, target: target, time: frame.targetPresentationTime)
        return FrameOutcome(newScenePostedAt: newScenePostedAt, retainedResources: retained)
    }

    /// Nhận cảnh mới nếu chữ của nó đã dựng xong. Chưa xong thì giữ cảnh cũ (không vẽ khung trống).
    private func advanceScene(layout: CanvasLayout, time: CFTimeInterval) -> CFTimeInterval? {
        guard let entry = mailbox.latest(), entry.revision != shownRevision else { return nil }
        let key = ProbeLayout.textKey(entry.scene.text, layout: layout)
        guard textCache.texture(for: key) != nil else { return nil }
        previousText = currentText
        currentText = key
        shownRevision = entry.revision
        // Lùi một chu kỳ để khung đầu tiên đã có một phần cảnh mới.
        transitionStart = previousText == nil ? nil : time - nominalPeriod
        return entry.postedAt
    }

    private func drawText(
        _ encoder: any MTLRenderCommandEncoder,
        layout: CanvasLayout,
        target: CGSize,
        time: CFTimeInterval
    ) {
        guard let currentText, let current = textCache.texture(for: currentText) else { return }
        let rect = layout.pixelRect(ProbeLayout.textBox)
        let progress = transitionStart.map { start in
            dissolveDuration > 0 ? min(1, max(0, (time - start) / dissolveDuration)) : 1
        }
        if let progress, progress < 1, let previousText, let previous = textCache.texture(for: previousText) {
            compositor.drawDissolve(
                encoder,
                from: previous,
                to: current,
                t: Float(progress),
                rect: rect,
                targetSize: target
            )
            return
        }
        transitionStart = nil
        self.previousText = nil
        compositor.drawQuad(encoder, texture: current, rect: rect, targetSize: target)
    }
}

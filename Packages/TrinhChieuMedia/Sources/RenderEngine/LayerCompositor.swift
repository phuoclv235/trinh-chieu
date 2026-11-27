import CoreGraphics
import CoreModel
import Foundation
import Metal
import os

/// Nguồn của một lớp kèm tỉ lệ đầu ra: cùng lớp nhưng đầu ra khác cỡ thì phải dựng lại chữ và ảnh.
struct LayerTarget: LayerSource {
    let layer: RenderLayer
    let scale: Double

    var contentID: UUID { layer.contentID }
}

/// Một lệnh vẽ. `rect` tính theo điểm ảnh, gốc ở góc trên trái của khung vẽ (chưa cộng lề).
struct DrawCommand {
    enum Source {
        /// Texture đã sẵn (màu, ảnh, chữ).
        case texture(any MTLTexture)
        /// Video: lấy khung mới mỗi lần vẽ; `rect` là khung của phần tử, cách đặt tính theo cỡ khung video.
        case video(VideoRef, fit: ContentFit)
    }

    let source: Source
    let rect: CGRect
    let fit: QuadFit

    init(texture: any MTLTexture, rect: CGRect, fit: QuadFit) {
        source = .texture(texture)
        self.rect = rect
        self.fit = fit
    }

    init(video: VideoRef, rect: CGRect, fit: ContentFit) {
        source = .video(video, fit: fit)
        self.rect = rect
        self.fit = .stretch
    }

    var hasVideo: Bool {
        if case .video = source { return true }
        return false
    }
}

/// Lớp đã dựng xong: giữ texture của chính nó, nên đệm có bỏ bớt cũng không mất hình trên màn.
struct ResolvedLayer {
    let commands: [DrawCommand]
    /// Màu phủ kín khung vẽ của lớp (chỉ lớp nền dùng để tô phần thừa ngoài khung vẽ).
    var letterbox: RGBA?

    var hasVideo: Bool { commands.contains { $0.hasVideo } }
}

/// Bộ trộn lớp của một đầu ra: mỗi `LayerKind` một `LayerSlot`, vẽ dưới lên trên, hoà tan theo lớp.
///
/// Theo đặc tả T1.6, một cảnh có tối đa một lớp cho mỗi `LayerKind` (chuyển cảnh theo từng loại lớp).
/// Cảnh lỡ có hai lớp cùng loại thì lớp sau thay lớp trước và có cảnh báo trong nhật ký.
///
/// Chỉ dùng trên một luồng (luồng vẽ của đầu ra, hoặc luồng gọi `renderOffscreen`).
final class LayerCompositor {
    private let gpu: GPUContext
    private let pipelines: Compositor
    private let cache: TextureCache
    /// Dựng ngoài màn hình: chờ dựng xong mọi texture thay vì giữ lớp cũ.
    private let blocking: Bool
    private let video: any VideoFrameProvider
    private let consumer: VideoConsumer
    /// Tài nguyên khung video của lần `encode` đang ghi, giữ tới khi GPU dựng xong.
    private var retainedFrames: [AnyObject] = []

    private var slots: [LayerKind: LayerSlot<LayerTarget, ResolvedLayer>] = [:]
    private var scene: RenderScene?
    private var intermediates: [any MTLTexture] = []
    private let logger = Logger(subsystem: "app.trinhchieu.RenderEngine", category: "LayerCompositor")

    init(
        gpu: GPUContext,
        pipelines: Compositor,
        cache: TextureCache,
        blocking: Bool,
        video: any VideoFrameProvider = StillVideoProvider.empty,
        consumer: VideoConsumer = VideoConsumer(role: .program)
    ) {
        self.gpu = gpu
        self.pipelines = pipelines
        self.cache = cache
        self.blocking = blocking
        self.video = video
        self.consumer = consumer
    }

    /// Cảnh đang vẽ có video hoặc đang chuyển cảnh: phải vẽ lại mỗi khung.
    var isAnimating: Bool {
        isTransitioning
            || slots.values.contains { slot in
                (slot.shown.content?.hasVideo ?? false) || (slot.target.content?.hasVideo ?? false)
            }
    }

    /// Cảnh mới nhất đã nhận.
    var currentScene: RenderScene? { scene }

    /// Có lớp nào đang hoà tan không.
    var isTransitioning: Bool { slots.values.contains { $0.transition != nil } }

    /// Sau lần `update` gần nhất còn lớp chưa dựng xong (chữ, ảnh, khung video đầu): phải thử lại ở nhịp sau.
    private(set) var hasPendingLayers = false

    /// Nhận cảnh mới nhất cho khung ở thời điểm `time`, cho đầu ra có kích thước `targetSize` (điểm ảnh).
    func update(scene: RenderScene, targetSize: CGSize, time: Double) {
        self.scene = scene
        let layout = CanvasLayout(canvasSize: scene.canvasSize.cgSize, targetSize: targetSize)
        var present: Set<LayerKind> = []
        var pending = false
        for layer in scene.layers {
            if !present.insert(layer.kind).inserted {
                logger.warning("Cảnh có hai lớp \(layer.kind.rawValue, privacy: .public): chỉ vẽ lớp sau")
            }
            let source = LayerTarget(layer: layer, scale: Double(layout.scale))
            slots[layer.kind, default: LayerSlot()].update(
                source: source,
                spec: scene.transition,
                time: time
            ) { resolve($0, canvas: scene.canvasSize, layout: layout) }
            if slots[layer.kind]?.target.source != source { pending = true }
        }
        hasPendingLayers = pending
        for kind in slots.keys where !present.contains(kind) {
            slots[kind]?.update(source: nil, spec: scene.transition, time: time) { _ in nil }
            if slots[kind]?.isIdle == true {
                slots[kind] = nil
            }
        }
    }

    /// Ghi lệnh vẽ khung ở thời điểm `time` vào `commandBuffer`, đích là `target`.
    func encode(into commandBuffer: any MTLCommandBuffer, target: any MTLTexture, time: Double) {
        let targetSize = CGSize(width: target.width, height: target.height)
        guard let scene else {
            clear(commandBuffer, target: target, color: .black)
            return
        }
        let layout = CanvasLayout(canvasSize: scene.canvasSize.cgSize, targetSize: targetSize)
        let canvasPixels = CGSize(
            width: max(1, (scene.canvasSize.width * Double(layout.scale)).rounded()),
            height: max(1, (scene.canvasSize.height * Double(layout.scale)).rounded())
        )

        enum Step {
            case steady(ResolvedLayer)
            case dissolve(from: any MTLTexture, to: any MTLTexture, t: Double)
        }
        var steps: [Step] = []
        var used = 0
        for kind in drawOrder(scene) {
            guard let slot = slots[kind] else { continue }
            switch slot.plan(at: time) {
            case .nothing:
                continue
            case .steady(let layer):
                steps.append(.steady(layer))
            case .dissolve(let from, let to, let t):
                guard
                    let fromTexture = intermediate(index: used, size: canvasPixels),
                    let toTexture = intermediate(index: used + 1, size: canvasPixels)
                else {
                    // Không cấp được texture trung gian: vẽ đích ngay, không để màn trống.
                    if let to { steps.append(.steady(to)) }
                    continue
                }
                used += 2
                drawLayerOffscreen(commandBuffer, layer: from, into: fromTexture, time: time)
                drawLayerOffscreen(commandBuffer, layer: to, into: toTexture, time: time)
                steps.append(.dissolve(from: fromTexture, to: toTexture, t: t))
            }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = letterboxColor(at: time).clearColor
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Compose"
        let canvasRect = CGRect(origin: layout.offset, size: canvasPixels)
        // Khung vẽ nằm ngoài đích (không xảy ra với kích thước hợp lệ): chỉ tô màu phần thừa.
        if let scissor = Self.scissor(canvasRect, targetSize: targetSize) {
            encoder.setScissorRect(scissor)
        } else {
            steps.removeAll()
        }
        for step in steps {
            switch step {
            case .steady(let layer):
                draw(layer, encoder: encoder, origin: layout.offset, targetSize: targetSize, time: time)
            case .dissolve(let from, let to, let t):
                pipelines.drawDissolve(
                    encoder,
                    from: from,
                    to: to,
                    t: Float(t),
                    rect: canvasRect,
                    targetSize: targetSize
                )
            }
        }
        encoder.endEncoding()
        if !retainedFrames.isEmpty {
            let frames = UncheckedSendableBox(retainedFrames)
            retainedFrames.removeAll()
            commandBuffer.addCompletedHandler { _ in
                withExtendedLifetime(frames) {}
            }
        }
    }

    // MARK: - Dựng lớp

    private func resolve(_ target: LayerTarget, canvas: PixelSize, layout: CanvasLayout) -> ResolvedLayer? {
        var commands: [DrawCommand] = []
        let scale = layout.scale
        for item in target.layer.items {
            switch item {
            case .color(let color, let frame):
                guard color.alpha > 0 else { continue }
                switch cache.lookup(.color(color), blocking: blocking) {
                case .ready(let cached):
                    let rect = Self.scaled(frame, scale)
                    commands.append(DrawCommand(texture: cached.texture, rect: rect, fit: .stretch))
                case .pending:
                    return nil
                case .failed:
                    continue
                }
            case .image(let media, let frame, let fit):
                let rect = Self.scaled(frame, scale)
                let size = layout.pixelSize(frame.cgRect.size)
                let key = ImageKey(media: media.id, pixelWidth: size.width, pixelHeight: size.height, fit: fit)
                switch cache.lookup(.image(key), blocking: blocking) {
                case .ready(let cached):
                    commands.append(Self.imageCommand(cached.texture, rect: rect, fit: fit))
                case .pending:
                    return nil
                case .failed:
                    // Ảnh mất hoặc hỏng: không vẽ gì thay thế lên đầu ra (lỗi chỉ báo trên màn điều khiển).
                    continue
                }
            case .text(let block, let frame):
                guard !block.string.isEmpty else { continue }
                let size = layout.pixelSize(frame.cgRect.size)
                let key = TextBlockKey(
                    block,
                    pixelWidth: size.width,
                    pixelHeight: size.height,
                    scale: Double(scale)
                )
                switch cache.lookup(.text(key), blocking: blocking) {
                case .ready(let cached):
                    let origin = CGPoint(
                        x: (frame.x * Double(scale)).rounded() - Double(cached.padding),
                        y: (frame.y * Double(scale)).rounded() - Double(cached.padding)
                    )
                    let rect = CGRect(
                        origin: origin,
                        size: CGSize(width: cached.texture.width, height: cached.texture.height)
                    )
                    commands.append(DrawCommand(texture: cached.texture, rect: rect, fit: .stretch))
                case .pending:
                    return nil
                case .failed:
                    continue
                }
            case .video(let ref, let frame, let fit):
                let rect = Self.scaled(frame, scale)
                switch video.availability(of: ref, for: consumer, frame: rect.size, fit: fit) {
                case .ready:
                    commands.append(DrawCommand(video: ref, rect: rect, fit: fit))
                case .pending:
                    // Chưa có khung đầu tiên: giữ lớp cũ. Dựng ngoài màn hình thì bỏ qua thay vì chờ mãi.
                    if blocking { continue }
                    return nil
                case .failed:
                    continue
                }
            }
        }
        return ResolvedLayer(commands: commands, letterbox: Self.coveringColor(target.layer, canvas: canvas))
    }

    static func imageCommand(_ texture: any MTLTexture, rect: CGRect, fit: ContentFit) -> DrawCommand {
        switch fit {
        case .fit:
            let size = CGSize(width: texture.width, height: texture.height)
            return DrawCommand(texture: texture, rect: aspectFitRect(contentSize: size, in: rect), fit: .stretch)
        case .fill:
            return DrawCommand(texture: texture, rect: rect, fit: .fill)
        case .stretch:
            return DrawCommand(texture: texture, rect: rect, fit: .stretch)
        }
    }

    static func scaled(_ frame: PixelRect, _ scale: CGFloat) -> CGRect {
        CGRect(
            x: frame.x * Double(scale),
            y: frame.y * Double(scale),
            width: frame.width * Double(scale),
            height: frame.height * Double(scale)
        )
    }

    // MARK: - Vẽ

    private func draw(
        _ layer: ResolvedLayer,
        encoder: any MTLRenderCommandEncoder,
        origin: CGPoint,
        targetSize: CGSize,
        time: Double
    ) {
        for command in layer.commands {
            let resolved: DrawCommand
            switch command.source {
            case .texture:
                resolved = command
            case .video(let ref, let fit):
                guard let frame = video.frame(of: ref, for: consumer, at: time) else { continue }
                if let retain = frame.retain { retainedFrames.append(retain) }
                resolved = Self.imageCommand(frame.texture, rect: command.rect, fit: fit)
            }
            guard case .texture(let texture) = resolved.source else { continue }
            pipelines.drawQuad(
                encoder,
                texture: texture,
                rect: resolved.rect.offsetBy(dx: origin.x, dy: origin.y),
                targetSize: targetSize,
                fit: resolved.fit
            )
        }
    }

    private func drawLayerOffscreen(
        _ commandBuffer: any MTLCommandBuffer,
        layer: ResolvedLayer?,
        into texture: any MTLTexture,
        time: Double
    ) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "Layer"
        if let layer {
            let size = CGSize(width: texture.width, height: texture.height)
            draw(layer, encoder: encoder, origin: .zero, targetSize: size, time: time)
        }
        encoder.endEncoding()
    }

    private func clear(_ commandBuffer: any MTLCommandBuffer, target: any MTLTexture, color: RGBA) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = color.clearColor
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    /// Texture trung gian cỡ khung vẽ để hoà tan; dùng lại giữa các khung.
    private func intermediate(index: Int, size: CGSize) -> (any MTLTexture)? {
        let width = Int(size.width)
        let height = Int(size.height)
        if index < intermediates.count {
            let existing = intermediates[index]
            if existing.width == width, existing.height == height { return existing }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = gpu.device.makeTexture(descriptor: descriptor) else {
            logger.error("Không tạo được texture trung gian \(width)x\(height)")
            return nil
        }
        texture.label = "Dissolve.\(index)"
        if index < intermediates.count {
            intermediates[index] = texture
        } else {
            intermediates.append(texture)
        }
        return texture
    }

    /// Thứ tự vẽ: theo thứ tự lớp trong cảnh; lớp đang biến mất chen vào theo thứ tự của `LayerKind`.
    private func drawOrder(_ scene: RenderScene) -> [LayerKind] {
        var order = scene.layers.map(\.kind)
        let rank = Dictionary(uniqueKeysWithValues: LayerKind.allCases.enumerated().map { ($1, $0) })
        for kind in LayerKind.allCases where slots[kind] != nil && !order.contains(kind) {
            let position = order.firstIndex { (rank[$0] ?? 0) > (rank[kind] ?? 0) } ?? order.count
            order.insert(kind, at: position)
        }
        var seen: Set<LayerKind> = []
        return order.filter { seen.insert($0).inserted }
    }

    /// Màu phần thừa khi tỉ lệ khung vẽ khác tỉ lệ màn: màu nền của lớp `background` đang hiện nếu là màu
    /// phủ kín, không thì đen. Lớp nền đang hoà tan thì phần thừa cũng chuyển màu theo cùng nhịp.
    func letterboxColor(at time: Double) -> RGBA {
        guard let slot = slots[.background] else { return .black }
        switch slot.plan(at: time) {
        case .nothing:
            return .black
        case .steady(let layer):
            return layer.letterbox ?? .black
        case .dissolve(let from, let to, let t):
            return (from?.letterbox ?? .black).mixed(with: to?.letterbox ?? .black, t: t)
        }
    }

    /// Màu của phần tử đầu tiên nếu là màu phủ kín khung vẽ (luôn đục).
    static func coveringColor(_ layer: RenderLayer, canvas: PixelSize) -> RGBA? {
        guard layer.kind == .background,
            case .color(let color, let frame)? = layer.items.first,
            frame.x <= 0, frame.y <= 0,
            frame.x + frame.width >= canvas.width,
            frame.y + frame.height >= canvas.height
        else { return nil }
        var opaque = color
        opaque.alpha = 255
        return opaque
    }

    static func scissor(_ rect: CGRect, targetSize: CGSize) -> MTLScissorRect? {
        let bounds = CGRect(origin: .zero, size: targetSize)
        let clipped = rect.integral.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return nil
        }
        return MTLScissorRect(
            x: Int(clipped.minX),
            y: Int(clipped.minY),
            width: Int(clipped.width),
            height: Int(clipped.height)
        )
    }
}

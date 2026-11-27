import CoreGraphics
import Metal
import simd

/// Tham số gửi cho shader `Compose.metal`. Bố cục phải khớp struct `QuadParams` trong shader.
struct QuadParams {
    var rect: SIMD4<Float>
    var uvRect: SIMD4<Float>
    var target: SIMD2<Float>
    var opacity: Float
    var mixT: Float
}

/// Cách đặt nội dung vào khung.
public enum QuadFit: Sendable, Equatable {
    /// Giãn cho vừa khung, có thể méo.
    case stretch
    /// Phủ kín khung, cắt phần thừa, giữ tỉ lệ.
    case fill
}

/// Ánh xạ khung vẽ logic (ví dụ 1920x1080) vào kích thước drawable thật, vừa khít, căn giữa.
public struct CanvasLayout: Sendable, Equatable {
    public let canvasSize: CGSize
    public let targetSize: CGSize
    public let scale: CGFloat
    public let offset: CGPoint

    public init(canvasSize: CGSize, targetSize: CGSize) {
        self.canvasSize = canvasSize
        self.targetSize = targetSize
        let scale = min(targetSize.width / canvasSize.width, targetSize.height / canvasSize.height)
        self.scale = scale
        self.offset = CGPoint(
            x: (targetSize.width - canvasSize.width * scale) / 2,
            y: (targetSize.height - canvasSize.height * scale) / 2
        )
    }

    /// Đổi một hình chữ nhật trên khung vẽ logic thành điểm ảnh của drawable.
    public func pixelRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: offset.x + rect.origin.x * scale,
            y: offset.y + rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// Kích thước điểm ảnh (làm tròn) của một hình chữ nhật trên khung vẽ, dùng để dựng chữ đúng độ nét.
    public func pixelSize(_ size: CGSize) -> (width: Int, height: Int) {
        (max(1, Int((size.width * scale).rounded())), max(1, Int((size.height * scale).rounded())))
    }
}

/// Vùng cần lấy trong texture để `fill` một khung mà vẫn giữ tỉ lệ.
public func fillUVRect(textureSize: CGSize, frameSize: CGSize) -> CGRect {
    guard textureSize.width > 0, textureSize.height > 0, frameSize.width > 0, frameSize.height > 0 else {
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let scale = max(frameSize.width / textureSize.width, frameSize.height / textureSize.height)
    let width = frameSize.width / (textureSize.width * scale)
    let height = frameSize.height / (textureSize.height * scale)
    return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
}

/// Hai pipeline của `Compose.metal`: vẽ một texture, và hoà tan hai texture.
public final class Compositor: @unchecked Sendable {
    let quadPipeline: any MTLRenderPipelineState
    let dissolvePipeline: any MTLRenderPipelineState

    public init(gpu: GPUContext, pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        quadPipeline = try Self.makePipeline(
            gpu: gpu,
            fragment: "quad_fragment",
            pixelFormat: pixelFormat
        )
        dissolvePipeline = try Self.makePipeline(
            gpu: gpu,
            fragment: "dissolve_fragment",
            pixelFormat: pixelFormat
        )
    }

    private static func makePipeline(
        gpu: GPUContext,
        fragment: String,
        pixelFormat: MTLPixelFormat
    ) throws -> any MTLRenderPipelineState {
        guard let vertexFunction = gpu.library.makeFunction(name: "quad_vertex"),
            let fragmentFunction = gpu.library.makeFunction(name: fragment)
        else {
            throw RenderEngineError.pipelineUnavailable(fragment)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = fragment
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = pixelFormat
        // Màu đã nhân sẵn alpha: nguồn * 1 + đích * (1 - alpha nguồn).
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try gpu.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RenderEngineError.pipelineUnavailable("\(fragment): \(error)")
        }
    }

    /// Vẽ một texture vào `rect` (điểm ảnh của drawable).
    public func drawQuad(
        _ encoder: any MTLRenderCommandEncoder,
        texture: any MTLTexture,
        rect: CGRect,
        targetSize: CGSize,
        fit: QuadFit = .stretch,
        opacity: Float = 1
    ) {
        var params = Self.params(
            textureSize: CGSize(width: texture.width, height: texture.height),
            rect: rect,
            targetSize: targetSize,
            fit: fit,
            opacity: opacity,
            mixT: 0
        )
        encoder.setRenderPipelineState(quadPipeline)
        encoder.setVertexBytes(&params, length: MemoryLayout<QuadParams>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<QuadParams>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Hoà tan từ `from` sang `to` theo `t` (0 là toàn cảnh cũ, 1 là toàn cảnh mới).
    /// Hai texture phải cùng kích thước khung.
    public func drawDissolve(
        _ encoder: any MTLRenderCommandEncoder,
        from: any MTLTexture,
        to: any MTLTexture,
        t: Float,
        rect: CGRect,
        targetSize: CGSize,
        opacity: Float = 1
    ) {
        var params = Self.params(
            textureSize: CGSize(width: to.width, height: to.height),
            rect: rect,
            targetSize: targetSize,
            fit: .stretch,
            opacity: opacity,
            mixT: t
        )
        encoder.setRenderPipelineState(dissolvePipeline)
        encoder.setVertexBytes(&params, length: MemoryLayout<QuadParams>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<QuadParams>.stride, index: 0)
        encoder.setFragmentTexture(from, index: 0)
        encoder.setFragmentTexture(to, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    static func params(
        textureSize: CGSize,
        rect: CGRect,
        targetSize: CGSize,
        fit: QuadFit,
        opacity: Float,
        mixT: Float
    ) -> QuadParams {
        let uv: CGRect
        switch fit {
        case .stretch:
            uv = CGRect(x: 0, y: 0, width: 1, height: 1)
        case .fill:
            uv = fillUVRect(textureSize: textureSize, frameSize: rect.size)
        }
        return QuadParams(
            rect: SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height)),
            uvRect: SIMD4(Float(uv.minX), Float(uv.minY), Float(uv.width), Float(uv.height)),
            target: SIMD2(Float(targetSize.width), Float(targetSize.height)),
            opacity: opacity,
            mixT: mixT
        )
    }
}

import CoreGraphics
import CoreModel
import Foundation
import Metal

/// Lõi dựng hình: nhận cảnh cho từng vai, vẽ ra các đầu ra.
///
/// T1.6 PR 1 có: hộp thư cảnh theo vai, bộ trộn lớp (màu, ảnh, chữ), chuyển cảnh theo lớp và `renderOffscreen`.
/// Gắn màn, xem trước, video, hiệu ứng chữ và thống kê nằm ở T1.6 PR 2 (sau cổng giai đoạn 0).
@MainActor
public final class RenderEngine {
    let gpu: GPUContext
    let pipelines: Compositor
    let cache: TextureCache
    private let mailboxes: [OutputRole: SceneMailbox<RenderScene>]

    /// Tạo thiết bị Metal dùng chung. Lỗi khi máy không có Metal. Tìm tệp media chỉ qua `mediaLocator`.
    public init(mediaLocator: any MediaLocator) throws {
        let gpu = try GPUContext()
        self.gpu = gpu
        pipelines = try Compositor(gpu: gpu)
        cache = TextureCache(device: gpu.device, mediaLocator: mediaLocator)
        var mailboxes: [OutputRole: SceneMailbox<RenderScene>] = [:]
        for role in OutputRole.allCases {
            mailboxes[role] = SceneMailbox()
        }
        self.mailboxes = mailboxes
    }

    /// Gửi cảnh mới cho một vai. Không chặn: vòng vẽ lấy cảnh mới nhất ở khung kế tiếp.
    public func setScene(_ scene: RenderScene, for role: OutputRole) {
        mailboxes[role]?.post(scene)
    }

    /// Cảnh mới nhất của một vai (vòng vẽ đọc mỗi khung, từ luồng vẽ).
    nonisolated func latestScene(for role: OutputRole) -> MailboxEntry<RenderScene>? {
        mailboxes[role]?.latest()
    }

    /// Dựng một cảnh ra ảnh, không cần màn hình. Dùng cho test ảnh và ảnh thu nhỏ.
    ///
    /// - Parameters:
    ///   - scene: cảnh cần dựng.
    ///   - previous: cảnh đang hiện trước đó. Có thì `scene` được gửi lúc 0 giây và chuyển cảnh theo
    ///     `scene.transition`; không có thì `scene` hiện ngay, không chuyển cảnh.
    ///   - size: kích thước ảnh ra (điểm ảnh). Khác tỉ lệ khung vẽ thì khung vẽ nằm giữa, phần thừa tô màu nền.
    ///   - time: thời điểm dựng, tính bằng giây kể từ lúc gửi `scene`.
    ///   - mediaLocator: tìm tệp ảnh.
    nonisolated public static func renderOffscreen(
        _ scene: RenderScene,
        after previous: RenderScene? = nil,
        size: PixelSize,
        at time: Double,
        mediaLocator: any MediaLocator = NoMediaLocator()
    ) async throws -> CGImage {
        let box: UncheckedSendableBox<CGImage> = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    with: Result<UncheckedSendableBox<CGImage>, any Error> {
                        let image = try OffscreenRenderer.render(
                            scene,
                            after: previous,
                            size: size,
                            at: time,
                            mediaLocator: mediaLocator
                        )
                        return UncheckedSendableBox(image)
                    }
                )
            }
        }
        return box.value
    }
}

/// Dựng ngoài màn hình. Thiết bị Metal và pipeline dùng chung cho mọi lần gọi; đệm texture riêng từng lần.
enum OffscreenRenderer {
    final class Shared: @unchecked Sendable {
        let gpu: GPUContext
        let pipelines: Compositor

        init() throws {
            gpu = try GPUContext()
            pipelines = try Compositor(gpu: gpu)
        }
    }

    static let shared: Result<Shared, any Error> = Result { try Shared() }

    static func render(
        _ scene: RenderScene,
        after previous: RenderScene?,
        size: PixelSize,
        at time: Double,
        mediaLocator: any MediaLocator
    ) throws -> CGImage {
        let shared = try shared.get()
        let gpu = shared.gpu
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let targetSize = CGSize(width: width, height: height)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let bytesPerRow = width * 4
        guard let target = gpu.device.makeTexture(descriptor: descriptor),
            let readback = gpu.device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
            let commandBuffer = gpu.commandQueue.makeCommandBuffer()
        else {
            throw RenderEngineError.textureUnavailable
        }
        commandBuffer.label = "Offscreen"

        let cache = TextureCache(device: gpu.device, mediaLocator: mediaLocator)
        let compositor = LayerCompositor(gpu: gpu, pipelines: shared.pipelines, cache: cache, blocking: true)
        if let previous {
            var settled = previous
            settled.transition = .cut
            compositor.update(scene: settled, targetSize: targetSize, time: 0)
            compositor.update(scene: scene, targetSize: targetSize, time: 0)
        } else {
            var settled = scene
            settled.transition = .cut
            compositor.update(scene: settled, targetSize: targetSize, time: 0)
        }
        compositor.encode(into: commandBuffer, target: target, time: time)

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(
                from: target,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: readback,
                destinationOffset: 0,
                destinationBytesPerRow: bytesPerRow,
                destinationBytesPerImage: bytesPerRow * height
            )
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw RenderEngineError.gpuFailed(String(describing: error))
        }

        let data = Data(bytes: readback.contents(), count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let provider = CGDataProvider(data: data as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw RenderEngineError.textureUnavailable
        }
        return image
    }
}

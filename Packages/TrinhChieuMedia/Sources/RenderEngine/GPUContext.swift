import CoreVideo
import Foundation
import Metal

/// Lỗi khi khởi tạo hoặc dùng lõi dựng hình.
public enum RenderEngineError: Error, Equatable, Sendable {
    case noMetalDevice
    case commandQueueUnavailable
    case shaderLibraryUnavailable(String)
    case pipelineUnavailable(String)
    case textureCacheUnavailable(Int32)
    case textureUnavailable
}

/// Thiết bị Metal dùng chung cho toàn ứng dụng. Tạo một lần, chia sẻ cho mọi đầu ra.
///
/// `MTLDevice`, `MTLCommandQueue` và `MTLLibrary` an toàn khi dùng từ nhiều luồng.
/// `CVMetalTextureCache` được tạo một lần và chỉ dùng để tạo texture từ khung video.
public final class GPUContext: @unchecked Sendable {
    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue
    public let library: any MTLLibrary
    public let textureCache: CVMetalTextureCache

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderEngineError.noMetalDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw RenderEngineError.commandQueueUnavailable
        }
        queue.label = "TrinhChieu.RenderEngine"
        self.device = device
        self.commandQueue = queue
        self.library = try Self.loadLibrary(device: device)

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else {
            throw RenderEngineError.textureCacheUnavailable(status)
        }
        self.textureCache = cache
    }

    /// Xcode biên dịch `Shaders/*.metal` thành `default.metallib` trong bundle của gói.
    /// `swift build` chỉ chép tệp nguồn, nên khi đó biên dịch shader lúc chạy.
    static func loadLibrary(device: any MTLDevice) throws -> any MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module),
            library.makeFunction(name: "quad_vertex") != nil
        {
            return library
        }
        guard let url = Bundle.module.url(forResource: "Compose", withExtension: "metal") else {
            throw RenderEngineError.shaderLibraryUnavailable("Không tìm thấy Compose.metal trong bundle")
        }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RenderEngineError.shaderLibraryUnavailable(String(describing: error))
        }
    }
}

import CoreModel
import Foundation
import Metal
import Testing

@testable import RenderEngine

@Suite("TextureCache", .enabled(if: hasMetal))
struct TextureCacheTests {
    private func makeCache(byteLimit: Int = TextureCache.defaultByteLimit) throws -> TextureCache {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return TextureCache(device: device, mediaLocator: TestMedia.locator, byteLimit: byteLimit)
    }

    @Test("Hỏi không chặn: lần đầu đang dựng, sau đó có texture")
    func asyncLookup() async throws {
        let cache = try makeCache()
        let key = TextureKey.color(SceneKit.navy)
        guard case .pending = cache.lookup(key, blocking: false) else {
            Issue.record("Lần đầu phải đang dựng")
            return
        }
        for _ in 0..<200 {
            if case .ready = cache.lookup(key, blocking: false) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Texture không xong sau 2 giây")
    }

    @Test("Hỏi chặn: có texture ngay, màu đã nhân alpha")
    func blockingLookup() throws {
        let cache = try makeCache()
        guard case .ready(let cached) = cache.lookup(.color(SceneKit.navy), blocking: true) else {
            Issue.record("Phải có texture ngay")
            return
        }
        #expect(cached.texture.width == 1)
        #expect(cache.byteCount == 4)
    }

    @Test("Vượt giới hạn dung lượng: bỏ texture dùng lâu nhất")
    func evictsLeastRecentlyUsed() throws {
        let cache = try makeCache(byteLimit: 8)
        let first = TextureKey.color(SceneKit.red)
        let second = TextureKey.color(SceneKit.blue)
        let third = TextureKey.color(SceneKit.green)
        _ = cache.lookup(first, blocking: true)
        _ = cache.lookup(second, blocking: true)
        _ = cache.lookup(first, blocking: true)  // dùng lại: `second` thành cũ nhất
        _ = cache.lookup(third, blocking: true)
        #expect(cache.byteCount == 8)
        guard case .pending = cache.lookup(second, blocking: false) else {
            Issue.record("`second` phải bị bỏ khỏi đệm")
            return
        }
    }

    @Test("Ảnh mất: báo lỗi, không thử lại ngay")
    func missingImageFails() throws {
        let cache = try makeCache()
        let key = TextureKey.image(ImageKey(media: TestMedia.missingID, pixelWidth: 100, pixelHeight: 100, fit: .fill))
        guard case .failed = cache.lookup(key, blocking: true) else {
            Issue.record("Phải báo lỗi")
            return
        }
        guard case .failed = cache.lookup(key, blocking: false) else {
            Issue.record("Không thử lại ngay")
            return
        }
    }

    @Test("Ảnh giải mã đúng kích thước cần vẽ, không giải mã cả ảnh gốc")
    func decodesAtTargetSize() throws {
        let cache = try makeCache()
        let key = TextureKey.image(ImageKey(media: TestMedia.splitID, pixelWidth: 200, pixelHeight: 100, fit: .fit))
        guard case .ready(let cached) = cache.lookup(key, blocking: true) else {
            Issue.record("Phải có texture")
            return
        }
        #expect(cached.texture.width == 200)
        #expect(cached.texture.height == 100)
    }

    @Test("Cạnh dài cần giải mã theo cách đặt")
    func decodeLongEdge() {
        let image = CGSize(width: 4000, height: 2000)
        let frame = CGSize(width: 1000, height: 1000)
        #expect(ImageLoader.decodeLongEdge(imageSize: image, frame: frame, fit: .fit) == 1000)
        #expect(ImageLoader.decodeLongEdge(imageSize: image, frame: frame, fit: .fill) == 2000)
        // Ảnh nhỏ hơn khung: không phóng to khi giải mã.
        #expect(ImageLoader.decodeLongEdge(imageSize: CGSize(width: 400, height: 200), frame: frame, fit: .fill) == 400)
    }
}

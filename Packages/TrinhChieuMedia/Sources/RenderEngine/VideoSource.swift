import AVFoundation
import CoreVideo
import Foundation
import Metal
import QuartzCore

/// Một video phát lặp. Mỗi đầu ra lấy khung qua một `VideoTap` riêng (một `AVPlayerItemVideoOutput` riêng),
/// nên hai đầu ra không giành khung của nhau.
@MainActor
public final class VideoSource {
    public let url: URL
    public let player: AVPlayer
    private let item: AVPlayerItem
    private var endObserver: (any NSObjectProtocol)?

    public init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        self.item = item
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restart()
            }
        }
    }

    /// Dừng phát và bỏ theo dõi điểm kết thúc. Gọi khi không dùng nguồn này nữa.
    public func invalidate() {
        player.pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    /// Tạo một nguồn khung cho một đầu ra.
    public func makeTap(gpu: GPUContext) -> VideoTap {
        let attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        return VideoTap(output: output, textureCache: gpu.textureCache)
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    private func restart() {
        player.seek(to: .zero)
        player.play()
    }
}

/// Lấy khung video cho một đầu ra. Chỉ dùng trên luồng vẽ của đầu ra đó.
public final class VideoTap: @unchecked Sendable {
    private let output: AVPlayerItemVideoOutput
    private let textureCache: CVMetalTextureCache
    private var current: CVMetalTexture?

    init(output: AVPlayerItemVideoOutput, textureCache: CVMetalTextureCache) {
        self.output = output
        self.textureCache = textureCache
    }

    /// Khung ứng với thời điểm hiển thị `hostTime` (theo `CACurrentMediaTime`).
    /// Chưa có khung mới thì trả lại khung trước đó; chưa từng có khung nào thì `nil`.
    /// `retain` phải được giữ sống tới khi command buffer dựng xong.
    public func frame(forHostTime hostTime: CFTimeInterval) -> (texture: any MTLTexture, retain: AnyObject)? {
        let itemTime = output.itemTime(forHostTime: hostTime)
        if output.hasNewPixelBuffer(forItemTime: itemTime),
            let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        {
            var texture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                CVPixelBufferGetWidth(pixelBuffer),
                CVPixelBufferGetHeight(pixelBuffer),
                0,
                &texture
            )
            if status == kCVReturnSuccess, let texture {
                current = texture
            }
        }
        guard let current, let texture = CVMetalTextureGetTexture(current) else { return nil }
        return (texture, current as AnyObject)
    }
}

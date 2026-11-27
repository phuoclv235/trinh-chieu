import AVFoundation
import CoreGraphics
import CoreModel
import Foundation
import Metal
import os

/// Một khung video sẵn để vẽ. `retain` phải sống tới khi command buffer dựng xong (ví dụ `CVMetalTexture`).
struct VideoFrame {
    let texture: any MTLTexture
    let retain: AnyObject?
}

/// Video của một phần tử đã sẵn chưa.
enum VideoAvailability: Equatable {
    /// Đã có ít nhất một khung.
    case ready
    /// Đang mở tệp hoặc chờ khung đầu tiên: giữ lớp cũ.
    case pending
    /// Tệp mất hoặc không giải mã được: bỏ phần tử này (lớp vẫn hiện), báo trên màn điều khiển.
    case failed
}

/// Bên dùng khung video: mỗi đầu ra (và mỗi bản xem trước) một bên, để không giành khung của nhau.
struct VideoConsumer: Hashable, Sendable {
    let id: UUID
    let role: OutputRole
    /// Đầu ra thật thì `true`; bản xem trước thì `false`: xem trước không bao giờ làm video phát tiếng.
    let audible: Bool

    init(role: OutputRole, audible: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.audible = audible
    }
}

/// Nguồn khung video cho bộ trộn lớp. Gọi từ luồng vẽ; không bao giờ chặn.
protocol VideoFrameProvider: AnyObject, Sendable {
    /// - Parameters:
    ///   - frame: cỡ khung vẽ của video trên đầu ra (điểm ảnh), để giải mã đúng cỡ.
    ///   - fit: cách đặt video trong khung.
    func availability(
        of video: VideoRef,
        for consumer: VideoConsumer,
        frame: CGSize,
        fit: ContentFit
    ) -> VideoAvailability
    /// Khung ứng với thời điểm `time` của vòng vẽ (đầu ra thật: thời điểm lên màn theo `CACurrentMediaTime`).
    /// Chưa có khung mới thì trả khung trước; chưa từng có thì `nil`.
    func frame(of video: VideoRef, for consumer: VideoConsumer, at time: Double) -> VideoFrame?
}

/// Khung video tĩnh cho `renderOffscreen`: giải mã sẵn (bất đồng bộ) một khung cho mỗi video trước khi dựng.
final class StillVideoProvider: VideoFrameProvider, @unchecked Sendable {
    private let frames: [UUID: VideoFrame]
    private let failed: Set<UUID>

    private init(frames: [UUID: VideoFrame], failed: Set<UUID>) {
        self.frames = frames
        self.failed = failed
    }

    /// Không có video nào.
    static let empty = StillVideoProvider(frames: [:], failed: [])

    /// Giải mã khung ở giây `time` (tính từ lúc video bắt đầu phát) của mọi video trong các cảnh.
    /// Video lặp thì lấy `time` theo vòng lặp; video không lặp mà `time` quá độ dài thì lấy khung cuối.
    static func prepare(
        scenes: [RenderScene],
        at time: Double,
        mediaLocator: any MediaLocator,
        device: any MTLDevice
    ) async -> StillVideoProvider {
        var videos: [UUID: VideoRef] = [:]
        for scene in scenes {
            for layer in scene.layers {
                for item in layer.items {
                    if case .video(let video, _, _) = item {
                        videos[video.playbackID] = video
                    }
                }
            }
        }
        guard !videos.isEmpty else { return .empty }
        var frames: [UUID: VideoFrame] = [:]
        var failed: Set<UUID> = []
        for (playbackID, video) in videos {
            guard let url = mediaLocator.url(for: video.media.id),
                let image = await Self.image(url: url, at: time, loop: video.loop),
                let texture = TextRasterizer.makeTexture(ImageLoader.bitmap(from: image), device: device)
            else {
                failed.insert(playbackID)
                continue
            }
            frames[playbackID] = VideoFrame(texture: texture, retain: nil)
        }
        return StillVideoProvider(frames: frames, failed: failed)
    }

    private static func image(url: URL, at time: Double, loop: Bool) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }
        var seconds = max(0, time)
        if loop {
            seconds = seconds.truncatingRemainder(dividingBy: duration.seconds)
        } else {
            seconds = min(seconds, max(0, duration.seconds - 0.001))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        return try? await generator.image(at: cmTime).image
    }

    func availability(
        of video: VideoRef,
        for consumer: VideoConsumer,
        frame: CGSize,
        fit: ContentFit
    ) -> VideoAvailability {
        if frames[video.playbackID] != nil { return .ready }
        return failed.contains(video.playbackID) ? .failed : .pending
    }

    func frame(of video: VideoRef, for consumer: VideoConsumer, at time: Double) -> VideoFrame? {
        frames[video.playbackID]
    }
}

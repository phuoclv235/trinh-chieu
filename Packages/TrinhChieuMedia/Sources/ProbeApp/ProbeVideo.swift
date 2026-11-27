import AVFoundation
import CoreVideo
import Foundation
import Metal
import QuartzCore
import RenderEngine
import os

/// Nguồn video của bản thử T0.6. Giống `VideoSource` của RenderEngine, thêm các cờ thử:
/// - `looper`: lặp bằng `AVPlayerLooper` (không `seek` trên luồng chính), biện pháp B3.
/// - kích thước giải mã riêng cho từng đầu ra (biện pháp B4, `--decode-size output`).
/// - hỏi "có khung mới chưa" mà không lấy khung, để vẽ theo nhu cầu (B1).
@MainActor
final class ProbeVideoSource {
    let url: URL
    let usesLooper: Bool
    private let player: AVPlayer
    private let item: AVPlayerItem?
    private var looper: AVPlayerLooper?
    private var endObserver: (any NSObjectProtocol)?
    private var itemObservation: NSKeyValueObservation?
    private var taps: [ProbeVideoTap] = []
    /// Các thời điểm (theo `CACurrentMediaTime`) video bắt đầu phát từ đầu.
    private(set) var loopStarts: [CFTimeInterval] = []

    init(url: URL, looper: Bool) {
        self.url = url
        self.usesLooper = looper
        if looper {
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.automaticallyWaitsToMinimizeStalling = false
            let template = AVPlayerItem(url: url)
            self.looper = AVPlayerLooper(player: queue, templateItem: template)
            self.player = queue
            self.item = nil
            itemObservation = queue.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
                // KVO của AVFoundation có thể gọi trên luồng bất kỳ.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.currentItemChanged()
                    }
                }
            }
        } else {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
            self.player = player
            self.item = item
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
    }

    /// Kích thước khung gốc của video, `nil` khi không đọc được.
    nonisolated static func naturalSize(of url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
            let size = try? await track.load(.naturalSize)
        else { return nil }
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    /// Tạo nguồn khung cho một đầu ra. `decodeSize` khác `nil` thì yêu cầu AVFoundation trả khung ở cỡ đó.
    func makeTap(gpu: GPUContext, decodeSize: CGSize?) -> ProbeVideoTap {
        var attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        if let decodeSize {
            attributes[kCVPixelBufferWidthKey as String] = Int(decodeSize.width)
            attributes[kCVPixelBufferHeightKey as String] = Int(decodeSize.height)
        }
        let tap = ProbeVideoTap(attributes: attributes, textureCache: gpu.textureCache)
        for item in playerItems() {
            tap.attach(to: item)
        }
        taps.append(tap)
        return tap
    }

    func play() {
        if loopStarts.isEmpty {
            loopStarts.append(CACurrentMediaTime())
        }
        player.play()
    }

    func invalidate() {
        player.pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        itemObservation?.invalidate()
        itemObservation = nil
        looper?.disableLooping()
    }

    private func playerItems() -> [AVPlayerItem] {
        if let looper {
            var items = looper.loopingPlayerItems
            if let current = player.currentItem, !items.contains(where: { $0 === current }) {
                items.append(current)
            }
            return items
        }
        return item.map { [$0] } ?? []
    }

    private func currentItemChanged() {
        // Bản sao mới của mục lặp (nếu có) cũng phải có đầu ra khung cho mọi đầu ra.
        for item in playerItems() {
            for tap in taps {
                tap.attach(to: item)
            }
        }
        if !loopStarts.isEmpty {
            loopStarts.append(CACurrentMediaTime())
        }
    }

    private func restart() {
        player.seek(to: .zero)
        player.play()
        loopStarts.append(CACurrentMediaTime())
    }
}

/// Lấy khung video cho một đầu ra. `frame` và `hasNewFrame` chỉ dùng trên luồng vẽ của đầu ra đó;
/// `attach` chạy trên luồng chính.
final class ProbeVideoTap: @unchecked Sendable {
    private struct Attached {
        var item: AVPlayerItem
        var output: AVPlayerItemVideoOutput
    }

    private let attributes: [String: any Sendable]
    private let textureCache: CVMetalTextureCache
    private let outputs = OSAllocatedUnfairLock<[UncheckedSendableBox<Attached>]>(initialState: [])
    /// Chỉ đọc ghi trên luồng vẽ.
    private var current: CVMetalTexture?

    init(attributes: [String: any Sendable], textureCache: CVMetalTextureCache) {
        self.attributes = attributes
        self.textureCache = textureCache
    }

    /// Gắn một đầu ra khung vào `item` nếu chưa gắn.
    @MainActor
    func attach(to item: AVPlayerItem) {
        let exists = outputs.withLock { $0 }.contains { $0.value.item === item }
        guard !exists else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        let entry = UncheckedSendableBox(Attached(item: item, output: output))
        outputs.withLock { $0.append(entry) }
    }

    private var attachedOutputs: [AVPlayerItemVideoOutput] {
        // `withLock` chỉ trả về được giá trị `Sendable`, nên lấy bản sao danh sách hộp rồi mở hộp ngoài khoá.
        outputs.withLock { $0 }.map(\.value.output)
    }

    /// Có khung mới cho thời điểm hiển thị `hostTime` hay không (không lấy khung ra).
    func hasNewFrame(forHostTime hostTime: CFTimeInterval) -> Bool {
        attachedOutputs.contains { output in
            output.hasNewPixelBuffer(forItemTime: output.itemTime(forHostTime: hostTime))
        }
    }

    /// Khung ứng với `hostTime`. Chưa có khung mới thì trả lại khung trước đó; chưa từng có khung nào thì `nil`.
    func frame(forHostTime hostTime: CFTimeInterval) -> (texture: any MTLTexture, retain: AnyObject)? {
        for output in attachedOutputs {
            let itemTime = output.itemTime(forHostTime: hostTime)
            guard output.hasNewPixelBuffer(forItemTime: itemTime),
                let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
            else { continue }
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
            break
        }
        guard let current, let texture = CVMetalTextureGetTexture(current) else { return nil }
        return (texture, current as AnyObject)
    }

    /// Cỡ khung đang có (để ghi vào báo cáo cỡ giải mã thật).
    var currentSize: CGSize? {
        guard let current, let texture = CVMetalTextureGetTexture(current) else { return nil }
        return CGSize(width: texture.width, height: texture.height)
    }
}

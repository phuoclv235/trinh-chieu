import AVFoundation
import CoreModel
import CoreVideo
import Foundation
import Metal
import QuartzCore
import os

/// Một `AVPlayer` cho mỗi `playbackID` đang dùng, chung cho mọi đầu ra.
///
/// - `playbackID` mới thì phát từ đầu; cùng `playbackID` thì giữ nguyên (đổi chữ trên nền video không khởi động lại).
/// - Lặp bằng `AVPlayerLooper`, không `seek` khi hết bài (bản thử T0.4: rớt khung dồn quanh điểm tua).
/// - Mỗi bên dùng (đầu ra, bản xem trước) có `AVPlayerItemVideoOutput` riêng trên từng item trong hàng đợi của
///   player (looper nhân bản item), nên không giành khung của nhau và có khung sẵn ngay lúc chuyển vòng lặp.
/// - Tiếng: theo `VideoRef.muted`; video chỉ hiện trên vai `stage` thì luôn tắt tiếng.
/// - Bỏ player `idleTimeout` giây sau lần cuối có bên lấy khung (đủ cho hoà tan).
///
/// Luồng vẽ chỉ đọc trạng thái dưới khoá và không bao giờ chờ; tạo, gắn và bỏ player làm trên luồng chính.
final class VideoPlayerPool: VideoFrameProvider, @unchecked Sendable {
    static let idleTimeout: TimeInterval = 2
    /// Vai chính không lấy khung quá chừng này giây (đã thôi chiếu video) thì tắt tiếng dù vai nhắc còn chiếu.
    static let programGrace: TimeInterval = 0.5

    /// Tiếng chỉ phát khi `VideoRef` không tắt tiếng và vai chính đang chiếu video này.
    static func shouldMute(_ video: VideoRef, programLastUse: CFTimeInterval?, now: CFTimeInterval) -> Bool {
        guard !video.muted, let programLastUse else { return true }
        return now - programLastUse > programGrace
    }

    private final class Entry: @unchecked Sendable {
        let video: VideoRef
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var observations: [NSKeyValueObservation] = []
        var taps: [VideoConsumer: PoolTap] = [:]
        /// Lần cuối mỗi vai lấy khung; vai chính thôi lấy quá `programGrace` giây thì tắt tiếng.
        var roleLastUse: [OutputRole: CFTimeInterval] = [:]
        var failed = false
        var lastUse: CFTimeInterval

        init(video: VideoRef, now: CFTimeInterval) {
            self.video = video
            lastUse = now
        }
    }

    private let gpu: GPUContext
    private let mediaLocator: any MediaLocator
    private let health: SourceHealth?
    /// Mọi trường của `Entry` chỉ đọc ghi dưới khoá này.
    private let entries = OSAllocatedUnfairLock<[UUID: Entry]>(initialState: [:])
    private let audioDevice = OSAllocatedUnfairLock<String?>(initialState: nil)
    private let logger = Logger(subsystem: "app.trinhchieu.RenderEngine", category: "VideoPlayerPool")
    /// Chỉ dùng trên luồng chính.
    private var sweepTimer: Timer?

    init(gpu: GPUContext, mediaLocator: any MediaLocator, health: SourceHealth? = nil) {
        self.gpu = gpu
        self.mediaLocator = mediaLocator
        self.health = health
    }

    /// Số player đang giữ.
    var playerCount: Int { entries.withLockUnchecked { $0.count } }

    // MARK: - Luồng vẽ

    func availability(of video: VideoRef, for consumer: VideoConsumer) -> VideoAvailability {
        let now = CACurrentMediaTime()
        enum Action {
            case none
            case createPlayer
            case refresh
        }
        let (result, action): (VideoAvailability, Action) = entries.withLockUnchecked { entries in
            guard let entry = entries[video.playbackID] else {
                let entry = Entry(video: video, now: now)
                entry.roleLastUse[consumer.role] = now
                entry.taps[consumer] = PoolTap(textureCache: gpu.textureCache)
                entries[video.playbackID] = entry
                return (.pending, .createPlayer)
            }
            entry.lastUse = now
            if entry.failed { return (.failed, .none) }
            var action = Action.none
            if entry.roleLastUse.updateValue(now, forKey: consumer.role) == nil { action = .refresh }
            guard let tap = entry.taps[consumer] else {
                entry.taps[consumer] = PoolTap(textureCache: gpu.textureCache)
                return (.pending, .refresh)
            }
            return (tap.hasFrame ? .ready : .pending, action)
        }
        switch action {
        case .none:
            break
        case .createPlayer:
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated { createPlayer(video.playbackID) }
            }
        case .refresh:
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated { refresh(video.playbackID) }
            }
        }
        if result == .pending, action != .createPlayer, let tap = tap(video.playbackID, consumer),
            tap.frame(forHostTime: now) != nil
        {
            // Khung đầu tiên vừa tới: nhận ngay ở khung này.
            return .ready
        }
        return result
    }

    private func tap(_ playbackID: UUID, _ consumer: VideoConsumer) -> PoolTap? {
        entries.withLockUnchecked { $0[playbackID]?.taps[consumer] }
    }

    func frame(of video: VideoRef, for consumer: VideoConsumer, at time: Double) -> VideoFrame? {
        let now = CACurrentMediaTime()
        let tap: PoolTap? = entries.withLockUnchecked { entries in
            guard let entry = entries[video.playbackID] else { return nil }
            entry.lastUse = now
            entry.roleLastUse[consumer.role] = now
            return entry.taps[consumer]
        }
        return tap?.frame(forHostTime: time)
    }

    // MARK: - Luồng chính

    /// Thiết bị ra âm thanh (`AVPlayer.audioOutputDeviceUniqueID`); `nil` theo hệ thống.
    @MainActor
    func setAudioOutputDevice(_ uniqueID: String?) {
        audioDevice.withLockUnchecked { $0 = uniqueID }
        let players = entries.withLockUnchecked { entries in entries.values.compactMap { $0.player } }
        for player in players {
            player.audioOutputDeviceUniqueID = uniqueID
        }
    }

    @MainActor
    private func createPlayer(_ playbackID: UUID) {
        startSweeping()
        guard let entry = entries.withLockUnchecked({ $0[playbackID] }) else { return }
        let video = entry.video
        guard let url = mediaLocator.url(for: video.media.id), FileManager.default.fileExists(atPath: url.path)
        else {
            markFailed(playbackID, reason: "Không tìm thấy tệp video")
            return
        }
        let template = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audioOutputDeviceUniqueID = audioDevice.withLockUnchecked { $0 }
        var looper: AVPlayerLooper?
        if video.loop {
            looper = AVPlayerLooper(player: player, templateItem: template)
        } else {
            player.actionAtItemEnd = .pause
            player.insert(template, after: nil)
        }
        let current = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refresh(playbackID) }
            }
        }
        let status = player.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
            guard player.currentItem?.status == .failed else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.markFailed(playbackID, reason: "Không giải mã được video") }
            }
        }
        entries.withLockUnchecked { _ in
            entry.player = player
            entry.looper = looper
            entry.observations = [current, status]
        }
        refresh(playbackID)
        player.play()
    }

    /// Gắn output cho mọi item đang trong hàng đợi của player, báo item đang phát cho từng bên dùng, đặt tiếng.
    @MainActor
    private func refresh(_ playbackID: UUID) {
        let snapshot: (Entry, AVQueuePlayer, [PoolTap], CFTimeInterval?)? = entries.withLockUnchecked { entries in
            guard let entry = entries[playbackID], let player = entry.player else { return nil }
            return (entry, player, Array(entry.taps.values), entry.roleLastUse[.program])
        }
        guard let snapshot else { return }
        let (entry, player, taps, programLastUse) = snapshot
        player.isMuted = Self.shouldMute(entry.video, programLastUse: programLastUse, now: CACurrentMediaTime())
        let items = player.items()
        for tap in taps {
            tap.sync(items: items, current: player.currentItem)
        }
    }

    @MainActor
    private func markFailed(_ playbackID: UUID, reason: String) {
        let entry: Entry? = entries.withLockUnchecked { entries in
            guard let entry = entries[playbackID] else { return nil }
            entry.failed = true
            return entry
        }
        guard let entry else { return }
        logger.warning("\(reason, privacy: .public): \(entry.video.media.id.rawValue, privacy: .private)")
        health?.report(.videoFailed(entry.video.media.id), message: reason)
    }

    @MainActor
    private func startSweeping() {
        guard sweepTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    /// Bỏ các player không còn ai lấy khung trong `idleTimeout` giây.
    @MainActor
    func sweep(now: CFTimeInterval = CACurrentMediaTime()) {
        let stale: [Entry] = entries.withLockUnchecked { entries in
            let stale = entries.values.filter { now - $0.lastUse > Self.idleTimeout }
            for entry in stale {
                entries[entry.video.playbackID] = nil
            }
            return stale
        }
        for entry in stale {
            let (observations, looper, player) = entries.withLockUnchecked { _ in
                (entry.observations, entry.looper, entry.player)
            }
            for observation in observations {
                observation.invalidate()
            }
            looper?.disableLooping()
            player?.pause()
            player?.removeAllItems()
        }
        let live: [(AVQueuePlayer, Bool)] = entries.withLockUnchecked { entries in
            entries.values.compactMap { entry -> (AVQueuePlayer, Bool)? in
                guard let player = entry.player else { return nil }
                let mute = Self.shouldMute(entry.video, programLastUse: entry.roleLastUse[.program], now: now)
                return (player, mute)
            }
        }
        for (player, mute) in live where player.isMuted != mute {
            player.isMuted = mute
        }
        if entries.withLockUnchecked({ $0.isEmpty }) {
            sweepTimer?.invalidate()
            sweepTimer = nil
        }
    }

    /// Dừng mọi player (khi tắt lõi dựng hình).
    @MainActor
    func invalidate() {
        sweep(now: .infinity)
    }
}

/// Nguồn khung của một bên dùng cho một player: một `AVPlayerItemVideoOutput` trên mỗi item trong hàng đợi.
/// `sync` gọi trên luồng chính; `frame` gọi trên luồng vẽ của bên dùng.
final class PoolTap: @unchecked Sendable {
    private struct State {
        var outputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
        var current: ObjectIdentifier?
        var hasFrame = false
    }

    private let textureCache: CVMetalTextureCache
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    /// Khung gần nhất; chỉ luồng vẽ đọc ghi.
    private var last: CVMetalTexture?

    init(textureCache: CVMetalTextureCache) {
        self.textureCache = textureCache
    }

    /// Đã từng có khung nào chưa.
    var hasFrame: Bool { state.withLockUnchecked { $0.hasFrame } }

    @MainActor
    func sync(items: [AVPlayerItem], current: AVPlayerItem?) {
        let attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var outputs = state.withLockUnchecked { $0.outputs }
        let live = Set(items.map(ObjectIdentifier.init))
        outputs = outputs.filter { live.contains($0.key) }
        for item in items where outputs[ObjectIdentifier(item)] == nil {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
            output.suppressesPlayerRendering = true
            item.add(output)
            outputs[ObjectIdentifier(item)] = output
        }
        let currentID = current.map(ObjectIdentifier.init)
        state.withLockUnchecked { state in
            state.outputs = outputs
            state.current = currentID
        }
    }

    func frame(forHostTime hostTime: CFTimeInterval) -> VideoFrame? {
        let output: AVPlayerItemVideoOutput? = state.withLockUnchecked { state in
            state.current.flatMap { state.outputs[$0] }
        }
        if let output {
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
                    last = texture
                    state.withLockUnchecked { $0.hasFrame = true }
                }
            }
        }
        // Tệp bị xoá hay item lỗi: giữ khung cuối, không bao giờ trả về khung trống.
        guard let last, let texture = CVMetalTextureGetTexture(last) else { return nil }
        return VideoFrame(texture: texture, retain: last)
    }
}

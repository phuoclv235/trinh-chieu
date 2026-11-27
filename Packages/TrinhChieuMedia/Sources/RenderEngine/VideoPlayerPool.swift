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
/// - Tiếng: theo `VideoRef.muted`; chỉ phát khi đầu ra thật của vai chính đang chiếu video.
/// - Giải mã ở cỡ vẽ trên đầu ra, không lớn hơn cỡ gốc (T0.6, B4); đầu ra đổi độ phân giải thì tính lại.
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

    /// Ghi lần lấy khung của một bên dùng vào `roleLastUse` (chỉ bên phát tiếng được, bản xem trước thì bỏ qua).
    /// Trả `true` khi vai này lần đầu xuất hiện, để đặt lại tiếng.
    @discardableResult
    static func noteUse(
        _ roleLastUse: inout [OutputRole: CFTimeInterval],
        by consumer: VideoConsumer,
        now: CFTimeInterval
    ) -> Bool {
        guard consumer.audible else { return false }
        return roleLastUse.updateValue(now, forKey: consumer.role) == nil
    }

    /// Cảnh mới giữ `playbackID` nhưng đổi cài đặt video: tắt tiếng thì đặt lại tiếng, lặp thì dựng lại player.
    enum SettingsChange: Equatable {
        case none
        case muted
        case loop
    }

    static func settingsChange(from old: VideoRef, to new: VideoRef) -> SettingsChange {
        if old.loop != new.loop || old.media != new.media { return .loop }
        return old.muted != new.muted ? .muted : .none
    }

    /// Cỡ giải mã cho khung vẽ `frame` (điểm ảnh) theo cách đặt `fit`: giữ tỉ lệ video, không phóng to quá cỡ gốc,
    /// làm tròn lên số chẵn. `stretch` thì đúng cỡ khung (vẫn không lớn hơn cỡ gốc).
    static func decodeSize(video: CGSize, frame: CGSize, fit: ContentFit) -> CGSize {
        guard video.width > 0, video.height > 0, frame.width > 0, frame.height > 0 else { return video }
        func even(_ value: CGFloat) -> CGFloat {
            // Bỏ sai số dấu phẩy động (1000.0000001 không thành 1002).
            max(2, (value / 2 - 1e-6).rounded(.up) * 2)
        }
        let scaleX = frame.width / video.width
        let scaleY = frame.height / video.height
        switch fit {
        case .stretch:
            return CGSize(width: even(video.width * min(1, scaleX)), height: even(video.height * min(1, scaleY)))
        case .fill, .fit:
            let scale = min(1, fit == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY))
            return CGSize(width: even(video.width * scale), height: even(video.height * scale))
        }
    }

    private final class Entry: @unchecked Sendable {
        var video: VideoRef
        /// Cỡ gốc của video (đã xoay theo `preferredTransform`), `nil` khi chưa đọc xong.
        var naturalSize: CGSize?
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

    func availability(
        of video: VideoRef,
        for consumer: VideoConsumer,
        frame: CGSize,
        fit: ContentFit
    ) -> VideoAvailability {
        let now = CACurrentMediaTime()
        enum Action {
            case none
            case createPlayer
            case refresh
            case rebuild
        }
        let (result, action): (VideoAvailability, Action) = entries.withLockUnchecked { entries in
            guard let entry = entries[video.playbackID] else {
                let entry = Entry(video: video, now: now)
                Self.noteUse(&entry.roleLastUse, by: consumer, now: now)
                let tap = PoolTap(textureCache: gpu.textureCache)
                tap.want(frame: frame, fit: fit)
                entry.taps[consumer] = tap
                entries[video.playbackID] = entry
                return (.pending, .createPlayer)
            }
            entry.lastUse = now
            var action = Action.none
            switch Self.settingsChange(from: entry.video, to: video) {
            case .none:
                break
            case .muted:
                entry.video = video
                action = .refresh
            case .loop:
                entry.video = video
                entry.failed = false
                action = .rebuild
            }
            if entry.failed { return (.failed, .none) }
            if Self.noteUse(&entry.roleLastUse, by: consumer, now: now) { action = .refresh }
            guard let tap = entry.taps[consumer] else {
                let tap = PoolTap(textureCache: gpu.textureCache)
                tap.want(frame: frame, fit: fit)
                entry.taps[consumer] = tap
                return (.pending, .refresh)
            }
            if tap.want(frame: frame, fit: fit), action == .none { action = .refresh }
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
        case .rebuild:
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated { rebuildPlayer(video.playbackID) }
            }
        }
        let fresh = action == .createPlayer || action == .rebuild
        if result == .pending, !fresh, let tap = tap(video.playbackID, consumer), tap.frame(forHostTime: now) != nil {
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
            Self.noteUse(&entry.roleLastUse, by: consumer, now: now)
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
        let playerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            let size = await Self.naturalSize(of: url)
            guard let self, let size else { return }
            let current = entries.withLockUnchecked { entries -> Bool in
                guard let entry = entries[playbackID], let live = entry.player, ObjectIdentifier(live) == playerID
                else { return false }
                entry.naturalSize = size
                return true
            }
            if current { refresh(playbackID) }
        }
    }

    /// Cỡ hiển thị của track hình đầu tiên (đã xoay theo `preferredTransform`).
    private static func naturalSize(of url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
            let loaded = try? await track.load(.naturalSize, .preferredTransform)
        else { return nil }
        let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// Bỏ player cũ (giữ khung cuối ở các bên dùng) rồi tạo player mới theo cài đặt hiện tại của video.
    @MainActor
    private func rebuildPlayer(_ playbackID: UUID) {
        guard let entry = entries.withLockUnchecked({ $0[playbackID] }) else { return }
        let (observations, looper, player) = entries.withLockUnchecked { _ in
            let old = (entry.observations, entry.looper, entry.player)
            entry.observations = []
            entry.looper = nil
            entry.player = nil
            return old
        }
        Self.tearDown(observations: observations, looper: looper, player: player)
        createPlayer(playbackID)
    }

    @MainActor
    private static func tearDown(
        observations: [NSKeyValueObservation],
        looper: AVPlayerLooper?,
        player: AVQueuePlayer?
    ) {
        for observation in observations {
            observation.invalidate()
        }
        looper?.disableLooping()
        player?.pause()
        player?.removeAllItems()
    }

    /// Gắn output cho mọi item đang trong hàng đợi của player, báo item đang phát cho từng bên dùng, đặt tiếng.
    @MainActor
    private func refresh(_ playbackID: UUID) {
        typealias Snapshot = (Entry, AVQueuePlayer, [PoolTap], CFTimeInterval?, CGSize?)
        let snapshot: Snapshot? = entries.withLockUnchecked { entries in
            guard let entry = entries[playbackID], let player = entry.player else { return nil }
            return (entry, player, Array(entry.taps.values), entry.roleLastUse[.program], entry.naturalSize)
        }
        guard let snapshot else { return }
        let (entry, player, taps, programLastUse, naturalSize) = snapshot
        player.isMuted = Self.shouldMute(entry.video, programLastUse: programLastUse, now: CACurrentMediaTime())
        let items = player.items()
        for tap in taps {
            tap.sync(items: items, current: player.currentItem, naturalSize: naturalSize)
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
            Self.tearDown(observations: observations, looper: looper, player: player)
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
    private struct Attached {
        let item: AVPlayerItem
        let output: AVPlayerItemVideoOutput
    }

    private struct State {
        var outputs: [ObjectIdentifier: Attached] = [:]
        var current: ObjectIdentifier?
        var hasFrame = false
        /// Khung vẽ (điểm ảnh) và cách đặt mà bên dùng cần; luồng vẽ ghi, luồng chính đọc.
        var wanted: (frame: CGSize, fit: ContentFit)?
        /// Cỡ giải mã của các output đang gắn (`nil`: cỡ gốc).
        var decodeSize: CGSize?
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

    /// Ghi khung vẽ mà bên dùng cần. Trả `true` khi khác lần trước (cần tính lại cỡ giải mã).
    @discardableResult
    func want(frame: CGSize, fit: ContentFit) -> Bool {
        state.withLockUnchecked { state in
            if let wanted = state.wanted, wanted.frame == frame, wanted.fit == fit { return false }
            state.wanted = (frame, fit)
            return true
        }
    }

    /// Gắn output cho các item mới, bỏ output của item đã rời hàng đợi, đổi cỡ giải mã khi cần.
    @MainActor
    func sync(items: [AVPlayerItem], current: AVPlayerItem?, naturalSize: CGSize?) {
        let (attached, wanted, previous) = state.withLockUnchecked { ($0.outputs, $0.wanted, $0.decodeSize) }
        var outputs = attached
        var applied = previous
        var size: CGSize?
        if let naturalSize, let wanted {
            size = VideoPlayerPool.decodeSize(video: naturalSize, frame: wanted.frame, fit: wanted.fit)
        }
        if size != applied {
            // Cỡ giải mã đổi: thay mọi output; khung cuối vẫn giữ tới khi có khung ở cỡ mới.
            for old in outputs.values {
                old.item.remove(old.output)
            }
            outputs.removeAll()
            applied = size
        }
        let live = Set(items.map(ObjectIdentifier.init))
        outputs = outputs.filter { live.contains($0.key) }
        var attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        if let size {
            attributes[kCVPixelBufferWidthKey as String] = Int(size.width)
            attributes[kCVPixelBufferHeightKey as String] = Int(size.height)
        }
        for item in items where outputs[ObjectIdentifier(item)] == nil {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
            output.suppressesPlayerRendering = true
            item.add(output)
            outputs[ObjectIdentifier(item)] = Attached(item: item, output: output)
        }
        let currentID = current.map(ObjectIdentifier.init)
        state.withLockUnchecked { state in
            state.outputs = outputs
            state.current = currentID
            state.decodeSize = applied
        }
    }

    func frame(forHostTime hostTime: CFTimeInterval) -> VideoFrame? {
        let output: AVPlayerItemVideoOutput? = state.withLockUnchecked { state in
            state.current.flatMap { state.outputs[$0]?.output }
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

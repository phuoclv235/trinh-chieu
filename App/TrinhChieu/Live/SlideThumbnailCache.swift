import CoreGraphics
import CoreModel
import Foundation
import Observation
import RenderEngine
import os

/// Ảnh thu nhỏ 320x180 của thẻ trang chiếu, dựng bằng `RenderEngine.renderOffscreen` ở nền.
///
/// Mỗi lần chỉ dựng một ảnh, độ ưu tiên thấp, để máy còn sức cho đầu ra, Zoom và trình duyệt chạy cùng buổi nhóm.
/// Ảnh lưu đệm theo ``ThumbnailKey`` (mã trang, băm nội dung, mã mẫu); đệm giữ tối đa ``capacity`` ảnh, bỏ ảnh dùng
/// lâu nhất trước.
@MainActor @Observable final class SlideThumbnailCache {
    /// Khoảng 230 KB mỗi ảnh: 240 ảnh chừng 55 MB.
    static let capacity = 240

    private struct Job {
        let key: ThumbnailKey
        let scene: RenderScene
    }

    @ObservationIgnored private var images: [ThumbnailKey: CGImage] = [:]
    /// Thứ tự dùng, cũ trước mới sau.
    @ObservationIgnored private var recency: [ThumbnailKey] = []
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var queued: Set<ThumbnailKey> = []
    @ObservationIgnored private var failed: Set<ThumbnailKey> = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    private let mediaLocator: any MediaLocator
    /// Bộ dựng cảnh riêng (bộ dựng nhớ lần phát video nền, không dùng chung với `ShowController`).
    private let resolver = SceneResolver()
    private let logger = Logger(subsystem: "app.trinhchieu.TrinhChieu", category: "Thumbnails")

    /// Gọi khi một ảnh dựng xong, để lưới gán ảnh cho thẻ đang hiện.
    @ObservationIgnored var onRendered: ((ThumbnailKey) -> Void)?

    /// Tăng mỗi khi có ảnh mới dựng xong: danh sách trang của trình soạn đọc số này để gán ảnh.
    private(set) var renderedCount = 0

    init(mediaLocator: any MediaLocator) {
        self.mediaLocator = mediaLocator
    }

    func image(for key: ThumbnailKey) -> CGImage? {
        guard let image = images[key] else { return nil }
        if let position = recency.lastIndex(of: key), position != recency.count - 1 {
            recency.remove(at: position)
            recency.append(key)
        }
        return image
    }

    /// Xếp hàng dựng ảnh cho các thẻ chưa có ảnh, theo thứ tự truyền vào. Hàng cũ bị thay (đổi nguồn thì
    /// không dựng tiếp ảnh của nguồn trước).
    func prepare(_ cards: [SlideCard], sequence: SlideSequence, provider: any ShowContentProvider) {
        queue.removeAll()
        queued.removeAll()
        let theme = provider.theme(sequence.themeID)
        for card in cards where images[card.thumbnail] == nil && !failed.contains(card.thumbnail) {
            guard queued.insert(card.thumbnail).inserted, sequence.slides.indices.contains(card.index) else {
                continue
            }
            let scene = Self.scene(
                for: sequence.slides[card.index].slide, at: card.index, in: sequence, theme: theme,
                provider: provider, resolver: resolver)
            queue.append(Job(key: card.thumbnail, scene: scene))
        }
        pump()
    }

    /// Bỏ hết ảnh (ví dụ khi đổi thư viện).
    func removeAll() {
        queue.removeAll()
        queued.removeAll()
        images.removeAll()
        recency.removeAll()
        failed.removeAll()
    }

    // MARK: - Dựng

    /// Cảnh của một trang như khi nó lên màn đầu ra chính: nền riêng của trang, không thì nền của mẫu.
    static func scene(
        for slide: Slide, at index: Int, in sequence: SlideSequence, theme: Theme,
        provider: any ShowContentProvider, resolver: SceneResolver
    ) -> RenderScene {
        let epoch = Date(timeIntervalSince1970: 0)
        var state = ShowState()
        state.live = LivePosition(source: sequence.source, slideIndex: index, slideID: slide.id, wentLiveAt: epoch)
        state.layers[.slide] = .slide(slideID: slide.id)
        if slide.background.kind != .none {
            state.layers[.background] = .background(slide.background, origin: slide.id)
        } else {
            state.layers[.background] = .background(theme.background, origin: theme.id)
        }
        return resolver.resolve(state: state, provider: provider, now: epoch).program
    }

    private func pump() {
        guard worker == nil, !queue.isEmpty else { return }
        let locator = mediaLocator
        worker = Task(priority: .utility) { [weak self] in
            while let job = self?.dequeue() {
                let rendered = await Self.render(job.scene, locator: locator)
                self?.finish(job.key, image: rendered?.image)
            }
            self?.worker = nil
            self?.pump()
        }
    }

    private func dequeue() -> Job? {
        guard !queue.isEmpty else { return nil }
        let job = queue.removeFirst()
        queued.remove(job.key)
        return job
    }

    private func finish(_ key: ThumbnailKey, image: CGImage?) {
        guard let image else {
            failed.insert(key)
            logger.warning("Không dựng được ảnh thu nhỏ của trang \(key.slideID.uuidString, privacy: .public)")
            return
        }
        images[key] = image
        recency.removeAll { $0 == key }
        recency.append(key)
        if recency.count > Self.capacity {
            let evicted = recency.prefix(recency.count - Self.capacity)
            for old in evicted {
                images[old] = nil
            }
            recency.removeFirst(evicted.count)
        }
        renderedCount &+= 1
        onRendered?(key)
    }

    /// Dựng một trang ở cỡ lớn cho khung vẽ của trình soạn (không lưu đệm). `nil` khi dựng lỗi.
    func renderLarge(
        _ slide: Slide, at index: Int, in sequence: SlideSequence, provider: any ShowContentProvider, size: PixelSize
    ) async -> CGImage? {
        let scene = Self.scene(
            for: slide, at: index, in: sequence, theme: provider.theme(sequence.themeID), provider: provider,
            resolver: resolver)
        let locator = mediaLocator
        return await Self.renderImage(scene, size: size, locator: locator)?.image
    }

    nonisolated private static func renderImage(
        _ scene: RenderScene, size: PixelSize, locator: any MediaLocator
    ) async -> RenderedImage? {
        do {
            let image = try await RenderEngine.renderOffscreen(scene, size: size, at: 0.5, mediaLocator: locator)
            return RenderedImage(image: image)
        } catch {
            return nil
        }
    }

    nonisolated private static func render(_ scene: RenderScene, locator: any MediaLocator) async -> RenderedImage? {
        do {
            let image = try await RenderEngine.renderOffscreen(
                scene, size: PixelSize(width: 320, height: 180), at: 0.5, mediaLocator: locator)
            return RenderedImage(image: image)
        } catch {
            return nil
        }
    }
}

/// Ảnh vừa dựng, chuyển từ luồng dựng về luồng chính. `CGImage` không đổi sau khi tạo nên chuyển an toàn.
private final class RenderedImage: @unchecked Sendable {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }
}

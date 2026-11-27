import CoreGraphics
import CoreModel
import Foundation
import Metal
import os

/// Khoá của một khối chữ đã dựng: toàn bộ `TextBlock` cùng kích thước khung theo điểm ảnh đầu ra.
struct TextBlockKey: Hashable, Sendable {
    let string: String
    let style: ResolvedTextStyle
    let autoFit: AutoFit
    let maxLines: Int?
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double

    init(_ block: TextBlock, pixelWidth: Int, pixelHeight: Int, scale: Double) {
        string = block.string
        style = block.style
        autoFit = block.autoFit
        maxLines = block.maxLines
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
    }

    var block: TextBlock {
        TextBlock(string: string, style: style, autoFit: autoFit, maxLines: maxLines)
    }
}

/// Khoá của một ảnh đã giải mã: mã media và kích thước giải mã (suy từ khung và cách đặt).
struct ImageKey: Hashable, Sendable {
    let media: MediaID
    let pixelWidth: Int
    let pixelHeight: Int
    let fit: ContentFit
}

/// Thứ cần có texture để vẽ.
enum TextureKey: Hashable, Sendable {
    case color(RGBA)
    case text(TextBlockKey)
    case image(ImageKey)
}

/// Texture đã sẵn cùng thông tin phụ (ví dụ phần chừa quanh chữ).
struct CachedTexture: @unchecked Sendable {
    let texture: any MTLTexture
    /// Điểm ảnh chừa thêm mỗi phía quanh khung (chỉ chữ dùng).
    let padding: Int
    /// Chữ bị cắt dòng cuối vì vẫn tràn sau khi co.
    let truncated: Bool

    var cost: Int { texture.width * texture.height * 4 }
}

/// Kết quả hỏi texture.
enum TextureLookup {
    case ready(CachedTexture)
    /// Đang dựng trên hàng đợi nền.
    case pending
    /// Nguồn lỗi (tệp mất, giải mã hỏng). Lớp vẫn hiện, bỏ qua phần tử này.
    case failed
}

/// Đệm texture cho chữ, ảnh và màu. Giới hạn theo dung lượng, bỏ phần dùng lâu nhất trước.
///
/// Vòng vẽ chỉ hỏi và không bao giờ chờ: chưa có thì xếp lịch dựng trên hàng đợi nền và trả `.pending`.
/// Dựng ngoài màn hình (`renderOffscreen`) thì dựng ngay trên luồng gọi.
final class TextureCache: Sendable {
    /// Giới hạn mặc định: 512 MB.
    static let defaultByteLimit = 512 * 1024 * 1024
    /// Nguồn lỗi được thử lại sau khoảng này (tệp có thể được chép lại vào thư viện).
    static let failureRetryInterval: TimeInterval = 5

    private enum Entry {
        case ready(CachedTexture, lastUse: UInt64)
        case pending
        case failed(at: Date)
    }

    private struct State: @unchecked Sendable {
        var entries: [TextureKey: Entry] = [:]
        var bytes = 0
        var clock: UInt64 = 0
    }

    private let device: UncheckedSendableBox<any MTLDevice>
    private let mediaLocator: any MediaLocator
    private let byteLimit: Int
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let textQueue = DispatchQueue(label: "TrinhChieu.TextureCache.text", qos: .userInitiated)
    private let imageQueue = DispatchQueue(
        label: "TrinhChieu.TextureCache.image",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let logger = Logger(subsystem: "app.trinhchieu.RenderEngine", category: "TextureCache")

    init(device: any MTLDevice, mediaLocator: any MediaLocator, byteLimit: Int = TextureCache.defaultByteLimit) {
        self.device = UncheckedSendableBox(device)
        self.mediaLocator = mediaLocator
        self.byteLimit = byteLimit
    }

    /// Dung lượng texture đang giữ (byte).
    var byteCount: Int { state.withLock { $0.bytes } }

    /// Hỏi texture cho `key`. `blocking` dựng ngay trên luồng gọi khi chưa có.
    func lookup(_ key: TextureKey, blocking: Bool) -> TextureLookup {
        enum Decision: Sendable {
            case found(UncheckedSendableBox<CachedTexture>)
            case wait
            case fail
            case produceNow
            case schedule
        }
        let now = Date()
        let decision: Decision = state.withLock { state in
            state.clock += 1
            switch state.entries[key] {
            case .ready(let cached, _):
                state.entries[key] = .ready(cached, lastUse: state.clock)
                return .found(UncheckedSendableBox(cached))
            case .pending:
                return blocking ? .produceNow : .wait
            case .failed(let at) where now.timeIntervalSince(at) < Self.failureRetryInterval:
                return .fail
            case .failed, nil:
                if blocking { return .produceNow }
                state.entries[key] = .pending
                return .schedule
            }
        }
        switch decision {
        case .found(let box):
            return .ready(box.value)
        case .wait:
            return .pending
        case .fail:
            return .failed
        case .produceNow:
            let made = produce(key)
            store(key, made)
            return made.map { .ready($0) } ?? .failed
        case .schedule:
            let queue: DispatchQueue
            switch key {
            case .image: queue = imageQueue
            case .text, .color: queue = textQueue
            }
            queue.async { [self] in
                store(key, produce(key))
            }
            return .pending
        }
    }

    private func store(_ key: TextureKey, _ made: CachedTexture?) {
        let box = UncheckedSendableBox(made)
        let failedKey = state.withLock { state -> Bool in
            if case .ready(let old, _) = state.entries[key] {
                state.bytes -= old.cost
            }
            guard let made = box.value else {
                state.entries[key] = .failed(at: Date())
                return true
            }
            state.clock += 1
            state.entries[key] = .ready(made, lastUse: state.clock)
            state.bytes += made.cost
            evictIfNeeded(&state, keep: key)
            return false
        }
        if failedKey {
            logger.warning("Không dựng được texture cho \(String(describing: key), privacy: .public)")
        }
    }

    /// Bỏ các texture dùng lâu nhất tới khi dưới giới hạn. Lớp đang hiện tự giữ texture của nó,
    /// nên bỏ khỏi đệm không làm mất hình trên màn.
    private func evictIfNeeded(_ state: inout State, keep: TextureKey) {
        guard state.bytes > byteLimit else { return }
        var candidates: [(key: TextureKey, lastUse: UInt64, cost: Int)] = []
        for (key, entry) in state.entries where key != keep {
            if case .ready(let cached, let lastUse) = entry {
                candidates.append((key, lastUse, cached.cost))
            }
        }
        candidates.sort { $0.lastUse < $1.lastUse }
        for candidate in candidates {
            guard state.bytes > byteLimit else { break }
            state.entries[candidate.key] = nil
            state.bytes -= candidate.cost
        }
    }

    private func produce(_ key: TextureKey) -> CachedTexture? {
        let device = device.value
        switch key {
        case .color(let color):
            let bitmap = BGRABitmap(width: 1, height: 1, bytesPerRow: 4, pixels: color.premultipliedBGRA)
            return TextRasterizer.makeTexture(bitmap, device: device).map {
                CachedTexture(texture: $0, padding: 0, truncated: false)
            }
        case .text(let textKey):
            let result = TextRenderer.render(
                textKey.block,
                frameSize: CGSize(width: textKey.pixelWidth, height: textKey.pixelHeight),
                scale: textKey.scale
            )
            if result.truncated {
                logger.warning("Chữ tràn khung sau khi co, đã cắt dòng cuối: \(textKey.string, privacy: .private)")
            }
            return TextRasterizer.makeTexture(result.bitmap, device: device).map {
                CachedTexture(texture: $0, padding: result.padding, truncated: result.truncated)
            }
        case .image(let imageKey):
            guard let url = mediaLocator.url(for: imageKey.media),
                let bitmap = ImageLoader.load(
                    url: url,
                    frame: CGSize(width: imageKey.pixelWidth, height: imageKey.pixelHeight),
                    fit: imageKey.fit
                )
            else { return nil }
            return TextRasterizer.makeTexture(bitmap, device: device).map {
                CachedTexture(texture: $0, padding: 0, truncated: false)
            }
        }
    }
}

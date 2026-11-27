import CoreModel
import Foundation
import LibraryStore
import RenderEngine
import os

/// Ghi log của lõi (`LogSink`) vào nhật ký hệ thống (`Logger`).
struct OSLogSink: LogSink {
    let subsystem = "app.trinhchieu.TrinhChieu"

    func log(_ entry: LogEntry) {
        let logger = Logger(subsystem: subsystem, category: entry.category)
        switch entry.level {
        case .debug:
            logger.debug("\(entry.message, privacy: .public)")
        case .info:
            logger.info("\(entry.message, privacy: .public)")
        case .warning:
            logger.warning("\(entry.message, privacy: .public)")
        case .error:
            logger.error("\(entry.message, privacy: .public)")
        }
    }
}

/// Tìm tệp media cho lõi dựng hình. Vòng vẽ gọi từ luồng riêng, nên giữ một bản sao bảng media sau khoá nhẹ;
/// luồng chính cập nhật bảng mỗi khi thư viện đổi.
final class LibraryMediaLocator: MediaLocator {
    private let table = OSAllocatedUnfairLock<[MediaID: URL]>(initialState: [:])

    func url(for id: MediaID) -> URL? {
        table.withLock { $0[id] }
    }

    @MainActor func update(from store: LibraryStore?) {
        var next: [MediaID: URL] = [:]
        if let store {
            for id in store.media.keys {
                if let url = store.mediaURL(id) {
                    next[id] = url
                }
            }
        }
        table.withLock { $0 = next }
    }
}

/// Nơi nhận cảnh của `ShowController`: đầu ra đi thẳng vào hộp thư của lõi dựng hình (không chặn), xem trước giữ lại
/// cho giao diện.
@MainActor final class AppSceneSink: SceneSink {
    private let engine: RenderEngine
    /// Cảnh xem trước mới nhất (khi tập dượt, khác với cảnh trên đầu ra).
    private(set) var latestPreview: ScenePublication?

    init(engine: RenderEngine) {
        self.engine = engine
    }

    func publishToOutputs(_ publication: ScenePublication) {
        engine.setScene(publication.program, for: .program)
        engine.setScene(publication.stage, for: .stage)
    }

    func publishToPreview(_ publication: ScenePublication) {
        latestPreview = publication
    }
}

import Foundation
import Synchronization

/// Một lô thay đổi trên đĩa trong thư mục thư viện.
public struct FileChangeEvent: Sendable, Hashable {
    /// Tệp hoặc thư mục bị đổi. Thư mục nghĩa là cần quét lại cả thư mục đó.
    public var urls: [URL]
    /// Bộ theo dõi bỏ lỡ sự kiện (FSEvents báo `MustScanSubDirs`): quét lại toàn bộ thư viện.
    public var rescanAll: Bool

    public init(urls: [URL], rescanAll: Bool = false) {
        self.urls = urls
        self.rescanAll = rescanAll
    }
}

/// Theo dõi thay đổi trong thư mục thư viện do chương trình khác gây ra (iCloud Drive, Dropbox).
///
/// Bản Mac dùng FSEvents, đặt ở `TrinhChieuMedia` hoặc App vì cần CoreServices. Linux và test dùng
/// ``ManualFileWatcher``; không cần theo dõi thì dùng ``NoFileWatching``.
public protocol FileWatching: Sendable {
    /// Luồng sự kiện thay đổi trong `root`. Luồng kết thúc khi người nhận ngừng lặp.
    func changes(in root: URL) -> AsyncStream<FileChangeEvent>
}

/// Không theo dõi gì.
public struct NoFileWatching: FileWatching {
    public init() {}

    public func changes(in root: URL) -> AsyncStream<FileChangeEvent> {
        AsyncStream { $0.finish() }
    }
}

/// Bộ theo dõi gửi sự kiện bằng tay: dùng cho test và trên Linux.
public final class ManualFileWatcher: FileWatching {
    private let continuations = Mutex<[UUID: AsyncStream<FileChangeEvent>.Continuation]>([:])

    public init() {}

    public func changes(in root: URL) -> AsyncStream<FileChangeEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: FileChangeEvent.self)
        let key = UUID()
        continuations.withLock { $0[key] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.continuations.withLock { $0.removeValue(forKey: key) }
        }
        return stream
    }

    /// Gửi một sự kiện tới mọi người đang theo dõi.
    public func send(_ event: FileChangeEvent) {
        let targets = continuations.withLock { Array($0.values) }
        for continuation in targets {
            continuation.yield(event)
        }
    }

    /// Gửi sự kiện đổi một tệp.
    public func send(changedFile url: URL) {
        send(FileChangeEvent(urls: [url]))
    }
}

import CoreServices
import Foundation
import LibraryStore

/// Theo dõi thư mục thư viện bằng FSEvents, để thay đổi do chương trình khác gây ra (iCloud Drive, Dropbox, sửa tay)
/// được `LibraryStore` nạp lại. Gom sự kiện 0,3 giây một lô.
struct FSEventsWatcher: FileWatching {
    func changes(in root: URL) -> AsyncStream<FileChangeEvent> {
        AsyncStream { continuation in
            let sink = EventSink(continuation)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(sink).toOpaque(),
                retain: nil,
                release: { info in
                    guard let info else { return }
                    Unmanaged<EventSink>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
                guard let info else { return }
                let sink = Unmanaged<EventSink>.fromOpaque(info).takeUnretainedValue()
                let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                var rescanAll = false
                for index in 0..<count {
                    let flag = flags[index]
                    if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
                        || flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
                    {
                        rescanAll = true
                    }
                }
                sink.continuation.yield(
                    FileChangeEvent(urls: list.map { URL(fileURLWithPath: $0) }, rescanAll: rescanAll))
            }
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagWatchRoot)
            guard
                let stream = FSEventStreamCreate(
                    kCFAllocatorDefault, callback, &context, [root.path] as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
            else {
                Unmanaged<EventSink>.fromOpaque(context.info!).release()
                continuation.finish()
                return
            }
            let handle = StreamHandle(stream)
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "app.trinhchieu.fsevents", qos: .utility))
            FSEventStreamStart(stream)
            continuation.onTermination = { _ in handle.stop() }
        }
    }
}

private final class EventSink: Sendable {
    let continuation: AsyncStream<FileChangeEvent>.Continuation

    init(_ continuation: AsyncStream<FileChangeEvent>.Continuation) {
        self.continuation = continuation
    }
}

/// Giữ luồng FSEvents để dừng khi người nhận ngừng lặp.
private final class StreamHandle: @unchecked Sendable {
    private let stream: FSEventStreamRef

    init(_ stream: FSEventStreamRef) {
        self.stream = stream
    }

    func stop() {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

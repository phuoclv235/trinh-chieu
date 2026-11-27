import Foundation

/// Mức độ của dòng log.
public enum LogLevel: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case debug
    case info
    case warning
    case error

    private var rank: Int {
        switch self {
        case .debug:
            return 0
        case .info:
            return 1
        case .warning:
            return 2
        case .error:
            return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Một dòng log.
public struct LogEntry: Sendable, Hashable {
    public var level: LogLevel
    public var category: String
    public var message: String

    public init(level: LogLevel, category: String, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }
}

/// Nơi ghi log của lõi. Phía Mac nối vào `Logger` của `os`; lõi không dùng `print`.
public protocol LogSink: Sendable {
    func log(_ entry: LogEntry)
}

extension LogSink {
    public func log(_ level: LogLevel, _ message: String, category: String) {
        log(LogEntry(level: level, category: category, message: message))
    }
}

/// Bỏ qua mọi dòng log.
public struct NullLogSink: LogSink {
    public init() {}

    public func log(_ entry: LogEntry) {}
}

/// Giữ log trong bộ nhớ, dùng cho test.
public final class InMemoryLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LogEntry] = []

    public init() {}

    public var entries: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func log(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(entry)
    }
}

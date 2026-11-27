import Foundation

/// Loại sự kiện trong nhật ký buổi nhóm.
public enum ServiceLogEventType: String, Sendable, Hashable, Codable, CaseIterable {
    case goLive
    case clearLayer
    case clearAll
    case freeze
    case rehearsal
}

/// Một sự kiện trong nhật ký buổi nhóm (xem `docs/dinh-dang-tep.md` mục 8).
public struct ServiceLogEvent: Sendable, Hashable, Codable {
    public var at: Date
    public var type: ServiceLogEventType
    public var itemID: UUID?
    public var presentationID: UUID?
    public var slideID: UUID?
    public var layer: LayerKind?
    /// Bật hay tắt, với `freeze` và `rehearsal`.
    public var enabled: Bool?

    public init(
        at: Date, type: ServiceLogEventType, itemID: UUID? = nil, presentationID: UUID? = nil, slideID: UUID? = nil,
        layer: LayerKind? = nil, enabled: Bool? = nil
    ) {
        self.at = at
        self.type = type
        self.itemID = itemID
        self.presentationID = presentationID
        self.slideID = slideID
        self.layer = layer
        self.enabled = enabled
    }
}

/// Tệp nhật ký buổi nhóm (`logs/<yyyy-mm-dd>-<uuid>.json`).
public struct ServiceLog: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var planID: UUID?
    public var startedAt: Date
    public var events: [ServiceLogEvent]

    public init(
        schemaVersion: Int = DocumentMigration.currentSchemaVersion, planID: UUID? = nil, startedAt: Date,
        events: [ServiceLogEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.planID = planID
        self.startedAt = startedAt
        self.events = events
    }
}

/// Nơi nhận sự kiện nhật ký. Bản ghi đĩa làm ở T1.3.
@MainActor public protocol ServiceLogSink: AnyObject {
    func record(_ event: ServiceLogEvent)
}

/// Nhật ký giữ trong bộ nhớ, dùng cho test.
@MainActor public final class InMemoryServiceLog: ServiceLogSink {
    public private(set) var events: [ServiceLogEvent] = []

    public init() {}

    public func record(_ event: ServiceLogEvent) {
        events.append(event)
    }
}

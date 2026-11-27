import CoreModel
import Foundation
import os

/// Vấn đề của một nguồn (tệp mất, giải mã lỗi, chữ tràn, phông thiếu) hoặc của một đầu ra.
/// Chỉ báo trên màn điều khiển qua `RenderEngine.statistics`, không bao giờ hiện lên đầu ra.
public enum RenderIssue: Hashable, Sendable {
    case imageFailed(MediaID)
    case videoFailed(MediaID)
    /// Chữ vẫn tràn sau khi co tới `minScale`, dòng cuối bị cắt.
    case textTruncated
    case fontMissing(String)
    /// Màn của đầu ra bị rút ra; đầu ra đã tự gỡ.
    case outputDetached(OutputID)
}

/// Một cảnh báo kèm lời mô tả tiếng Việt cho màn điều khiển.
public struct RenderWarning: Hashable, Sendable {
    public let issue: RenderIssue
    public let message: String
}

/// Ghi nhận nguồn lỗi. Lớp đang hiện giữ texture cuối của nó, nên nguồn lỗi chỉ làm phần tử đó không đổi
/// hoặc không vẽ; ở đây chỉ gom cảnh báo (mỗi vấn đề một lần mỗi chu kỳ) để `statistics` phát ra.
public final class SourceHealth: Sendable {
    private let pending = OSAllocatedUnfairLock<[RenderWarning]>(initialState: [])
    private let logger = Logger(subsystem: "app.trinhchieu.RenderEngine", category: "SourceHealth")

    public init() {}

    func report(_ issue: RenderIssue, message: String) {
        let warning = RenderWarning(issue: issue, message: message)
        let isNew = pending.withLock { warnings in
            guard !warnings.contains(warning) else { return false }
            warnings.append(warning)
            return true
        }
        if isNew {
            logger.warning("\(message, privacy: .public)")
        }
    }

    /// Lấy và xoá các cảnh báo đã gom.
    func drain() -> [RenderWarning] {
        pending.withLock { warnings in
            let drained = warnings
            warnings.removeAll()
            return drained
        }
    }
}

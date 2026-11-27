import CoreModel
import Foundation

/// Nguồn của một lớp: thứ cần dựng, kèm mã nội dung để quyết định chuyển cảnh.
protocol LayerSource: Equatable {
    var contentID: UUID { get }
}

/// Trạng thái hiển thị của một `LayerKind`: một lớp đang hiện và (khi đang chuyển cảnh) một lớp đang tới.
///
/// Thuần logic, không đụng GPU, để test được. `Content` là thứ đã dựng xong (texture), `Source` là thứ cần dựng.
/// - `contentID` đổi: dựng lớp mới; chưa dựng xong thì giữ nguyên lớp cũ (không bao giờ vẽ lớp trống thay thế).
///   Dựng xong thì hoà tan (`dissolve`, thời lượng lớn hơn 0) hoặc thay ngay (`cut`).
/// - `contentID` giữ nguyên nhưng nội dung khác (ví dụ đổi kích thước đầu ra): thay tại chỗ khi dựng xong,
///   không chuyển cảnh.
/// - Lớp biến mất khỏi cảnh: chuyển sang "trống" theo cùng quy tắc.
struct LayerSlot<Source: LayerSource, Content> {
    struct Shown {
        /// `nil` là lớp trống (không vẽ gì).
        var source: Source?
        var content: Content?

        static var empty: Shown { Shown(source: nil, content: nil) }
    }

    struct Transition {
        var from: Shown
        var to: Shown
        var start: Double
        var duration: Double
    }

    enum Plan {
        case nothing
        case steady(Content)
        /// Hoà tan: `from` hoặc `to` có thể trống. `t` đã qua hàm êm.
        case dissolve(from: Content?, to: Content?, t: Double)
    }

    private(set) var shown: Shown = .empty
    private(set) var transition: Transition?

    /// Lớp đang hiện hoặc đang tới (đích hiện tại).
    var target: Shown { transition?.to ?? shown }

    /// Không còn gì để vẽ và không chuyển cảnh: có thể bỏ ô này.
    var isIdle: Bool { transition == nil && shown.source == nil }

    /// Cập nhật theo nguồn mới của khung này.
    /// - Parameters:
    ///   - source: nguồn lớp trong cảnh mới nhất, `nil` khi lớp không có trong cảnh.
    ///   - spec: chuyển cảnh của cảnh mới nhất.
    ///   - time: thời điểm của khung (giây).
    ///   - resolve: dựng nguồn; `nil` khi chưa xong.
    mutating func update(
        source: Source?,
        spec: TransitionSpec,
        time: Double,
        resolve: (Source) -> Content?
    ) {
        finishTransitionIfDone(at: time)
        let current = target
        if current.source == source { return }

        let next: Shown
        if let source {
            guard let content = resolve(source) else { return }
            next = Shown(source: source, content: content)
        } else {
            next = .empty
        }

        if let currentID = current.source?.contentID, currentID == source?.contentID {
            // Cùng nội dung, chỉ dựng lại: thay tại chỗ, không chuyển cảnh.
            if transition != nil {
                transition?.to = next
            } else {
                shown = next
            }
            return
        }

        if spec.kind == .dissolve, spec.duration > 0 {
            // Đang hoà tan dở mà có cảnh mới: lấy lớp đang tới làm điểm xuất phát.
            transition = Transition(from: current, to: next, start: time, duration: spec.duration)
        } else {
            transition = nil
            shown = next
        }
    }

    /// Kết thúc chuyển cảnh nếu đã hết thời lượng.
    mutating func finishTransitionIfDone(at time: Double) {
        guard let transition, time >= transition.start + transition.duration else { return }
        shown = transition.to
        self.transition = nil
    }

    /// Cách vẽ lớp ở thời điểm `time`.
    func plan(at time: Double) -> Plan {
        if let transition {
            let progress = (time - transition.start) / transition.duration
            if progress < 1 {
                return .dissolve(
                    from: transition.from.content,
                    to: transition.to.content,
                    t: smoothstep(progress)
                )
            }
            return transition.to.content.map { .steady($0) } ?? .nothing
        }
        return shown.content.map { .steady($0) } ?? .nothing
    }
}

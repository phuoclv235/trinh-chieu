import CoreGraphics
import Foundation
import RenderEngine

/// Một màn đang cắm, đã đọc xong thông tin (không giữ `NSScreen` để test được).
struct DisplayDescriptor: Equatable, Hashable, Sendable, Identifiable {
    /// UUID ổn định của màn (`CGDisplayCreateUUIDFromDisplayID`).
    let uuid: String
    let displayID: UInt32
    let name: String
    /// Khung theo toạ độ chung của macOS (điểm), dùng vẽ sơ đồ sắp xếp.
    let frame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Int
    let isBuiltIn: Bool

    var id: String { uuid }
}

/// Tính đầu ra nào cần gắn vào màn nào từ cài đặt và các màn đang cắm. Thuần, không đụng AppKit.
enum OutputPlanner {
    struct Plan: Equatable {
        /// Đầu ra cần có: mã đầu ra → (màn, vai).
        var outputs: [OutputID: Target]
        /// Vai đã gán nhưng màn đang vắng (rút ra, tắt).
        var missing: [OutputAssignment]
        /// Vai đã gán cho màn đang chứa cửa sổ chính: chưa gắn để không che cửa sổ điều khiển.
        var blocked: [OutputAssignment]
    }

    struct Target: Equatable {
        var display: DisplayDescriptor
        var role: OutputRole
    }

    /// Mã đầu ra cố định theo màn, để cắm lại thì nhận lại đúng mã.
    static func outputID(forDisplay uuid: String) -> OutputID {
        OutputID("display-\(uuid)")
    }

    /// - Parameters:
    ///   - assignments: vai đã lưu trong cài đặt.
    ///   - displays: các màn đang cắm.
    ///   - controlDisplayUUID: màn đang chứa cửa sổ chính.
    ///   - attached: đầu ra đang gắn. Đầu ra đã gắn không bị gỡ chỉ vì cửa sổ chính vừa kéo sang màn đó (gỡ giữa
    ///     buổi nhóm làm mất hình trên đầu ra); chỉ lần gắn mới bị chặn.
    static func plan(
        assignments: [OutputAssignment], displays: [DisplayDescriptor], controlDisplayUUID: String?,
        attached: Set<OutputID> = []
    ) -> Plan {
        var plan = Plan(outputs: [:], missing: [], blocked: [])
        let byUUID = Dictionary(displays.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for assignment in assignments {
            guard let display = byUUID[assignment.displayUUID] else {
                plan.missing.append(assignment)
                continue
            }
            let id = outputID(forDisplay: display.uuid)
            if display.uuid == controlDisplayUUID, !attached.contains(id) {
                plan.blocked.append(assignment)
                continue
            }
            plan.outputs[id] = Target(display: display, role: assignment.role)
        }
        return plan
    }

    /// Thứ tự hiển thị các màn (cũng là số "Hiện số trên từng màn"): trái sang phải, trên xuống dưới.
    static func ordered(_ displays: [DisplayDescriptor]) -> [DisplayDescriptor] {
        displays.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.maxY > rhs.frame.maxY
        }
    }
}

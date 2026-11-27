import CoreModel
import Foundation

/// Giờ dự kiến của chương trình buổi nhóm: giờ bắt đầu của từng mục tính dồn từ `plannedStart` theo thời lượng
/// dự kiến của các mục trước (mục chưa đặt thời lượng tính là 0).
struct PlanSchedule: Equatable {
    /// Giờ bắt đầu dự kiến của từng mục; trống khi chương trình chưa có giờ bắt đầu hoặc ngày sai dạng.
    let starts: [UUID: Date]
    /// Giờ bắt đầu và kết thúc dự kiến của cả chương trình.
    let start: Date?
    let end: Date?

    init(plan: ServicePlan, calendar: Calendar = .current) {
        guard let start = Self.startDate(of: plan, calendar: calendar) else {
            starts = [:]
            self.start = nil
            end = nil
            return
        }
        var cursor = start
        var starts: [UUID: Date] = [:]
        for item in plan.items {
            starts[item.id] = cursor
            cursor = cursor.addingTimeInterval(max(0, item.plannedDuration ?? 0))
        }
        self.starts = starts
        self.start = start
        end = cursor
    }

    /// Ngày nhóm (`yyyy-MM-dd`) ghép giờ bắt đầu (`HH:mm`).
    static func startDate(of plan: ServicePlan, calendar: Calendar = .current) -> Date? {
        guard let plannedStart = plan.plannedStart, let day = day(plan.date, calendar: calendar),
            let time = clock(plannedStart)
        else { return nil }
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }

    /// "2026-11-29" → nửa đêm ngày đó theo `calendar`.
    static func day(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "8:50", "08:50" → (8, 50). Sai dạng thì `nil`.
    static func clock(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour),
            (0..<60).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    /// Viết lại giờ bắt đầu theo dạng lưu trong tệp: "08:50".
    static func storedClock(_ text: String) -> String? {
        guard let time = clock(text) else { return nil }
        return String(format: "%02d:%02d", time.hour, time.minute)
    }

    /// Giờ lưu trong tệp viết lại để hiện: "08:50" → "8:50".
    static func displayClock(_ stored: String) -> String {
        guard let time = clock(stored) else { return stored }
        return String(format: "%d:%02d", time.hour, time.minute)
    }

    /// Ngày lưu trong tệp: "2026-11-29".
    static func storedDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }

    /// Thời lượng dạng "4′", "1:05′"; chưa đặt thì "–".
    static func durationText(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 {
            return String(format: "%d:%02d′", minutes / 60, minutes % 60)
        }
        return "\(max(1, minutes))′"
    }
}

/// Chênh lệch giữa giờ bắt đầu thật và dự kiến của mục đang chiếu.
enum Punctuality: Equatable {
    case early(minutes: Int)
    case onTime
    case late(minutes: Int)

    /// Trễ quá 2 phút thì báo màu hổ phách; sớm, đúng giờ hay trễ trong 2 phút là xanh.
    static let lateThreshold: TimeInterval = 120

    init(actual: Date, planned: Date) {
        let difference = actual.timeIntervalSince(planned)
        let minutes = Int((abs(difference) / 60).rounded())
        if minutes == 0 {
            self = .onTime
        } else if difference > 0 {
            self = .late(minutes: minutes)
        } else {
            self = .early(minutes: minutes)
        }
    }

    /// `true` khi trễ quá ``lateThreshold``.
    static func isLate(actual: Date, planned: Date) -> Bool {
        actual.timeIntervalSince(planned) > lateThreshold
    }
}

/// Chọn và tạo chương trình buổi nhóm.
enum PlanDefaults {
    /// Chương trình có ngày gần hôm nay nhất; cách đều thì lấy chương trình sắp tới.
    static func nearest(_ plans: [ServicePlan], to today: Date, calendar: Calendar = .current) -> ServicePlan? {
        let base = calendar.startOfDay(for: today)
        func distance(_ plan: ServicePlan) -> (Double, Int) {
            guard let day = PlanSchedule.day(plan.date, calendar: calendar) else { return (.infinity, 1) }
            let difference = day.timeIntervalSince(base)
            return (abs(difference), difference >= 0 ? 0 : 1)
        }
        return plans.min { lhs, rhs in
            let left = distance(lhs)
            let right = distance(rhs)
            if left != right {
                return left < right
            }
            return lhs.title < rhs.title
        }
    }

    /// Ngày Chúa Nhật kế tiếp (hôm nay là Chúa Nhật thì lấy hôm nay).
    static func nextSunday(from today: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (8 - weekday) % 7
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    /// Chương trình mới: "Chúa Nhật 29/11/2026", bắt đầu 09:00.
    static func newPlan(today: Date, calendar: Calendar = .current) -> ServicePlan {
        let sunday = nextSunday(from: today, calendar: calendar)
        let parts = calendar.dateComponents([.day, .month, .year], from: sunday)
        let title = String(
            format: "%@ %02d/%02d/%d", LiveClock.weekdays[0], parts.day ?? 1, parts.month ?? 1, parts.year ?? 2000)
        return ServicePlan(
            title: title, date: PlanSchedule.storedDay(sunday, calendar: calendar), plannedStart: "09:00")
    }
}

import CoreModel
import Foundation
import Scripture
import Testing

@testable import TrinhChieu

@Suite("Giờ dự kiến của chương trình buổi nhóm")
struct PlanScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }

    @Test("Giờ bắt đầu từng mục tính dồn theo thời lượng; mục chưa đặt thời lượng tính 0")
    func cumulativeStarts() throws {
        let welcome = ServicePlanItem.header(PlanHeaderItem(title: "Ca ngợi", plannedDuration: nil))
        let song = ServicePlanItem.presentation(PlanPresentationItem(presentationID: UUID(), plannedDuration: 240))
        let note = ServicePlanItem.note(PlanNoteItem(text: "Mục sư lên bục"))
        let reading = ServicePlanItem.scripture(
            PlanScriptureItem(reference: "Giăng 3:16", translation: "vi1934", plannedDuration: 180))
        let plan = ServicePlan(
            title: "Chúa Nhật", date: "2026-11-29", plannedStart: "08:50", items: [welcome, song, note, reading])
        let schedule = PlanSchedule(plan: plan, calendar: calendar)
        let start = try date(29, 8, 50)
        let afterSong = try date(29, 8, 54)
        let end = try date(29, 8, 57)
        #expect(schedule.starts[welcome.id] == start)
        #expect(schedule.starts[song.id] == start)
        #expect(schedule.starts[note.id] == afterSong)
        #expect(schedule.starts[reading.id] == afterSong)
        #expect(schedule.end == end)
    }

    @Test("Chưa có giờ bắt đầu hoặc ngày sai dạng thì không có giờ dự kiến")
    func missingStart() {
        let item = ServicePlanItem.note(PlanNoteItem(text: "A"))
        #expect(PlanSchedule(plan: ServicePlan(title: "A", date: "2026-11-29", items: [item])).starts.isEmpty)
        let broken = ServicePlan(title: "A", date: "29/11/2026", plannedStart: "09:00", items: [item])
        #expect(PlanSchedule(plan: broken).start == nil)
    }

    @Test("Đọc và viết giờ, thời lượng")
    func clockAndDuration() {
        #expect(PlanSchedule.clock("8:50")?.hour == 8)
        #expect(PlanSchedule.clock("8:50")?.minute == 50)
        #expect(PlanSchedule.clock(" 08:05 ")?.minute == 5)
        #expect(PlanSchedule.clock("24:00") == nil)
        #expect(PlanSchedule.clock("9h") == nil)
        #expect(PlanSchedule.storedClock("8:5") == "08:05")
        #expect(PlanSchedule.displayClock("08:50") == "8:50")
        #expect(PlanSchedule.durationText(nil) == "–")
        #expect(PlanSchedule.durationText(240) == "4′")
        #expect(PlanSchedule.durationText(20) == "1′")
        #expect(PlanSchedule.durationText(3900) == "1:05′")
    }
}

@MainActor @Suite("Chênh lệch giờ của mục đang chiếu")
struct PunctualityTests {
    @Test("Trễ, sớm, đúng giờ; báo hổ phách khi trễ quá 2 phút")
    func punctuality() {
        let planned = Date(timeIntervalSinceReferenceDate: 0)
        #expect(Punctuality(actual: planned.addingTimeInterval(180), planned: planned) == .late(minutes: 3))
        #expect(Punctuality(actual: planned.addingTimeInterval(-120), planned: planned) == .early(minutes: 2))
        #expect(Punctuality(actual: planned.addingTimeInterval(20), planned: planned) == .onTime)
        #expect(Punctuality.isLate(actual: planned.addingTimeInterval(121), planned: planned))
        #expect(!Punctuality.isLate(actual: planned.addingTimeInterval(120), planned: planned))
        #expect(LiveClockBlock.punctualityText(.onTime) == String(localized: "On time"))
    }
}

@Suite("Chọn và tạo chương trình buổi nhóm")
struct PlanDefaultsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    @Test("Chúa Nhật kế tiếp; hôm nay là Chúa Nhật thì lấy hôm nay")
    func nextSunday() throws {
        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 15)))
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 29)))
        #expect(PlanDefaults.nextSunday(from: friday, calendar: calendar) == sunday)
        #expect(PlanDefaults.nextSunday(from: sunday.addingTimeInterval(3600), calendar: calendar) == sunday)
        let plan = PlanDefaults.newPlan(today: friday, calendar: calendar)
        #expect(plan.title == "Chúa Nhật 29/11/2026")
        #expect(plan.date == "2026-11-29")
        #expect(plan.plannedStart == "09:00")
    }

    @Test("Mở chương trình gần hôm nay nhất; cách đều thì lấy chương trình sắp tới")
    func nearest() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27)))
        let past = ServicePlan(title: "Trước", date: "2026-11-25")
        let next = ServicePlan(title: "Sau", date: "2026-11-29")
        let far = ServicePlan(title: "Xa", date: "2026-12-20")
        #expect(PlanDefaults.nearest([far, past, next], to: today, calendar: calendar)?.id == next.id)
        #expect(PlanDefaults.nearest([], to: today, calendar: calendar) == nil)
    }
}

@MainActor @Suite("Sắp xếp và kéo thả mục")
struct PlanEditingTests {
    @Test("Chuyển mục như List.onMove")
    func move() {
        var items = ["a", "b", "c", "d"]
        PlanEditing.move(&items, from: [0], to: 3)
        #expect(items == ["b", "c", "a", "d"])
        PlanEditing.move(&items, from: [3], to: 0)
        #expect(items == ["d", "b", "c", "a"])
        PlanEditing.move(&items, from: [0, 2], to: 4)
        #expect(items == ["b", "a", "d", "c"])
        PlanEditing.move(&items, from: [9], to: 0)
        #expect(items == ["b", "a", "d", "c"])
    }

    @Test("Chuỗi kéo dòng thư viện")
    func dragPayload() {
        let id = UUID()
        let song = LibraryRow(
            id: "s", leading: .number("1"), title: "A", subtitle: "",
            source: .presentation(id: id, arrangementID: nil))
        #expect(LibraryDrag.payload(for: song) == "trinhchieu:presentation:" + id.uuidString)
        let verse = LibraryRow(
            id: "v", leading: .symbol("book"), title: "Giăng 3:16", subtitle: "vi1934",
            source: .scripture(translation: "vi1934", reference: "Giăng 3:16"))
        #expect(LibraryDrag.payload(for: verse) == "trinhchieu:scripture:vi1934|Giăng 3:16")
        let theme = LibraryRow(id: "t", leading: .symbol("paintpalette"), title: "T", subtitle: "", source: nil)
        #expect(LibraryDrag.payload(for: theme) == nil)
    }

    @Test("Câu thuộc đoạn: một câu, nhiều câu, trọn chương, qua chương")
    func verseInRange() {
        func verse(_ chapter: Int, _ number: Int) -> Verse {
            Verse(book: "John", chapter: chapter, verse: number, text: "")
        }
        #expect(VerseList.range(.verse("John", 3, 16), contains: verse(3, 16)))
        #expect(!VerseList.range(.verse("John", 3, 16), contains: verse(3, 17)))
        #expect(VerseList.range(.verses("John", 3, 16, 18), contains: verse(3, 17)))
        #expect(VerseList.range(.chapters("John", 3, 3), contains: verse(3, 1)))
        #expect(!VerseList.range(.chapters("John", 3, 3), contains: verse(4, 1)))
        let across = VerseRange(book: "John", startChapter: 3, startVerse: 30, endChapter: 4, endVerse: 2)
        #expect(VerseList.range(across, contains: verse(4, 1)))
        #expect(!VerseList.range(across, contains: verse(4, 3)))
        #expect(!VerseList.range(.verse("Rom", 3, 16), contains: verse(3, 16)))
    }
}

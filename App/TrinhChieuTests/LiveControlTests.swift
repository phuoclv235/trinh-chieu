import AppKit
import CoreModel
import Foundation
import Testing

@testable import TrinhChieu

@Suite("Phím chế độ Trực tiếp")
struct LiveKeyMapTests {
    @Test("Phím sang trang, lùi trang, Home")
    func navigationKeys() {
        let none: NSEvent.ModifierFlags = []
        for code in [LiveKeyMap.rightArrow, LiveKeyMap.space, LiveKeyMap.downArrow, LiveKeyMap.pageDown] {
            #expect(LiveKeyMap.key(keyCode: code, modifiers: none) == .next)
        }
        for code in [LiveKeyMap.leftArrow, LiveKeyMap.upArrow, LiveKeyMap.pageUp] {
            #expect(LiveKeyMap.key(keyCode: code, modifiers: none) == .previous)
        }
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.home, modifiers: none) == .first)
    }

    @Test("Phím F có tác dụng cả khi giữ fn")
    func functionKeysWithAndWithoutFn() {
        let pairs: [(UInt16, LiveKey)] = [
            (LiveKeyMap.f1, .clearAll), (LiveKeyMap.f2, .clearText), (LiveKeyMap.f3, .clearBackground),
            (LiveKeyMap.f4, .clearAudio),
        ]
        for (code, key) in pairs {
            #expect(LiveKeyMap.key(keyCode: code, modifiers: []) == key)
            #expect(LiveKeyMap.key(keyCode: code, modifiers: .function) == key)
        }
    }

    @Test("Phím mũi tên mang cờ bàn phím số vẫn nhận; có ⌘ hay ⌥ thì không")
    func modifiers() {
        let arrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.rightArrow, modifiers: arrowFlags) == .next)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.rightArrow, modifiers: .command) == nil)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.space, modifiers: .option) == nil)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.z, modifiers: .command) == .undo)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.z, modifiers: [.command, .shift]) == .redo)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.z, modifiers: []) == nil)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.backspace, modifiers: []) == .delete)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.forwardDelete, modifiers: .function) == .delete)
        #expect(LiveKeyMap.key(keyCode: LiveKeyMap.backspace, modifiers: .command) == nil)
    }
}

@MainActor @Suite("Thẻ trang chiếu")
struct SlideCardsTests {
    private func sequence() -> SlideSequence {
        let a1 = Slide(elements: [.text(TextElement(slot: .body, text: "  Ngài là Đấng chăn giữ tôi  "))])
        let a2 = Slide(enabled: false, elements: [.text(TextElement(slot: .body, text: "Tôi chẳng thiếu thốn gì"))])
        let b1 = Slide(elements: [.text(TextElement(slot: .body, text: "Dù qua trũng bóng tối"))])
        let verse = SlideGroup(label: GroupLabel(kind: .verse, number: 1), slides: [a1, a2])
        let chorus = SlideGroup(
            label: GroupLabel(kind: .chorus), color: RGBA(red: 10, green: 20, blue: 30), slides: [b1])
        let arrangement = Arrangement(name: "Lặp", groupIDs: [verse.id, chorus.id, verse.id])
        let presentation = Presentation(
            kind: .song, title: "Đấng Chăn Giữ Tôi", createdAt: Date(), modifiedAt: Date(), groups: [verse, chorus],
            arrangements: [arrangement], activeArrangementID: arrangement.id)
        return SlideSequence(
            presentation: presentation, source: .presentation(id: presentation.id, arrangementID: nil),
            arrangementID: nil, themeID: nil)
    }

    @Test("Mỗi vị trí một thẻ, kể cả trang lặp lại; nhãn đoạn, chữ thô, trang tắt")
    func cardsFollowSequence() {
        let sequence = sequence()
        let colors: [UUID: RGBA] = [sequence.slides[2].groupID!: RGBA(red: 10, green: 20, blue: 30)]
        let cards = SlideCards.make(sequence, theme: .fallback(), groupColors: colors)
        #expect(cards.map(\.index) == [0, 1, 2, 3, 4])
        #expect(cards.map(\.number) == ["01", "02", "03", "04", "05"])
        #expect(cards[0].label == "Câu 1")
        #expect(cards[2].label == "Điệp khúc")
        #expect(cards[2].groupColor == RGBA(red: 10, green: 20, blue: 30))
        #expect(cards[0].text == "Ngài là Đấng chăn giữ tôi")
        #expect(cards[1].enabled == false)
        #expect(cards[3].slideID == cards[0].slideID)
        #expect(cards[3].thumbnail == cards[0].thumbnail)
    }

    @Test("Thẻ kế tiếp bỏ qua trang tắt; trang đầu là trang bật đầu tiên")
    func nextAndFirst() {
        let sequence = sequence()
        let cards = SlideCards.make(sequence, theme: .fallback())
        #expect(SlideCards.nextEnabled(after: 0, in: cards) == 2)
        #expect(SlideCards.nextEnabled(after: 4, in: cards) == nil)
        #expect(SlideCards.nextEnabled(after: nil, in: cards) == nil)
        #expect(SlideCards.firstEnabled(in: sequence) == 0)
    }

    @Test("Ảnh thu nhỏ đổi khoá khi chữ hoặc mẫu đổi")
    func thumbnailKeyTracksContent() {
        let slide = Slide(elements: [.text(TextElement(slot: .body, text: "A"))])
        var edited = slide
        edited.elements = [.text(TextElement(slot: .body, text: "B"))]
        let theme = Theme.fallback()
        var otherTheme = theme
        otherTheme.background = .color(.white)
        #expect(ThumbnailKey(slide: slide, theme: theme) == ThumbnailKey(slide: slide, theme: theme))
        #expect(ThumbnailKey(slide: slide, theme: theme) != ThumbnailKey(slide: edited, theme: theme))
        #expect(ThumbnailKey(slide: slide, theme: theme) != ThumbnailKey(slide: slide, theme: otherTheme))
    }

    @Test("Cỡ thẻ 3 đến 8 thành 8 đến 3 cột")
    func columns() {
        #expect(SlideStage.columns(forCardSize: 3) == 8)
        #expect(SlideStage.columns(forCardSize: 6) == 5)
        #expect(SlideStage.columns(forCardSize: 8) == 3)
        #expect(SlideStage.columns(forCardSize: 20) == 3)
    }
}

@Suite("Đồng hồ giờ thật")
struct LiveClockTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    @Test("Ngày gọi Chúa Nhật, giờ không đệm số 0 ở giờ")
    func formats() throws {
        // 2026-11-29 là Chúa Nhật; 9:12:48 giờ Việt Nam.
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 29, hour: 9, minute: 12, second: 48)))
        #expect(LiveClock.dayText(date, calendar: calendar) == "Chúa Nhật 29/11/2026")
        #expect(LiveClock.timeText(date, calendar: calendar) == "9:12:48")
        #expect(LiveClock.shortTime(date, calendar: calendar) == "9:12")
        let monday = date.addingTimeInterval(86_400)
        #expect(LiveClock.dayText(monday, calendar: calendar) == "Thứ Hai 30/11/2026")
    }
}

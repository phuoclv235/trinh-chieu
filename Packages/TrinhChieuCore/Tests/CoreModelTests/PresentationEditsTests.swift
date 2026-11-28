import Foundation
import Testing

@testable import CoreModel

/// Bài thử: Câu 1 (2 trang), Điệp khúc (1 trang), Câu 2 (1 trang); thứ tự hát "Mặc định" theo thứ tự gốc.
private func sample() -> Presentation {
    func slide(_ text: String) -> Slide {
        Slide(elements: [.text(TextElement(slot: .body, text: text))])
    }
    let verse1 = SlideGroup(label: GroupLabel(kind: .verse, number: 1), slides: [slide("A\nB"), slide("C\nD")])
    let chorus = SlideGroup(label: GroupLabel(kind: .chorus), slides: [slide("E\nF\nG\nH")])
    let verse2 = SlideGroup(label: GroupLabel(kind: .verse, number: 2), slides: [slide("I")])
    let arrangement = Arrangement(name: Arrangement.defaultName, groupIDs: [verse1.id, chorus.id, verse2.id])
    let now = Date(timeIntervalSince1970: 0)
    return Presentation(
        kind: .song, title: "Bài thử", createdAt: now, modifiedAt: now, song: SongInfo(),
        groups: [verse1, chorus, verse2], arrangements: [arrangement], activeArrangementID: arrangement.id)
}

@Suite("Thao tác soạn: trang")
struct PresentationSlideEditTests {
    @Test("Chữ chính: ô body trước, không có thì phần tử chữ đầu tiên; chưa có thì thêm")
    func primaryText() {
        let caption = TextElement(slot: .title, text: "Tiêu đề")
        var slide = Slide(elements: [.text(caption), .text(TextElement(slot: .body, text: "Lời"))])
        #expect(slide.primaryTextIndex == 1)
        slide.elements.remove(at: 1)
        #expect(slide.primaryText == "Tiêu đề")
        var empty = Slide(background: .color(.black))
        #expect(empty.primaryText == nil)
        empty.setPrimaryText("Mới")
        #expect(empty.primaryText == "Mới")
        #expect(empty.elements.count == 1)
    }

    @Test("Thêm trang sau trang chọn, theo bố cục trang đầu đoạn, chữ rỗng")
    func addSlideAfter() throws {
        var presentation = sample()
        presentation.groups[0].slides[0].background = .color(.white)
        presentation.groups[0].slides[0].notes = "ghi chú"
        let anchor = presentation.groups[0].slides[0].id
        let id = presentation.addSlide(after: anchor)
        let added = try #require(presentation.slide(id))
        #expect(presentation.location(ofSlide: id) == SlideLocation(group: 0, slide: 1))
        #expect(added.background == .color(.white))
        #expect(added.notes.isEmpty)
        #expect(added.primaryText == "")
        #expect(added.elements[0].id != presentation.groups[0].slides[0].elements[0].id)
    }

    @Test("Thêm trang khi chưa chọn: cuối đoạn cuối; bài trống thì tạo đoạn và đưa vào thứ tự hát")
    func addSlideWithoutAnchor() {
        var presentation = sample()
        let id = presentation.addSlide(after: nil)
        #expect(presentation.location(ofSlide: id) == SlideLocation(group: 2, slide: 1))
        var empty = Presentation.newSong(title: "Trống")
        empty.deleteGroup(empty.groups[0].id)
        let first = empty.addSlide(after: nil)
        #expect(empty.groups.count == 1)
        #expect(empty.arrangements[0].groupIDs == [empty.groups[0].id])
        #expect(empty.location(ofSlide: first) == SlideLocation(group: 0, slide: 0))
    }

    @Test("Nhân đôi: bản sao ngay sau, mã mới, cùng chữ")
    func duplicate() throws {
        var presentation = sample()
        let original = presentation.groups[1].slides[0]
        let duplicated = presentation.duplicateSlide(original.id)
        let id = try #require(duplicated)
        #expect(presentation.groups[1].slides.map(\.id) == [original.id, id])
        #expect(presentation.groups[1].slides[1].primaryText == original.primaryText)
    }

    @Test("Tắt rồi bật trang")
    func toggleEnabled() {
        var presentation = sample()
        let id = presentation.groups[0].slides[1].id
        presentation.setSlideEnabled(id, false)
        #expect(presentation.groups[0].slides[1].enabled == false)
        presentation.setSlideEnabled(id, true)
        #expect(presentation.groups[0].slides[1].enabled)
    }

    @Test("Tách trang tại dòng; dòng tách mặc định theo cặp")
    func splitAtLine() throws {
        var presentation = sample()
        let id = presentation.groups[1].slides[0].id
        #expect(Presentation.defaultSplitLine(lineCount: 4) == 2)
        #expect(Presentation.defaultSplitLine(lineCount: 6) == 4)
        #expect(Presentation.defaultSplitLine(lineCount: 3) == 2)
        #expect(Presentation.defaultSplitLine(lineCount: 1) == nil)
        let split = presentation.splitSlide(id, atLine: 2)
        let tail = try #require(split)
        #expect(presentation.groups[1].slides.map(\.id) == [id, tail])
        #expect(presentation.groups[1].slides.map(\.primaryText) == ["E\nF", "G\nH"])
        let atStart = presentation.splitSlide(id, atLine: 0)
        let pastEnd = presentation.splitSlide(id, atLine: 2)
        #expect(atStart == nil)
        #expect(pastEnd == nil)
    }

    @Test("Gộp với trang sau trong cùng đoạn; trang cuối đoạn thì không gộp")
    func mergeWithNext() {
        var presentation = sample()
        let first = presentation.groups[0].slides[0].id
        let merged = presentation.mergeSlideWithNext(first)
        #expect(merged)
        #expect(presentation.groups[0].slides.count == 1)
        #expect(presentation.groups[0].slides[0].id == first)
        #expect(presentation.groups[0].slides[0].primaryText == "A\nB\nC\nD")
        let mergedAgain = presentation.mergeSlideWithNext(first)
        #expect(mergedAgain == false)
    }

    @Test("Xoá trang cuối cùng của đoạn thì xoá đoạn và gỡ khỏi thứ tự hát")
    func deleteLastSlideDeletesGroup() {
        var presentation = sample()
        let chorus = presentation.groups[1]
        presentation.arrangements[0].groupIDs.append(chorus.id)
        presentation.deleteSlide(chorus.slides[0].id)
        #expect(presentation.groups.count == 2)
        #expect(presentation.arrangements[0].groupIDs.contains(chorus.id) == false)
        let other = presentation.groups[0].slides[1].id
        presentation.deleteSlide(other)
        #expect(presentation.groups[0].slides.count == 1)
    }

    @Test("Kéo trang trong đoạn và sang đoạn khác; đoạn nguồn hết trang thì bị xoá")
    func moveSlides() {
        var presentation = sample()
        let a = presentation.groups[0].slides[0].id
        let c = presentation.groups[0].slides[1].id
        presentation.moveSlide(a, toGroup: presentation.groups[0].id, at: 2)
        #expect(presentation.groups[0].slides.map(\.id) == [c, a])
        let verse2 = presentation.groups[2]
        presentation.moveSlide(verse2.slides[0].id, toGroup: presentation.groups[1].id, at: 0)
        #expect(presentation.groups.count == 2)
        #expect(presentation.groups[1].slides.first?.id == verse2.slides[0].id)
        #expect(presentation.arrangements[0].groupIDs.contains(verse2.id) == false)
    }
}

@Suite("Thao tác soạn: đoạn và thứ tự hát")
struct PresentationGroupEditTests {
    @Test("Đổi nhãn, đổi màu, kéo đoạn đổi thứ tự gốc")
    func groupEdits() {
        var presentation = sample()
        let ids = presentation.groups.map(\.id)
        presentation.setGroupLabel(ids[2], GroupLabel(kind: .custom, custom: "Lời chứng"))
        presentation.setGroupColor(ids[1], RGBA(red: 10, green: 20, blue: 30))
        #expect(presentation.groups[2].label.custom == "Lời chứng")
        #expect(presentation.groups[1].color == RGBA(red: 10, green: 20, blue: 30))
        presentation.moveGroup(ids[2], to: 0)
        #expect(presentation.groups.map(\.id) == [ids[2], ids[0], ids[1]])
        presentation.moveGroup(ids[2], to: 3)
        #expect(presentation.groups.map(\.id) == [ids[0], ids[1], ids[2]])
        #expect(presentation.arrangements[0].groupIDs == ids)
    }

    @Test("Thứ tự hát: thêm đoạn nhiều lần, gỡ, kéo đổi chỗ")
    func arrangementOccurrences() {
        var presentation = sample()
        let ids = presentation.groups.map(\.id)
        presentation.appendToActiveArrangement(ids[1])
        #expect(presentation.arrangements[0].groupIDs == [ids[0], ids[1], ids[2], ids[1]])
        presentation.moveInActiveArrangement(from: 3, to: 0)
        #expect(presentation.arrangements[0].groupIDs == [ids[1], ids[0], ids[1], ids[2]])
        presentation.removeFromActiveArrangement(at: 0)
        #expect(presentation.arrangements[0].groupIDs == [ids[0], ids[1], ids[2]])
    }

    @Test("Tạo thứ tự hát mới chép thứ tự đang dùng, đổi tên, chọn, xoá")
    func arrangementsLifecycle() throws {
        var presentation = sample()
        let first = try #require(presentation.activeArrangementID)
        let short = presentation.addArrangement(name: "Rút gọn")
        #expect(presentation.activeArrangementID == short)
        #expect(presentation.arrangements[1].groupIDs == presentation.arrangements[0].groupIDs)
        presentation.removeFromActiveArrangement(at: 2)
        presentation.renameArrangement(short, to: "  Ngắn  ")
        presentation.renameArrangement(short, to: "   ")
        #expect(presentation.arrangements[1].name == "Ngắn")
        #expect(presentation.orderedGroups().count == 2)
        presentation.setActiveArrangement(first)
        #expect(presentation.orderedGroups().count == 3)
        presentation.setActiveArrangement(short)
        presentation.deleteArrangement(short)
        #expect(presentation.activeArrangementID == first)
        #expect(presentation.defaultArrangementIndex == 0)
    }

    @Test("Chưa có thứ tự hát: thêm đoạn vào thứ tự thì tạo 'Mặc định' theo thứ tự gốc")
    func arrangementCreatedOnDemand() {
        var presentation = sample()
        presentation.arrangements = []
        presentation.activeArrangementID = nil
        let ids = presentation.groups.map(\.id)
        presentation.appendToActiveArrangement(ids[0])
        #expect(presentation.arrangements.count == 1)
        #expect(presentation.arrangements[0].name == Arrangement.defaultName)
        #expect(presentation.arrangements[0].groupIDs == ids + [ids[0]])
        #expect(presentation.activeArrangementID == presentation.arrangements[0].id)
    }

    @Test("Bộ trình chiếu trống: generic, một trang có ô tiêu đề")
    func newGeneric() {
        let presentation = Presentation.newGeneric(title: "Thông báo")
        #expect(presentation.kind == .generic)
        #expect(presentation.song == nil)
        #expect(presentation.slideCount == 1)
        guard case .text(let text) = presentation.groups[0].slides[0].elements[0] else {
            Issue.record("Thiếu phần tử chữ")
            return
        }
        #expect(text.slot == .title)
    }
}

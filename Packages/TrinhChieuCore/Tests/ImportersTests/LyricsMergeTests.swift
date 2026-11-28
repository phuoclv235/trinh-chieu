import CoreModel
import Foundation
import Testing

@testable import Importers

/// Bài hát dựng từ văn bản, như khi nhập tệp `.txt`.
private func song(_ text: String) -> Presentation {
    LyricsText.parse(text).makePresentation(fallbackTitle: "Bài thử", now: Date(timeIntervalSince1970: 0))
}

private let threeSections = """
    Tiêu đề: Đấng Chăn Giữ Tôi

    [Câu 1]
    Chúa là Đấng chăn giữ tôi
    Tôi chẳng thiếu thốn gì

    Ngài cho tôi an nghỉ
    Nơi đồng cỏ xanh tươi

    [Điệp khúc]
    Dù qua trũng bóng tối tăm
    Tôi chẳng sợ điều chi

    [Câu 2]
    Ngài dọn bàn cho tôi
    """

/// Chữ lời các trang của từng đoạn.
private func texts(_ presentation: Presentation) -> [[String]] {
    presentation.groups.map { $0.slides.map(LyricsText.slideText) }
}

/// Đổi một dòng trong văn bản dựng lại từ bài.
private func edited(_ presentation: Presentation, replacing old: String, with new: String) -> String {
    LyricsText.render(presentation).replacingOccurrences(of: old, with: new)
}

@Suite("LyricsMerge: giữ nguyên khi chỉ sửa chữ")
struct LyricsMergeKeepTests {
    @Test("Văn bản không đổi thì bộ trình chiếu bằng đúng bản cũ")
    func unchangedTextIsIdentity() {
        let original = song(threeSections)
        let merged = LyricsMerge.merge(text: LyricsText.render(original), into: original)
        #expect(merged == original)
    }

    @Test("Sửa chữ một trang giữ mã mọi đoạn và mọi trang")
    func editingTextKeepsIDs() {
        let original = song(threeSections)
        let text = edited(original, replacing: "Tôi chẳng thiếu thốn gì", with: "Tôi sẽ chẳng thiếu thốn gì")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.groups.map(\.id) == original.groups.map(\.id))
        #expect(merged.groups.map { $0.slides.map(\.id) } == original.groups.map { $0.slides.map(\.id) })
        #expect(texts(merged)[0][0] == "Chúa là Đấng chăn giữ tôi\nTôi sẽ chẳng thiếu thốn gì")
        #expect(merged.arrangements == original.arrangements)
    }

    @Test("Trang khớp giữ phần tử không phải chữ, nền, ghi chú, trạng thái tắt")
    func matchedSlideKeepsEverythingElse() {
        var original = song(threeSections)
        let image = Element.image(ImageElement(frame: PixelRect(x: 0, y: 0, width: 10, height: 10), mediaID: "abc"))
        original.groups[1].slides[0].elements.append(image)
        original.groups[1].slides[0].background = .color(.white)
        original.groups[1].slides[0].notes = "Hát chậm"
        original.groups[1].slides[0].enabled = false
        let text = edited(original, replacing: "Tôi chẳng sợ điều chi", with: "Tôi không sợ điều chi")
        let merged = LyricsMerge.merge(text: text, into: original)
        let slide = merged.groups[1].slides[0]
        #expect(slide.id == original.groups[1].slides[0].id)
        #expect(slide.elements.count == 2)
        #expect(slide.elements[1] == image)
        #expect(slide.background == .color(.white))
        #expect(slide.notes == "Hát chậm")
        #expect(slide.enabled == false)
        #expect(LyricsText.slideText(slide) == "Dù qua trũng bóng tối tăm\nTôi không sợ điều chi")
    }

    @Test("Chỉ thay chữ phần tử ô body; phần tử chữ khác giữ nguyên")
    func onlyBodySlotIsReplaced() {
        var original = song(threeSections)
        let title = TextElement(slot: .title, text: "Tiêu đề trên trang")
        original.groups[0].slides[0].elements.insert(.text(title), at: 0)
        let text = edited(original, replacing: "Chúa là Đấng chăn giữ tôi", with: "Chúa chăn giữ tôi")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.groups[0].slides[0].elements[0] == .text(title))
        #expect(merged.groups[0].slides[0].primaryText == "Chúa chăn giữ tôi\nTôi chẳng thiếu thốn gì")
        #expect(LyricsText.render(merged).contains("Tiêu đề trên trang") == false)
    }

    @Test("Trang không có ô body thì thay chữ phần tử chữ đầu tiên")
    func firstTextElementWithoutBodySlot() {
        var original = song(threeSections)
        let first = TextElement(frame: PixelRect(x: 10, y: 10, width: 500, height: 200), text: "Lời cũ")
        let second = TextElement(frame: PixelRect(x: 10, y: 300, width: 500, height: 200), text: "Chú thích")
        original.groups[2].slides[0].elements = [.text(first), .text(second)]
        let text = edited(original, replacing: "[Câu 2]\nLời cũ", with: "[Câu 2]\nLời mới")
        let merged = LyricsMerge.merge(text: text, into: original)
        let elements = merged.groups[2].slides[0].elements
        guard case .text(let updated) = elements[0], case .text(let untouched) = elements[1] else {
            Issue.record("Phần tử chữ bị mất")
            return
        }
        #expect(updated.text == "Lời mới")
        #expect(updated.frame == first.frame)
        #expect(untouched == second)
    }

    @Test("Đổi thứ tự đoạn trong văn bản thì đổi thứ tự gốc, giữ mã")
    func reorderingSectionsKeepsIDs() {
        let original = song(threeSections)
        let text = """
            Tiêu đề: Đấng Chăn Giữ Tôi

            [Điệp khúc]
            Dù qua trũng bóng tối tăm
            Tôi chẳng sợ điều chi

            [Câu 1]
            Chúa là Đấng chăn giữ tôi
            Tôi chẳng thiếu thốn gì

            Ngài cho tôi an nghỉ
            Nơi đồng cỏ xanh tươi

            [Câu 2]
            Ngài dọn bàn cho tôi
            """
        let merged = LyricsMerge.merge(text: text, into: original)
        let ids = original.groups.map(\.id)
        #expect(merged.groups.map(\.id) == [ids[1], ids[0], ids[2]])
        #expect(merged.groups[1].slides.map(\.id) == original.groups[0].slides.map(\.id))
    }
}

@Suite("LyricsMerge: thêm, xoá trang và đoạn")
struct LyricsMergeStructureTests {
    @Test("Thêm trang trong đoạn: trang mới theo bố cục trang đầu đoạn, chèn sau trang cuối có chữ")
    func addedSlideUsesFirstSlideLayout() {
        var original = song(threeSections)
        let image = Element.image(ImageElement(frame: PixelRect(x: 0, y: 0, width: 10, height: 10), mediaID: "abc"))
        original.groups[2].slides[0].elements.append(image)
        original.groups[2].slides[0].background = .color(.white)
        original.groups[2].slides[0].notes = "Ghi chú riêng"
        let text = edited(original, replacing: "Ngài dọn bàn cho tôi", with: "Ngài dọn bàn cho tôi\n\nTrước mặt kẻ thù")
        let merged = LyricsMerge.merge(text: text, into: original)
        let slides = merged.groups[2].slides
        #expect(slides.count == 2)
        #expect(slides[0].id == original.groups[2].slides[0].id)
        #expect(slides[1].id != slides[0].id)
        #expect(LyricsText.slideText(slides[1]) == "Trước mặt kẻ thù")
        #expect(slides[1].background == .color(.white))
        #expect(slides[1].notes.isEmpty)
        #expect(slides[1].elements.count == 2)
        #expect(slides[1].elements.map(\.id) != slides[0].elements.map(\.id))
    }

    @Test("Bỏ trang cuối của đoạn trong văn bản thì xoá trang đó, trang đầu giữ mã")
    func removedSlideIsDeleted() {
        let original = song(threeSections)
        let text = edited(original, replacing: "\n\nNgài cho tôi an nghỉ\nNơi đồng cỏ xanh tươi", with: "")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.groups[0].slides.map(\.id) == [original.groups[0].slides[0].id])
    }

    @Test("Đoạn mới: thêm vào cuối thứ tự hát mặc định, trang theo trang mặc định của mẫu")
    func newSectionAppendsToDefaultArrangement() {
        let original = song(threeSections)
        let layout = Slide(elements: [.text(TextElement(slot: .body, text: "")), .shape(rectangle)])
        let text = LyricsText.render(original) + "\n[Cầu nối]\nHồn tôi được bổ lại\n"
        let merged = LyricsMerge.merge(text: text, into: original, defaultSlide: layout)
        #expect(merged.groups.count == 4)
        let bridge = merged.groups[3]
        #expect(bridge.label == GroupLabel(kind: .bridge))
        #expect(bridge.slides.count == 1)
        #expect(bridge.slides[0].elements.count == 2)
        #expect(LyricsText.slideText(bridge.slides[0]) == "Hồn tôi được bổ lại")
        #expect(merged.arrangements[0].groupIDs == original.arrangements[0].groupIDs + [bridge.id])
    }

    @Test("Đoạn không còn trong văn bản bị xoá và gỡ khỏi mọi thứ tự hát")
    func removedSectionLeavesAllArrangements() {
        var original = song(threeSections)
        let chorus = original.groups[1].id
        let ids = original.groups.map(\.id)
        original.arrangements.append(Arrangement(name: "Rút gọn", groupIDs: [chorus, ids[0], chorus]))
        let chorusText = "[Điệp khúc]\nDù qua trũng bóng tối tăm\nTôi chẳng sợ điều chi\n\n"
        let text = edited(original, replacing: chorusText, with: "")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.groups.map(\.id) == [ids[0], ids[2]])
        #expect(merged.arrangements[0].groupIDs == [ids[0], ids[2]])
        #expect(merged.arrangements[1].groupIDs == [ids[0]])
    }

    @Test("Đổi nhãn đoạn trong văn bản: đoạn nhãn cũ bị xoá, đoạn nhãn mới được tạo")
    func relabelingReplacesGroup() {
        let original = song(threeSections)
        let text = edited(original, replacing: "[Câu 2]", with: "[Kết]")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.groups.count == 3)
        #expect(merged.groups[2].label == GroupLabel(kind: .ending))
        #expect(merged.groups[2].id != original.groups[2].id)
        #expect(merged.arrangements[0].groupIDs == [original.groups[0].id, original.groups[1].id, merged.groups[2].id])
    }

    @Test("Hai đoạn cùng nhãn khớp lần lượt theo thứ tự")
    func duplicateLabelsMatchInOrder() {
        let original = song("[Điệp khúc]\nHát lên\n\n[Điệp khúc]\nCa ngợi\n")
        #expect(original.groups.count == 2)
        let merged = LyricsMerge.merge(text: "[Điệp khúc]\nHát lên mãi\n\n[Điệp khúc]\nCa ngợi Chúa\n", into: original)
        #expect(merged.groups.map(\.id) == original.groups.map(\.id))
        #expect(texts(merged) == [["Hát lên mãi"], ["Ca ngợi Chúa"]])
    }

    @Test("Nhãn còn nhưng hết chữ: đoạn giữ lại với một trang rỗng")
    func emptySectionKeepsOneBlankSlide() {
        let original = song(threeSections)
        let text = edited(original, replacing: "[Câu 2]\nNgài dọn bàn cho tôi", with: "[Câu 2]")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.groups[2].id == original.groups[2].id)
        #expect(merged.groups[2].slides.map(\.id) == original.groups[2].slides.map(\.id))
        #expect(LyricsText.slideText(merged.groups[2].slides[0]).isEmpty)
    }

    @Test("Bài mới: gõ lời điền vào trang rỗng có sẵn, không thêm trang")
    func newSongFillsBlankSlide() {
        let original = Presentation.newSong(title: "Bài mới", now: Date(timeIntervalSince1970: 0))
        let merged = LyricsMerge.merge(text: "Tiêu đề: Bài mới\n\n[Câu 1]\nDòng đầu tiên\n", into: original)
        #expect(merged.groups.map(\.id) == original.groups.map(\.id))
        #expect(merged.groups[0].slides.map(\.id) == original.groups[0].slides.map(\.id))
        #expect(texts(merged) == [["Dòng đầu tiên"]])
    }

    @Test("Trang chỉ có media không hiện trong văn bản và được giữ nguyên chỗ")
    func mediaOnlySlideIsKept() {
        var original = song(threeSections)
        let media = Slide(background: .media("abc"))
        original.groups[0].slides.insert(media, at: 1)
        let text = edited(original, replacing: "Nơi đồng cỏ xanh tươi", with: "Bên dòng nước bình tịnh")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.groups[0].slides.map(\.id) == original.groups[0].slides.map(\.id))
        #expect(merged.groups[0].slides[1] == media)
        #expect(LyricsText.slideText(merged.groups[0].slides[2]) == "Ngài cho tôi an nghỉ\nBên dòng nước bình tịnh")
    }

    @Test("Gõ bài 3 đoạn vào bài mới: lưới trang và thứ tự hát đúng")
    func typingThreeSectionsIntoNewSong() {
        let original = Presentation.newSong(title: "Bài mới", now: Date(timeIntervalSince1970: 0))
        let merged = LyricsMerge.merge(text: threeSections, into: original)
        #expect(merged.title == "Đấng Chăn Giữ Tôi")
        #expect(merged.groups.map(\.label.kind) == [.verse, .chorus, .verse])
        #expect(merged.groups[0].id == original.groups[0].id)
        #expect(texts(merged).map(\.count) == [2, 1, 1])
        #expect(merged.orderedGroups().map(\.id) == merged.groups.map(\.id))
    }
}

@Suite("LyricsMerge: thứ tự hát và thông tin bài")
struct LyricsMergeOrderTests {
    @Test("Dòng 'Thứ tự:' mới thay thứ tự hát đang dùng")
    func explicitOrderReplacesActiveArrangement() {
        let original = song(threeSections)
        let text = LyricsText.render(original).replacingOccurrences(
            of: "Tiêu đề: Đấng Chăn Giữ Tôi\n", with: "Tiêu đề: Đấng Chăn Giữ Tôi\nThứ tự: Câu 1, ĐK, Câu 2, ĐK\n")
        let merged = LyricsMerge.merge(text: text, into: original)
        let ids = original.groups.map(\.id)
        #expect(merged.arrangements.count == 1)
        #expect(merged.arrangements[0].groupIDs == [ids[0], ids[1], ids[2], ids[1]])
        #expect(merged.groups.map(\.id) == ids)
    }

    @Test("Dòng 'Thứ tự:' giống thứ tự đang dùng thì thứ tự hát không đổi")
    func sameExplicitOrderKeepsArrangement() {
        var original = song(threeSections)
        let ids = original.groups.map(\.id)
        original.arrangements[0].groupIDs = [ids[0], ids[1], ids[2], ids[1]]
        let rendered = LyricsText.render(original)
        #expect(rendered.contains("Thứ tự: Câu 1, Điệp khúc, Câu 2, Điệp khúc"))
        let text = rendered.replacingOccurrences(of: "Ngài dọn bàn cho tôi", with: "Ngài dọn bàn")
        let merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.arrangements == original.arrangements)
    }

    @Test("Tiêu đề, tác giả, tông cập nhật; thiếu dòng tiêu đề thì giữ tiêu đề cũ")
    func metadataUpdates() {
        let original = song(threeSections)
        let header = "Tiêu đề: Chúa Chăn Giữ\nTác giả: A, B\nTông: G"
        var text = edited(original, replacing: "Tiêu đề: Đấng Chăn Giữ Tôi", with: header)
        var merged = LyricsMerge.merge(text: text, into: original)
        #expect(merged.title == "Chúa Chăn Giữ")
        #expect(merged.song?.authors == ["A", "B"])
        #expect(merged.song?.key == "G")
        text = LyricsText.render(merged).replacingOccurrences(of: "Tiêu đề: Chúa Chăn Giữ\n", with: "")
        merged = LyricsMerge.merge(text: text, into: merged)
        #expect(merged.title == "Chúa Chăn Giữ")
    }

    @Test("Xoá hết văn bản thì bài không còn đoạn nào, thứ tự hát rỗng")
    func clearingEverything() {
        let original = song(threeSections)
        let merged = LyricsMerge.merge(text: "", into: original)
        #expect(merged.groups.isEmpty)
        #expect(merged.arrangements[0].groupIDs.isEmpty)
        #expect(merged.title == original.title)
    }
}

@Suite("LyricsSplit: chia trang theo mẫu")
struct LyricsSplitTests {
    private func lines(_ count: Int) -> [String] {
        (1...count).map { "Dòng \($0)" }
    }

    @Test("Ưu tiên ranh giới cặp dòng, ít trang nhất")
    func pairBoundaries() {
        #expect(LyricsSplit.pages(lines(6), maxLines: 4).map(\.count) == [4, 2])
        #expect(LyricsSplit.pages(lines(8), maxLines: 4).map(\.count) == [4, 4])
        #expect(LyricsSplit.pages(lines(5), maxLines: 4).map(\.count) == [4, 1])
        #expect(LyricsSplit.pages(lines(10), maxLines: 4).map(\.count) == [4, 4, 2])
        #expect(LyricsSplit.pages(lines(9), maxLines: 6).map(\.count) == [6, 3])
    }

    @Test("Cặp dòng làm tăng số trang thì chia đều theo dòng; không vượt giới hạn thì giữ nguyên")
    func fallbackAndNoSplit() {
        #expect(LyricsSplit.pages(lines(7), maxLines: 3).map(\.count) == [3, 2, 2])
        #expect(LyricsSplit.pages(lines(3), maxLines: 1).map(\.count) == [1, 1, 1])
        #expect(LyricsSplit.pages(lines(4), maxLines: 4).map(\.count) == [4])
        #expect(LyricsSplit.pages(lines(6), maxLines: 4).flatMap { $0 } == lines(6))
    }

    @Test("Chia bài: trang đầu giữ mã, trang sau cùng bố cục, thứ tự hát không đổi")
    func splitPresentation() {
        let original = song("[Câu 1]\nA\nB\nC\nD\nE\nF\n\n[Điệp khúc]\nG\nH\n")
        let split = LyricsSplit.splitLongSlides(original, maxLinesPerSlide: 4)
        #expect(texts(split) == [["A\nB\nC\nD", "E\nF"], ["G\nH"]])
        #expect(split.groups[0].slides[0].id == original.groups[0].slides[0].id)
        #expect(split.groups[0].slides[1].id != original.groups[0].slides[0].id)
        #expect(split.groups[1] == original.groups[1])
        #expect(split.arrangements == original.arrangements)
        #expect(LyricsSplit.splitLongSlides(split, maxLinesPerSlide: 4) == split)
    }
}

private let rectangle = ShapeElement(frame: PixelRect(x: 0, y: 900, width: 1920, height: 180), fill: .black)

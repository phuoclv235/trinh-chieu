import CoreModel
import Foundation
import Testing

@testable import Importers

@Suite("LyricsText: nhận dạng nhãn")
struct LyricsLabelTests {
    @Test("Nhãn tiếng Việt và tiếng Anh, có hoặc không có số, so khớp sau khi gộp dấu")
    func knownLabels() {
        #expect(LyricsText.knownLabel("Câu 1") == GroupLabel(kind: .verse, number: 1))
        #expect(LyricsText.knownLabel("CÂU 12:") == GroupLabel(kind: .verse, number: 12))
        #expect(LyricsText.knownLabel("ĐK") == GroupLabel(kind: .chorus))
        #expect(LyricsText.knownLabel("Đk 2") == GroupLabel(kind: .chorus, number: 2))
        #expect(LyricsText.knownLabel("Điệp khúc:") == GroupLabel(kind: .chorus))
        #expect(LyricsText.knownLabel("Tiền điệp khúc") == GroupLabel(kind: .prechorus))
        #expect(LyricsText.knownLabel("Cầu nối") == GroupLabel(kind: .bridge))
        #expect(LyricsText.knownLabel("Kết") == GroupLabel(kind: .ending))
        #expect(LyricsText.knownLabel("Dạo") == GroupLabel(kind: .intro))
        #expect(LyricsText.knownLabel("Verse 3") == GroupLabel(kind: .verse, number: 3))
        #expect(LyricsText.knownLabel("Pre-Chorus") == GroupLabel(kind: .prechorus))
        #expect(LyricsText.knownLabel("Chorus") == GroupLabel(kind: .chorus))
        #expect(LyricsText.knownLabel("Bridge 2") == GroupLabel(kind: .bridge, number: 2))
        #expect(LyricsText.knownLabel("Tag") == GroupLabel(kind: .tag))
        #expect(LyricsText.knownLabel("Intro") == GroupLabel(kind: .intro))
        #expect(LyricsText.knownLabel("Ending") == GroupLabel(kind: .ending))
        #expect(LyricsText.knownLabel("2.") == GroupLabel(kind: .verse, number: 2))
    }

    @Test("Dòng lời không bị nhận nhầm là nhãn")
    func lyricLinesAreNotLabels() {
        #expect(LyricsText.knownLabel("Câu chuyện tình yêu") == nil)
        #expect(LyricsText.knownLabel("Điệp khúc vang lên") == nil)
        #expect(LyricsText.knownLabel("Kết thúc ngày dài") == nil)
        #expect(LyricsText.knownLabel("Chúa ơi") == nil)
        #expect(LyricsText.knownLabel("") == nil)
    }

    @Test("Tên nhãn hiển thị")
    func labelNames() {
        #expect(LyricsText.labelName(GroupLabel(kind: .verse, number: 1)) == "Câu 1")
        #expect(LyricsText.labelName(GroupLabel(kind: .chorus)) == "Điệp khúc")
        #expect(LyricsText.labelName(GroupLabel(kind: .bridge, number: 2)) == "Cầu nối 2")
        #expect(LyricsText.labelName(GroupLabel(kind: .custom, custom: "Lời chứng")) == "Lời chứng")
        #expect(LyricsText.labelName(GroupLabel(kind: .custom)) == "Đoạn")
    }
}

@Suite("LyricsText: phân tích")
struct LyricsParseTests {
    @Test("Số đứng một mình không phải nhãn; '1.' và '1. lời' là nhãn")
    func numbersAsLabels() {
        let parsed = LyricsText.parse("1.\nLời một\n\n2. Lời hai\n3\nvẫn là lời hai")
        let labels = [GroupLabel(kind: .verse, number: 1), GroupLabel(kind: .verse, number: 2)]
        #expect(parsed.sections.map(\.label) == labels)
        #expect(parsed.sections.map(\.slides) == [["Lời một"], ["Lời hai\n3\nvẫn là lời hai"]])
    }

    @Test("Địa chỉ câu và giờ không phải nhãn liền dòng")
    func colonsInsideLyrics() {
        let parsed = LyricsText.parse("[Câu 1]\nGiăng 3:16 dạy rằng\nCâu: lời có dấu hai chấm")
        #expect(parsed.sections.count == 1)
        #expect(parsed.sections[0].slides == ["Giăng 3:16 dạy rằng\nCâu: lời có dấu hai chấm"])
    }

    @Test("Lời đứng trước nhãn đầu tiên thành đoạn 'Câu' không số")
    func leadingUnlabeledText() {
        let parsed = LyricsText.parse("Lời mở đầu\n\n[ĐK]\nĐiệp khúc")
        #expect(parsed.sections.map(\.label) == [GroupLabel(kind: .verse), GroupLabel(kind: .chorus)])
        #expect(parsed.order == [0, 1])
    }

    @Test("Cùng nhãn nhưng khác lời là đoạn mới; cùng nhãn cùng lời là hát lại")
    func repeatedLabels() {
        let parsed = LyricsText.parse("[ĐK]\nA\n\n[ĐK]\nB\n\n[ĐK]\nA")
        #expect(parsed.sections.map(\.slides) == [["A"], ["B"]])
        #expect(parsed.order == [0, 1, 0])
    }

    @Test("Văn bản không nhãn có hai khối lặp: Điệp khúc 1 và Điệp khúc 2")
    func twoRepeatedBlocks() {
        let parsed = LyricsText.parse("A\n\nX\n\nB\n\nY\n\nX\n\nY")
        #expect(
            parsed.sections.map(\.label) == [
                GroupLabel(kind: .verse, number: 1), GroupLabel(kind: .chorus, number: 1),
                GroupLabel(kind: .verse, number: 2), GroupLabel(kind: .chorus, number: 2),
            ])
        #expect(parsed.order == [0, 1, 2, 3, 1, 3])
    }

    @Test("Thứ tự 'ĐK' khớp 'Điệp khúc 1' khi bài chỉ có một điệp khúc; nhãn tự đặt khớp theo chữ gộp dấu")
    func orderMatching() {
        let parsed = LyricsText.parse("Thứ tự: Câu 1, ĐK, Loi chung, ĐK\n[Câu 1]\nA\n[Điệp khúc 1]\nB\n[Lời chứng]\nC")
        #expect(parsed.hasExplicitOrder)
        #expect(parsed.order == [0, 1, 2, 1])
        #expect(parsed.issues.isEmpty)
    }

    @Test("Văn bản rỗng cho kết quả rỗng, không lỗi")
    func emptyText() {
        let parsed = LyricsText.parse("\n\n   \n")
        #expect(parsed.sections.isEmpty)
        #expect(parsed.order.isEmpty)
    }

    @Test("Siêu dữ liệu chỉ đọc ở đầu bài; tác giả tách bằng dấu phẩy hoặc chấm phẩy")
    func metadata() {
        let parsed = LyricsText.parse("Tác giả: A; B , C\nSố: 5\n\nLời\nTông: không phải siêu dữ liệu")
        #expect(parsed.authors == ["A", "B", "C"])
        #expect(parsed.number == "5")
        #expect(parsed.key == nil)
        #expect(parsed.sections.first?.slides == ["Lời\nTông: không phải siêu dữ liệu"])
    }
}

@Suite("LyricsText: dựng văn bản")
struct LyricsRenderTests {
    @Test("Bài mới có trang trống: render rồi parse vẫn có một trang trống")
    func newSongRoundTrip() {
        let song = Presentation.newSong(title: "Bài mới", now: fixedDate)
        let text = LyricsText.render(song)
        #expect(text == "Tiêu đề: Bài mới\n\n[Câu 1]\n")
        let again = LyricsText.parse(text).makePresentation(fallbackTitle: "x", now: fixedDate)
        #expect(SongShape(again) == SongShape(song))
    }

    @Test("Ghi dòng Thứ tự khi thứ tự hát khác thứ tự đoạn; dòng trống trong trang bị bỏ")
    func rendersOrderAndCleansSlides() {
        var song = Presentation.newSong(title: "Bài", now: fixedDate)
        let verse = song.groups[0]
        let chorus = SlideGroup(
            label: GroupLabel(kind: .chorus),
            slides: [Slide(elements: [.text(TextElement(slot: .body, text: "  Dòng một  \n\n Dòng hai"))])])
        song.groups.append(chorus)
        song.arrangements[0].groupIDs = [verse.id, chorus.id, verse.id]
        song.song?.authors = ["A", "B"]
        let text = LyricsText.render(song)
        let header = "Tiêu đề: Bài\nTác giả: A, B\nThứ tự: Câu 1, Điệp khúc, Câu 1\n"
        #expect(text == header + "\n[Câu 1]\n\n[Điệp khúc]\nDòng một\nDòng hai\n")
    }
}

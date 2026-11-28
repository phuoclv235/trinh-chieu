import CoreModel
import Foundation
import LibraryIndex
import Scripture
import Testing

@testable import LibraryStore

/// Lệnh như ứng dụng đưa vào (tên đã dịch sang tiếng Việt).
private let commands: [PaletteCommand] = [
    PaletteCommand(id: .clearAll, title: "Xoá tất cả", keywords: ["xoa man"], shortcut: "F1"),
    PaletteCommand(id: .clearText, title: "Xoá chữ", shortcut: "F2"),
    PaletteCommand(id: .clearBackground, title: "Xoá nền", shortcut: "F3"),
    PaletteCommand(id: .toggleRehearsal, title: "Bật hoặc tắt Tập dượt", shortcut: "⌘R"),
    PaletteCommand(id: .toggleFreeze, title: "Bật hoặc tắt Đóng băng", shortcut: "⇧⌘F"),
    PaletteCommand(id: .liveMode, title: "Chế độ Trực tiếp", shortcut: "⌘1"),
    PaletteCommand(id: .editorMode, title: "Chế độ Soạn thảo", shortcut: "⌘2"),
    PaletteCommand(id: .newSong, title: "Bài hát mới", shortcut: "⌘N"),
    PaletteCommand(id: .importFiles, title: "Nhập tệp", shortcut: "⌘I"),
    PaletteCommand(id: .openSettings, title: "Mở Cài đặt", shortcut: "⌘,"),
    PaletteCommand(id: .identifyScreens, title: "Hiện số trên từng màn"),
]

private let tt1925 = PaletteScriptureContext(
    translationCode: "tt1925", abbreviation: "TT1925",
    previewText:
        "Vì Đức Chúa Trời yêu thương thế gian, đến nỗi đã ban Con một của Ngài, hầu cho hễ ai tin Con ấy không bị "
        + "hư mất mà được sự sống đời đời.")

private func song(_ title: String, number: String? = nil, score: Double = -1, id: UUID = UUID()) -> SearchHit {
    SearchHit(id: id.uuidString, kind: .presentation, title: title, subtitle: number, score: score)
}

private func rank(
    _ query: String, hits: [SearchHit] = [], planItems: [PaletteItem] = [], recents: [PaletteItem] = [],
    usage: [String: Int] = [:], scripture: PaletteScriptureContext? = tt1925,
    kind: (String) -> PresentationKind? = { _ in nil }
) -> [PaletteSection] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    let parse = trimmed.isEmpty ? nil : ReferenceParser().parse(trimmed)
    return PaletteRanker().rank(
        query: query, scriptureParse: parse, scripture: scripture, hits: hits, presentationKind: kind,
        commands: commands, planItems: planItems, recents: recents, commandUsage: usage)
}

private func section(_ group: PaletteGroup, in sections: [PaletteSection]) -> PaletteSection? {
    sections.first { $0.group == group }
}

@Suite("Bảng lệnh: Kinh Thánh")
struct PaletteScriptureTests {
    @Test("“gi 3 16”: nhóm Kinh Thánh lên đầu, một dòng Giăng 3:16 (TT1925)")
    func fullReferenceFirst() throws {
        let sections = rank("gi 3 16", hits: [song("Giăng tay đón Chúa")])
        let first = try #require(sections.first)
        #expect(first.group == .scripture)
        #expect(first.rows.count == 1)
        let row = try #require(first.rows.first)
        #expect(row.title == "Giăng 3:16")
        #expect(row.detail == "(TT1925)")
        #expect(row.target == .scripture(translation: "tt1925", reference: "Giăng 3:16"))
        #expect(row.target.hasSecondaryAction)
    }

    @Test("Câu dài: chỉ 80 ký tự đầu, thêm dấu ba chấm")
    func previewIsCut() throws {
        let row = try #require(rank("gi 3:16").first?.rows.first)
        let subtitle = try #require(row.subtitle)
        #expect(subtitle.hasSuffix("…"))
        #expect(subtitle.count <= PaletteRanker.previewLength + 1)
        #expect(subtitle.hasPrefix("Vì Đức Chúa Trời yêu thương thế gian"))
    }

    @Test("Câu ngắn giữ nguyên; khoảng trắng thừa được gộp")
    func shortPreviewKept() {
        #expect(PaletteRanker.preview("Chúa  là\nĐấng chăn giữ ta") == "Chúa là Đấng chăn giữ ta")
        #expect(PaletteRanker.preview("   ") == nil)
        let exact = String(repeating: "a", count: PaletteRanker.previewLength)
        #expect(PaletteRanker.preview(exact) == exact)
    }

    @Test("Chưa có bản dịch: vẫn hiện địa chỉ, không có hành động phụ, không ghi gần đây")
    func referenceWithoutTranslation() throws {
        let row = try #require(rank("rô 8:28", scripture: nil).first?.rows.first)
        #expect(row.target == .scripture(translation: nil, reference: "Rô-ma 8:28"))
        #expect(row.detail == nil)
        #expect(row.subtitle == nil)
        #expect(!row.target.hasSecondaryAction)
        #expect(!row.target.isRecordable)
    }

    @Test("Chỉ có tên sách: liệt kê sách ứng viên, chọn thì điền tên sách")
    func bookOnlyListsCandidates() throws {
        let sections = rank("gi")
        let scripture = try #require(section(.scripture, in: sections))
        #expect(scripture.rows.first?.title == "Giăng")
        #expect(scripture.rows.first?.target == .bookCompletion(text: "Giăng "))
        #expect(scripture.rows.count > 1)
        #expect(scripture.rows.count <= 5)
        #expect(Set(scripture.rows.map(\.id)).count == scripture.rows.count)
        #expect(scripture.rows.allSatisfy { !$0.target.hasSecondaryAction })
    }

    @Test("Tên sách mơ hồ: giữ phần chương câu đã gõ khi điền")
    func ambiguousBookKeepsRest() throws {
        let scripture = try #require(section(.scripture, in: rank("e-xơ 1")))
        let texts = scripture.rows.compactMap { row -> String? in
            if case .bookCompletion(let text) = row.target { return text }
            return nil
        }
        #expect(texts.count == 2)
        #expect(texts.allSatisfy { $0.hasSuffix(" 1") })
    }

    @Test("Địa chỉ sai: không có nhóm Kinh Thánh")
    func invalidReferenceHasNoScripture() {
        #expect(section(.scripture, in: rank("gi 3:0")) == nil)
        #expect(section(.scripture, in: rank("xyz 3:16")) == nil)
    }
}

@Suite("Bảng lệnh: bài hát, bộ trình chiếu, media")
struct PaletteLibraryTests {
    @Test("“123”: thánh ca số 123 ở dòng đầu, dù chỉ mục trả số khớp tiền tố trước")
    func numberMatchFirst() throws {
        let exact = song("Ngợi khen Chúa", number: "123", score: LibraryIndex.exactNumberScore)
        let hits = [
            song("Bài 1234", number: "1234", score: LibraryIndex.numberPrefixScore),
            exact,
            song("Lời có số 123", score: -2),
        ]
        let sections = rank("123", hits: hits)
        let first = try #require(sections.first)
        #expect(first.group == .songs)
        #expect(first.rows.first?.title == "Ngợi khen Chúa")
        #expect(first.rows.count == 3)
    }

    @Test("Truy vấn toàn số: không gợi ý Kinh Thánh hay lệnh")
    func numberHasNoScriptureOrCommands() {
        let sections = rank("3")
        #expect(section(.scripture, in: sections) == nil)
        #expect(section(.commands, in: sections) == nil)
    }

    @Test("Bộ trình chiếu không phải bài hát vào nhóm riêng")
    func genericPresentationsSeparated() throws {
        let notice = song("Thông báo Chúa Nhật")
        let hymn = song("Thánh ca buổi sáng")
        let sections = rank("th", hits: [notice, hymn]) { $0 == notice.id ? .generic : .song }
        #expect(section(.songs, in: sections)?.rows.map(\.title) == ["Thánh ca buổi sáng"])
        #expect(section(.presentations, in: sections)?.rows.map(\.title) == ["Thông báo Chúa Nhật"])
    }

    @Test("Không rõ loại (chỉ mục cũ): coi là bài hát")
    func unknownKindIsSong() {
        let sections = rank("ân", hits: [song("Ân điển lạ lùng")])
        #expect(section(.songs, in: sections)?.rows.count == 1)
        #expect(section(.presentations, in: sections) == nil)
    }

    @Test("Media vào nhóm Media, đích là mã media")
    func mediaHits() throws {
        let hit = SearchHit(id: "abc123", kind: .media, title: "Nền núi.jpg", subtitle: nil, score: -1)
        let media = try #require(section(.media, in: rank("nen", hits: [hit])))
        #expect(media.rows.first?.target == .media(MediaID("abc123")))
        #expect(media.rows.first?.target.hasSecondaryAction == true)
    }

    @Test("Bỏ qua mẫu, chương trình, câu Kinh Thánh của chỉ mục và kết quả trùng")
    func ignoresOtherKindsAndDuplicates() {
        let id = UUID()
        let hits = [
            SearchHit(id: UUID().uuidString, kind: .theme, title: "Nền tối", subtitle: nil, score: -1),
            SearchHit(id: UUID().uuidString, kind: .plan, title: "Nhóm Chúa Nhật", subtitle: nil, score: -1),
            SearchHit(id: "bible:tt1925:John.3.16", kind: .verse, title: "Giăng 3:16", subtitle: nil, score: -1),
            song("Nước sông Giô-đanh", id: id),
            song("Nước sông Giô-đanh", id: id),
        ]
        let sections = rank("nuoc", hits: hits)
        #expect(sections.flatMap(\.rows).filter { $0.group != .commands }.count == 1)
    }

    @Test("Nhóm Bài hát tối đa 8 dòng, giữ thứ tự điểm")
    func songLimit() throws {
        let hits = (1...12).map { song("Chúa \($0)", score: Double(-$0)) }
        let songs = try #require(section(.songs, in: rank("chua", hits: hits)))
        #expect(songs.rows.count == 8)
        #expect(songs.rows.first?.title == "Chúa 1")
    }

    @Test("Không có kết quả: không có nhóm rỗng")
    func noEmptySections() {
        let sections = rank("qqqq")
        #expect(sections.allSatisfy { !$0.rows.isEmpty })
        #expect(sections.isEmpty)
    }
}

@Suite("Bảng lệnh: lệnh và chương trình buổi nhóm")
struct PaletteCommandTests {
    @Test("“xoa chu”: lệnh Xoá chữ ở nhóm Lệnh, dòng đầu")
    func clearTextCommand() throws {
        let sections = rank("xoa chu")
        let group = try #require(section(.commands, in: sections))
        #expect(group.rows.first?.target == .command(.clearText))
        #expect(group.rows.first?.shortcut == "F2")
        #expect(group.rows.count == 1)
    }

    @Test("“xoa”: ba lệnh xoá, đúng thứ tự khai báo")
    func clearCommandsByPrefix() throws {
        let group = try #require(section(.commands, in: rank("xoá")))
        #expect(group.rows.map(\.target) == [.command(.clearAll), .command(.clearText), .command(.clearBackground)])
    }

    @Test("Gõ đảo từ vẫn ra lệnh, xếp sau lệnh khớp tiền tố")
    func wordOrderMatch() throws {
        let group = try #require(section(.commands, in: rank("chu xoa")))
        #expect(group.rows.map(\.target) == [.command(.clearText)])
        let mixed = try #require(section(.commands, in: rank("bat")))
        #expect(mixed.rows.first?.target == .command(.toggleRehearsal))
    }

    @Test("Tìm bằng tên khác của lệnh")
    func keywordMatch() throws {
        let group = try #require(section(.commands, in: rank("xoa man")))
        #expect(group.rows.first?.target == .command(.clearAll))
    }

    @Test("Lệnh khớp tiền tố đứng trên bài hát chỉ khớp lời")
    func commandBeforeWeakSongs() throws {
        let sections = rank("xoa chu", hits: [song("Ơn Chúa xoá tội", score: -3)])
        #expect(sections.first?.group == .commands)
        #expect(section(.songs, in: sections) != nil)
    }

    @Test("Bài hát và lệnh cùng khớp tiền tố: bài hát trước")
    func songsBeforeCommandsOnTie() throws {
        let sections = rank("nhap", hits: [song("Nhập vào nơi thánh")])
        #expect(sections.map(\.group).prefix(2) == [.songs, .commands])
    }

    @Test("Mục chương trình lọc theo chữ đã gõ, khớp tiền tố trước")
    func planItemsFiltered() throws {
        let welcome = UUID()
        let sermon = UUID()
        let items = [
            PaletteItem(target: .planItem(id: sermon), title: "Bài giảng", subtitle: "Mục sư Quản nhiệm"),
            PaletteItem(target: .planItem(id: welcome), title: "Chào mừng", subtitle: "Bài giảng sau đó"),
            PaletteItem(target: .planItem(id: UUID()), title: "Dâng hiến"),
        ]
        let group = try #require(section(.planItems, in: rank("bai giang", planItems: items)))
        #expect(group.rows.map(\.target) == [.planItem(id: sermon), .planItem(id: welcome)])
        #expect(group.rows.allSatisfy { $0.target.hasSecondaryAction })
    }

    @Test("Lệnh không có hành động phụ và không ghi vào gần đây")
    func commandTargetFlags() {
        let target = PaletteTarget.command(.clearAll)
        #expect(!target.hasSecondaryAction)
        #expect(!target.isRecordable)
        #expect(!PaletteTarget.bookCompletion(text: "Giăng ").isRecordable)
        #expect(PaletteTarget.presentation(id: UUID()).isRecordable)
    }
}

@Suite("Bảng lệnh: ô trống và lịch sử")
struct PaletteHistoryTests {
    private func recent(_ title: String) -> PaletteItem {
        PaletteItem(target: .presentation(id: UUID()), title: title)
    }

    @Test("Ô trống: 5 mục gần đây và 4 lệnh hay dùng")
    func emptyQueryShowsRecentsAndCommands() throws {
        let recents = (1...7).map { recent("Bài \($0)") }
        let sections = rank("", recents: recents)
        #expect(sections.map(\.group) == [.recent, .commands])
        #expect(sections[0].rows.count == 5)
        #expect(sections[0].rows.first?.title == "Bài 1")
        #expect(
            sections[1].rows.map(\.target) == PaletteCommandID.defaultFrequent.map { PaletteTarget.command($0) })
    }

    @Test("Ô chỉ có khoảng trắng coi như trống; chưa dùng gì thì chỉ có lệnh")
    func whitespaceIsEmpty() {
        let sections = rank("   ")
        #expect(sections.map(\.group) == [.commands])
        #expect(sections.first?.rows.count == PaletteRanker.frequentCommandCount)
    }

    @Test("Lệnh dùng nhiều nhất lên đầu")
    func usageOrdersCommands() throws {
        let usage = ["identifyScreens": 5, "toggleFreeze": 2]
        let group = try #require(section(.commands, in: rank("", usage: usage)))
        let expected: [PaletteCommandID] = [.identifyScreens, .toggleFreeze, .clearAll, .clearText]
        #expect(group.rows.map(\.target) == expected.map { PaletteTarget.command($0) })
    }

    @Test("Ghi gần đây: mới nhất lên đầu, bỏ trùng, tối đa 5")
    func recordingKeepsFiveUnique() {
        var recents: [PaletteItem] = []
        let first = recent("Bài A")
        recents = PaletteHistory.recording(first, in: recents)
        for index in 1...6 {
            recents = PaletteHistory.recording(recent("Bài \(index)"), in: recents)
        }
        #expect(recents.count == 5)
        #expect(recents.first?.title == "Bài 6")
        recents = PaletteHistory.recording(recents[3], in: recents)
        #expect(recents.first?.title == "Bài 3")
        #expect(Set(recents.map(\.target)).count == 5)
        let command = PaletteItem(target: .command(.clearAll), title: "Xoá tất cả")
        #expect(PaletteHistory.recording(command, in: recents) == recents)
    }

    @Test("Đếm số lần dùng lệnh")
    func countingUsage() {
        var usage: [String: Int] = [:]
        usage = PaletteHistory.counting(.clearText, in: usage)
        usage = PaletteHistory.counting(.clearText, in: usage)
        #expect(usage["clearText"] == 2)
        #expect(PaletteHistory.frequent(usage, count: 2) == [.clearText, .clearAll])
        #expect(PaletteHistory.frequent([:], count: 0).isEmpty)
    }

    @Test("Mục gần đây mã hoá JSON rồi đọc lại không đổi")
    func recentsRoundTrip() throws {
        let items = [
            PaletteItem(target: .scripture(translation: "tt1925", reference: "Giăng 3:16"), title: "Giăng 3:16"),
            PaletteItem(target: .media(MediaID("m1")), title: "Nền", subtitle: "Ảnh"),
            PaletteItem(target: .planItem(id: UUID()), title: "Chào mừng"),
        ]
        let data = try JSONEncoder().encode(items)
        #expect(try JSONDecoder().decode([PaletteItem].self, from: data) == items)
    }

    @Test("Mã dòng không trùng giữa các nhóm")
    func rowIDsUnique() {
        let id = UUID()
        let recentRow = PaletteRow(group: .recent, target: .presentation(id: id), title: "A")
        let songRow = PaletteRow(group: .songs, target: .presentation(id: id), title: "A")
        #expect(recentRow.id != songRow.id)
    }
}

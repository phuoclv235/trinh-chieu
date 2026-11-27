import CoreModel
import Foundation
import Testing

@testable import Importers

/// Kết quả mong đợi viết tay cho 5 tệp OpenLyrics mẫu.
let expectedOpenLyrics: [String: SongShape] = [
    "01-co-ban.xml": SongShape(
        title: "Bài OpenLyrics Cơ Bản", number: "12", hymnal: "Thánh Ca", authors: ["Người Viết Thử"],
        copyright: "Dữ liệu thử của Hệ thống",
        groups: [
            group(.verse, 1, "Câu một dòng một\nCâu một dòng hai"),
            group(.chorus, nil, "Điệp khúc dòng một\nĐiệp khúc dòng hai"),
            group(.verse, 2, "Câu hai dòng một\nCâu hai dòng hai"),
        ],
        order: [0, 1, 2, 1]
    ),
    "02-hop-am.xml": SongShape(
        title: "Bài Có Hợp Âm",
        groups: [
            group(.verse, 1, "Ngợi khen Chúa\nHát lên mãi"),
            group(.chorus, 1, "Ha-lê-lu-gia"),
        ]
    ),
    "03-nhieu-tac-gia.xml": SongShape(
        title: "Bài Nhiều Tác Giả", authors: ["Tác Giả Lời", "Tác Giả Nhạc", "Người Dịch"],
        copyright: "2026 Dữ liệu thử", ccli: "1234567", key: "D", tempo: 72,
        groups: [group(.verse, 1, "Lời câu một")]
    ),
    "04-thu-tu.xml": SongShape(
        title: "Bài Thứ Tự Hát",
        groups: [
            group(.verse, 1, "Trang một câu một", "Trang hai câu một"),
            group(.prechorus, 1, "Tiền điệp khúc"),
            group(.chorus, nil, "Điệp khúc"),
            group(.bridge, 1, "Cầu nối"),
            group(.ending, nil, "A-men"),
        ],
        order: [0, 1, 2, 3, 2, 4]
    ),
    "05-nhieu-ngon-ngu.xml": SongShape(
        title: "Bài Hai Ngôn Ngữ",
        groups: [
            group(.verse, 1, "Lời tiếng Việt\ndòng hai"),
            custom("Lời dẫn", "Hãy cùng đứng lên"),
        ]
    ),
]

@Suite("OpenLyrics: nhập")
struct OpenLyricsImportTests {
    @Test("Có đủ 5 tệp mẫu và mỗi tệp có kết quả mong đợi")
    func fixturesAreComplete() throws {
        let names = try fixtureNames(in: "OpenLyrics")
        #expect(names.count == 5)
        #expect(Set(names) == Set(expectedOpenLyrics.keys))
    }

    @Test("Nhập đúng như kết quả viết tay", arguments: expectedOpenLyrics.keys.sorted())
    func importsAsExpected(name: String) throws {
        let data = try fixtureData("OpenLyrics/" + name)
        #expect(OpenLyricsImporter.canImport(data, filename: name))
        #expect(!PlainLyricsImporter.canImport(data, filename: name))
        let result = try importFixture("OpenLyrics/" + name)
        #expect(result.shape == expectedOpenLyrics[name])
        #expect(result.presentation.kind == .song)
    }

    @Test("Hợp âm bị bỏ, cảnh báo một lần mỗi tệp")
    func chordsWarnOnce() throws {
        let warnings = try importFixture("OpenLyrics/02-hop-am.xml").warnings
        #expect(warnings.map(\.message) == ["Tệp có hợp âm; Hệ thống bỏ qua hợp âm khi nhập."])
        #expect(warnings.first?.filename == "02-hop-am.xml")
    }

    @Test("Thứ tự hát nhắc đoạn không có: bỏ tên đó, cảnh báo có vị trí")
    func unknownVerseOrderName() throws {
        let warnings = try importFixture("OpenLyrics/04-thu-tu.xml").warnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.location == "verseOrder")
        #expect(warnings.first?.message.contains("“x9”") == true)
    }

    @Test("Lời nhiều ngôn ngữ: giữ ngôn ngữ đầu, cảnh báo")
    func multipleLanguages() throws {
        let warnings = try importFixture("OpenLyrics/05-nhieu-ngon-ngu.xml").warnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.contains("nhiều ngôn ngữ") == true)
    }

    @Test("Tên đoạn OpenLyrics thành nhãn")
    func verseNames() {
        #expect(OpenLyricsImporter.label(forVerseName: "v1") == GroupLabel(kind: .verse, number: 1))
        #expect(OpenLyricsImporter.label(forVerseName: "v1a") == GroupLabel(kind: .verse, number: 1))
        #expect(OpenLyricsImporter.label(forVerseName: "C2") == GroupLabel(kind: .chorus, number: 2))
        #expect(OpenLyricsImporter.label(forVerseName: "chorus") == GroupLabel(kind: .chorus))
        #expect(OpenLyricsImporter.label(forVerseName: "p") == GroupLabel(kind: .prechorus))
        #expect(OpenLyricsImporter.label(forVerseName: "i") == GroupLabel(kind: .intro))
        #expect(OpenLyricsImporter.label(forVerseName: "o-Lời_dẫn") == GroupLabel(kind: .custom, custom: "Lời dẫn"))
        #expect(OpenLyricsImporter.label(forVerseName: "x") == GroupLabel(kind: .custom, custom: "x"))
    }

    @Test("XML hỏng: lỗi tiếng Việt có tên tệp và dòng")
    func brokenXML() throws {
        let data = try fixtureData("Broken/hong.xml")
        #expect(throws: ImportError.self) {
            try openLyricsImporter.importDocuments(from: data, filename: "hong.xml")
        }
        do {
            _ = try openLyricsImporter.importDocuments(from: data, filename: "hong.xml")
        } catch let error as ImportError {
            guard case .invalidXML(let filename, let line, _) = error else {
                Issue.record("Sai loại lỗi: \(error)")
                return
            }
            #expect(filename == "hong.xml")
            #expect(line != nil)
            #expect(error.message.hasPrefix("Tệp hong.xml bị hỏng"))
        }
    }

    @Test("XML không phải bài hát: lỗi tiếng Việt")
    func notASong() {
        let data = Data("<?xml version=\"1.0\"?><song xmlns=\"http://openlyrics.info/namespace/2009/song\"/>".utf8)
        #expect(throws: ImportError.empty(filename: "rong.xml")) {
            try openLyricsImporter.importDocuments(from: data, filename: "rong.xml")
        }
        let other = Data("<?xml version=\"1.0\"?><html><body>openlyrics</body></html>".utf8)
        #expect(throws: ImportError.self) {
            try openLyricsImporter.importDocuments(from: other, filename: "trang.html")
        }
    }
}

@Suite("OpenLyrics: xuất")
struct OpenLyricsExportTests {
    /// Mọi tệp mẫu (văn bản và OpenLyrics).
    static let allFixtures: [String] = {
        let lyrics = expectedLyrics.keys.sorted().map { "Lyrics/" + $0 }
        return lyrics + expectedOpenLyrics.keys.sorted().map { "OpenLyrics/" + $0 }
    }()

    @Test("Xuất rồi nhập lại không mất nội dung", arguments: allFixtures)
    func exportImportRoundTrip(path: String) throws {
        let original = try importFixture(path).presentation
        let data = OpenLyricsExporter.export(original, modifiedDate: fixedDate)
        #expect(OpenLyricsImporter.canImport(data, filename: "xuat.xml"))
        let outcome = try openLyricsImporter.importDocuments(from: data, filename: "xuat.xml")
        let again = try #require(outcome.presentations.first)
        #expect(SongShape(again) == SongShape(original))
        #expect(outcome.warnings.isEmpty)
    }

    @Test("Văn bản lời bài hát giữ nội dung của tệp OpenLyrics", arguments: expectedOpenLyrics.keys.sorted())
    func openLyricsThroughLyricsText(name: String) throws {
        let original = try importFixture("OpenLyrics/" + name).presentation
        let again = LyricsText.parse(LyricsText.render(original)).makePresentation(fallbackTitle: "x", now: fixedDate)
        #expect(SongShape(again) == SongShape(original).lyricsTextFields)
    }

    @Test("Ký tự đặc biệt được thoát; tên đoạn không trùng")
    func escapingAndUniqueNames() throws {
        var song = Presentation.newSong(title: "A & B <C>", now: fixedDate)
        let first = song.groups[0]
        let second = SlideGroup(
            label: first.label, slides: [Slide(elements: [.text(TextElement(slot: .body, text: "\"x\" & y"))])])
        song.groups.append(second)
        song.arrangements[0].groupIDs = [first.id, second.id]
        let xml = OpenLyricsExporter.exportString(song, modifiedDate: fixedDate)
        #expect(xml.contains("<title>A &amp; B &lt;C&gt;</title>"))
        #expect(xml.contains("<verseOrder>v1 v1b</verseOrder>"))
        #expect(xml.contains("<lines>&quot;x&quot; &amp; y</lines>"))
        let again = try openLyricsImporter.importDocuments(from: Data(xml.utf8), filename: "x.xml")
        #expect(SongShape(try #require(again.presentations.first)) == SongShape(song))
    }
}

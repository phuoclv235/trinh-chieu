import CoreModel
import Foundation
import Testing

@testable import Importers

/// Kết quả mong đợi viết tay cho 10 tệp văn bản lời bài hát mẫu.
let expectedLyrics: [String: SongShape] = [
    "01-nhan-ngoac-vuong.txt": SongShape(
        title: "Ngợi Khen Đấng Chăn Hiền Lành", number: "12", authors: ["Người Viết Thử", "Nhóm Biên Soạn"],
        copyright: "Dữ liệu thử của Hệ thống", key: "G",
        groups: [
            group(
                .verse, 1, "Sáng nay con cất tiếng ca\nDâng lên Cha lời cảm tạ",
                "Bước theo Chúa suốt đường xa\nLòng con vui hát hoà ca"),
            group(.chorus, nil, "Ha-lê-lu-gia, ngợi khen Chúa\nHa-lê-lu-gia, Ngài yêu thương"),
            group(.verse, 2, "Chiều buông con vẫn ngợi ca\nChúa luôn ở cùng chúng ta"),
        ],
        order: [0, 1, 2, 1]
    ),
    "02-nhan-khong-ngoac.txt": SongShape(
        title: "02-nhan-khong-ngoac",
        groups: [
            group(.verse, 1, "Trên đồi xanh con lắng nghe\nTiếng Chúa gọi êm như gió hè"),
            group(.chorus, nil, "Con xin theo, con xin theo\nDù đường xa hay núi đèo"),
            group(.verse, 2, "Khi đêm sâu con chẳng lo\nChúa soi đường như ánh đuốc to"),
        ]
    ),
    "03-nhan-tieng-anh.txt": SongShape(
        title: "Morning Song Test",
        groups: [
            group(.intro, nil, "Oh oh oh"),
            group(.verse, 1, "Morning light upon the hill\nEvery heart is calm and still"),
            group(.prechorus, nil, "And we lift our voice"),
            group(.chorus, nil, "Glory, glory in the morning\nGlory, glory all day long"),
            group(.bridge, nil, "Hold on, hold on"),
            group(.tag, nil, "All day long"),
            group(.ending, nil, "Amen"),
        ]
    ),
    "04-nhan-dong-lien.txt": SongShape(
        title: "Bài Nhãn Liền Dòng",
        groups: [
            group(.verse, 1, "Đất trời đều hát lên\nNgợi danh Chúa thánh thiện"),
            group(.chorus, nil, "Hô-sa-na, Hô-sa-na\nVinh hiển thay danh Ngài"),
            group(.verse, 2, "Biển sâu cùng núi cao\nĐều ca tụng Chúa nào"),
        ]
    ),
    "05-khong-nhan.txt": SongShape(
        title: "05-khong-nhan",
        groups: [
            group(.verse, 1, "Con đi trong ánh sáng\nChúa dẫn từng bước chân"),
            group(.chorus, nil, "Ngợi khen Chúa, ngợi khen Chúa\nLòng con vui mãi không thôi"),
            group(.verse, 2, "Dù mưa giông bão tố\nChúa vẫn ở bên con"),
            group(.verse, 3, "Một ngày kia con sẽ\nVề nhà Cha trên cao"),
        ],
        order: [0, 1, 2, 1, 3, 1]
    ),
    "06-utf16le.txt": SongShape(
        title: "Bài UTF-16",
        groups: [
            group(.verse, 1, "Chúa ơi con đến cùng Ngài\nLòng con tin cậy chẳng phai"),
            group(.chorus, nil, "Bình an, bình an\nTrong tay Chúa con an vui"),
        ]
    ),
    "07-windows-1258.txt": SongShape(
        title: "Bài Windows-1258",
        groups: [
            group(.verse, 1, "Việt Nam đất nước Chúa thương\nĐồng xanh sông núi mọi phương"),
            group(.chorus, nil, "Ngợi khen Đức Chúa Trời\nMuôn đời chẳng hề thôi"),
        ]
    ),
    "08-trang-dai-nhan-rieng.txt": SongShape(
        title: "Bài Có Trang Dài",
        groups: [
            group(.verse, 1, "Dòng một\nDòng hai\nDòng ba\nDòng bốn\nDòng năm\nDòng sáu"),
            custom("Lời chứng", "Chúa đã làm việc lớn cho tôi"),
        ],
        order: [0, 1, 0]
    ),
    "09-crlf-bom-utf8.txt": SongShape(
        title: "Bài CRLF",
        groups: [
            group(.verse, 1, "Lời câu một dòng một\nLời câu một dòng hai"),
            group(.chorus, nil, "Điệp khúc dòng một\nĐiệp khúc dòng hai"),
            group(.verse, 2, "Lời câu hai"),
        ],
        order: [0, 1, 2, 1]
    ),
    "10-nhan-tieng-viet-khac.txt": SongShape(
        title: "Bài Đủ Loại Nhãn",
        groups: [
            group(.intro, nil, "La la la"),
            group(.verse, 1, "Lời câu một"),
            group(.prechorus, nil, "Lời tiền điệp khúc"),
            group(.chorus, nil, "Lời điệp khúc"),
            group(.bridge, nil, "Lời cầu nối"),
            group(.ending, nil, "A-men"),
        ]
    ),
]

@Suite("Văn bản lời bài hát: 10 tệp mẫu")
struct PlainLyricsFixtureTests {
    @Test("Có đủ 10 tệp mẫu và mỗi tệp có kết quả mong đợi")
    func fixturesAreComplete() throws {
        let names = try fixtureNames(in: "Lyrics")
        #expect(names.count == 10)
        #expect(Set(names) == Set(expectedLyrics.keys))
    }

    @Test("Nhập đúng như kết quả viết tay", arguments: expectedLyrics.keys.sorted())
    func importsAsExpected(name: String) throws {
        let result = try importFixture("Lyrics/" + name)
        #expect(result.shape == expectedLyrics[name])
        #expect(result.presentation.kind == .song)
        #expect(result.presentation.createdAt == fixedDate)
        #expect(result.presentation.arrangements.count == 1)
        #expect(result.presentation.activeArrangementID == result.presentation.arrangements.first?.id)
        for slide in result.presentation.groups.flatMap(\.slides) {
            guard case .text(let text) = slide.elements.first else {
                Issue.record("Trang không có phần tử chữ")
                continue
            }
            #expect(text.slot == .body)
        }
    }

    @Test("Tệp chỉ có nhãn và lời không sinh cảnh báo", arguments: ["01", "02", "03", "04", "05", "06", "09", "10"])
    func noWarnings(prefix: String) throws {
        let name = try #require(expectedLyrics.keys.first { $0.hasPrefix(prefix) })
        #expect(try importFixture("Lyrics/" + name).warnings.isEmpty)
    }

    @Test("Windows-1258: cảnh báo đã đọc theo bảng mã này, có tên tệp")
    func windows1258Warning() throws {
        let warnings = try importFixture("Lyrics/07-windows-1258.txt").warnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.filename == "07-windows-1258.txt")
        #expect(warnings.first?.message.contains("Windows-1258") == true)
    }

    @Test("Trang quá 4 dòng chỉ cảnh báo, không tự chia; thứ tự hát nhắc đoạn không có thì cảnh báo")
    func longSlideAndUnknownOrderName() throws {
        let result = try importFixture("Lyrics/08-trang-dai-nhan-rieng.txt")
        #expect(result.presentation.groups[0].slides.count == 1)
        #expect(result.warnings.map(\.location) == ["dòng 2", "dòng 4"])
        #expect(result.warnings[0].message.contains("“Câu 9”"))
        #expect(result.warnings[1].message.contains("Trang 1 của Câu 1 có 6 dòng"))
        #expect(result.warnings[1].description.hasPrefix("08-trang-dai-nhan-rieng.txt, dòng 4: "))
    }

    @Test("Kiểm vòng: render rồi parse giữ nguyên nội dung", arguments: expectedLyrics.keys.sorted())
    func renderParseRoundTrip(name: String) throws {
        let original = try importFixture("Lyrics/" + name).presentation
        let text = LyricsText.render(original)
        let parsed = LyricsText.parse(text)
        let again = parsed.makePresentation(fallbackTitle: "không dùng", now: fixedDate)
        #expect(SongShape(again) == SongShape(original))
        #expect(LyricsText.render(again) == text)
    }
}

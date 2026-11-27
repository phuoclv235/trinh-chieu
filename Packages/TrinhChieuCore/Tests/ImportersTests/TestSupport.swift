import CoreModel
import Foundation
import Testing

@testable import Importers

/// Ngày giờ cố định cho bộ trình chiếu nhập trong test.
let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

/// Đường dẫn tệp mẫu trong `Fixtures/`.
func fixtureURL(_ path: String) throws -> URL {
    let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return root.appendingPathComponent(path)
}

func fixtureData(_ path: String) throws -> Data {
    try Data(contentsOf: try fixtureURL(path))
}

/// Tên mọi tệp trong một thư mục mẫu, xếp theo tên.
func fixtureNames(in directory: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: try fixtureURL(directory).path).sorted()
}

/// Hình dạng nội dung của một đoạn: nhãn và chữ các trang.
struct GroupShape: Equatable, Sendable, CustomStringConvertible {
    var label: GroupLabel
    var slides: [String]

    var description: String {
        "\(LyricsText.labelName(label)) \(slides)"
    }
}

/// Hình dạng nội dung một bài hát, bỏ qua mã UUID và ngày giờ, để so sánh trong test.
struct SongShape: Equatable, Sendable {
    var title: String
    var number: String?
    var hymnal: String?
    var authors: [String] = []
    var copyright: String?
    var ccli: String?
    var key: String?
    var tempo: Int?
    var groups: [GroupShape]
    /// Thứ tự hát đang chọn, ghi bằng chỉ số đoạn.
    var order: [Int]

    init(
        title: String, number: String? = nil, hymnal: String? = nil, authors: [String] = [],
        copyright: String? = nil, ccli: String? = nil, key: String? = nil, tempo: Int? = nil,
        groups: [GroupShape], order: [Int]? = nil
    ) {
        self.title = title
        self.number = number
        self.hymnal = hymnal
        self.authors = authors
        self.copyright = copyright
        self.ccli = ccli
        self.key = key
        self.tempo = tempo
        self.groups = groups
        self.order = order ?? Array(groups.indices)
    }

    init(_ presentation: Presentation) {
        let song = presentation.song ?? SongInfo()
        let groups = presentation.groups.map { group in
            GroupShape(label: group.label, slides: group.slides.map(LyricsText.slideText))
        }
        let indexByID = Dictionary(uniqueKeysWithValues: presentation.groups.enumerated().map { ($1.id, $0) })
        self.init(
            title: presentation.title, number: song.number, hymnal: song.hymnal, authors: song.authors,
            copyright: song.copyright, ccli: song.ccli, key: song.key, tempo: song.tempo, groups: groups,
            order: presentation.orderedGroups().compactMap { indexByID[$0.id] }
        )
    }

    /// Chỉ các trường mà văn bản lời bài hát giữ được (không có tập thánh ca, CCLI, nhịp).
    var lyricsTextFields: SongShape {
        var copy = self
        copy.hymnal = nil
        copy.ccli = nil
        copy.tempo = nil
        return copy
    }
}

/// Đoạn `kind`, số `number`, các trang.
func group(_ kind: GroupLabelKind, _ number: Int? = nil, _ slides: String...) -> GroupShape {
    GroupShape(label: GroupLabel(kind: kind, number: number), slides: slides)
}

/// Đoạn có nhãn tự đặt.
func custom(_ name: String, _ slides: String...) -> GroupShape {
    GroupShape(label: GroupLabel(kind: .custom, custom: name), slides: slides)
}

/// Bộ nhập văn bản và OpenLyrics có ngày giờ cố định.
let plainImporter = PlainLyricsImporter(now: { fixedDate })
let openLyricsImporter = OpenLyricsImporter(now: { fixedDate })
let testRegistry = ImportRegistry(importers: [openLyricsImporter, plainImporter])

/// Nhập một tệp mẫu, trả bài hát duy nhất và các cảnh báo.
func importFixture(_ path: String) throws -> (shape: SongShape, presentation: Presentation, warnings: [ImportWarning]) {
    let url = try fixtureURL(path)
    let outcome = try testRegistry.importDocuments(from: try Data(contentsOf: url), filename: url.lastPathComponent)
    let presentation = try #require(outcome.presentations.first)
    #expect(outcome.presentations.count == 1)
    return (SongShape(presentation), presentation, outcome.warnings)
}

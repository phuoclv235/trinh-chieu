import Foundation
import Testing

@testable import CoreModel

private let fixturesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/schema-v1")

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixturesDirectory.appendingPathComponent(name))
}

private struct RoundTrip<T> {
    var original: String
    var written: String
    var value: T
}

/// Đọc rồi ghi lại, so từng byte.
private func roundTrip<T: Codable>(_ type: T.Type, _ name: String) throws -> RoundTrip<T> {
    let data = try fixture(name)
    let value = try DocumentCoding.decode(type, from: data)
    let written = try DocumentCoding.encode(value)
    let original = String(decoding: data, as: UTF8.self)
    return RoundTrip(original: original, written: String(decoding: written, as: UTF8.self), value: value)
}

@Suite("Tài liệu schema 1: đọc rồi ghi lại giống từng byte")
struct FixtureRoundTripTests {
    @Test("Bài hát 3 đoạn, 2 thứ tự hát")
    func songRoundTrips() throws {
        let result = try roundTrip(Presentation.self, "presentation-song.json")
        #expect(result.written == result.original)
        let song = result.value
        #expect(song.kind == .song)
        #expect(song.groups.count == 3)
        #expect(song.arrangements.count == 2)
        #expect(song.orderedGroups().map(\.id) == song.arrangements[1].groupIDs)
        #expect(song.groups[2].slides[0].enabled == false)
    }

    @Test("Bộ generic có ảnh và video")
    func genericRoundTrips() throws {
        let result = try roundTrip(Presentation.self, "presentation-generic.json")
        #expect(result.written == result.original)
        let elements = result.value.groups.flatMap(\.slides).flatMap(\.elements)
        #expect(elements.contains { if case .image = $0 { true } else { false } })
        #expect(elements.contains { if case .video = $0 { true } else { false } })
        #expect(elements.contains { if case .shape = $0 { true } else { false } })
        #expect(result.value.song == nil)
    }

    @Test("Mẫu trình bày")
    func themeRoundTrips() throws {
        let result = try roundTrip(Theme.self, "theme.json")
        #expect(result.written == result.original)
        #expect(result.value.slots[.reference].style.maxLines == 1)
        #expect(result.value.transition == TransitionSpec(kind: .dissolve, duration: 0.35))
    }

    @Test("Chương trình 5 loại mục")
    func planRoundTrips() throws {
        let result = try roundTrip(ServicePlan.self, "plan.json")
        #expect(result.written == result.original)
        #expect(result.value.items.map(\.isLiveable) == [false, true, true, true, false])
        #expect(result.value.items.map(\.plannedDuration) == [nil, 300, 120, nil, 30])
    }

    static let fixtureKinds: [(String, DocumentKind)] = [
        ("presentation-song.json", .presentation), ("presentation-generic.json", .presentation),
        ("theme.json", .theme), ("plan.json", .plan),
    ]

    @Test("Tệp mẫu đi qua migration không đổi", arguments: fixtureKinds)
    func fixturesPassMigrationUnchanged(name: String, kind: DocumentKind) throws {
        let data = try fixture(name)
        let (migrated, from) = try migrate(data, kind: kind)
        #expect(migrated == data)
        #expect(from == nil)
    }
}

@Suite("Mã hoá dùng chung")
struct DocumentCodingTests {
    @Test("RGBA đọc #RRGGBB và #RRGGBBAA, không phân biệt hoa thường; ghi #RRGGBBAA")
    func rgbaParsing() throws {
        #expect(try RGBA(hex: "#ff8000") == RGBA(red: 255, green: 128, blue: 0, alpha: 255))
        #expect(try RGBA(hex: "#FF800080") == RGBA(red: 255, green: 128, blue: 0, alpha: 128))
        #expect(try RGBA(hex: "#aBcDeF12").hexString == "#ABCDEF12")
        let decoded = try JSONDecoder().decode([RGBA].self, from: Data(##"["#00ff00"]"##.utf8))
        #expect(decoded == [RGBA(red: 0, green: 255, blue: 0)])
        let encoded = try JSONEncoder().encode([RGBA(red: 1, green: 2, blue: 3, alpha: 4)])
        #expect(String(decoding: encoded, as: UTF8.self) == ##"["#01020304"]"##)
    }

    @Test("RGBA sai định dạng ném lỗi tiếng Việt", arguments: ["", "#12345", "123456", "#GG0000", "#1234567"])
    func rgbaRejectsInvalid(value: String) {
        #expect(throws: DocumentError.invalidColor(value)) {
            try RGBA(hex: value)
        }
        #expect(DocumentError.invalidColor(value).message.contains("không hợp lệ"))
        let json = Data("[\"\(value)\"]".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([RGBA].self, from: json)
        }
    }

    @Test("frame thành [x, y, w, h], canvasSize thành [w, h]")
    func geometryEncodesAsArrays() throws {
        let encoder = JSONEncoder()
        let rect = PixelRect(x: 1, y: 2.5, width: 300, height: 40)
        #expect(String(decoding: try encoder.encode(rect), as: UTF8.self) == "[1,2.5,300,40]")
        #expect(String(decoding: try encoder.encode(PixelSize.fullHD), as: UTF8.self) == "[1920,1080]")
        #expect(try JSONDecoder().decode(PixelRect.self, from: Data("[1,2.5,300,40]".utf8)) == rect)
        let insets = EdgeInsets(top: 1, right: 2, bottom: 3, left: 4)
        #expect(try JSONDecoder().decode(EdgeInsets.self, from: try encoder.encode(insets)) == insets)
        #expect(PixelRect(size: .fullHD) == PixelRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    @Test("Ngày giờ ISO 8601 UTC, có phần nghìn giây khi khác 0")
    func datesUseISO8601() throws {
        let whole = Date(timeIntervalSince1970: 1_764_151_200)
        #expect(DocumentCoding.string(from: whole) == "2025-11-26T10:00:00Z")
        let fractional = whole.addingTimeInterval(0.12)
        #expect(DocumentCoding.string(from: fractional) == "2025-11-26T10:00:00.120Z")
        #expect(DocumentCoding.date(from: "2025-11-26T10:00:00Z") == whole)
        let parsed = try #require(DocumentCoding.date(from: "2025-11-26T10:00:00.120Z"))
        #expect(abs(parsed.timeIntervalSince(fractional)) < 0.0005)
        #expect(DocumentCoding.date(from: "hôm qua") == nil)
        #expect(throws: DecodingError.self) {
            try DocumentCoding.decode([Date].self, from: Data(#"["hôm qua"]"#.utf8))
        }
    }

    @Test("Không thoát dấu gạch chéo, không thoát chữ có dấu")
    func encoderKeepsSlashesAndVietnamese() throws {
        let plan = ServicePlan(id: fixedID(1), title: "Chúa Nhật 30/11", date: "2026-11-30")
        let json = String(decoding: try DocumentCoding.encode(plan), as: UTF8.self)
        #expect(json.contains("\"Chúa Nhật 30/11\""))
    }

    @Test("TextStyle.applying chỉ đè các trường có giá trị")
    func textStyleApplyingOverride() {
        let base = TextStyle(fontWeight: 600, fontSize: 72)
        #expect(base.applying(TextStyleOverride()) == base)
        #expect(TextStyleOverride().isEmpty)
        let override = TextStyleOverride(
            fontFamily: "Inter", fontWeight: 700, fontSize: 48, color: .black, alignment: .left,
            verticalAlignment: .top, lineHeight: 1.5, letterSpacing: 2, transform: .uppercase,
            stroke: TextStroke(color: .white, width: 2), shadow: TextShadow.none, box: TextBox.none,
            autoFit: AutoFit(mode: .shrink, minScale: 0.5), maxLines: 2
        )
        let result = base.applying(override)
        let expected = TextStyle(
            fontFamily: "Inter", fontWeight: 700, fontSize: 48, color: .black, alignment: .left,
            verticalAlignment: .top, lineHeight: 1.5, letterSpacing: 2, transform: .uppercase,
            stroke: TextStroke(color: .white, width: 2), shadow: TextShadow.none, box: TextBox.none,
            autoFit: AutoFit(mode: .shrink, minScale: 0.5), maxLines: 2
        )
        #expect(result == expected)
        #expect(!override.isEmpty)
        let partial = base.applying(TextStyleOverride(fontSize: 40))
        #expect(partial.fontSize == 40)
        #expect(partial.fontWeight == 600)
    }

    @Test("Element và ServicePlanItem dùng khoá phân biệt type")
    func discriminatedUnions() throws {
        let element = Element.shape(ShapeElement(id: fixedID(1), frame: .zero, fill: .black))
        let json = String(decoding: try ShowCommand.makeEncoder().encode(element), as: UTF8.self)
        let id = fixedID(1).uuidString
        let expected =
            ##"{"cornerRadius":0,"fill":"#000000FF","frame":[0,0,0,0],"id":"\##(id)","shape":"rect","type":"shape"}"##
        #expect(json == expected)
        #expect(element.id == fixedID(1))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Element.self, from: Data(#"{"type":"sticker"}"#.utf8))
        }
        let items: [ServicePlanItem] = [
            .header(PlanHeaderItem(id: fixedID(1), title: "A")),
            .presentation(PlanPresentationItem(id: fixedID(2), presentationID: fixedID(9))),
            .scripture(PlanScriptureItem(id: fixedID(3), reference: "Thi thiên 23", translation: "vi1925")),
            .media(PlanMediaItem(id: fixedID(4), mediaID: "abc")),
            .note(PlanNoteItem(id: fixedID(5), text: "Ghi chú")),
        ]
        let decoded = try DocumentCoding.decode([ServicePlanItem].self, from: try DocumentCoding.encode(items))
        #expect(decoded == items)
        #expect(decoded.map(\.id) == (1...5).map(fixedID))
    }

    @Test("Tài liệu khác đi qua mã hoá không mất dữ liệu")
    func otherDocumentsRoundTrip() throws {
        let created = Date(timeIntervalSince1970: 1_764_151_200)
        let library = LibraryInfo(id: fixedID(1), createdAt: created, defaultThemeID: fixedID(2))
        #expect(try DocumentCoding.decode(LibraryInfo.self, from: try DocumentCoding.encode(library)) == library)
        let linked = MediaOrigin(kind: .linked, url: "https://nas.local/d/abc/video.mp4", provider: "slate", etag: "x")
        let media = MediaAssetInfo(
            id: "l-0123456789", kind: .video, originalName: "Video.mp4", fileExtension: "mp4", byteCount: 1024,
            pixelSize: .fullHD, duration: 12.5, tags: ["nền"], importedAt: created, origin: linked
        )
        let mediaJSON = try DocumentCoding.encode(media)
        #expect(try DocumentCoding.decode(MediaAssetInfo.self, from: mediaJSON) == media)
        #expect(String(decoding: mediaJSON, as: UTF8.self).contains("https://nas.local/d/abc/video.mp4"))
        let event = ServiceLogEvent(at: created, type: .clearLayer, layer: .slide)
        let log = ServiceLog(planID: fixedID(3), startedAt: created, events: [event])
        #expect(try DocumentCoding.decode(ServiceLog.self, from: try DocumentCoding.encode(log)) == log)
        #expect(MediaOrigin.copied.kind == .copied)
    }

    @Test("MediaID mã hoá thành chuỗi, băm thành UUID ổn định")
    func mediaIdentifiers() throws {
        let id: MediaID = "a1b2c3d4e5f6"
        #expect(String(decoding: try JSONEncoder().encode([id]), as: UTF8.self) == #"["a1b2c3d4e5f6"]"#)
        #expect(id.contentUUID == MediaID("a1b2c3d4e5f6").contentUUID)
        #expect(id.contentUUID != MediaID("a1b2c3d4e5f7").contentUUID)
        #expect(id.description == "a1b2c3d4e5f6")
        #expect(MediaID("a") < MediaID("b"))
        #expect(UUID(hashing: "x") == UUID(hashing: "x"))
        #expect(UUID(hashing: "x").uuidString.dropFirst(14).first == "8")
    }
}

@Suite("Presentation")
struct PresentationTests {
    @Test("newSong: một đoạn verse 1, một trang, một phần tử chữ ở ô body, thứ tự hát Mặc định")
    func newSongDefaults() throws {
        let now = Date(timeIntervalSince1970: 1_764_151_200)
        let song = Presentation.newSong(title: "Bài mới", now: now)
        #expect(song.kind == .song)
        #expect(song.title == "Bài mới")
        #expect(song.createdAt == now)
        #expect(song.groups.count == 1)
        let group = try #require(song.groups.first)
        #expect(group.label == GroupLabel(kind: .verse, number: 1))
        #expect(group.slides.count == 1)
        guard case .text(let text) = group.slides[0].elements.first else {
            Issue.record("Trang đầu phải có một phần tử chữ")
            return
        }
        #expect(text.slot == .body)
        #expect(song.arrangements.map(\.name) == ["Mặc định"])
        #expect(song.activeArrangementID == song.arrangements.first?.id)
        #expect(song.orderedGroups() == song.groups)
    }

    @Test("orderedGroups: theo thứ tự hát đang chọn, bỏ id không tồn tại; không có thì thứ tự gốc")
    func orderedGroupsFollowArrangement() {
        let a = SlideGroup(id: fixedID(1), label: GroupLabel(kind: .verse, number: 1), slides: [])
        let b = SlideGroup(id: fixedID(2), label: GroupLabel(kind: .chorus), slides: [])
        let repeated = [fixedID(2), fixedID(99), fixedID(1), fixedID(2)]
        let order = Arrangement(id: fixedID(10), name: "Lặp", groupIDs: repeated)
        let other = Arrangement(id: fixedID(11), name: "Ngắn", groupIDs: [fixedID(1)])
        let date = Date(timeIntervalSince1970: 0)
        var song = Presentation(
            kind: .song, title: "T", createdAt: date, modifiedAt: date, groups: [a, b], arrangements: [order, other],
            activeArrangementID: fixedID(10)
        )
        #expect(song.orderedGroups().map(\.id) == [fixedID(2), fixedID(1), fixedID(2)])
        #expect(song.orderedGroups(arrangementID: fixedID(11)).map(\.id) == [fixedID(1)])
        #expect(song.orderedGroups(arrangementID: fixedID(55)).map(\.id) == [fixedID(2), fixedID(1), fixedID(2)])
        song.activeArrangementID = nil
        #expect(song.orderedGroups().map(\.id) == [fixedID(1), fixedID(2)])
        song.activeArrangementID = fixedID(77)
        #expect(song.orderedGroups().map(\.id) == [fixedID(1), fixedID(2)])
    }

    @Test("ThemeSlots đọc ghi theo vai trò; mẫu tối thiểu hợp lệ")
    func themeSlotsSubscript() {
        var theme = Theme.fallback(id: fixedID(1))
        #expect(theme.canvasSize == .fullHD)
        #expect(theme.background == .color(.black))
        for kind in ThemeSlotKind.allCases {
            var slot = theme.slots[kind]
            slot.frame = PixelRect(x: 1, y: 1, width: 1, height: 1)
            theme.slots[kind] = slot
            #expect(theme.slots[kind].frame.width == 1)
        }
    }
}

@Suite("Migration")
struct MigrationTests {
    @Test("Thiếu schemaVersion thì coi là 1, không đổi dữ liệu")
    func missingVersionIsOne() throws {
        let data = Data(#"{"id":"x"}"#.utf8)
        let (migrated, from) = try DocumentMigration.migrate(data, kind: .presentation)
        #expect(migrated == data)
        #expect(from == nil)
    }

    @Test("Phiên bản mới hơn thì ném lỗi tiếng Việt")
    func newerVersionThrows() {
        let data = Data(#"{"schemaVersion":2}"#.utf8)
        #expect(throws: DocumentError.newerSchema(found: 2, supported: 1)) {
            try migrate(data, kind: .theme)
        }
        let message = DocumentError.newerSchema(found: 2, supported: 1).description
        #expect(message.hasPrefix("Tệp được tạo bởi phiên bản Hệ thống mới hơn"))
    }

    @Test("Dữ liệu không phải tài liệu thì ném lỗi", arguments: [#"[1, 2]"#, "không phải JSON"])
    func invalidDocumentThrows(text: String) {
        #expect(throws: DocumentError.notAnObject) {
            try migrate(Data(text.utf8), kind: .plan)
        }
    }

    @Test("schemaVersion không hợp lệ thì ném lỗi", arguments: [#"{"schemaVersion":0}"#, #"{"schemaVersion":"1"}"#])
    func invalidVersionThrows(text: String) {
        #expect(throws: DocumentError.invalidSchemaVersion) {
            try migrate(Data(text.utf8), kind: .media)
        }
        #expect(!DocumentError.invalidSchemaVersion.message.isEmpty)
        #expect(!DocumentError.notAnObject.message.isEmpty)
    }
}

import Foundation
import Testing

@testable import LibraryIndex

@Suite("LibraryIndex: tìm kiếm")
struct LibraryIndexSearchTests {
    static let sampleSongs: [IndexEntry] = [
        song("rock", "Chúa Là Đá Muôn Đời", number: "245", lyrics: "Chúa là vầng đá muôn đời, con ẩn náu nơi Ngài"),
        song("great", "Lớn Bấy Duy Ngài", number: "123", lyrics: "Lạy Chúa, Đấng toàn năng"),
        song("h1234", "Ân Điển Lạ Lùng", number: "1234", lyrics: "Ân điển Chúa lạ lùng thay"),
        song("h12", "Ngợi Khen Cha", number: "12", lyrics: "Ngợi khen Cha thiên thượng"),
        song("dang", "Đấng Christ Đã Sống Lại", number: "301", lyrics: "Ha-lê-lu-gia"),
        song("lord", "Chúa Ơi", number: "88", lyrics: "Đấng chăn chiên hiền lành"),
        IndexEntry(id: "theme-dark", kind: .theme, title: "Nền tối Chúa Nhật"),
        IndexEntry(id: "plan-1", kind: .plan, title: "Buổi nhóm Chúa Nhật 29/11", subtitle: "123 người"),
        IndexEntry(id: "media-1", kind: .media, title: "Đá núi.mp4", subtitle: "1920x1080", path: "Media/da-nui.mp4"),
        verse("bible:TT1925:PSA.18.2", reference: "Thi Thiên 18:2", text: "Đức Giê-hô-va là hòn đá tôi"),
        verse("bible:TT1925:1CO.12.3", reference: "1 Cô-rinh-tô 12:3", text: "Đức Chúa Jêsus là Chúa"),
    ]

    static func makeIndex(_ dir: borrowing TemporaryDirectory) async throws -> LibraryIndex {
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        try await index.upsert(sampleSongs)
        return index
    }

    @Test("\"chua la da\" ra \"Chúa Là Đá Muôn Đời\" đứng đầu")
    func unaccentedQueryFindsAccentedTitle() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        let hits = try await index.search("chua la da", kinds: [.presentation])
        #expect(hits.first?.id == "rock")
        #expect(hits.first?.title == "Chúa Là Đá Muôn Đời")
        #expect(hits.first?.subtitle == "245")
        #expect(try await index.search("Chúa Là Đá", kinds: [.presentation]).first?.id == "rock")
    }

    @Test("\"dang\" ra mục có chữ \"Đấng\"; tên khớp xếp trên nội dung khớp")
    func dStrokeMatches() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        let hits = try await index.search("dang", kinds: [.presentation])
        #expect(Set(hits.map(\.id)) == ["dang", "great", "lord"])
        #expect(hits.first?.id == "dang")
    }

    @Test("\"123\" ra thánh ca số 123 đứng đầu, rồi số bắt đầu bằng 123, rồi kết quả toàn văn")
    func hymnNumberFirst() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        let hits = try await index.search("123", kinds: Set(IndexKind.allCases))
        // "123 người" của chương trình cũng đúng số 123 (sau số là khoảng trắng), xếp sau vì phụ đề dài hơn.
        #expect(hits.map(\.id) == ["great", "plan-1", "h1234"])
        let exact = LibraryIndex.exactNumberScore
        #expect(hits.map(\.score) == [exact, exact, LibraryIndex.numberPrefixScore])

        let twelve = try await index.search("12", kinds: [.presentation])
        #expect(twelve.map(\.id) == ["h12", "great", "h1234"])
    }

    @Test("Số không áp cho câu Kinh Thánh: \"1\" không kéo ra mọi câu 1 Cô-rinh-tô")
    func numberSearchSkipsVerses() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        let hits = try await index.search("1", kinds: [.verse])
        #expect(hits.allSatisfy { $0.score < LibraryIndex.numberPrefixScore })
    }

    @Test("Lọc theo loại")
    func filtersByKind() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        #expect(try await index.search("da", kinds: [.verse]).map(\.id) == ["bible:TT1925:PSA.18.2"])
        #expect(try await index.search("da", kinds: [.media]).map(\.id) == ["media-1"])
        let songsAndMedia = try await index.search("da", kinds: [.presentation, .media])
        #expect(Set(songsAndMedia.map(\.kind)) == [.presentation, .media])
        let songsAndVerses = try await index.search("da", kinds: [.presentation, .verse])
        #expect(Set(songsAndVerses.map(\.kind)) == [.presentation, .verse])
        let all = try await index.search("chua nhat", kinds: Set(IndexKind.allCases))
        #expect(Set(all.map(\.id)) == ["theme-dark", "plan-1"])
        let allButVerse = try await index.search("chua", kinds: Set(IndexKind.allCases).subtracting([.verse]))
        #expect(!allButVerse.contains { $0.kind == .verse })
        #expect(allButVerse.contains { $0.kind == .theme })
    }

    @Test("Truy vấn rỗng, chỉ dấu câu, kinds rỗng, limit 0: trả rỗng")
    func emptyQueries() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        #expect(try await index.search("", kinds: [.presentation]).isEmpty)
        #expect(try await index.search("   ", kinds: [.presentation]).isEmpty)
        #expect(try await index.search("- : !", kinds: [.presentation]).isEmpty)
        #expect(try await index.search("chua", kinds: []).isEmpty)
        #expect(try await index.search("chua", kinds: [.presentation], limit: 0).isEmpty)
    }

    @Test("Mọi từ phải có (AND), mỗi từ khớp tiền tố")
    func termsAreAndedPrefixes() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        #expect(try await index.search("ch muo", kinds: [.presentation]).map(\.id) == ["rock"])
        #expect(try await index.search("chua xyz", kinds: [.presentation]).isEmpty)
    }

    @Test("Dấu ngoặc kép và ký tự đặc biệt của FTS5 trong truy vấn không gây lỗi")
    func specialCharactersAreEscaped() async throws {
        let dir = try TemporaryDirectory()
        let index = try await Self.makeIndex(dir)
        let queries = [
            "\"chua", "chua\"", "\"\"", "chua AND OR NOT", "chua*", "(da)", "title_f:chua", "^chua", "a\"b\"c", "NEAR(",
        ]
        for query in queries {
            _ = try await index.search(query, kinds: Set(IndexKind.allCases))
        }
        #expect(try await index.search("\"Chúa\" là", kinds: [.presentation]).first?.id == "rock")
    }

    @Test("Hoà điểm thì xếp theo tên đã gộp dấu; limit được tôn trọng")
    func tieBreakByTitleAndLimit() async throws {
        let dir = try TemporaryDirectory()
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        // Cùng độ dài, cùng một lần xuất hiện nên cùng điểm bm25. Thứ tự byte của tên gốc là "Ca" < "Ân" < "Đấng",
        // còn thứ tự chữ cái (đã gộp dấu) là "an" < "ca" < "dang".
        try await index.upsert([song("d", "Đấng Chúa"), song("c", "Ca Chúa"), song("a", "Ân Chúa")])
        let hits = try await index.search("chua", kinds: [.presentation])
        #expect(hits.map(\.id) == ["a", "c", "d"])
        #expect(Set(hits.map(\.score)).count == 1)
        let limited = try await index.search("chua", kinds: [.presentation], limit: 2)
        #expect(limited.map(\.id) == ["a", "c"])
    }
}

@Suite("LibraryIndex: ghi, xoá, đếm")
struct LibraryIndexWriteTests {
    @Test("upsert thay mục cùng id, không nhân đôi trong chỉ mục toàn văn")
    func upsertReplaces() async throws {
        let dir = try TemporaryDirectory()
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        try await index.upsert([song("s1", "Tên cũ", number: "1", lyrics: "lời cũ")])
        try await index.upsert([song("s1", "Tên mới", number: "2", lyrics: "lời mới")])
        #expect(try await index.count(kind: .presentation) == 1)
        #expect(try await index.search("cu", kinds: [.presentation]).isEmpty)
        let hits = try await index.search("moi", kinds: [.presentation])
        #expect(hits.map(\.id) == ["s1"])
        #expect(hits.first?.title == "Tên mới")
        #expect(hits.first?.subtitle == "2")
    }

    @Test("Trùng id trong một lô: mục sau thắng")
    func duplicateIdsInOneBatch() async throws {
        let dir = try TemporaryDirectory()
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        try await index.upsert([song("s1", "Một"), song("s1", "Hai")])
        #expect(try await index.count(kind: .presentation) == 1)
        #expect(try await index.search("hai", kinds: [.presentation]).map(\.id) == ["s1"])
        #expect(try await index.search("mot", kinds: [.presentation]).isEmpty)
    }

    @Test("Đổi loại giữa câu Kinh Thánh và loại khác vẫn tìm đúng")
    func kindChangeAcrossVerseRange() async throws {
        let dir = try TemporaryDirectory()
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        try await index.upsert([song("x", "Bình an")])
        try await index.upsert([verse("x", reference: "Giăng 14:27", text: "Ta để sự bình an lại cho các ngươi")])
        #expect(try await index.count(kind: .presentation) == 0)
        #expect(try await index.count(kind: .verse) == 1)
        #expect(try await index.search("binh an", kinds: [.presentation]).isEmpty)
        #expect(try await index.search("binh an", kinds: [.verse]).map(\.id) == ["x"])
        try await index.upsert([song("x", "Bình an")])
        #expect(try await index.search("binh an", kinds: [.verse]).isEmpty)
        #expect(try await index.search("binh an", kinds: [.presentation]).map(\.id) == ["x"])
    }

    @Test("remove và removeAll")
    func removal() async throws {
        let dir = try TemporaryDirectory()
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        try await index.upsert(LibraryIndexSearchTests.sampleSongs)
        #expect(try await index.count(kind: .presentation) == 6)
        #expect(try await index.count(kind: .verse) == 2)

        try await index.remove(ids: ["rock", "khong-co"])
        #expect(try await index.count(kind: .presentation) == 5)
        #expect(try await index.search("muon doi", kinds: [.presentation]).isEmpty)

        try await index.removeAll(kind: .verse)
        #expect(try await index.count(kind: .verse) == 0)
        #expect(try await index.search("da", kinds: [.verse]).isEmpty)
        #expect(try await index.count(kind: .presentation) == 5)

        try await index.upsert([verse("v", reference: "Giăng 3:16", text: "Vì Đức Chúa Trời yêu thương thế gian")])
        #expect(try await index.search("yeu thuong", kinds: [.verse]).map(\.id) == ["v"])
    }

    @Test("Lô rỗng không lỗi")
    func emptyBatches() async throws {
        let dir = try TemporaryDirectory()
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        try await index.upsert([])
        try await index.remove(ids: [])
        #expect(try await index.count(kind: .presentation) == 0)
    }
}

@Suite("LibraryIndex: tệp chỉ mục và phiên bản")
struct LibraryIndexLifecycleTests {
    @Test("Dữ liệu còn sau khi đóng và mở lại")
    func persistsAcrossReopen() async throws {
        let dir = try TemporaryDirectory()
        do {
            let index = try LibraryIndex(databaseURL: dir.indexURL)
            try await index.upsert([song("s1", "Chúa Là Đá Muôn Đời")])
        }
        let reopened = try LibraryIndex(databaseURL: dir.indexURL)
        #expect(try await reopened.search("chua", kinds: [.presentation]).map(\.id) == ["s1"])
    }

    @Test("Xoá tệp chỉ mục rồi mở lại: tự tạo lại lược đồ, không lỗi")
    func recreatesDeletedFile() async throws {
        let dir = try TemporaryDirectory()
        do {
            let index = try LibraryIndex(databaseURL: dir.indexURL)
            try await index.upsert([song("s1", "Chúa Là Đá Muôn Đời")])
        }
        try FileManager.default.removeItem(at: dir.indexURL.deletingLastPathComponent())
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        #expect(try await index.count(kind: .presentation) == 0)
        try await index.upsert([song("s2", "Ngợi Khen")])
        #expect(try await index.search("ngoi", kinds: [.presentation]).map(\.id) == ["s2"])
    }

    @Test("Đổi indexVersion: dữ liệu cũ bị xoá, bảng tạo lại")
    func versionChangeRebuilds() async throws {
        let dir = try TemporaryDirectory()
        do {
            let index = try LibraryIndex(databaseURL: dir.indexURL, indexVersion: 1)
            try await index.upsert([song("s1", "Chúa Là Đá Muôn Đời")])
        }
        do {
            let same = try LibraryIndex(databaseURL: dir.indexURL, indexVersion: 1)
            #expect(try await same.count(kind: .presentation) == 1)
        }
        let bumped = try LibraryIndex(databaseURL: dir.indexURL, indexVersion: 2)
        #expect(try await bumped.count(kind: .presentation) == 0)
        try await bumped.upsert([song("s2", "Ngợi Khen")])
        #expect(try await bumped.search("ngoi", kinds: [.presentation]).map(\.id) == ["s2"])
        let reopened = try LibraryIndex(databaseURL: dir.indexURL, indexVersion: 2)
        #expect(try await reopened.count(kind: .presentation) == 1)
    }

    @Test("Tệp chỉ mục hỏng: xoá và tạo lại")
    func corruptFileIsReplaced() async throws {
        let dir = try TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: dir.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 8192).write(to: dir.indexURL)
        let index = try LibraryIndex(databaseURL: dir.indexURL)
        #expect(try await index.count(kind: .presentation) == 0)
        try await index.upsert([song("s1", "Ngợi Khen")])
        #expect(try await index.search("ngoi khen", kinds: [.presentation]).map(\.id) == ["s1"])
    }

    @Test("Biểu thức MATCH: mỗi từ có ngoặc kép và dấu sao, thoát ngoặc kép, bỏ từ chỉ có dấu câu")
    func matchExpressionBuilding() {
        #expect(LibraryIndex.matchExpression(["chua", "la"]) == "\"chua\"* \"la\"*")
        #expect(LibraryIndex.matchExpression(["a\"b"]) == "\"a\"\"b\"*")
        #expect(LibraryIndex.matchExpression(["-", ":"]) == nil)
        #expect(LibraryIndex.matchExpression(["3:16"]) == "\"3:16\"*")
    }
}

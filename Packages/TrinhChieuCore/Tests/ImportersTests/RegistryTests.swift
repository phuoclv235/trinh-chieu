import Foundation
import Testing

@testable import Importers

@Suite("ImportRegistry: chọn bộ nhập, nhập nhiều tệp")
struct RegistryTests {
    @Test("Chọn bộ nhập theo nội dung, không theo đuôi tệp")
    func choosesByContent() throws {
        let openLyrics = try fixtureData("OpenLyrics/01-co-ban.xml")
        let text = try fixtureData("Lyrics/01-nhan-ngoac-vuong.txt")
        let registry = ImportRegistry.standard
        #expect(registry.importer(for: openLyrics, filename: "bai-hat.txt") is OpenLyricsImporter)
        #expect(registry.importer(for: text, filename: "bai-hat.xml") is PlainLyricsImporter)
        #expect(registry.importer(for: try fixtureData("Lyrics/06-utf16le.txt"), filename: "a") is PlainLyricsImporter)
        #expect(registry.importer(for: try fixtureData("Broken/khong-phai-van-ban.pdf"), filename: "a.txt") == nil)
        #expect(registry.importer(for: Data(), filename: "a.txt") == nil)
        #expect(OpenLyricsImporter.displayName == "OpenLyrics")
        #expect(PlainLyricsImporter.displayName == "Văn bản lời bài hát")
    }

    @Test("Nhập nhiều tệp song song: kết quả theo thứ tự tệp, tệp lỗi không chặn tệp khác, lỗi có tên tệp")
    func batchImport() async throws {
        let lyrics = try fixtureNames(in: "Lyrics").map { try fixtureURL("Lyrics/" + $0) }
        let openLyrics = try fixtureNames(in: "OpenLyrics").map { try fixtureURL("OpenLyrics/" + $0) }
        let broken = try ["hong.xml", "khong-phai-van-ban.pdf", "rong.txt"].map { try fixtureURL("Broken/" + $0) }
        let missing = try fixtureURL("Broken/khong-co-tep-nay.txt")
        let urls = lyrics + broken + openLyrics + [missing]

        let report = await testRegistry.importFiles(at: urls)
        #expect(report.files.map(\.filename) == urls.map(\.lastPathComponent))
        #expect(report.successCount == 15)
        #expect(report.presentations.count == 15)
        #expect(report.failures.count == 4)
        let failedNames = ["hong.xml", "khong-phai-van-ban.pdf", "rong.txt", missing.lastPathComponent]
        #expect(report.failures.map(\.filename) == failedNames)
        for failure in report.failures {
            #expect(failure.message.contains(failure.filename))
        }
        guard case .invalidXML = report.failures[0] else {
            Issue.record("hong.xml phải là lỗi XML: \(report.failures[0])")
            return
        }
        #expect(report.failures[1] == .unsupportedFormat(filename: "khong-phai-van-ban.pdf"))
        #expect(report.failures[2] == .empty(filename: "rong.txt"))
        guard case .unreadable = report.failures[3] else {
            Issue.record("Tệp không có phải là lỗi đọc: \(report.failures[3])")
            return
        }
        // 07 (Windows-1258), 08 (2 cảnh báo), OpenLyrics 02, 04, 05 (mỗi tệp 1 cảnh báo).
        #expect(report.warnings.count == 6)
        #expect(report.summary == "Đã nhập 15/19 tệp, 6 cảnh báo, 4 tệp lỗi.")
    }

    @Test("Báo cáo khi mọi tệp thành công, không có cảnh báo")
    func cleanSummary() async throws {
        let report = await testRegistry.importFiles(at: [try fixtureURL("Lyrics/01-nhan-ngoac-vuong.txt")])
        #expect(report.summary == "Đã nhập 1/1 tệp, không có cảnh báo.")
    }
}

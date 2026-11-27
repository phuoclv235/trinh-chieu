import Foundation
import Testing

@Suite("Chuỗi giao diện")
struct LocalizationTests {
    private func vietnameseBundle() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test("Chữ giao diện là tiếng Việt, đúng thuật ngữ")
    func termsAreVietnamese() throws {
        let bundle = try vietnameseBundle()
        let expected = [
            "Live": "Trực tiếp",
            "Editor": "Soạn thảo",
            "Main output": "Đầu ra chính",
            "Stage display": "Màn hình nhắc",
            "Rehearsal": "Tập dượt",
            "Freeze": "Đóng băng",
            "Showing on screen. Quit the system?": "Đang chiếu. Thoát Hệ thống?",
            "Stay": "Ở lại",
        ]
        for (key, value) in expected {
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == value)
        }
    }

    @Test("Chuỗi có tham số giữ đúng chỗ giữ tham số")
    func formatPlaceholdersSurvive() throws {
        let bundle = try vietnameseBundle()
        let format = bundle.localizedString(forKey: "Screen \"%@\" (%@) is disconnected.", value: nil, table: nil)
        #expect(String(format: format, "LED", "Đầu ra chính").contains("\"LED\" (Đầu ra chính)"))
    }
}

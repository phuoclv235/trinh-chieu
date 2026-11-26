import Foundation
import Testing

@Suite("Chuỗi giao diện")
struct LocalizationTests {
    @Test("Chữ mặc định là tiếng Việt")
    func readyMessageIsVietnamese() throws {
        let path = try #require(Bundle.main.path(forResource: "vi", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let text = bundle.localizedString(forKey: "System ready", value: nil, table: nil)
        #expect(text == "Hệ thống đã sẵn sàng")
    }
}

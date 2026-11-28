import Foundation
import RenderEngine
import Testing

@testable import TrinhChieu

@Suite("Cài đặt ứng dụng")
struct AppSettingsTests {
    @Test("Gán vai: mỗi vai một màn, mỗi màn một vai; màn đang giữ vai tự chuyển sang Không dùng")
    func assignKeepsRolesExclusive() {
        var settings = AppSettings()
        settings.assign(.program, toDisplay: "A", name: "LED")
        settings.assign(.stage, toDisplay: "B", name: "Bục giảng")
        #expect(settings.role(forDisplay: "A") == .program)
        #expect(settings.role(forDisplay: "B") == .stage)

        settings.assign(.program, toDisplay: "B", name: "Bục giảng")
        #expect(settings.role(forDisplay: "A") == nil)
        #expect(settings.role(forDisplay: "B") == .program)
        #expect(settings.outputAssignments.count == 1)

        settings.assign(nil, toDisplay: "B", name: "Bục giảng")
        #expect(settings.outputAssignments.isEmpty)
    }

    @Test("Mã hoá rồi giải mã giữ nguyên mọi trường")
    func roundTrip() throws {
        var settings = AppSettings(
            libraryPath: "/Volumes/NAS/TrinhChieu", audioOutputDeviceID: "BuiltInSpeakerDevice",
            defaultTranslation: "tt1925", advanceToNextItem: false, welcomeDismissed: true)
        settings.assign(.program, toDisplay: "37D8832A-2D66-02CA-B9F7-8F30A301B230", name: "LED")
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test("Cài đặt thiếu trường (bản cũ) lấy giá trị mặc định, không mất phần đã có")
    func decodesOlderSettings() throws {
        // Bản cũ còn trường "appearance" (đã bỏ, chỉ còn giao diện tối): vẫn đọc được, trường đó bị bỏ qua.
        let json = #"{"libraryPath":"/tmp/thu-vien","outputAssignments":[],"appearance":"light"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.libraryPath == "/tmp/thu-vien")
        #expect(settings.advanceToNextItem)
        #expect(!settings.welcomeDismissed)
    }

    @Test("Một trường sai kiểu chỉ trường đó về mặc định, không mất các trường khác")
    func malformedFieldKeepsOthers() throws {
        let json =
            #"{"libraryPath":"/tmp/thu-vien","advanceToNextItem":"có","appearance":"xanh","#
            + #""outputAssignments":[{"displayUUID":"A","role":"program","displayName":"LED"}]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.libraryPath == "/tmp/thu-vien")
        #expect(settings.advanceToNextItem)
        #expect(settings.role(forDisplay: "A") == .program)
    }

    @Test("SettingsStore ghi vào khoá app.settings.v1 và đọc lại được")
    @MainActor func storePersists() throws {
        let suite = "app.trinhchieu.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.value.assign(.stage, toDisplay: "B", name: "Bục giảng")
        #expect(defaults.data(forKey: "app.settings.v1") != nil)
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.value.role(forDisplay: "B") == .stage)
    }

    @Test("Mã bản dịch lấy từ tên tệp: bỏ dấu, chữ thường, gạch nối")
    func translationCode() {
        #expect(AppEnvironment.translationCode(from: "Bản Truyền Thống 1925") == "ban-truyen-thong-1925")
        #expect(AppEnvironment.translationCode(from: "Đức Chúa Trời") == "duc-chua-troi")
        #expect(AppEnvironment.translationCode(from: "***") == "ban-dich")
    }
}

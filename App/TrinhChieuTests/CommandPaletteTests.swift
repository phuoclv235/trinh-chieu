import Foundation
import LibraryStore
import Testing

@testable import TrinhChieu

@Suite("Bảng lệnh: nối với ứng dụng")
@MainActor
struct CommandPaletteTests {
    private func makeEnvironment() throws -> (AppEnvironment, UserDefaults, String) {
        let suite = "app.trinhchieu.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (AppEnvironment(settings: SettingsStore(defaults: defaults)), defaults, suite)
    }

    private var host: PaletteHost {
        PaletteHost(setMode: { _ in }, openSettings: {})
    }

    @Test("Đủ 11 lệnh của đặc tả, mỗi lệnh một lần, có tên tìm được bằng tiếng Anh")
    func commandsAreComplete() {
        let commands = AppEnvironment.paletteCommands()
        #expect(commands.map(\.id) == PaletteCommandID.allCases)
        #expect(commands.allSatisfy { !$0.title.isEmpty && !$0.keywords.isEmpty })
    }

    @Test("Chọn tên sách: điền vào ô, không đóng")
    func bookCompletionFills() throws {
        let (environment, defaults, suite) = try makeEnvironment()
        defer { defaults.removePersistentDomain(forName: suite) }
        let row = PaletteRow(group: .scripture, target: .bookCompletion(text: "Giăng "), title: "Giăng")
        #expect(environment.performPalette(row, secondary: false, host: host) == .fill("Giăng "))
        #expect(environment.performPalette(row, secondary: true, host: host) == .unavailable)
    }

    @Test("Chạy lệnh: đổi chế độ, đếm số lần dùng, không ghi vào gần đây")
    func commandRunsAndCounts() throws {
        let (environment, defaults, suite) = try makeEnvironment()
        defer { defaults.removePersistentDomain(forName: suite) }
        var mode: WorkspaceMode?
        let host = PaletteHost(setMode: { mode = $0 }, openSettings: {})
        let row = PaletteRow(group: .commands, target: .command(.editorMode), title: "Chế độ Soạn thảo")
        #expect(environment.performPalette(row, secondary: false, host: host) == .close)
        #expect(mode == .editor)
        #expect(environment.settings.value.paletteCommandUsage["editorMode"] == 1)
        #expect(environment.settings.value.paletteRecents.isEmpty)
    }

    @Test("Chưa mở thư viện: bài hát, câu Kinh Thánh báo không làm được, không ghi gần đây")
    func unavailableWithoutLibrary() throws {
        let (environment, defaults, suite) = try makeEnvironment()
        defer { defaults.removePersistentDomain(forName: suite) }
        let song = PaletteRow(group: .songs, target: .presentation(id: UUID()), title: "Ân điển")
        let verse = PaletteRow(
            group: .scripture, target: .scripture(translation: "tt1925", reference: "Giăng 3:16"), title: "Giăng 3:16")
        #expect(environment.performPalette(song, secondary: false, host: host) == .unavailable)
        #expect(environment.performPalette(verse, secondary: false, host: host) == .unavailable)
        #expect(environment.settings.value.paletteRecents.isEmpty)
    }

    @Test("Mở Bảng lệnh ghi lúc bấm; đang mở thì bấm lại không đổi")
    func openRecordsTime() throws {
        let (environment, defaults, suite) = try makeEnvironment()
        defer { defaults.removePersistentDomain(forName: suite) }
        environment.openCommandPalette()
        #expect(environment.isCommandPalettePresented)
        let first = try #require(environment.commandPaletteRequestedAt)
        environment.openCommandPalette()
        #expect(environment.commandPaletteRequestedAt == first)
        #expect(environment.perform(.next) == false)
    }

    @Test("Cài đặt cũ không có trường Bảng lệnh vẫn đọc được")
    func oldSettingsDecode() throws {
        let json = #"{"libraryPath":"/tmp/thu-vien","outputAssignments":[]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.paletteRecents.isEmpty)
        #expect(settings.paletteCommandUsage.isEmpty)
    }

    @Test("Mục gần đây và số lần dùng lệnh lưu lại qua lần mở sau")
    func historyPersists() throws {
        let (environment, defaults, suite) = try makeEnvironment()
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = PaletteItem(target: .presentation(id: UUID()), title: "Ân điển lạ lùng", subtitle: "123")
        environment.settings.value.paletteRecents = [item]
        environment.settings.value.paletteCommandUsage = ["clearAll": 3]
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.value.paletteRecents == [item])
        #expect(reopened.value.paletteCommandUsage == ["clearAll": 3])
    }
}

import AppKit
import CoreModel
import LibraryStore
import SwiftUI

/// Cài đặt > Âm thanh: thiết bị ra cho âm thanh media.
struct AudioSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var devices: [AudioOutputDevice] = []

    var body: some View {
        SettingsPage {
            SectionHeader(title: "Media audio")
            SettingsGroup {
                SettingsRow(
                    title: "Output device",
                    detail: String(localized: "Sound of videos and audio files goes to this device."),
                    showsDivider: false
                ) {
                    Picker(selection: selection) {
                        Text("Follow system").tag(String?.none)
                        if let missing = missingDevice {
                            Text(String(format: String(localized: "%@ (not connected)"), missing))
                                .tag(String?.some(missing))
                        }
                        ForEach(devices) { device in
                            Text(verbatim: device.name).tag(String?.some(device.uniqueID))
                        }
                    } label: {
                        Text("Output device")
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }
            }
        }
        .onAppear { devices = AudioDevices.outputs() }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { environment.settings.value.audioOutputDeviceID },
            set: { environment.setAudioOutputDevice($0) }
        )
    }

    /// Thiết bị đã chọn nhưng đang không cắm: vẫn giữ trong danh sách để không mất lựa chọn.
    private var missingDevice: String? {
        guard let id = environment.settings.value.audioOutputDeviceID else { return nil }
        return devices.contains { $0.uniqueID == id } ? nil : id
    }
}

/// Cài đặt > Thư viện: thư mục, chỉ mục tìm kiếm, mẫu mặc định, bản dịch mặc định.
struct LibrarySettingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var errorText: String?

    var body: some View {
        SettingsPage {
            SectionHeader(title: "Library folder")
            SettingsGroup {
                SettingsRow(title: "Location", detail: environment.library?.root.path, showsDivider: true) {
                    HStack(spacing: 8) {
                        Button {
                            if let root = environment.library?.root {
                                FilePicker.revealInFinder(root)
                            }
                        } label: {
                            Text("Open in Finder")
                        }
                        .buttonStyle(ControlButtonStyle(small: true))
                        Button(action: changeFolder) {
                            Text("Change folder…")
                        }
                        .buttonStyle(ControlButtonStyle(small: true))
                    }
                }
                SettingsRow(
                    title: "Search index",
                    detail: environment.library?.isIndexing == true
                        ? String(localized: "Rebuilding… search keeps working meanwhile.")
                        : String(localized: "Rebuild if search results look wrong."),
                    showsDivider: false
                ) {
                    Button {
                        environment.library?.rebuildIndex()
                    } label: {
                        Text("Rebuild search index")
                    }
                    .buttonStyle(ControlButtonStyle(small: true))
                    .disabled(environment.library == nil || environment.library?.isIndexing == true)
                }
            }
            SectionHeader(title: "Defaults")
            SettingsGroup {
                SettingsRow(title: "Theme for songs") {
                    themePicker(\.defaultThemeID)
                }
                SettingsRow(title: "Theme for Bible passages") {
                    themePicker(\.defaultScriptureThemeID)
                }
                SettingsRow(title: "Default Bible translation", showsDivider: false) {
                    Picker(selection: translation) {
                        if environment.translations.isEmpty {
                            Text("No translation yet").tag(String?.none)
                        }
                        ForEach(environment.translations, id: \.code) { info in
                            Text(verbatim: info.name).tag(String?.some(info.code))
                        }
                    } label: {
                        Text("Default Bible translation")
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .disabled(environment.translations.isEmpty)
                }
            }
            if let errorText {
                Text(verbatim: errorText).font(Typography.caption).foregroundStyle(Palette.danger)
            }
        }
    }

    private var themes: [Theme] {
        (environment.library?.themes.values.map { $0 } ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func themePicker(_ keyPath: WritableKeyPath<LibraryInfo, UUID?>) -> some View {
        Picker(selection: themeBinding(keyPath)) {
            ForEach(themes, id: \.id) { theme in
                Text(verbatim: theme.name).tag(UUID?.some(theme.id))
            }
        } label: {
            Text("Theme")
        }
        .labelsHidden()
        .frame(width: 260)
        .disabled(environment.library == nil)
    }

    private func themeBinding(_ keyPath: WritableKeyPath<LibraryInfo, UUID?>) -> Binding<UUID?> {
        Binding(
            get: { environment.library?.info[keyPath: keyPath] },
            set: { newValue in
                guard let library = environment.library else { return }
                var info = library.info
                info[keyPath: keyPath] = newValue
                Task {
                    do {
                        try await library.setDefaultThemes(
                            presentation: info.defaultThemeID, scripture: info.defaultScriptureThemeID)
                        errorText = nil
                    } catch {
                        errorText = String(describing: error)
                    }
                }
            }
        )
    }

    private var translation: Binding<String?> {
        Binding(
            get: { environment.settings.value.defaultTranslation },
            set: { environment.settings.value.defaultTranslation = $0 }
        )
    }

    private func changeFolder() {
        guard
            let folder = FilePicker.folder(
                message: String(localized: "Choose the library folder, or an empty folder for a new library"),
                prompt: String(localized: "Use this folder"), startingAt: environment.library?.root)
        else { return }
        if environment.isShowingOnProgram {
            let alert = NSAlert()
            alert.messageText = String(localized: "Showing on the main output. Change the library now?")
            alert.informativeText = String(localized: "The main output keeps its last picture until you go live again.")
            alert.addButton(withTitle: String(localized: "Change library"))
            alert.addButton(withTitle: String(localized: "Stay"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task { await environment.openLibrary(at: folder) }
    }
}

/// Cài đặt > Trực tiếp: sang mục kế khi hết trang, giao diện sáng tối, phím tắt (chỉ hiển thị ở giai đoạn 1).
struct LiveSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SettingsPage {
            SectionHeader(title: "Presenting")
            SettingsGroup {
                SettingsRow(
                    title: "Move to the next item after the last slide",
                    detail: String(localized: "Next slide on the last slide goes to the next service plan item.")
                ) {
                    Toggle(isOn: advance) {
                        Text("Move to the next item after the last slide")
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                SettingsRow(title: "Appearance", showsDivider: false) {
                    SegmentedChoice(
                        options: [
                            .init(value: AppearancePreference.dark, title: String(localized: "Dark")),
                            .init(value: .light, title: String(localized: "Light")),
                            .init(value: .system, title: String(localized: "Follow system")),
                        ],
                        selection: appearance,
                        accessibilityTitle: Text("Appearance")
                    )
                }
            }
            SectionHeader(title: "Keyboard shortcuts")
            SettingsGroup {
                ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    HStack {
                        Text(shortcut.title).font(Typography.body).foregroundStyle(Palette.text)
                        Spacer()
                        KeyCap(keys: shortcut.keys)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        if index < Self.shortcuts.count - 1 {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private var advance: Binding<Bool> {
        Binding(
            get: { environment.settings.value.advanceToNextItem },
            set: { environment.setAdvanceToNextItem($0) }
        )
    }

    private var appearance: Binding<AppearancePreference> {
        Binding(
            get: { environment.settings.value.appearance },
            set: { environment.setAppearance($0) }
        )
    }

    private static let shortcuts: [(title: LocalizedStringKey, keys: String)] = [
        ("Live", "⌘1"),
        ("Editor", "⌘2"),
        ("Open command palette", "⌘K"),
        ("Next slide", "→  Space"),
        ("Previous slide", "←"),
        ("Clear all", "F1"),
        ("Clear text", "F2"),
        ("Clear background", "F3"),
        ("Rehearsal", "⌘R"),
        ("Freeze", "⌘⇧F"),
        ("Show or hide right column", "⌥⌘0"),
        ("Settings", "⌘,"),
    ]
}

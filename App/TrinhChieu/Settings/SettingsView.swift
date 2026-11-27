import SwiftUI

/// Tab của cửa sổ Cài đặt (`⌘,`). Lưu tab đang mở để "Chọn lại màn hình" mở thẳng tab Đầu ra.
enum SettingsTab: String, CaseIterable {
    case outputs
    case audio
    case library
    case live

    static let storageKey = "settings.tab"
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.outputs.rawValue

    var body: some View {
        TabView(selection: $tab) {
            OutputsSettingsTab()
                .tabItem { Label("Outputs", systemImage: "display") }
                .tag(SettingsTab.outputs.rawValue)
            AudioSettingsTab()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
                .tag(SettingsTab.audio.rawValue)
            LibrarySettingsTab()
                .tabItem { Label("Library", systemImage: "folder") }
                .tag(SettingsTab.library.rawValue)
            LiveSettingsTab()
                .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                .tag(SettingsTab.live.rawValue)
        }
        .frame(width: 760)
        .tint(Palette.accent)
        .background(Palette.bgPanel)
    }
}

/// Khung chung của một tab: cuộn dọc, lề 24, nền `--bg-panel`.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 420, idealHeight: 640)
        .background(Palette.bgPanel)
    }
}

/// Nhóm biểu mẫu: viền 1 px, bo 8, các hàng chia bằng đường mảnh.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: Metrics.radiusLarge).fill(Palette.bgWindow))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusLarge).strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// Một hàng trong nhóm: nhãn và mô tả bên trái, điều khiển bên phải.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringKey
    var detail: String?
    var showsDivider = true
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.body).foregroundStyle(Palette.text)
                if let detail {
                    Text(verbatim: detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.text3)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(Text(verbatim: detail))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Hairline()
            }
        }
    }
}

import SwiftUI

/// Thanh cảnh báo dưới thanh công cụ: cảnh báo khẩn nhất, cách khắc phục, và danh sách đầy đủ khi có nhiều cảnh báo.
struct WarningBanner: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.outputs.rawValue
    @State private var showsAll = false

    var body: some View {
        let warnings = environment.warnings.warnings(library: environment.library, outputs: environment.outputs)
        if let first = warnings.first {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.warn)
                    .accessibilityHidden(true)
                Text(verbatim: first.message)
                    .font(Typography.control)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .help(Text(verbatim: first.message))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if warnings.count > 1 {
                    Button {
                        showsAll.toggle()
                    } label: {
                        Text(String(format: String(localized: "%lld more"), warnings.count - 1))
                    }
                    .buttonStyle(ControlButtonStyle(kind: .quiet, small: true))
                    .popover(isPresented: $showsAll, arrowEdge: .bottom) {
                        WarningList(warnings: warnings, perform: perform, dismiss: dismiss)
                    }
                }
                if let remedy = first.remedy {
                    Button {
                        perform(remedy)
                    } label: {
                        Text(remedyTitle(remedy))
                    }
                    .buttonStyle(ControlButtonStyle(small: true))
                }
                IconButton(systemImage: "xmark", label: "Hide warning", small: true) {
                    dismiss(first)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .frame(minHeight: 38)
            .background(Palette.warnSoft)
            .overlay(alignment: .bottom) { Hairline() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Warnings"))
        }
    }

    private func perform(_ remedy: AppWarning.Remedy) {
        switch remedy {
        case .chooseScreens:
            settingsTab = SettingsTab.outputs.rawValue
            openSettings()
        case .revealInFinder(let url):
            FilePicker.revealInFinder(url)
        }
    }

    private func dismiss(_ warning: AppWarning) {
        environment.warnings.dismiss(warning, library: environment.library)
    }
}

func remedyTitle(_ remedy: AppWarning.Remedy) -> LocalizedStringKey {
    switch remedy {
    case .chooseScreens: return "Choose screens again"
    case .revealInFinder: return "Show file in Finder"
    }
}

private struct WarningList: View {
    let warnings: [AppWarning]
    let perform: (AppWarning.Remedy) -> Void
    let dismiss: (AppWarning) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(warnings) { warning in
                    HStack(alignment: .top, spacing: 10) {
                        Text(verbatim: warning.message)
                            .font(Typography.control)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let remedy = warning.remedy {
                            Button {
                                perform(remedy)
                            } label: {
                                Text(remedyTitle(remedy))
                            }
                            .buttonStyle(ControlButtonStyle(small: true))
                        }
                        IconButton(systemImage: "xmark", label: "Hide warning", small: true) {
                            dismiss(warning)
                        }
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(width: 460)
        .frame(maxHeight: 360)
    }
}

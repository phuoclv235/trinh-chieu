import SwiftUI
import UniformTypeIdentifiers

/// Màn chào ba bước khi thư viện còn trống, nằm trong cửa sổ chính. Bỏ qua được; xong cả ba bước thì tự đóng.
struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.outputs.rawValue
    @State private var note: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Palette.scrim.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome").font(Typography.sourceTitle).foregroundStyle(Palette.text)
                    Text("Three short steps and the system is ready for the next service.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.text2)
                }
                .padding(.bottom, 20)
                step(
                    number: 1, title: "Choose the projection screen",
                    detail: "Assign the main output and the stage display.", done: hasProgramScreen,
                    action: "Choose screens", run: chooseScreens)
                Hairline()
                step(
                    number: 2, title: "Import songs or create your first one",
                    detail: "Plain text lyrics or OpenLyrics files.", done: hasSongs,
                    action: "Import lyrics…", run: importLyrics)
                Hairline()
                step(
                    number: 3, title: "Add a Bible translation",
                    detail: "OSIS, Zefania or USFM files.", done: hasTranslation,
                    action: "Add translation…", run: importBible)
                if let note {
                    Text(verbatim: note)
                        .font(Typography.control)
                        .foregroundStyle(Palette.text2)
                        .padding(.top, 14)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button {
                        environment.settings.value.welcomeDismissed = true
                    } label: {
                        Text(allDone ? "Start" : "Skip")
                    }
                    .buttonStyle(ControlButtonStyle(kind: allDone ? .primary : .quiet))
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 20)
            }
            .padding(28)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: Metrics.radiusPop).fill(Palette.bgOverlay))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radiusPop).strokeBorder(Palette.lineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 16)
            .disabled(isWorking)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var hasProgramScreen: Bool {
        environment.settings.value.outputAssignments.contains { $0.role == .program }
    }

    private var hasSongs: Bool {
        !(environment.library?.presentations.isEmpty ?? true)
    }

    private var hasTranslation: Bool {
        !environment.translations.isEmpty
    }

    private var allDone: Bool {
        hasProgramScreen && hasSongs && hasTranslation
    }

    private func step(
        number: Int, title: LocalizedStringKey, detail: LocalizedStringKey, done: Bool, action: LocalizedStringKey,
        run: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(done ? Palette.ok : Palette.lineStrong, lineWidth: 1)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ok)
                } else {
                    Text(verbatim: "\(number)").font(Typography.number).foregroundStyle(Palette.text2)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.bodyStrong).foregroundStyle(Palette.text)
                Text(detail).font(Typography.caption).foregroundStyle(Palette.text3)
            }
            Spacer(minLength: 12)
            Button(action: run) {
                Text(action)
            }
            .buttonStyle(ControlButtonStyle(small: true))
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(done ? "Done" : "Not done"))
    }

    private func chooseScreens() {
        settingsTab = SettingsTab.outputs.rawValue
        openSettings()
    }

    private func importLyrics() {
        let urls = FilePicker.files(
            message: String(localized: "Choose lyrics files to import"), prompt: String(localized: "Import"),
            types: [.plainText, .xml, .text])
        guard !urls.isEmpty else { return }
        isWorking = true
        Task {
            note = await environment.importLyrics(from: urls)
            isWorking = false
        }
    }

    private func importBible() {
        let urls = FilePicker.files(
            message: String(localized: "Choose the files of one Bible translation"),
            prompt: String(localized: "Add"), types: [.xml, .plainText, .data])
        guard !urls.isEmpty else { return }
        isWorking = true
        Task {
            do {
                let info = try await environment.importBible(from: urls)
                note = String(format: String(localized: "Added translation \"%@\"."), info.name)
            } catch {
                note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isWorking = false
        }
    }
}

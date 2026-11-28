import AppKit
import SwiftUI

/// Gốc của cửa sổ chính: khởi động, các trạng thái lỗi khi mở, rồi cửa sổ làm việc.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            switch environment.phase {
            case .starting, .renderUnavailable:
                Palette.bgWindow
            case .ready:
                MainWindowView()
            case .libraryMissing(let url):
                LibraryProblemView(
                    title: "Library folder not found",
                    message: String(
                        format: String(localized: "Folder \"%@\" is missing. Plug the external drive back in."),
                        url.path),
                    url: url)
            case .libraryFailed(let url, let reason):
                LibraryProblemView(title: "Cannot open the library", message: reason, url: url)
            }
        }
        .frame(minWidth: 1180, minHeight: 700)
        .background(Palette.bgWindow)
        .background(WindowConfigurator { window in environment.outputs.observeMainWindow(window) })
        .task { await environment.start() }
        .onChange(of: environment.phase) { _, phase in
            if case .renderUnavailable = phase {
                Self.reportMetalUnavailable()
            }
        }
    }

    /// "Máy này không hỗ trợ Metal" rồi thoát.
    private static func reportMetalUnavailable() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "This Mac does not support Metal")
        alert.informativeText = String(localized: "The system needs Metal to draw the outputs and will quit now.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.runModal()
        NSApp.terminate(nil)
    }
}

/// Thư mục thư viện không còn hoặc mở lỗi: chọn lại thư mục, tạo thư viện mới, hoặc thử lại.
private struct LibraryProblemView: View {
    let title: LocalizedStringKey
    let message: String
    let url: URL
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.late)
                .accessibilityHidden(true)
            Text(title).font(Typography.blockTitle).foregroundStyle(Palette.text)
            Text(verbatim: message)
                .font(Typography.body)
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 8) {
                Button {
                    Task { await environment.openLibrary(at: url) }
                } label: {
                    Text("Try again")
                }
                .buttonStyle(ControlButtonStyle())
                Button {
                    choose(prompt: String(localized: "Create library"))
                } label: {
                    Text("Create new library…")
                }
                .buttonStyle(ControlButtonStyle())
                Button {
                    choose(prompt: String(localized: "Open library"))
                } label: {
                    Text("Choose folder again…")
                }
                .buttonStyle(ControlButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func choose(prompt: String) {
        guard
            let folder = FilePicker.folder(
                message: String(localized: "Choose the library folder, or an empty folder for a new library"),
                prompt: prompt)
        else { return }
        Task { await environment.openLibrary(at: folder) }
    }
}

/// Cửa sổ làm việc: thanh công cụ, thanh cảnh báo, chế độ Trực tiếp hoặc Soạn thảo, màn chào khi thư viện trống.
struct MainWindowView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @SceneStorage("main.mode") private var modeRaw = WorkspaceMode.live.rawValue
    @SceneStorage("main.rightRail") private var showsRightRail = true
    /// Đang dựng thử Bảng lệnh (trong suốt) để làm ấm.
    @State private var warmsUpPalette = false

    var body: some View {
        let mode = WorkspaceMode(rawValue: modeRaw) ?? .live
        VStack(spacing: 0) {
            MainToolbar(mode: modeBinding, showsRightRail: $showsRightRail)
                // Nền các cột tràn lên vùng an toàn trên cùng: thanh công cụ phải vẽ sau để không bị đè.
                .zIndex(1)
            WarningBanner()
            Group {
                switch mode {
                case .live:
                    LiveWorkspace(showsRightRail: showsRightRail) { presentationID in
                        environment.editingPresentationID = presentationID
                        modeRaw = WorkspaceMode.editor.rawValue
                    }
                case .editor: EditorWorkspace()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if mode == .editor || !showsRightRail {
                    MiniOutputPreview()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(Motion.standard(reduceMotion: reduceMotion), value: showsRightRail)
        .overlay {
            if environment.show?.state.isRehearsal == true {
                Rectangle()
                    .strokeBorder(Palette.warn, lineWidth: 2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if showsWelcome {
                WelcomeView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: showsWelcome)
        .overlay {
            if environment.isCommandPalettePresented {
                CommandPalette(host: paletteHost)
            } else if warmsUpPalette {
                CommandPalette(host: paletteHost, isWarmUp: true)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task {
            // Làm ấm Bảng lệnh sau khi cửa sổ đã vẽ xong: dựng thử một lần rồi bỏ.
            try? await Task.sleep(for: .milliseconds(800))
            guard !environment.isCommandPalettePresented else { return }
            warmsUpPalette = true
            try? await Task.sleep(for: .milliseconds(400))
            warmsUpPalette = false
        }
        .animation(Motion.standard(reduceMotion: reduceMotion), value: environment.isCommandPalettePresented)
        .background {
            // `⌘K` mở Bảng lệnh ở cả hai chế độ.
            Button("Open command palette") { environment.openCommandPalette() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onChange(of: environment.outputs.missing) { _, _ in
            environment.warnings.pruneDismissed(outputs: environment.outputs)
        }
    }

    private var modeBinding: Binding<WorkspaceMode> {
        Binding(
            get: { WorkspaceMode(rawValue: modeRaw) ?? .live },
            set: { modeRaw = $0.rawValue }
        )
    }

    private var paletteHost: PaletteHost {
        PaletteHost(
            setMode: { modeRaw = $0.rawValue },
            openSettings: { openSettings() })
    }

    private var showsWelcome: Bool {
        environment.isLibraryEmpty && !environment.settings.value.welcomeDismissed
    }
}

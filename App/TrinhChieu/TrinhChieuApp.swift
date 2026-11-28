import AppKit
import SwiftUI

@main
struct TrinhChieuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        Window(Text("Main window"), id: "main") {
            RootView()
                .environment(environment)
                // Nền của thanh công cụ rỗng (giữ chỗ cho ba nút cửa sổ) không được che thanh tự vẽ.
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .onAppear { delegate.environment = environment }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1512, height: 945)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(environment)
        }
    }
}

/// Hỏi trước khi thoát khi đang chiếu, ghi thư viện và nhật ký buổi nhóm rồi mới thoát.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var environment: AppEnvironment?
    private var isTerminating = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        if environment.isShowingOnProgram {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Showing on screen. Quit the system?")
            alert.informativeText = String(localized: "The main output goes dark when the system quits.")
            alert.addButton(withTitle: String(localized: "Quit"))
            alert.addButton(withTitle: String(localized: "Stay"))
            // "Ở lại" là nút mặc định: lỡ tay bấm Enter không làm tắt hình giữa buổi nhóm.
            alert.buttons[0].keyEquivalent = ""
            alert.buttons[1].keyEquivalent = "\r"
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        isTerminating = true
        Task { @MainActor in
            await environment.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

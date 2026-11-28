import CoreModel
import SwiftUI

/// Phần thanh công cụ của chế độ Soạn thảo (mẫu `design/editor.html`): hoàn tác, làm lại, tạo mới, trạng thái lưu,
/// Nhập, Lên màn. Nút thêm phần tử (Chữ, Ảnh, Video, Hình) đi cùng khung vẽ ở PR 2 của T1.9.
struct EditorToolbarItems: View {
    @Binding var mode: WorkspaceMode
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let editing = environment.presentationEditing
        let editor = editing.editor
        HStack(spacing: 8) {
            IconButton(systemImage: "arrow.uturn.backward", label: "Undo", shortcutHint: "⌘Z") {
                environment.undoEditing()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(editor?.canUndo != true)
            IconButton(systemImage: "arrow.uturn.forward", label: "Redo", shortcutHint: "⇧⌘Z") {
                environment.redoEditing()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(editor?.canRedo != true)
        }
        .padding(.leading, 12)
        Spacer(minLength: 12)
        HStack(spacing: 8) {
            SaveMeter(savedAt: editing.savedAt, isOpen: editor != nil)
            Menu {
                Button("New song") { environment.createSong() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Blank presentation") { environment.createBlankPresentation() }
            } label: {
                Label("New", systemImage: "plus")
            }
            .menuStyle(.button)
            .fixedSize()
            .help(Text("New song (⌘N) or blank presentation"))
            Button {
                EditorImport.choose(environment)
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(ControlButtonStyle())
            .keyboardShortcut("i", modifiers: .command)
            .disabled(editing.isImporting)
            .help(Text("Import OpenLyrics, PDF, lyrics text") + Text(verbatim: " (⌘I)"))
            Button {
                environment.goLiveFromEditor()
                mode = .live
            } label: {
                HStack(spacing: 6) {
                    Text("Go live")
                    KeyCap(keys: "⇧⌘↩", bare: true)
                }
            }
            .buttonStyle(ControlButtonStyle(kind: .primary))
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(editor == nil || environment.show == nil)
            .help(Text("Show the selected slide on the main output"))
        }
        .fixedSize()
        // `⌘N` cũng chạy khi menu "Mới" đang đóng.
        .background {
            Button("New song") { environment.createSong() }
                .keyboardShortcut("n", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// "Đã lưu 9:41": thư viện ghi đĩa sau 1 giây mỗi lần sửa.
private struct SaveMeter: View {
    let savedAt: Date?
    let isOpen: Bool

    var body: some View {
        if isOpen {
            HStack(spacing: 8) {
                Lamp(style: .steady(Palette.ok))
                if let savedAt {
                    Text(verbatim: String(format: String(localized: "Saved %@"), Self.time(savedAt)))
                } else {
                    Text("Saved")
                }
            }
            .font(Typography.numberSmall)
            .foregroundStyle(Palette.text2)
            .padding(.horizontal, 10)
            .frame(height: Metrics.controlHeight)
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.line, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "vi_VN")))
    }
}

import CoreModel
import SwiftUI
import UniformTypeIdentifiers

/// Phần thanh công cụ của chế độ Soạn thảo (mẫu `design/editor.html`): hoàn tác, làm lại, tạo mới, trạng thái lưu,
/// thêm phần tử (Chữ, Ảnh, Video, Hình), Nhập, Lên màn.
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
        AddElementButtons()
            .disabled(environment.editingSlide == nil)
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
        // `⌘N` cũng chạy khi menu "Mới" đang đóng; `⌘]` `⌘[` đổi lớp phần tử đang chọn.
        .background {
            ZStack {
                Button("New song") { environment.createSong() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Bring forward") {
                    if let id = editing.selectedElementID { environment.bringElementForward(id) }
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(editing.selectedElementID == nil)
                Button("Send backward") {
                    if let id = editing.selectedElementID { environment.sendElementBackward(id) }
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(editing.selectedElementID == nil)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}

/// Nhóm "Thêm phần tử": Chữ (phím T trên khung vẽ), Ảnh và Video (từ thư viện Media hoặc chọn tệp), Hình.
private struct AddElementButtons: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 8) {
            Button {
                environment.addElement(.text)
            } label: {
                Label("Text", systemImage: "textformat")
            }
            .buttonStyle(ControlButtonStyle())
            .help(Text("Add a text box") + Text(verbatim: " (T)"))
            mediaMenu(.image, title: "Image", systemImage: "photo", help: "Add an image from Media or drop a file")
            mediaMenu(.video, title: "Video", systemImage: "film", help: "Add a video")
            Button {
                environment.addElement(.rectangle)
            } label: {
                Label("Shape", systemImage: "rectangle")
            }
            .buttonStyle(ControlButtonStyle())
            .help(Text("Add a rectangle"))
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Add element"))
    }

    private func mediaMenu(
        _ kind: MediaKind, title: LocalizedStringKey, systemImage: String, help: LocalizedStringKey
    ) -> some View {
        Menu {
            Button("Choose file…") { chooseFile(kind) }
            let items = environment.libraryMedia(kind)
            if !items.isEmpty {
                Divider()
                ForEach(items.prefix(20), id: \.id) { info in
                    Button {
                        environment.addElement(kind == .image ? .image(info.id) : .video(info.id))
                    } label: {
                        Text(verbatim: info.originalName)
                    }
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .menuStyle(.button)
        .fixedSize()
        .help(Text(help))
    }

    private func chooseFile(_ kind: MediaKind) {
        let urls = FilePicker.files(
            message: String(localized: "Choose files to place on the slide"), prompt: String(localized: "Add"),
            types: kind == .image ? [.image] : [.movie])
        guard !urls.isEmpty else { return }
        Task { await environment.addMediaElements(from: urls, at: nil) }
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

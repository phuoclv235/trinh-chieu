import CoreModel
import SwiftUI

/// Cột phải của trình soạn: các tab thuộc tính (mẫu `design/editor.html`, `.insp`). PR 1 của T1.9 có tab
/// "Bộ trình chiếu"; các tab Chữ, Bố cục, Nền trang đi cùng khung vẽ ở PR 2.
struct PresentationInspector: View {
    let presentation: Presentation

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Presentation")
                    .font(Typography.controlStrong)
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.accent).frame(height: 2) }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .overlay(alignment: .bottom) { Hairline() }
            ScrollView {
                PresentationFields(presentation: presentation)
                    .padding(16)
            }
        }
    }
}

/// Các trường của tab "Bộ trình chiếu": tiêu đề, loại, số, sách thánh ca, tác giả, bản quyền, tông, thẻ, mẫu.
private struct PresentationFields: View {
    let presentation: Presentation
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title") {
                TextField("Title", text: binding(\.title, key: "title"))
            }
            field("Type") {
                Picker("Type", selection: kindBinding) {
                    Text("Song").tag(PresentationKind.song)
                    Text("Presentation").tag(PresentationKind.generic)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if presentation.kind == .song {
                HStack(spacing: 8) {
                    field("Number") {
                        TextField("Number", text: songBinding(\.number, key: "number"))
                    }
                    field("Key") {
                        TextField("Key", text: songBinding(\.key, key: "key"))
                    }
                }
                field("Hymnal") {
                    TextField("Hymnal", text: songBinding(\.hymnal, key: "hymnal"))
                }
                field("Authors") {
                    ListField(value: presentation.song?.authors ?? []) { authors in
                        edit("authors") { presentation in
                            var song = presentation.song ?? SongInfo()
                            song.authors = authors
                            presentation.song = song
                        }
                    }
                }
                field("Copyright") {
                    TextField("Copyright", text: songBinding(\.copyright, key: "copyright"))
                }
            }
            field("Tags") {
                ListField(value: presentation.tags) { tags in edit("tags") { $0.tags = tags } }
            }
            field("Theme") {
                Picker("Theme", selection: themeBinding) {
                    Text("Library default").tag(UUID?.none)
                    ForEach(themes) { theme in
                        Text(verbatim: theme.name).tag(UUID?.some(theme.id))
                    }
                }
                .labelsHidden()
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(Typography.body)
    }

    private var themes: [Theme] {
        (environment.library?.themes.values.map { $0 } ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.text2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ràng buộc: mỗi lần gõ là một thay đổi, các lần gõ liền nhau gộp thành một bước hoàn tác.

    private func edit(_ key: String, _ change: @escaping (inout Presentation) -> Void) {
        environment.editPresentation(String(localized: "Edit presentation info"), coalescingKey: "info.\(key)", change)
    }

    private func binding(_ path: WritableKeyPath<Presentation, String>, key: String) -> Binding<String> {
        Binding(
            get: { presentation[keyPath: path] },
            set: { value in edit(key) { $0[keyPath: path] = value } })
    }

    private func songBinding(_ path: WritableKeyPath<SongInfo, String?>, key: String) -> Binding<String> {
        Binding(
            get: { presentation.song?[keyPath: path] ?? "" },
            set: { value in
                edit(key) { presentation in
                    var song = presentation.song ?? SongInfo()
                    song[keyPath: path] = value.isEmpty ? nil : value
                    presentation.song = song
                }
            })
    }

    private var kindBinding: Binding<PresentationKind> {
        Binding(
            get: { presentation.kind },
            set: { kind in
                edit("kind") { presentation in
                    presentation.kind = kind
                    if kind == .song, presentation.song == nil {
                        presentation.song = SongInfo()
                    }
                }
            })
    }

    private var themeBinding: Binding<UUID?> {
        Binding(
            get: { presentation.themeID },
            set: { id in edit("theme") { $0.themeID = id } })
    }
}

/// Ô danh sách cách nhau bằng dấu phẩy (tác giả, thẻ): gõ tự do, lưu khi nhấn Return hoặc rời ô.
private struct ListField: View {
    let value: [String]
    let onCommit: ([String]) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Separate with commas", text: $draft)
            .focused($isFocused)
            .onSubmit { commit() }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onAppear { draft = value.joined(separator: ", ") }
            .onChange(of: value) { _, newValue in
                if !isFocused { draft = newValue.joined(separator: ", ") }
            }
    }

    private func commit() {
        let items = draft.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if items != value { onCommit(items) }
    }
}

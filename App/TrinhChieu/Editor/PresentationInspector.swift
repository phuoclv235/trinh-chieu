import CoreModel
import SwiftUI

/// Cột phải của trình soạn: bốn thẻ thuộc tính (mẫu `design/editor.html`, `.insp`): Chữ, Bố cục, Nền trang, Bộ trình
/// chiếu. Thẻ Chữ và Bố cục làm việc với phần tử đang chọn trên khung vẽ, thẻ Nền trang với trang đang chọn.
struct PresentationInspector: View {
    let presentation: Presentation
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var editing = environment.presentationEditing
        VStack(spacing: 0) {
            InspectorTabs(selection: $editing.inspectorTab)
            ScrollView {
                Group {
                    switch editing.inspectorTab {
                    case .text: TextInspector()
                    case .layout: LayoutInspector()
                    case .background: BackgroundInspector()
                    case .presentation: PresentationFields(presentation: presentation)
                    }
                }
                .padding(16)
            }
        }
    }
}

/// Hàng thẻ (`.tabs`): thẻ đang mở chữ đậm, vạch cam đất 2 px ở đáy.
private struct InspectorTabs: View {
    @Binding var selection: InspectorTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    Text(title(tab))
                        .font(selected ? Typography.controlStrong : Typography.control)
                        .foregroundStyle(selected ? Palette.text : Palette.text2)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if selected { Rectangle().fill(Palette.accent).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Property groups"))
    }

    private func title(_ tab: InspectorTab) -> LocalizedStringKey {
        switch tab {
        case .text: return "Text"
        case .layout: return "Layout"
        case .background: return "Slide background"
        case .presentation: return "Presentation"
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

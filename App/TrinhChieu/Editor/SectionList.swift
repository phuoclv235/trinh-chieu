import CoreGraphics
import CoreModel
import Importers
import SwiftUI

/// Cột trái của trình soạn (mẫu `design/editor.html`, "Đoạn và trang"): đoạn dạng nhóm có nhãn và màu, trang là thẻ
/// nhỏ. Kéo thả trang trong đoạn và giữa các đoạn; kéo tiêu đề đoạn để đổi thứ tự gốc. Menu ngữ cảnh theo mẫu.
struct SectionList: View {
    let presentation: Presentation
    @Environment(AppEnvironment.self) private var environment
    @FocusState private var isFocused: Bool
    @State private var relabeling: SlideGroup?

    var body: some View {
        let editing = environment.presentationEditing
        let cards = environment.editorCards()
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(presentation.groups.enumerated()), id: \.element.id) { groupIndex, group in
                            GroupSection(
                                group: group, groupIndex: groupIndex, firstNumber: firstNumber(of: groupIndex),
                                cards: cards, selectedSlideID: editing.selectedSlideID,
                                onSelect: { select($0) }, onRelabel: { relabeling = $0 })
                        }
                        // Thả vào cuối danh sách: đoạn kéo tới cuối thứ tự gốc.
                        Color.clear
                            .frame(height: 40)
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items, beforeGroup: presentation.groups.count)
                            }
                    }
                }
                .onChange(of: editing.selectedSlideID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.delete) {
            deleteSelected()
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .background { shortcuts }
        .sheet(item: $relabeling) { group in
            GroupLabelSheet(group: group) { label in
                environment.editPresentation(String(localized: "Rename section")) { $0.setGroupLabel(group.id, label) }
            }
        }
        .onAppear { prepareThumbnails(cards) }
        .onChange(of: cards?.cards ?? []) { _, _ in prepareThumbnails(cards) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Sections and slides").font(Typography.blockTitle).foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            EditorCaption(text: String(format: String(localized: "%lld slides"), presentation.slideCount))
            IconButton(systemImage: "plus", label: "Add slide", shortcutHint: "⌘↩", small: true) {
                addSlide()
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    /// Phím tắt không có nút riêng: `⌘D` nhân đôi trang đang chọn.
    private var shortcuts: some View {
        Button {
            if let id = environment.presentationEditing.selectedSlideID {
                duplicate(id)
            }
        } label: {
            EmptyView()
        }
        .keyboardShortcut("d", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func firstNumber(of groupIndex: Int) -> Int {
        presentation.groups.prefix(groupIndex).reduce(1) { $0 + $1.slides.count }
    }

    private func prepareThumbnails(_ cards: (cards: [SlideCard], provider: EditorContentProvider)?) {
        guard let cards else { return }
        environment.thumbnails.prepare(cards.cards, sequence: cards.provider.sequence, provider: cards.provider)
    }

    // MARK: - Thao tác

    private func select(_ id: UUID) {
        environment.presentationEditing.selectedSlideID = id
        isFocused = true
    }

    private func moveSelection(by step: Int) {
        let ids = presentation.groups.flatMap { $0.slides.map(\.id) }
        guard !ids.isEmpty else { return }
        let current = environment.presentationEditing.selectedSlideID.flatMap { ids.firstIndex(of: $0) } ?? -1
        let next = min(max(0, current + step), ids.count - 1)
        environment.presentationEditing.selectedSlideID = ids[next]
    }

    private func addSlide() {
        var newID: UUID?
        let anchor = environment.presentationEditing.selectedSlideID
        environment.editPresentation(String(localized: "Add slide")) { newID = $0.addSlide(after: anchor) }
        if let newID { environment.presentationEditing.selectedSlideID = newID }
    }

    private func duplicate(_ id: UUID) {
        var newID: UUID?
        environment.editPresentation(String(localized: "Duplicate slide")) { newID = $0.duplicateSlide(id) }
        if let newID { environment.presentationEditing.selectedSlideID = newID }
    }

    private func deleteSelected() {
        guard let id = environment.presentationEditing.selectedSlideID else { return }
        SlideActions.delete(slideID: id, in: presentation, environment: environment)
    }

    /// Thả trang hoặc đoạn (chuỗi `slide:<mã>` hoặc `group:<mã>`) vào trước đoạn thứ `index`.
    private func handleDrop(_ items: [String], beforeGroup index: Int) -> Bool {
        guard let item = items.first, let payload = DragPayload(item) else { return false }
        switch payload {
        case .group(let id):
            environment.editPresentation(String(localized: "Move section")) { $0.moveGroup(id, to: index) }
        case .slide(let id):
            guard let last = presentation.groups.last else { return false }
            environment.editPresentation(String(localized: "Move slide")) {
                $0.moveSlide(id, toGroup: last.id, at: last.slides.count)
            }
        }
        return true
    }
}

/// Nội dung kéo thả trong trình soạn, dạng chuỗi để dùng `Transferable` có sẵn của `String`.
enum DragPayload: Equatable {
    case slide(UUID)
    case group(UUID)

    init?(_ string: String) {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "slide": self = .slide(id)
        case "group": self = .group(id)
        default: return nil
        }
    }

    var string: String {
        switch self {
        case .slide(let id): return "slide:\(id.uuidString)"
        case .group(let id): return "group:\(id.uuidString)"
        }
    }
}

/// Một đoạn: tiêu đề (kéo để đổi thứ tự gốc) và các trang.
private struct GroupSection: View {
    let group: SlideGroup
    let groupIndex: Int
    let firstNumber: Int
    let cards: (cards: [SlideCard], provider: EditorContentProvider)?
    let selectedSlideID: UUID?
    let onSelect: (UUID) -> Void
    let onRelabel: (SlideGroup) -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            groupHeader
            ForEach(Array(group.slides.enumerated()), id: \.element.id) { index, slide in
                SlideRow(
                    slide: slide, number: firstNumber + index, card: card(for: slide.id),
                    isSelected: slide.id == selectedSlideID
                )
                .id(slide.id)
                .onTapGesture { onSelect(slide.id) }
                .draggable(DragPayload.slide(slide.id).string)
                .dropDestination(for: String.self) { items, location in
                    dropSlide(items, at: location.y > SlideRow.height / 2 ? index + 1 : index)
                }
                .contextMenu { SlideMenu(slide: slide, group: group, onRelabel: onRelabel) }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var groupHeader: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(GroupColors.color(group))
                .frame(width: 8, height: 8)
            Text(verbatim: group.label.displayName)
                .font(Typography.controlStrong)
                .foregroundStyle(Palette.text)
            Spacer(minLength: 4)
            Text(verbatim: String(format: String(localized: "%lld slides"), group.slides.count))
                .font(Typography.numberSmall)
                .foregroundStyle(Palette.text3)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 26)
        .background(isTargeted ? Palette.accentSoft : Color.clear)
        .contentShape(Rectangle())
        .draggable(DragPayload.group(group.id).string) {
            Text(verbatim: group.label.displayName)
                .font(Typography.controlStrong)
                .padding(6)
                .background(Palette.bgRaised)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first, let payload = DragPayload(item) else { return false }
            switch payload {
            case .group(let id):
                environment.editPresentation(String(localized: "Move section")) { $0.moveGroup(id, to: groupIndex) }
                return true
            case .slide:
                return dropSlide(items, at: 0)
            }
        } isTargeted: {
            isTargeted = $0
        }
        .contextMenu { GroupMenu(group: group, onRelabel: onRelabel) }
        .accessibilityAddTraits(.isHeader)
    }

    private func card(for slideID: UUID) -> SlideCard? {
        cards?.cards.first { $0.slideID == slideID }
    }

    private func dropSlide(_ items: [String], at index: Int) -> Bool {
        guard let item = items.first, case .slide(let id)? = DragPayload(item) else { return false }
        environment.editPresentation(String(localized: "Move slide")) { $0.moveSlide(id, toGroup: group.id, at: index) }
        return true
    }
}

/// Một trang trong danh sách: số, ảnh thu nhỏ 92 điểm, hai dòng chữ.
private struct SlideRow: View {
    static let height: CGFloat = 60

    let slide: Slide
    let number: Int
    let card: SlideCard?
    let isSelected: Bool
    @Environment(AppEnvironment.self) private var environment
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(number)")
                .font(Typography.numberSmall)
                .foregroundStyle(Palette.text3)
                .frame(width: 16, alignment: .leading)
            thumbnail
                .frame(width: 92, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineStrong, lineWidth: 1))
            Text(verbatim: summary)
                .font(Typography.small)
                .foregroundStyle(isSelected ? Palette.text : Palette.text2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: Self.height)
        .opacity(slide.enabled ? 1 : 0.45)
        .background(isSelected ? Palette.accentSoft : (isHovered ? Palette.bgHover : Color.clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? Palette.accent : Color.clear).frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(number). \(summary)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var thumbnail: some View {
        // Đọc số ảnh đã dựng để gán ảnh ngay khi dựng xong.
        let _ = environment.thumbnails.renderedCount
        if let card, let image = environment.thumbnails.image(for: card.thumbnail) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
        } else {
            ZStack {
                Color.black
                Text(verbatim: summary)
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(4)
            }
        }
    }

    /// Hai dòng đầu nối bằng " / ", như mẫu.
    private var summary: String {
        let text = SlideCards.plainText(slide)
        if text.isEmpty {
            return slide.elements.isEmpty ? String(localized: "Media slide") : String(localized: "Empty slide")
        }
        return text.split(separator: "\n").prefix(2).joined(separator: " / ")
    }
}

/// Thao tác dùng chung cho menu ngữ cảnh và phím.
@MainActor enum SlideActions {
    /// Xoá trang sau khi hỏi. Trang cuối của đoạn thì hỏi xoá cả đoạn.
    static func delete(slideID: UUID, in presentation: Presentation, environment: AppEnvironment) {
        guard let location = presentation.location(ofSlide: slideID) else { return }
        let group = presentation.groups[location.group]
        if group.slides.count == 1 {
            deleteGroup(group, environment: environment)
            return
        }
        let title = String(
            format: String(localized: "Delete slide %lld of \"%@\"?"), location.slide + 1, group.label.displayName)
        let message = String(localized: "You can undo right after deleting.")
        guard DeleteConfirmation.ask(title: title, message: message, confirm: String(localized: "Delete slide"))
        else { return }
        environment.editPresentation(String(localized: "Delete slide")) { $0.deleteSlide(slideID) }
    }

    /// "Xoá đoạn 'Điệp khúc' và 3 trang?", có Hoàn tác.
    static func deleteGroup(_ group: SlideGroup, environment: AppEnvironment) {
        let title = String(
            format: String(localized: "Delete section \"%@\" and %lld slides?"), group.label.displayName,
            group.slides.count)
        let message = String(localized: "It is also removed from every arrangement. You can undo right after deleting.")
        guard DeleteConfirmation.ask(title: title, message: message, confirm: String(localized: "Delete section"))
        else { return }
        environment.editPresentation(String(localized: "Delete section")) { $0.deleteGroup(group.id) }
    }
}

/// Menu ngữ cảnh của một trang (mẫu `design/editor.html`, trạng thái "Menu ngữ cảnh").
private struct SlideMenu: View {
    let slide: Slide
    let group: SlideGroup
    let onRelabel: (SlideGroup) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let presentation = environment.editingPresentation
        let lineCount = LyricsText.cleanLines(slide.primaryText ?? "").count
        let isLast = group.slides.last?.id == slide.id
        Button("Add slide") {
            var newID: UUID?
            environment.editPresentation(String(localized: "Add slide")) { newID = $0.addSlide(after: slide.id) }
            environment.presentationEditing.selectedSlideID = newID ?? slide.id
        }
        Button("Duplicate") {
            var newID: UUID?
            environment.editPresentation(String(localized: "Duplicate slide")) { newID = $0.duplicateSlide(slide.id) }
            environment.presentationEditing.selectedSlideID = newID ?? slide.id
        }
        Button(slide.enabled ? LocalizedStringKey("Disable slide") : LocalizedStringKey("Enable slide")) {
            let enabled = !slide.enabled
            let name = enabled ? String(localized: "Enable slide") : String(localized: "Disable slide")
            environment.editPresentation(name) { $0.setSlideEnabled(slide.id, enabled) }
        }
        Divider()
        Button("Split slide in half") {
            guard let line = Presentation.defaultSplitLine(lineCount: lineCount) else { return }
            environment.editPresentation(String(localized: "Split slide")) { presentation in
                // Tách theo dòng đã bỏ dòng trống: chuẩn hoá chữ trước để chỉ số dòng khớp.
                if let location = presentation.location(ofSlide: slide.id) {
                    let clean = LyricsText.cleanLines(slide.primaryText ?? "").joined(separator: "\n")
                    presentation.groups[location.group].slides[location.slide].setPrimaryText(clean)
                }
                presentation.splitSlide(slide.id, atLine: line)
            }
        }
        .disabled(lineCount < 2)
        Button("Merge with next slide") {
            environment.editPresentation(String(localized: "Merge slides")) { $0.mergeSlideWithNext(slide.id) }
        }
        .disabled(isLast)
        Divider()
        GroupMenuItems(group: group, onRelabel: onRelabel)
        Divider()
        Button("Delete slide…", role: .destructive) {
            if let presentation {
                SlideActions.delete(slideID: slide.id, in: presentation, environment: environment)
            }
        }
        Button(
            String(format: String(localized: "Delete section \"%@\"…"), group.label.displayName), role: .destructive
        ) {
            SlideActions.deleteGroup(group, environment: environment)
        }
    }
}

/// Menu ngữ cảnh của tiêu đề đoạn.
private struct GroupMenu: View {
    let group: SlideGroup
    let onRelabel: (SlideGroup) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        GroupMenuItems(group: group, onRelabel: onRelabel)
        Divider()
        Button(
            String(format: String(localized: "Delete section \"%@\"…"), group.label.displayName), role: .destructive
        ) {
            SlideActions.deleteGroup(group, environment: environment)
        }
    }
}

/// "Đổi nhãn đoạn…", "Đổi màu đoạn".
private struct GroupMenuItems: View {
    let group: SlideGroup
    let onRelabel: (SlideGroup) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Button("Rename section…") { onRelabel(group) }
        Menu("Section color") {
            Button("By section type") { setColor(nil) }
            Divider()
            ForEach(GroupColors.choices.indices, id: \.self) { index in
                let choice = GroupColors.choices[index]
                Button {
                    setColor(choice.color)
                } label: {
                    Text(LocalizedStringKey(choice.name))
                }
            }
        }
    }

    private func setColor(_ color: RGBA?) {
        environment.editPresentation(String(localized: "Change section color")) { $0.setGroupColor(group.id, color) }
    }
}

/// Hộp đổi nhãn đoạn: loại, số, tên tự đặt.
private struct GroupLabelSheet: View {
    let group: SlideGroup
    let onSave: (GroupLabel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: GroupLabelKind
    @State private var number: String
    @State private var custom: String

    init(group: SlideGroup, onSave: @escaping (GroupLabel) -> Void) {
        self.group = group
        self.onSave = onSave
        _kind = State(initialValue: group.label.kind)
        _number = State(initialValue: group.label.number.map(String.init) ?? "")
        _custom = State(initialValue: group.label.custom ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename section").font(Typography.blockTitle).foregroundStyle(Palette.text)
            Picker("Section type", selection: $kind) {
                ForEach(GroupLabelKind.allCases, id: \.self) { kind in
                    Text(verbatim: Self.kindName(kind)).tag(kind)
                }
            }
            if kind == .custom {
                TextField("Section name", text: $custom)
            } else {
                TextField("Number (optional)", text: $number)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(ControlButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    onSave(label)
                    dismiss()
                }
                .buttonStyle(ControlButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(Typography.body)
        .padding(20)
        .frame(width: 320)
        .background(Palette.bgOverlay)
    }

    private var label: GroupLabel {
        if kind == .custom {
            let name = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return GroupLabel(kind: .custom, custom: name.isEmpty ? nil : name)
        }
        let value = Int(number.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        return GroupLabel(kind: kind, number: value)
    }

    /// Tên loại đoạn như trong văn bản lời ("Câu", "Điệp khúc"...), tên tự đặt là "Tên riêng".
    static func kindName(_ kind: GroupLabelKind) -> String {
        kind == .custom ? String(localized: "Custom name") : GroupLabel(kind: kind).displayName
    }
}

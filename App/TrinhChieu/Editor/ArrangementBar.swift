import CoreModel
import SwiftUI

/// Đầu cột giữa của trình soạn: tên bộ trình chiếu, loại, thanh thứ tự hát (mẫu `design/editor.html`, `.doc-head`).
struct DocumentHeader: View {
    let presentation: Presentation

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: presentation.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .layoutPriority(1)
            Text(presentation.kind == .song ? LocalizedStringKey("Song") : LocalizedStringKey("Presentation"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.text2)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineStrong, lineWidth: 1))
            Spacer(minLength: 12)
            if presentation.kind == .song || !presentation.arrangements.isEmpty {
                ArrangementBar(presentation: presentation)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.bgPanel)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Thanh thứ tự hát: chọn thứ tự đang dùng, các chip đoạn kéo thả để đổi chỗ, thêm một đoạn (nhiều lần cũng được),
/// tạo thứ tự hát mới, đổi tên, xoá.
struct ArrangementBar: View {
    let presentation: Presentation
    @Environment(AppEnvironment.self) private var environment
    @State private var naming: ArrangementNaming?

    var body: some View {
        let occurrences = presentation.orderedGroupOccurrences
        HStack(spacing: 6) {
            Text("Arrangement").font(Typography.caption).foregroundStyle(Palette.text3)
            arrangementMenu
            ForEach(occurrences) { occurrence in
                ArrangementChip(group: occurrence.group, position: occurrence.position, count: occurrences.count)
            }
            Menu {
                ForEach(presentation.groups) { group in
                    Button(group.label.displayName) {
                        environment.editPresentation(String(localized: "Add to arrangement")) {
                            $0.appendToActiveArrangement(group.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.text2)
                    .frame(width: 24, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radius)
                            .strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Add a section to the arrangement"))
            .accessibilityLabel(Text("Add a section to the arrangement"))
        }
        .sheet(item: $naming) { naming in
            ArrangementNameSheet(naming: naming) { name in
                switch naming.mode {
                case .create:
                    environment.editPresentation(String(localized: "New arrangement")) { $0.addArrangement(name: name) }
                case .rename(let id):
                    environment.editPresentation(String(localized: "Rename arrangement")) {
                        $0.renameArrangement(id, to: name)
                    }
                }
            }
        }
    }

    private var activeArrangement: Arrangement? {
        presentation.arrangements.first { $0.id == presentation.activeArrangementID }
    }

    private var arrangementMenu: some View {
        Menu {
            ForEach(presentation.arrangements) { arrangement in
                Button {
                    environment.editPresentation(String(localized: "Choose arrangement")) {
                        $0.setActiveArrangement(arrangement.id)
                    }
                } label: {
                    if arrangement.id == presentation.activeArrangementID {
                        Label(arrangement.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: arrangement.name)
                    }
                }
            }
            Divider()
            Button("New arrangement…") {
                naming = ArrangementNaming(mode: .create, name: "")
            }
            if let active = activeArrangement {
                Button("Rename arrangement…") {
                    naming = ArrangementNaming(mode: .rename(active.id), name: active.name)
                }
                Button("Delete this arrangement", role: .destructive) {
                    environment.editPresentation(String(localized: "Delete arrangement")) {
                        $0.deleteArrangement(active.id)
                    }
                }
                .disabled(presentation.arrangements.count < 2)
            }
        } label: {
            Text(verbatim: activeArrangement?.name ?? String(localized: "Original order"))
                .font(Typography.caption)
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(Text("Choose arrangement"))
    }
}

/// Một lần xuất hiện của đoạn trong thứ tự hát: kéo để đổi chỗ, menu để gỡ.
private struct ArrangementChip: View {
    let group: SlideGroup
    let position: Int
    let count: Int
    @Environment(AppEnvironment.self) private var environment
    @State private var isTargeted = false

    var body: some View {
        let color = GroupColors.color(group)
        Text(verbatim: group.label.displayName)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(color.opacity(0.16)))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(isTargeted ? Palette.accent : color.opacity(0.6), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
            .draggable("arrangement:\(position)")
            .dropDestination(for: String.self) { items, location in
                guard let item = items.first, item.hasPrefix("arrangement:"),
                    let from = Int(item.dropFirst("arrangement:".count))
                else { return false }
                let target = location.x > 30 ? position + 1 : position
                environment.editPresentation(String(localized: "Reorder arrangement")) {
                    $0.moveInActiveArrangement(from: from, to: target)
                }
                return true
            } isTargeted: {
                isTargeted = $0
            }
            .contextMenu {
                Button("Remove from arrangement") {
                    environment.editPresentation(String(localized: "Remove from arrangement")) {
                        $0.removeFromActiveArrangement(at: position)
                    }
                }
                Button("Move left") {
                    environment.editPresentation(String(localized: "Reorder arrangement")) {
                        $0.moveInActiveArrangement(from: position, to: position - 1)
                    }
                }
                .disabled(position == 0)
                Button("Move right") {
                    environment.editPresentation(String(localized: "Reorder arrangement")) {
                        $0.moveInActiveArrangement(from: position, to: position + 2)
                    }
                }
                .disabled(position == count - 1)
            }
            .help(Text("Drag to reorder"))
            .accessibilityLabel(Text(verbatim: group.label.displayName))
    }
}

/// Đang tạo hoặc đổi tên thứ tự hát.
struct ArrangementNaming: Identifiable {
    enum Mode {
        case create
        case rename(UUID)
    }

    let id = UUID()
    let mode: Mode
    let name: String
}

private struct ArrangementNameSheet: View {
    let naming: ArrangementNaming
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(naming: ArrangementNaming, onSave: @escaping (String) -> Void) {
        self.naming = naming
        self.onSave = onSave
        _name = State(initialValue: naming.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .create = naming.mode {
                Text("New arrangement").font(Typography.blockTitle).foregroundStyle(Palette.text)
                Text("Copies the arrangement in use; then add, remove or drag sections.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
            } else {
                Text("Rename arrangement").font(Typography.blockTitle).foregroundStyle(Palette.text)
            }
            TextField("Arrangement name", text: $name)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(ControlButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(ControlButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(Typography.body)
        .padding(20)
        .frame(width: 340)
        .background(Palette.bgOverlay)
    }
}

/// Một lần xuất hiện của đoạn trong thứ tự hát đang dùng.
struct GroupOccurrence: Identifiable {
    let position: Int
    let group: SlideGroup

    var id: Int { position }
}

extension Presentation {
    /// Các lần xuất hiện của đoạn theo thứ tự hát đang dùng, kèm vị trí trong thứ tự.
    var orderedGroupOccurrences: [GroupOccurrence] {
        orderedGroups().enumerated().map { GroupOccurrence(position: $0.offset, group: $0.element) }
    }
}

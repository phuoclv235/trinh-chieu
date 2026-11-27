import CoreModel
import SwiftUI

/// Cột giữa của chế độ Trực tiếp: tiêu đề nguồn đang xem, lưới trang chiếu, thanh cỡ thẻ.
struct SlideStage: View {
    /// Bấm "Soạn" (`⌘E`) với bộ trình chiếu đang xem.
    let onEdit: (UUID) -> Void
    @Environment(AppEnvironment.self) private var environment
    /// Cỡ thẻ 3 (nhỏ, 8 cột) đến 8 (lớn, 3 cột).
    @AppStorage("live.cardSize") private var cardSize = 6

    var body: some View {
        // Thư viện đổi (sửa lời, đổi mẫu) thì dựng lại thẻ.
        let _ = environment.contentRevision
        let source = environment.browsedSource
        VStack(spacing: 0) {
            if let source, let sequence = environment.sequence(for: source) {
                let cards = environment.cards(for: sequence)
                let live = liveIndex(of: source, in: sequence)
                SourceHeader(source: source, sequence: sequence, liveIndex: live, onEdit: onEdit)
                Hairline()
                if cards.isEmpty {
                    EmptyStateView(
                        systemImage: "rectangle.dashed", title: "No slides",
                        message: "This item has no slides yet. Open it in the editor to add some."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SlideGrid(
                        cards: cards, liveIndex: live, nextIndex: SlideCards.nextEnabled(after: live, in: cards),
                        columns: Self.columns(forCardSize: cardSize), thumbnails: environment.thumbnails
                    ) { index in
                        environment.goLive(source, slideIndex: index)
                    }
                    .onAppear { environment.prepareThumbnails(cards, sequence: sequence) }
                    .onChange(of: cards) { _, updated in environment.prepareThumbnails(updated, sequence: sequence) }
                }
                Hairline()
                GridFooter(count: cards.count, liveIndex: live, cardSize: $cardSize)
            } else if source != nil {
                EmptyStateView(
                    systemImage: "questionmark.square.dashed", title: "Content not found",
                    message: "This item is no longer in the library, or its file is missing."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    systemImage: "rectangle.on.rectangle", title: "Nothing selected",
                    message: "Choose a song, Bible passage or media in the library to see its slides here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.bgStage)
        .dropDestination(for: String.self) { values, _ in
            // Thả một dòng thư viện vào giữa: xem lưới trang của nó (chưa lên màn).
            guard let row = values.lazy.compactMap({ LibraryDrag.row(from: $0, environment: environment) }).first,
                let source = row.source
            else { return false }
            environment.send(.selectItem(source))
            return true
        }
    }

    /// Cỡ thẻ càng lớn, càng ít cột: 3 → 8 cột, 8 → 3 cột.
    static func columns(forCardSize size: Int) -> Int {
        11 - min(8, max(3, size))
    }

    private func liveIndex(of source: LiveSource, in sequence: SlideSequence) -> Int? {
        guard let live = environment.show?.state.live, live.source == source else { return nil }
        return sequence.index(of: live)
    }
}

/// Thanh trên lưới (`.src-head`): tiêu đề nguồn 26, dòng thông tin, thứ tự hát, nút Soạn.
struct SourceHeader: View {
    let source: LiveSource
    let sequence: SlideSequence
    let liveIndex: Int?
    let onEdit: (UUID) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let presentation = presentationID.flatMap { environment.library?.presentations[$0] }
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: sequence.title)
                    .font(Typography.sourceTitle)
                    .tracking(-0.6)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(Text(verbatim: sequence.title))
                Text(verbatim: meta(presentation))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let presentation, !presentation.arrangements.isEmpty {
                    ArrangementControls(
                        presentation: presentation, sequence: sequence, liveIndex: liveIndex,
                        current: currentArrangementID(presentation)
                    ) { arrangementID in
                        environment.selectArrangement(arrangementID, for: source)
                    }
                }
                if let presentationID {
                    IconButton(
                        systemImage: "pencil", label: "Edit this presentation", shortcutHint: "⌘E", small: true
                    ) {
                        onEdit(presentationID)
                    }
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Palette.bgPanel)
    }

    private var presentationID: UUID? {
        sequence.slides.first?.presentationID
    }

    private func currentArrangementID(_ presentation: Presentation) -> UUID? {
        environment.arrangementID(for: source) ?? presentation.activeArrangementID
    }

    /// "Thánh ca 47 · Tác giả · 9 trang".
    private func meta(_ presentation: Presentation?) -> String {
        var parts: [String] = []
        switch source {
        case .scripture:
            parts.append(String(localized: "Bible"))
        case .media:
            parts.append(String(localized: "Media"))
        case .planItem, .presentation:
            if let song = presentation?.song {
                if let number = song.number, !number.isEmpty {
                    let hymn = String(format: String(localized: "Hymn %@"), number)
                    parts.append(song.hymnal.map { "\($0) \(number)" } ?? hymn)
                }
                let authors = song.authors.filter { !$0.isEmpty }
                if !authors.isEmpty {
                    parts.append(authors.joined(separator: ", "))
                }
            } else if presentation != nil {
                parts.append(String(localized: "Presentation"))
            }
        }
        parts.append(String(format: String(localized: "%lld slides"), sequence.slides.count))
        return parts.joined(separator: " · ")
    }
}

/// Thứ tự hát: chip từng đoạn theo thứ tự (đoạn đang chiếu viền cam đất) và menu chọn thứ tự hát.
private struct ArrangementControls: View {
    let presentation: Presentation
    let sequence: SlideSequence
    let liveIndex: Int?
    let current: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        let groups = presentation.orderedGroups(arrangementID: current)
        let liveChip = chipIndex(containing: liveIndex, groups: groups)
        HStack(spacing: 6) {
            Text("Song order").font(Typography.caption).foregroundStyle(Palette.text3)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        GroupChip(
                            label: group.label.displayName, color: group.color, kind: group.label.kind,
                            isSelected: index == liveChip)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxWidth: 320)
            .fixedSize(horizontal: true, vertical: false)
            Menu {
                ForEach(presentation.arrangements) { arrangement in
                    Button {
                        onSelect(arrangement.id)
                    } label: {
                        if arrangement.id == current {
                            Label(arrangement.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: arrangement.name)
                        }
                    }
                }
            } label: {
                Text(verbatim: currentName)
            }
            .menuStyle(.button)
            .buttonStyle(ControlButtonStyle(small: true))
            .fixedSize()
            .accessibilityLabel(Text("Choose song order"))
        }
    }

    private var currentName: String {
        presentation.arrangements.first(where: { $0.id == current })?.name ?? String(localized: "Default")
    }

    /// Chip của đoạn chứa trang `index` (đếm cả các lần lặp).
    private func chipIndex(containing index: Int?, groups: [SlideGroup]) -> Int? {
        guard let index else { return nil }
        var start = 0
        for (position, group) in groups.enumerated() {
            if index >= start && index < start + group.slides.count {
                return position
            }
            start += group.slides.count
        }
        return nil
    }
}

/// Chip đoạn (`.chip`): vạch màu đoạn 2 px bên trái.
private struct GroupChip: View {
    let label: String
    let color: RGBA?
    let kind: GroupLabelKind
    let isSelected: Bool

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? Palette.text : Palette.text2)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(Palette.bgRaised))
            .overlay(alignment: .leading) {
                Rectangle().fill(tint).frame(width: 2).padding(.vertical, 1).padding(.leading, 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(isSelected ? Palette.accent : Palette.lineStrong, lineWidth: 1)
            )
    }

    private var tint: Color {
        if let color {
            return Color(
                .sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255,
                opacity: Double(color.alpha) / 255)
        }
        switch kind {
        case .verse: return Palette.groupVerse
        case .chorus, .prechorus: return Palette.groupChorus
        case .bridge: return Palette.groupBridge
        case .ending, .tag: return Palette.groupEnding
        case .intro: return Palette.groupIntro
        case .custom: return .clear
        }
    }
}

/// Thanh dưới lưới (`.grid-foot`): vị trí trang, thanh trượt cỡ thẻ, `⌘−` và `⌘+`.
private struct GridFooter: View {
    let count: Int
    let liveIndex: Int?
    @Binding var cardSize: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: counter)
                .font(Typography.number)
                .foregroundStyle(Palette.text3)
            Spacer(minLength: 8)
            Text("Card size").font(Typography.caption).foregroundStyle(Palette.text3)
            Slider(
                value: Binding(get: { Double(cardSize) }, set: { cardSize = Int($0.rounded()) }),
                in: 3...8, step: 1
            )
            .controlSize(.small)
            .tint(Palette.accent)
            .frame(width: 120)
            .accessibilityLabel(Text("Card size"))
            sizeButton(keys: "⌘ −", label: "Smaller cards", delta: -1, key: "-")
            sizeButton(keys: "⌘ +", label: "Larger cards", delta: 1, key: "=")
                .background {
                    // ⌘+ trên bàn phím cần giữ Shift: nhận cả hai dạng.
                    Button("") { change(by: 1) }
                        .keyboardShortcut("+", modifiers: .command)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
        .background(Palette.bgPanel)
    }

    private var counter: String {
        if let liveIndex {
            return String(format: String(localized: "Slide %@ / %@"), Self.two(liveIndex + 1), Self.two(count))
        }
        return String(format: String(localized: "%lld slides"), count)
    }

    private static func two(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private func change(by delta: Int) {
        cardSize = min(8, max(3, cardSize + delta))
    }

    private func sizeButton(keys: String, label: LocalizedStringKey, delta: Int, key: KeyEquivalent) -> some View {
        Button {
            change(by: delta)
        } label: {
            KeyCap(keys: keys)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help(Text(label) + Text(verbatim: " (\(keys))"))
        .accessibilityLabel(Text(label))
    }
}

import AppKit
import CoreModel
import LibraryIndex
import LibraryStore
import Scripture
import SwiftUI
import os

/// Bảng lệnh `⌘K` (mẫu `design/live.html`, `.palette`): một ô tìm cho Kinh Thánh, bài hát, bộ trình chiếu, media,
/// mục chương trình và lệnh. `↑ ↓` chọn, `Enter` hành động chính, `⌘Enter` hành động phụ, `Esc` đóng.
///
/// Mỗi lần mở là một khung mới nên mở lại thì ô trống. Gõ đến đâu tìm đến đó, không chờ: kết quả cũ giữ nguyên
/// cho tới khi có kết quả mới (không nháy), `Enter` bấm khi đang tìm thì chạy ngay khi tìm xong.
struct CommandPalette: View {
    let host: PaletteHost
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var sections: [PaletteSection] = []
    @State private var selection = 0
    @State private var planItems: [PaletteItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    /// `Enter` bấm khi đang tìm: `true` là `⌘Enter`.
    @State private var pendingSubmit: Bool?

    private static let ranker = PaletteRanker()
    @MainActor private static let commands = AppEnvironment.paletteCommands()
    private static let logger = Logger(subsystem: "app.trinhchieu.TrinhChieu", category: "Palette")
    /// Số dòng hiện được trước khi phải cuộn.
    static let visibleRows = 8
    static let rowHeight: CGFloat = 40
    static let labelHeight: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            Palette.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .accessibilityHidden(true)
            panel
                .padding(.top, 88)
                .padding(.horizontal, 24)
        }
        .onAppear(perform: appeared)
        .onDisappear { searchTask?.cancel() }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            inputRow
            results
            footer
        }
        .frame(maxWidth: 620)
        .background(RoundedRectangle(cornerRadius: Metrics.radiusPop).fill(Palette.bgOverlay))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusPop))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusPop).strokeBorder(Palette.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 18)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Command palette"))
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Ô gõ

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.text3)
                .accessibilityHidden(true)
            PaletteTextField(
                text: $query,
                placeholder: String(localized: "Search songs, Bible verses, commands…"),
                onMove: { move($0) },
                onSubmit: { submit(secondary: $0) },
                onCancel: { close() }
            )
            .frame(maxWidth: .infinity)
            .onChange(of: query) { _, _ in refresh() }
            KeyCap(keys: "Esc")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: - Kết quả

    private var rows: [PaletteRow] {
        sections.flatMap(\.rows)
    }

    @ViewBuilder private var results: some View {
        if sections.isEmpty {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching {
                Text("No results")
                    .font(Typography.control)
                    .foregroundStyle(Palette.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            Text(Self.label(section.group))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.text3)
                                .padding(.horizontal, 16)
                                .frame(height: Self.labelHeight, alignment: .bottomLeading)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.rows) { row in
                                let index = rows.firstIndex(of: row) ?? 0
                                PaletteRowView(row: row, isSelected: index == selection, symbol: symbol(for: row))
                                    .id(row.id)
                                    .onTapGesture {
                                        selection = index
                                        submit(secondary: false)
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(height: resultsHeight)
                .scrollIndicators(.automatic)
                .onChange(of: selection) { _, value in
                    guard rows.indices.contains(value) else { return }
                    proxy.scrollTo(rows[value].id)
                }
            }
        }
    }

    /// Vừa khít nội dung, tối đa 8 dòng (cùng nhãn nhóm của chúng) rồi cuộn.
    private var resultsHeight: CGFloat {
        var height: CGFloat = 8
        var shown = 0
        for section in sections where shown < Self.visibleRows {
            height += Self.labelHeight
            let take = min(section.rows.count, Self.visibleRows - shown)
            height += CGFloat(take) * Self.rowHeight
            shown += take
        }
        return height
    }

    private var footer: some View {
        let selected = rows.indices.contains(selection) ? rows[selection] : nil
        return HStack(spacing: 16) {
            hint(keys: ["↑", "↓"], label: "select")
            if let selected {
                hint(keys: ["↵"], label: Self.primaryLabel(selected.target))
                if let secondary = Self.secondaryLabel(selected.target) {
                    hint(keys: ["⌘↵"], label: secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.text3)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Hairline() }
    }

    private func hint(keys: [String], label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { KeyCap(keys: $0) }
            Text(label)
        }
    }

    // MARK: - Tìm

    private func appeared() {
        planItems = environment.palettePlanItems()
        refresh()
        guard let requested = environment.commandPaletteRequestedAt else { return }
        environment.commandPaletteRequestedAt = nil
        // Đo tới vòng chạy kế tiếp: lúc đó khung đầu tiên của Bảng lệnh đã được vẽ.
        DispatchQueue.main.async {
            let elapsed = ContinuousClock.now - requested
            Self.logger.info("Bảng lệnh hiện sau \(Self.milliseconds(elapsed), format: .fixed(precision: 1)) ms")
        }
    }

    /// Xếp hạng lại theo chữ đang gõ. Phân tích địa chỉ và lệnh chạy ngay; tìm thư viện chạy nền.
    private func refresh() {
        searchTask?.cancel()
        // Chữ đã đổi sau khi bấm Enter: bỏ lần Enter chờ, không chạy dòng của truy vấn cũ.
        pendingSubmit = nil
        let text = query
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let library = environment.library else {
            isSearching = false
            apply(rank(text, hits: []))
            return
        }
        isSearching = true
        searchTask = Task { @MainActor in
            let hits = await library.search(trimmed, kinds: [.presentation, .media])
            guard !Task.isCancelled else { return }
            apply(rank(text, hits: hits))
            isSearching = false
            if let secondary = pendingSubmit {
                pendingSubmit = nil
                submit(secondary: secondary)
            }
        }
    }

    private func rank(_ text: String, hits: [SearchHit]) -> [PaletteSection] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parse = trimmed.isEmpty ? nil : Self.ranker.parser.parse(trimmed)
        let kinds = environment.palettePresentationKinds(hits)
        let settings = environment.settings.value
        return Self.ranker.rank(
            query: text, scriptureParse: parse, scripture: environment.paletteScriptureContext(for: parse),
            hits: hits, presentationKind: { kinds[$0] }, commands: Self.commands, planItems: planItems,
            recents: settings.paletteRecents, commandUsage: settings.paletteCommandUsage)
    }

    private func apply(_ ranked: [PaletteSection]) {
        sections = ranked
        selection = 0
    }

    // MARK: - Phím

    private func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = min(rows.count - 1, max(0, selection + delta))
    }

    private func submit(secondary: Bool) {
        if isSearching {
            pendingSubmit = secondary
            return
        }
        guard rows.indices.contains(selection) else { return }
        let started = ContinuousClock.now
        let row = rows[selection]
        switch environment.performPalette(row, secondary: secondary, host: host) {
        case .close:
            let elapsed = Self.milliseconds(ContinuousClock.now - started)
            Self.logger.info("Bảng lệnh: Enter tới lúc gửi lệnh \(elapsed, format: .fixed(precision: 1)) ms")
            close()
        case .fill(let text):
            query = text
        case .unavailable:
            NSSound.beep()
        }
    }

    private func close() {
        searchTask?.cancel()
        environment.isCommandPalettePresented = false
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    // MARK: - Chữ và biểu tượng

    private func symbol(for row: PaletteRow) -> String {
        switch row.target {
        case .scripture, .bookCompletion: return "book"
        case .presentation(let id):
            return environment.library?.presentations[id]?.kind == .generic ? "rectangle.stack" : "music.note"
        case .media(let id):
            switch environment.library?.media[id]?.kind {
            case .image?: return "photo"
            case .audio?: return "waveform"
            default: return "film"
            }
        case .planItem: return "list.bullet"
        case .command: return "command"
        }
    }

    static func label(_ group: PaletteGroup) -> LocalizedStringKey {
        switch group {
        case .recent: return "Recent"
        case .scripture: return "Bible"
        case .songs: return "Songs"
        case .presentations: return "Other presentations"
        case .media: return "Media"
        case .planItems: return "Service plan items"
        case .commands: return "Commands"
        }
    }

    static func primaryLabel(_ target: PaletteTarget) -> LocalizedStringKey {
        switch target {
        case .scripture: return "Go live"
        case .bookCompletion: return "Choose book"
        case .presentation: return "Show slides"
        case .media: return "Show as background"
        case .planItem: return "Select item"
        case .command: return "Run"
        }
    }

    static func secondaryLabel(_ target: PaletteTarget) -> LocalizedStringKey? {
        guard target.hasSecondaryAction else { return nil }
        switch target {
        case .planItem: return "Go live"
        default: return "Add to service plan"
        }
    }
}

/// Một dòng của Bảng lệnh (`.palette .row`): phiến chọn nền cam nhạt, vạch trái 2 px, gợi ý phím bên phải.
private struct PaletteRowView: View {
    let row: PaletteRow
    let isSelected: Bool
    let symbol: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Palette.accent : Palette.text3)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                (Text(verbatim: row.title).foregroundStyle(Palette.text)
                    + Text(verbatim: row.detail.map { " " + $0 } ?? "").foregroundStyle(Palette.text3))
                    .font(Typography.control)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    subtitle
                        .font(Typography.small)
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .frame(minHeight: CommandPalette.rowHeight)
        .background(isSelected ? Palette.accentSoft : (isHovered ? Palette.bgHover : Color.clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? Palette.accent : Color.clear).frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var subtitle: Text? {
        if let text = row.subtitle, !text.isEmpty {
            return Text(verbatim: text)
        }
        switch row.target {
        case .scripture(let translation, _) where translation == nil:
            return Text("Import a Bible translation in Settings to show verses.")
        case .bookCompletion: return Text("Type the chapter and verse next")
        default: return nil
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 6) {
            if isSelected {
                Text(CommandPalette.primaryLabel(row.target))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
                KeyCap(keys: "↵")
            } else if let shortcut = row.shortcut {
                KeyCap(keys: shortcut, bare: true)
            }
        }
    }
}

import CoreModel
import LibraryIndex
import LibraryStore
import SwiftUI

/// Tab của thư viện thu gọn.
enum LibraryTab: String, CaseIterable, Sendable {
    case songs
    case scripture
    case media
    case themes

    var title: LocalizedStringKey {
        switch self {
        case .songs: return "Songs"
        case .scripture: return "Bible"
        case .media: return "Media"
        case .themes: return "Themes"
        }
    }
}

/// Một dòng trong thư viện thu gọn.
struct LibraryRow: Identifiable, Equatable, Sendable {
    let id: String
    /// Cột trái: số thánh ca (bài hát) hoặc tên biểu tượng SF Symbols (media, mẫu).
    let leading: Leading
    let title: String
    let subtitle: String
    /// Nguồn xem được ở lưới giữa; `nil` với mẫu trình bày.
    let source: LiveSource?

    enum Leading: Equatable, Sendable {
        case number(String)
        case symbol(String)
    }
}

/// Thư viện thu gọn ở cột trái dưới (mẫu `design/live.html`, `.lib-body`): tab, ô tìm không dấu, danh sách.
/// Bấm một lần: xem lưới trang ở giữa (chưa lên màn). Bấm đúp: thêm vào cuối chương trình.
struct CompactLibrary: View {
    /// Bấm đúp một dòng: thêm vào chương trình đang mở.
    var onAdd: ((LibraryRow) -> Void)?
    @Environment(AppEnvironment.self) private var environment
    @SceneStorage("live.libraryTab") private var tabRaw = LibraryTab.songs.rawValue
    @State private var query = ""
    @State private var rows: [LibraryRow] = []
    @State private var isSearching = false
    @State private var isLoaded = false
    @FocusState private var searchFocused: Bool

    private var tab: LibraryTab {
        LibraryTab(rawValue: tabRaw) ?? .songs
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryTabs(selection: Binding(get: { tab }, set: { tabRaw = $0.rawValue }))
            if tab == .scripture {
                ScripturePanel()
            } else {
                SearchField(
                    text: $query, prompt: "Search without accents", isFocused: $searchFocused
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                list
            }
        }
        .task(id: Reload(tab: tab, query: query, revision: environment.contentRevision)) {
            await reload()
        }
    }

    @ViewBuilder private var list: some View {
        if !isLoaded {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty && !isSearching {
            EmptyStateView(systemImage: emptySymbol, title: emptyTitle, message: emptyMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        LibraryRowView(row: row, isSelected: isSelected(row))
                            .onTapGesture(count: 2) { onAdd?(row) }
                            .simultaneousGesture(TapGesture().onEnded { select(row) })
                            .libraryDrag(row)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func isSelected(_ row: LibraryRow) -> Bool {
        guard let source = row.source else { return false }
        return environment.show?.state.selected == source
    }

    private func select(_ row: LibraryRow) {
        guard let source = row.source else { return }
        environment.send(.selectItem(source))
    }

    // MARK: - Nạp danh sách

    private struct Reload: Equatable {
        let tab: LibraryTab
        let query: String
        let revision: Int
    }

    /// Gõ đến đâu ra đến đó, trễ 120 ms để không tìm lại sau mỗi phím.
    private func reload() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let library = environment.library, tab != .scripture else {
            rows = []
            return
        }
        if trimmed.isEmpty {
            rows = LibraryRows.all(tab, library: library)
            isSearching = false
            isLoaded = true
            return
        }
        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(120))
        } catch {
            return
        }
        let kinds: Set<IndexKind> = tab == .media ? [.media] : tab == .themes ? [.theme] : [.presentation]
        let hits = await library.search(trimmed, kinds: kinds)
        guard !Task.isCancelled else { return }
        rows = LibraryRows.rows(for: hits, tab: tab, library: library)
        isSearching = false
        isLoaded = true
    }

    // MARK: - Trạng thái rỗng

    private var emptySymbol: String {
        query.isEmpty ? "music.note.list" : "magnifyingglass"
    }

    private var emptyTitle: LocalizedStringKey {
        guard query.isEmpty else { return "No results" }
        switch tab {
        case .songs: return "No songs yet"
        case .media: return "No media yet"
        case .themes, .scripture: return "No themes yet"
        }
    }

    private var emptyMessage: LocalizedStringKey {
        guard query.isEmpty else { return "Try fewer words, or search by hymn number." }
        switch tab {
        case .songs: return "Import lyrics files from the welcome screen."
        case .media: return "Media you import into the library appears here."
        case .themes, .scripture: return "Themes control how slides look on the main output."
        }
    }
}

/// Dòng thư viện từ dữ liệu của `LibraryStore`.
@MainActor enum LibraryRows {
    static func all(_ tab: LibraryTab, library: LibraryStore) -> [LibraryRow] {
        switch tab {
        case .songs:
            return library.presentations.values
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .map(row(for:))
        case .media:
            return library.media.values
                .sorted { $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending }
                .map(row(for:))
        case .themes:
            let defaultID = library.info.defaultThemeID
            return library.themes.values
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { row(for: $0, isDefault: $0.id == defaultID) }
        case .scripture:
            return []
        }
    }

    /// Kết quả tìm, giữ thứ tự điểm của chỉ mục.
    static func rows(for hits: [SearchHit], tab: LibraryTab, library: LibraryStore) -> [LibraryRow] {
        hits.compactMap { hit in
            switch hit.kind {
            case .presentation:
                return UUID(uuidString: hit.id).flatMap { library.presentations[$0] }.map(row(for:))
            case .media:
                return library.media[MediaID(hit.id)].map(row(for:))
            case .theme:
                return UUID(uuidString: hit.id).flatMap { library.themes[$0] }.map {
                    row(for: $0, isDefault: $0.id == library.info.defaultThemeID)
                }
            case .plan, .verse:
                return nil
            }
        }
    }

    static func row(for presentation: Presentation) -> LibraryRow {
        let number = presentation.song?.number?.trimmingCharacters(in: .whitespaces) ?? ""
        let authors = presentation.song?.authors.filter { !$0.isEmpty }.joined(separator: ", ") ?? ""
        let subtitle: String
        if presentation.kind == .generic {
            subtitle = String(localized: "Presentation")
        } else {
            subtitle = authors.isEmpty ? String(localized: "Song") : authors
        }
        return LibraryRow(
            id: presentation.id.uuidString,
            leading: .number(number.isEmpty ? "–" : number),
            title: presentation.title,
            subtitle: subtitle,
            source: .presentation(id: presentation.id, arrangementID: nil)
        )
    }

    static func row(for media: MediaAssetInfo) -> LibraryRow {
        let symbol: String
        var parts: [String] = []
        switch media.kind {
        case .image:
            symbol = "photo"
            parts.append(String(localized: "Picture"))
        case .video:
            symbol = "film"
            parts.append(String(localized: "Video"))
        case .audio:
            symbol = "waveform"
            parts.append(String(localized: "Audio"))
        }
        if let size = media.pixelSize {
            parts.append("\(Int(size.width))×\(Int(size.height))")
        }
        if let duration = media.duration {
            parts.append(Self.duration(duration))
        }
        return LibraryRow(
            id: media.id.rawValue, leading: .symbol(symbol), title: media.originalName,
            subtitle: parts.joined(separator: " · "), source: .media(media.id))
    }

    static func row(for theme: Theme, isDefault: Bool) -> LibraryRow {
        LibraryRow(
            id: theme.id.uuidString, leading: .symbol("paintpalette"), title: theme.name,
            subtitle: isDefault ? String(localized: "Library default") : String(localized: "Theme"), source: nil)
    }

    /// "2:05", "1:02:05".
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }
}

/// Dòng danh sách (`.row`): phiến chọn nền cam nhạt và vạch trái 2 px.
struct LibraryRowView: View {
    let row: LibraryRow
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            switch row.leading {
            case .number(let number):
                Text(verbatim: number)
                    .font(Typography.numberSmall)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .frame(width: 30, alignment: .trailing)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text3)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.title)
                    .font(Typography.control)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !row.subtitle.isEmpty {
                    Text(verbatim: row.subtitle)
                        .font(Typography.small)
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .frame(minHeight: 34)
        .background(isSelected ? Palette.accentSoft : (isHovered ? Palette.bgHover : Color.clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? Palette.accent : Color.clear).frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(Text(verbatim: row.title))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Hàng tab (`.tabs`): tab đang chọn nền nổi và vạch cam đất 2 px ở đáy.
struct LibraryTabs: View {
    @Binding var selection: LibraryTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(LibraryTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 {
                    Rectangle().fill(Palette.line).frame(width: 1)
                }
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(selected ? Palette.text : Palette.text2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(selected ? Palette.bgRaised : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(Palette.accent).frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Library type"))
    }
}

/// Ô tìm (`.search`): biểu tượng, ô gõ, phím tắt. `⌘F` đưa con trỏ vào ô.
struct SearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var isFocused: FocusState<Bool>.Binding
    var symbol = "magnifyingglass"
    var shortcut = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.text3)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(prompt).foregroundStyle(Palette.text3)) {
                Text(prompt)
            }
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Palette.text)
            .focused(isFocused)
            if shortcut {
                KeyCap(keys: "⌘F")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: Metrics.controlHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(Palette.bgStage))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .strokeBorder(isFocused.wrappedValue ? Palette.accent : Palette.lineStrong, lineWidth: 1)
        )
        .background {
            if shortcut {
                Button("") { isFocused.wrappedValue = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Kéo dòng thư viện vào chương trình buổi nhóm hoặc lưới trang (mẫu trình bày không kéo được).
    @ViewBuilder func libraryDrag(_ row: LibraryRow) -> some View {
        if let payload = LibraryDrag.payload(for: row) {
            onDrag { NSItemProvider(object: payload as NSString) }
        } else {
            self
        }
    }
}

import CoreModel
import Scripture
import SwiftUI

/// Tab Kinh Thánh của thư viện thu gọn: ô địa chỉ câu (phân tích khi gõ), chọn bản dịch, danh sách câu của chương.
///
/// `Enter`: xem lưới trang của đoạn. `⌘Enter`: lên màn trang đầu ngay. `⌘⇧Enter`: thêm vào chương trình. Tên sách
/// gõ chưa rõ (ví dụ "gi" khớp nhiều sách) thì hiện các sách để chọn bằng phím mũi tên.
struct ScripturePanel: View {
    @Environment(AppEnvironment.self) private var environment
    @SceneStorage("live.scriptureReference") private var text = ""
    @State private var candidateIndex = 0
    @FocusState private var fieldFocused: Bool

    private let parser = ReferenceParser()

    var body: some View {
        let code = translationCode
        let result = parse()
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                SearchField(
                    text: $text, prompt: "Reference, e.g. John 3:16", isFocused: $fieldFocused, symbol: "book"
                )
                .onKeyPress(.upArrow) { moveCandidate(-1, in: result) }
                .onKeyPress(.downArrow) { moveCandidate(1, in: result) }
                .onKeyPress(.return, phases: .down) { press in
                    submit(result, code: code, modifiers: press.modifiers)
                }
                .onChange(of: text) { _, _ in candidateIndex = 0 }
                translationPicker(code)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            content(result, code: code)
        }
    }

    // MARK: - Bản dịch

    private var translationCode: String? {
        let available = environment.translations
        if let preferred = environment.settings.value.defaultTranslation,
            available.contains(where: { $0.code == preferred })
        {
            return preferred
        }
        return available.first?.code
    }

    @ViewBuilder private func translationPicker(_ code: String?) -> some View {
        let available = environment.translations
        if available.count > 1 {
            Picker(
                selection: Binding(
                    get: { code ?? "" }, set: { environment.settings.value.defaultTranslation = $0 })
            ) {
                ForEach(available, id: \.code) { info in
                    Text(verbatim: info.name).tag(info.code)
                }
            } label: {
                Text("Translation")
            }
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(Text("Translation"))
        } else if let only = available.first {
            Text(verbatim: only.name)
                .font(Typography.caption)
                .foregroundStyle(Palette.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Nội dung

    private func parse() -> ParseResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parser.parse(trimmed)
    }

    @ViewBuilder private func content(_ result: ParseResult?, code: String?) -> some View {
        if environment.translations.isEmpty {
            EmptyStateView(
                systemImage: "book.closed", title: "No Bible translation yet",
                message: "Import a translation file in Settings, Library, to look up verses here."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch result {
            case nil:
                hint("Type a book, chapter and verse: \"gi 3 16\", \"Thi 23\", \"Rô 8:28; 12:1-2\".")
            case .invalid(let reason)?:
                hint(verbatim: reason)
            case .incomplete(let book)?:
                hint(verbatim: String(format: String(localized: "%@: type a chapter number."), book.nameVi))
            case .ambiguousBook(let candidates, let rest)?:
                candidateList(candidates, rest: rest)
            case .reference(let reference)?:
                VerseList(reference: reference, translation: environment.bibleTranslation(code)) { verse in
                    text = "\(verse.bookName) \(verse.chapter):\(verse.verse)"
                }
            }
        }
    }

    private func hint(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Typography.caption)
            .foregroundStyle(Palette.text3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private func hint(verbatim: String) -> some View {
        Text(verbatim: verbatim)
            .font(Typography.caption)
            .foregroundStyle(Palette.text3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private func candidateList(_ candidates: [Book], rest: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, book in
                    LibraryRowView(
                        row: LibraryRow(
                            id: book.osis, leading: .symbol("book"), title: book.nameVi,
                            subtitle: String(localized: "Press Return to choose"), source: nil),
                        isSelected: index == candidateIndex
                    )
                    .onTapGesture { choose(book, rest: rest) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Phím

    private func moveCandidate(_ delta: Int, in result: ParseResult?) -> KeyPress.Result {
        guard case .ambiguousBook(let candidates, _)? = result, !candidates.isEmpty else { return .ignored }
        candidateIndex = min(candidates.count - 1, max(0, candidateIndex + delta))
        return .handled
    }

    private func submit(_ result: ParseResult?, code: String?, modifiers: EventModifiers) -> KeyPress.Result {
        switch result {
        case .ambiguousBook(let candidates, let rest)?:
            guard candidates.indices.contains(candidateIndex) else { return .ignored }
            choose(candidates[candidateIndex], rest: rest)
            return .handled
        case .reference(let reference)?:
            guard let code else { return .ignored }
            let source = LiveSource.scripture(translation: code, reference: reference.canonical)
            if modifiers.contains(.command) && modifiers.contains(.shift) {
                environment.appendToPlan(
                    .scripture(PlanScriptureItem(reference: reference.canonical, translation: code)))
            } else if modifiers.contains(.command) {
                environment.send(.selectItem(source))
                environment.goToFirst()
            } else {
                environment.send(.selectItem(source))
            }
            return .handled
        default:
            return .ignored
        }
    }

    private func choose(_ book: Book, rest: String) {
        let tail = rest.trimmingCharacters(in: .whitespaces)
        text = tail.isEmpty ? book.nameVi + " " : book.nameVi + " " + tail
        candidateIndex = 0
    }
}

/// Câu của chương đang gõ; câu thuộc địa chỉ được tô phiến chọn. Bấm một câu để chọn câu đó.
struct VerseList: View {
    struct Line: Identifiable {
        let verse: Int
        let chapter: Int
        let bookName: String
        let text: String
        let isSelected: Bool

        var id: Int { verse }
    }

    let reference: ScriptureReference
    let translation: BibleTranslation?
    let onPick: (Line) -> Void

    var body: some View {
        let lines = Self.lines(reference: reference, translation: translation)
        if lines.isEmpty {
            Text("No verses found for this reference in the chosen translation.")
                .font(Typography.caption)
                .foregroundStyle(Palette.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(verbatim: "\(line.verse)")
                                    .font(Typography.numberSmall)
                                    .foregroundStyle(Palette.text3)
                                    .frame(width: 22, alignment: .leading)
                                Text(verbatim: line.text)
                                    .font(Typography.control)
                                    .foregroundStyle(Palette.text)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, 14)
                            .padding(.trailing, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(line.isSelected ? Palette.accentSoft : Color.clear)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(line.isSelected ? Palette.accent : Color.clear).frame(width: 2)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(line) }
                            .id(line.verse)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear { scroll(proxy, lines) }
                .onChange(of: reference) { _, _ in scroll(proxy, lines) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, _ lines: [Line]) {
        if let first = lines.first(where: \.isSelected) {
            proxy.scrollTo(first.verse, anchor: .top)
        }
    }

    /// Cả chương của đoạn đầu trong địa chỉ.
    static func lines(reference: ScriptureReference, translation: BibleTranslation?) -> [Line] {
        guard let translation, let first = reference.ranges.first else { return [] }
        let chapter = ScriptureReference(ranges: [.chapters(first.book, first.startChapter, first.startChapter)])
        guard let verses = try? translation.verses(chapter) else { return [] }
        let bookName = BookCatalog.standard.book(osis: first.book)?.nameVi ?? first.book
        return verses.map { verse in
            Line(
                verse: verse.verse, chapter: verse.chapter, bookName: bookName, text: verse.text,
                isSelected: reference.ranges.contains { Self.range($0, contains: verse) })
        }
    }

    /// Câu có thuộc đoạn không (đoạn không có số câu là trọn chương).
    static func range(_ range: VerseRange, contains verse: Verse) -> Bool {
        guard range.book == verse.book else { return false }
        let position = (verse.chapter, verse.verse)
        let start = (range.startChapter, range.startVerse ?? 0)
        let end = (range.endChapter, range.endVerse ?? Int.max)
        return position >= start && position <= end
    }
}

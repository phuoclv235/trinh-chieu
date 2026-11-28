import CoreModel
import Foundation
import LibraryIndex
import Scripture
import VietText

/// Xếp hạng kết quả của Bảng lệnh (đặc tả T1.10 mục "Xếp hạng"). Hàm thuần: không đọc thư viện, không đọc đĩa.
///
/// Ứng dụng phân tích địa chỉ Kinh Thánh, tìm trong `LibraryIndex`, lấy chữ câu đầu, rồi đưa hết vào ``rank``:
/// 1. Địa chỉ đầy đủ: nhóm Kinh Thánh lên đầu, một dòng "Giăng 3:16 (TT1925)" kèm 80 ký tự đầu của câu.
/// 2. Chỉ có tên sách: nhóm Kinh Thánh liệt kê sách ứng viên; chọn thì điền tên sách vào ô.
/// 3. Truy vấn toàn số: bài hát có số thánh ca trùng lên đầu.
/// 4. Còn lại: theo điểm của chỉ mục; lệnh khớp tiền tố tên đã gộp dấu.
/// 5. Ô trống: 5 mục dùng gần đây và 4 lệnh hay dùng.
///
/// Thứ tự nhóm: nhóm khớp mạnh hơn đứng trước (địa chỉ đầy đủ, số thánh ca trùng; rồi tên bắt đầu bằng chữ đã gõ;
/// rồi khớp thường), bằng nhau thì theo thứ tự khai báo của ``PaletteGroup``.
public struct PaletteRanker: Sendable {
    /// Số ký tự đầu của câu Kinh Thánh hiện dưới địa chỉ.
    public static let previewLength = 80
    /// Số dòng tối đa của mỗi nhóm.
    public static let limits: [PaletteGroup: Int] = [
        .recent: PaletteHistory.recentLimit, .scripture: 5, .songs: 8, .presentations: 5, .media: 5, .planItems: 5,
        .commands: 6,
    ]
    /// Số lệnh hay dùng hiện khi ô trống.
    public static let frequentCommandCount = 4

    public let parser: ReferenceParser

    public init(parser: ReferenceParser = ReferenceParser()) {
        self.parser = parser
    }

    /// Độ mạnh của một nhóm, dùng để xếp nhóm.
    enum Strength: Int, Comparable {
        case weak = 1
        /// Tên bắt đầu bằng chữ đã gõ.
        case prefix = 2
        /// Địa chỉ Kinh Thánh đầy đủ, số thánh ca trùng hẳn.
        case exact = 3

        static func < (lhs: Strength, rhs: Strength) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Xếp hạng.
    ///
    /// - Parameters:
    ///   - query: chữ trong ô.
    ///   - scriptureParse: kết quả `ReferenceParser.parse(query)`; `nil` khi không phân tích.
    ///   - scripture: bản dịch đang chọn và chữ câu đầu, cho dòng địa chỉ đầy đủ.
    ///   - hits: kết quả `LibraryIndex` (bộ trình chiếu, media), giữ nguyên thứ tự điểm.
    ///   - presentationKind: loại của bộ trình chiếu theo `id` của kết quả; `nil` (không rõ) coi là bài hát.
    ///   - commands: các lệnh, tên đã dịch.
    ///   - planItems: mục của chương trình buổi nhóm đang mở.
    ///   - recents: mục dùng gần đây, mới nhất trước.
    ///   - commandUsage: số lần dùng theo `PaletteCommandID.rawValue`.
    public func rank(
        query: String,
        scriptureParse: ParseResult?,
        scripture: PaletteScriptureContext? = nil,
        hits: [SearchHit],
        presentationKind: (String) -> PresentationKind? = { _ in nil },
        commands: [PaletteCommand],
        planItems: [PaletteItem],
        recents: [PaletteItem] = [],
        commandUsage: [String: Int] = [:]
    ) -> [PaletteSection] {
        let folded = VietText.fold(query)
        if folded.isEmpty {
            return emptyQuerySections(commands: commands, recents: recents, commandUsage: commandUsage)
        }
        let terms = folded.split(separator: " ").map(String.init)
        let isNumber = folded.allSatisfy { $0.isASCII && $0.isNumber }

        var candidates: [(section: PaletteSection, strength: Strength)] = []
        func add(_ group: PaletteGroup, _ rows: [(PaletteRow, Strength)]) {
            let limited = Array(rows.prefix(Self.limits[group] ?? rows.count))
            guard let strongest = limited.map({ $0.1 }).max() else { return }
            candidates.append((PaletteSection(group: group, rows: limited.map { $0.0 }), strongest))
        }

        if !isNumber {
            add(.scripture, scriptureRows(scriptureParse, query: query, context: scripture))
        }
        let library = hitRows(hits, folded: folded, isNumber: isNumber, presentationKind: presentationKind)
        add(.songs, library.songs)
        add(.presentations, library.presentations)
        add(.media, library.media)
        add(.planItems, planRows(planItems, folded: folded, terms: terms))
        if !isNumber {
            add(.commands, commandRows(commands, folded: folded, terms: terms))
        }

        let order = PaletteGroup.allCases
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.strength != rhs.strength {
                return lhs.strength > rhs.strength
            }
            let left = order.firstIndex(of: lhs.section.group) ?? order.count
            let right = order.firstIndex(of: rhs.section.group) ?? order.count
            return left < right
        }
        return sorted.map { $0.section }
    }

    // MARK: - Ô trống

    private func emptyQuerySections(
        commands: [PaletteCommand], recents: [PaletteItem], commandUsage: [String: Int]
    ) -> [PaletteSection] {
        var sections: [PaletteSection] = []
        let recentRows = recents.prefix(PaletteHistory.recentLimit).map { item in
            PaletteRow(group: .recent, target: item.target, title: item.title, subtitle: item.subtitle)
        }
        if !recentRows.isEmpty {
            sections.append(PaletteSection(group: .recent, rows: Array(recentRows)))
        }
        let available = Dictionary(commands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let frequent = PaletteHistory.frequent(commandUsage, count: PaletteCommandID.allCases.count)
            .compactMap { available[$0] }
            .prefix(Self.frequentCommandCount)
            .map(Self.row(for:))
        if !frequent.isEmpty {
            sections.append(PaletteSection(group: .commands, rows: Array(frequent)))
        }
        return sections
    }

    // MARK: - Kinh Thánh

    private func scriptureRows(
        _ parse: ParseResult?, query: String, context: PaletteScriptureContext?
    ) -> [(PaletteRow, Strength)] {
        switch parse {
        case .reference(let reference)?:
            let row = PaletteRow(
                group: .scripture,
                target: .scripture(translation: context?.translationCode, reference: reference.canonical),
                title: reference.canonical,
                detail: context.map { "(\($0.abbreviation))" },
                subtitle: context?.previewText.flatMap(Self.preview))
            return [(row, .exact)]
        case .incomplete(let book)?:
            var books = [book]
            for candidate in parser.bookCandidates(query, limit: Self.limits[.scripture] ?? 5)
            where candidate != book {
                books.append(candidate)
            }
            return books.map { (Self.bookRow($0, rest: ""), .prefix) }
        case .ambiguousBook(let candidates, let rest)?:
            return candidates.map { (Self.bookRow($0, rest: rest), .prefix) }
        case .invalid?, nil:
            return []
        }
    }

    private static func bookRow(_ book: Book, rest: String) -> PaletteRow {
        let tail = rest.trimmingCharacters(in: .whitespaces)
        let text = tail.isEmpty ? book.nameVi + " " : book.nameVi + " " + tail
        return PaletteRow(group: .scripture, target: .bookCompletion(text: text), title: book.nameVi)
    }

    /// Cắt còn ``previewLength`` ký tự đầu (gộp khoảng trắng), thêm "…" khi bị cắt.
    static func preview(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > previewLength else { return collapsed }
        let cut = collapsed.prefix(previewLength).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    // MARK: - Thư viện

    private struct LibraryRows {
        var songs: [(PaletteRow, Strength)] = []
        var presentations: [(PaletteRow, Strength)] = []
        var media: [(PaletteRow, Strength)] = []
    }

    private func hitRows(
        _ hits: [SearchHit], folded: String, isNumber: Bool, presentationKind: (String) -> PresentationKind?
    ) -> LibraryRows {
        var rows = LibraryRows()
        var seen = Set<String>()
        for hit in hits where seen.insert(hit.kind.rawValue + hit.id).inserted {
            let strength = Self.strength(of: hit, folded: folded, isNumber: isNumber)
            switch hit.kind {
            case .presentation:
                guard let id = UUID(uuidString: hit.id) else { continue }
                let isGeneric = presentationKind(hit.id) == .generic
                let row = PaletteRow(
                    group: isGeneric ? .presentations : .songs, target: .presentation(id: id), title: hit.title,
                    subtitle: hit.subtitle)
                if isGeneric {
                    rows.presentations.append((row, strength))
                } else {
                    rows.songs.append((row, strength))
                }
            case .media:
                let row = PaletteRow(
                    group: .media, target: .media(MediaID(hit.id)), title: hit.title, subtitle: hit.subtitle)
                rows.media.append((row, strength))
            case .theme, .plan, .verse:
                continue
            }
        }
        if isNumber {
            // Số thánh ca trùng hẳn đứng trước, giữ thứ tự của chỉ mục trong từng phần.
            rows.songs = Self.stablePartition(rows.songs) { $0.1 == .exact }
            rows.presentations = Self.stablePartition(rows.presentations) { $0.1 == .exact }
        }
        return rows
    }

    private static func strength(of hit: SearchHit, folded: String, isNumber: Bool) -> Strength {
        if isNumber {
            return hit.score >= LibraryIndex.exactNumberScore ? .exact : .prefix
        }
        return titleStarts(hit.title, with: folded) ? .prefix : .weak
    }

    // MARK: - Chương trình buổi nhóm

    private func planRows(_ items: [PaletteItem], folded: String, terms: [String]) -> [(PaletteRow, Strength)] {
        var prefixRows: [(PaletteRow, Strength)] = []
        var otherRows: [(PaletteRow, Strength)] = []
        for item in items {
            let words = Self.words(item.title) + Self.words(item.subtitle ?? "")
            guard Self.allTermsMatch(terms, words: words) else { continue }
            let row = PaletteRow(group: .planItems, target: item.target, title: item.title, subtitle: item.subtitle)
            if Self.titleStarts(item.title, with: folded) {
                prefixRows.append((row, .prefix))
            } else {
                otherRows.append((row, .weak))
            }
        }
        return prefixRows + otherRows
    }

    // MARK: - Lệnh

    private func commandRows(
        _ commands: [PaletteCommand], folded: String, terms: [String]
    ) -> [(PaletteRow, Strength)] {
        var prefixRows: [(PaletteRow, Strength)] = []
        var otherRows: [(PaletteRow, Strength)] = []
        for command in commands {
            let names = [command.title] + command.keywords
            if names.contains(where: { Self.titleStarts($0, with: folded) }) {
                prefixRows.append((Self.row(for: command), .prefix))
            } else if names.contains(where: { Self.allTermsMatch(terms, words: Self.words($0)) }) {
                otherRows.append((Self.row(for: command), .weak))
            }
        }
        return prefixRows + otherRows
    }

    private static func row(for command: PaletteCommand) -> PaletteRow {
        PaletteRow(group: .commands, target: .command(command.id), title: command.title, shortcut: command.shortcut)
    }

    // MARK: - So khớp

    /// Tên (đã gộp dấu, bỏ dấu câu) bắt đầu bằng truy vấn đã gộp: "Xoá chữ" khớp "xoa c", "xoa chu".
    static func titleStarts(_ title: String, with folded: String) -> Bool {
        let loose = VietText.foldLoose(title)
        let query = VietText.foldLoose(folded)
        return !query.isEmpty && loose.hasPrefix(query)
    }

    /// Mọi từ truy vấn là tiền tố của một từ nào đó trong tên: "chu xoa" khớp "Xoá chữ".
    static func allTermsMatch(_ terms: [String], words: [String]) -> Bool {
        guard !terms.isEmpty else { return false }
        return terms.allSatisfy { term in
            let looseTerm = VietText.foldLoose(term)
            guard !looseTerm.isEmpty else { return true }
            return looseTerm.split(separator: " ").allSatisfy { part in words.contains { $0.hasPrefix(part) } }
        }
    }

    static func words(_ text: String) -> [String] {
        VietText.foldLoose(text).split(separator: " ").map(String.init)
    }

    private static func stablePartition<T>(_ items: [T], first: (T) -> Bool) -> [T] {
        items.filter(first) + items.filter { !first($0) }
    }
}

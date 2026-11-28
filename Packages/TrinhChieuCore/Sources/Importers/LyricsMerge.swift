import CoreModel
import Foundation

/// Hợp nhất lời bài hát dạng văn bản vào bộ trình chiếu đang soạn (ô soạn lời, đặc tả T1.9 mục 4).
///
/// Quy tắc:
/// 1. Đoạn khớp theo nhãn (loại, số, tên tự đặt), theo thứ tự; trang trong đoạn khớp theo vị trí.
/// 2. Trang khớp giữ nguyên mã, phần tử không phải chữ, nền, ghi chú; chỉ thay chữ chính
///    (`Slide.primaryText`: phần tử ô `body`, không có thì phần tử chữ đầu tiên).
/// 3. Trang mới dùng bố cục của trang đầu đoạn (đoạn mới thì `defaultSlide`). Trang và đoạn không còn trong văn bản
///    thì bị xoá.
/// 4. Đoạn bị xoá bị gỡ khỏi mọi thứ tự hát; đoạn mới thêm vào cuối thứ tự hát mặc định. Văn bản có dòng "Thứ tự:"
///    khác thứ tự đang dùng thì thứ tự đang dùng theo dòng đó.
///
/// Văn bản không đổi gì so với `LyricsText.render(presentation)` thì kết quả bằng đúng `presentation`, để trình soạn
/// không tạo bước hoàn tác thừa.
///
/// Trang chỉ có media (không có phần tử chữ) không hiện trong văn bản, nên được giữ nguyên chỗ. Trang có chữ chính
/// rỗng cũng không hiện; nó được giữ, trừ khi cả đoạn chưa có trang nào có chữ (bài mới): khi đó trang rỗng được điền
/// chữ trước khi tạo trang mới.
public enum LyricsMerge {
    /// Phân tích `text` rồi hợp nhất vào `presentation`.
    public static func merge(
        text: String, into presentation: Presentation, defaultSlide: Slide? = nil,
        maxLinesPerSlide: Int = LyricsText.defaultMaxLinesPerSlide
    ) -> Presentation {
        let parsed = LyricsText.parse(text, maxLinesPerSlide: maxLinesPerSlide)
        return merge(parsed, into: presentation, defaultSlide: defaultSlide)
    }

    /// Hợp nhất lời đã phân tích vào `presentation`. `defaultSlide` là bố cục cho trang của đoạn mới (trang mặc định
    /// của mẫu); `nil` là một phần tử chữ ở ô `body`.
    public static func merge(
        _ parsed: ParsedLyrics, into presentation: Presentation, defaultSlide: Slide? = nil
    ) -> Presentation {
        var result = presentation
        applyMetadata(parsed, to: &result)

        var used = Set<Int>()
        var groups: [SlideGroup] = []
        for section in parsed.sections {
            let match = presentation.groups.indices.first { index in
                !used.contains(index) && presentation.groups[index].label == section.label
            }
            if let match {
                used.insert(match)
                groups.append(mergeGroup(presentation.groups[match], texts: section.slides))
            } else {
                let slides = (section.slides.isEmpty ? [""] : section.slides).map { text in
                    var slide = Slide.blank(like: defaultSlide)
                    slide.setPrimaryText(text)
                    return slide
                }
                groups.append(SlideGroup(label: section.label, slides: slides))
            }
        }
        result.groups = groups

        let oldIDs = Set(presentation.groups.map(\.id))
        let newIDs = Set(groups.map(\.id))
        let removed = oldIDs.subtracting(newIDs)
        let added = groups.map(\.id).filter { !oldIDs.contains($0) }
        for index in result.arrangements.indices {
            result.arrangements[index].groupIDs.removeAll { removed.contains($0) }
        }
        if !added.isEmpty, let index = result.defaultArrangementIndex {
            result.arrangements[index].groupIDs.append(contentsOf: added)
        }
        applyExplicitOrder(parsed, sectionGroupIDs: groups.map(\.id), current: presentation, to: &result)
        return result
    }

    // MARK: - Nội bộ

    /// Tiêu đề và thông tin bài hát từ phần đầu văn bản. Chỉ gán khi khác về nghĩa (để bài không đổi gì thì bằng
    /// đúng bản cũ). Tiêu đề trống hoặc thiếu thì giữ tiêu đề cũ.
    private static func applyMetadata(_ parsed: ParsedLyrics, to presentation: inout Presentation) {
        let title = parsed.title.map(LyricsText.oneLine) ?? ""
        if !title.isEmpty, title != LyricsText.oneLine(presentation.title) {
            presentation.title = title
        }
        guard presentation.kind == .song || presentation.song != nil else { return }
        var song = presentation.song ?? SongInfo()
        if (song.number ?? "") != (parsed.number ?? "") { song.number = parsed.number }
        if song.authors.map(LyricsText.oneLine) != parsed.authors { song.authors = parsed.authors }
        if (song.copyright ?? "") != (parsed.copyright ?? "") { song.copyright = parsed.copyright }
        if (song.key ?? "") != (parsed.key ?? "") { song.key = parsed.key }
        if song != presentation.song { presentation.song = song }
    }

    /// Hợp nhất chữ các trang của một đoạn đã khớp nhãn.
    private static func mergeGroup(_ group: SlideGroup, texts: [String]) -> SlideGroup {
        var slides = group.slides
        let texts = texts.isEmpty ? [""] : texts
        var candidates = slides.indices.filter { !LyricsText.slideText(slides[$0]).isEmpty }
        if candidates.isEmpty {
            candidates = slides.indices.filter { slides[$0].primaryTextIndex != nil }
        }
        for (position, index) in candidates.enumerated() where position < texts.count {
            if LyricsText.slideText(slides[index]) != texts[position] {
                slides[index].setPrimaryText(texts[position])
            }
        }
        let template = group.slides.first
        if texts.count > candidates.count {
            let insertAt = (candidates.last.map { $0 + 1 }) ?? slides.count
            let extra = texts[candidates.count...].map { text -> Slide in
                var slide = Slide.blank(like: template)
                slide.setPrimaryText(text)
                return slide
            }
            slides.insert(contentsOf: extra, at: insertAt)
        } else if candidates.count > texts.count {
            let removed = Set(candidates[texts.count...].map { slides[$0].id })
            slides.removeAll { removed.contains($0.id) }
        }
        var merged = group
        if merged.slides != slides { merged.slides = slides }
        return merged
    }

    /// Dòng "Thứ tự:" khác thứ tự đang dùng (so theo nhãn) thì thay thứ tự hát đang dùng.
    private static func applyExplicitOrder(
        _ parsed: ParsedLyrics, sectionGroupIDs: [UUID], current: Presentation, to presentation: inout Presentation
    ) {
        guard parsed.hasExplicitOrder else { return }
        let labels = parsed.order.map { parsed.sections[$0].label }
        guard labels != current.orderedGroups().map(\.label) else { return }
        let order = parsed.order.map { sectionGroupIDs[$0] }
        if let index = presentation.arrangements.firstIndex(where: { $0.id == presentation.activeArrangementID }) {
            presentation.arrangements[index].groupIDs = order
        } else if let index = presentation.defaultArrangementIndex {
            presentation.arrangements[index].groupIDs = order
            presentation.activeArrangementID = presentation.arrangements[index].id
        } else {
            let arrangement = Arrangement(name: Arrangement.defaultName, groupIDs: order)
            presentation.arrangements.append(arrangement)
            presentation.activeArrangementID = arrangement.id
        }
    }
}

/// Chia trang dài theo số dòng của mẫu (nút "Chia trang theo mẫu" của ô soạn lời).
public enum LyricsSplit {
    /// Chia các dòng thành từng trang không quá `maxLines` dòng, ít trang nhất có thể. Ưu tiên tách ở ranh giới cặp
    /// dòng (lời hát thường đi theo cặp) khi việc đó không làm tăng số trang; không được thì chia đều theo dòng. Trang
    /// đầu không ít dòng hơn trang sau.
    public static func pages(_ lines: [String], maxLines: Int) -> [[String]] {
        let count = lines.count
        guard maxLines >= 1, count > maxLines else { return [lines] }
        let pageCount = (count + maxLines - 1) / maxLines
        var sizes: [Int] = []
        let pairs = (count + 1) / 2
        if maxLines >= 2, (pairs + pageCount - 1) / pageCount * 2 <= maxLines {
            let base = pairs / pageCount
            let extra = pairs % pageCount
            var remaining = count
            for page in 0..<pageCount {
                let size = min(remaining, (base + (page < extra ? 1 : 0)) * 2)
                sizes.append(size)
                remaining -= size
            }
        } else {
            let base = count / pageCount
            let extra = count % pageCount
            sizes = (0..<pageCount).map { base + ($0 < extra ? 1 : 0) }
        }
        var result: [[String]] = []
        var start = 0
        for size in sizes where size > 0 {
            result.append(Array(lines[start..<(start + size)]))
            start += size
        }
        return result
    }

    /// Chia mọi trang có chữ chính dài hơn `maxLinesPerSlide` dòng. Trang đầu giữ mã cũ; các trang sau là bản sao
    /// cùng bố cục, mã mới, không ghi chú. Thứ tự hát không đổi vì chỉ tham chiếu đoạn.
    public static func splitLongSlides(_ presentation: Presentation, maxLinesPerSlide: Int) -> Presentation {
        var result = presentation
        for groupIndex in result.groups.indices {
            var slides: [Slide] = []
            for slide in result.groups[groupIndex].slides {
                let lines = LyricsText.cleanLines(slide.primaryText ?? "")
                let pages = pages(lines, maxLines: maxLinesPerSlide)
                guard pages.count > 1 else {
                    slides.append(slide)
                    continue
                }
                for (index, page) in pages.enumerated() {
                    var piece = index == 0 ? slide : slide.copyWithNewIDs()
                    if index > 0 {
                        piece.label = nil
                        piece.notes = ""
                    }
                    piece.setPrimaryText(page.joined(separator: "\n"))
                    slides.append(piece)
                }
            }
            if slides != result.groups[groupIndex].slides {
                result.groups[groupIndex].slides = slides
            }
        }
        return result
    }
}

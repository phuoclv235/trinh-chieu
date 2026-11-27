import CoreModel
import Foundation

/// Khoá ảnh thu nhỏ của một trang: mã trang, băm nội dung (trang và mẫu đang áp), mã mẫu.
struct ThumbnailKey: Hashable, Sendable {
    let slideID: UUID
    let contentHash: Int
    let themeID: UUID?

    init(slide: Slide, theme: Theme) {
        var hasher = Hasher()
        hasher.combine(slide)
        hasher.combine(theme)
        slideID = slide.id
        contentHash = hasher.finalize()
        themeID = theme.id
    }
}

/// Một thẻ trong lưới trang chiếu. Một trang có thể xuất hiện nhiều lần (điệp khúc hát lại), nên thẻ nhận diện bằng
/// vị trí trong chuỗi, không bằng mã trang.
struct SlideCard: Equatable, Sendable, Identifiable {
    /// Vị trí trong `SlideSequence.slides`.
    let index: Int
    let slideID: UUID
    /// Nhãn đoạn ("Câu 1", "Điệp khúc") hoặc nhãn riêng của trang.
    let label: String
    let groupKind: GroupLabelKind?
    /// Màu đoạn đặt riêng trong bộ trình chiếu; `nil` thì theo loại đoạn.
    let groupColor: RGBA?
    /// Chữ thô của trang, hiện khi chưa có ảnh thu nhỏ.
    let text: String
    let enabled: Bool
    let thumbnail: ThumbnailKey

    var id: Int { index }

    /// "01", "02"…
    var number: String {
        String(format: "%02d", index + 1)
    }
}

enum SlideCards {
    /// Thẻ của mọi trang trong chuỗi, theo thứ tự chiếu.
    static func make(_ sequence: SlideSequence, theme: Theme, groupColors: [UUID: RGBA] = [:]) -> [SlideCard] {
        sequence.slides.enumerated().map { index, entry in
            let slide = entry.slide
            let label = entry.groupLabel?.displayName ?? slide.label ?? ""
            return SlideCard(
                index: index,
                slideID: slide.id,
                label: label,
                groupKind: entry.groupLabel?.kind,
                groupColor: entry.groupID.flatMap { groupColors[$0] },
                text: plainText(slide),
                enabled: slide.enabled,
                thumbnail: ThumbnailKey(slide: slide, theme: theme)
            )
        }
    }

    /// Màu đặt riêng của các đoạn trong một bộ trình chiếu.
    static func groupColors(_ presentation: Presentation?) -> [UUID: RGBA] {
        var colors: [UUID: RGBA] = [:]
        for group in presentation?.groups ?? [] {
            if let color = group.color {
                colors[group.id] = color
            }
        }
        return colors
    }

    /// Chữ của các phần tử chữ, mỗi phần tử một dòng.
    static func plainText(_ slide: Slide) -> String {
        var lines: [String] = []
        for element in slide.elements {
            if case .text(let text) = element {
                let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Trang bật đầu tiên ở sau `index` (thẻ "Kế tiếp"); `nil` khi hết.
    static func nextEnabled(after index: Int?, in cards: [SlideCard]) -> Int? {
        guard let index else { return nil }
        return cards.first { $0.index > index && $0.enabled }?.index
    }

    /// Trang bật đầu tiên của chuỗi (phím `Home`, phím sang trang khi chưa có gì trên màn).
    static func firstEnabled(in sequence: SlideSequence) -> Int? {
        sequence.slides.indices.first { sequence.slides[$0].slide.enabled }
    }
}

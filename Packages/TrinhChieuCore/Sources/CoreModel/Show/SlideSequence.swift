import Foundation

/// Chuỗi trang phẳng của một nguồn, theo đúng thứ tự chiếu.
public struct SlideSequence: Sendable, Equatable {
    public var source: LiveSource
    public var title: String
    /// Mẫu đã giải theo ưu tiên: mục chương trình > bộ trình chiếu > mặc định thư viện (`nil`).
    public var themeID: UUID?
    public var slides: [SequencedSlide]

    public init(source: LiveSource, title: String, themeID: UUID? = nil, slides: [SequencedSlide]) {
        self.source = source
        self.title = title
        self.themeID = themeID
        self.slides = slides
    }

    /// Chuỗi phẳng của một bộ trình chiếu theo thứ tự hát `arrangementID` (xem `Presentation.orderedGroups`).
    public init(presentation: Presentation, source: LiveSource, arrangementID: UUID?, themeID: UUID?) {
        var slides: [SequencedSlide] = []
        for group in presentation.orderedGroups(arrangementID: arrangementID) {
            for (index, slide) in group.slides.enumerated() {
                let item = SequencedSlide(
                    slide: slide, groupID: group.id, groupLabel: group.label, indexInGroup: index,
                    presentationID: presentation.id
                )
                slides.append(item)
            }
        }
        self.init(source: source, title: presentation.title, themeID: themeID, slides: slides)
    }

    /// Chuỗi một trang có nền là media `id`, không có chữ.
    public init(media id: MediaID, source: LiveSource, title: String, loop: Bool = false) {
        let slide = Slide(id: id.contentUUID, background: .media(id, loop: loop))
        let item = SequencedSlide(slide: slide, groupID: nil, groupLabel: nil, indexInGroup: 0, presentationID: nil)
        self.init(source: source, title: title, slides: [item])
    }

    /// Chỉ số của trang có `slideID`, `nil` nếu không còn.
    public func index(ofSlide slideID: UUID) -> Int? {
        slides.firstIndex { $0.slide.id == slideID }
    }
}

/// Một trang trong chuỗi, kèm vị trí của nó trong bộ trình chiếu.
public struct SequencedSlide: Sendable, Equatable {
    public var slide: Slide
    public var groupID: UUID?
    public var groupLabel: GroupLabel?
    public var indexInGroup: Int
    public var presentationID: UUID?

    public init(slide: Slide, groupID: UUID?, groupLabel: GroupLabel?, indexInGroup: Int, presentationID: UUID?) {
        self.slide = slide
        self.groupID = groupID
        self.groupLabel = groupLabel
        self.indexInGroup = indexInGroup
        self.presentationID = presentationID
    }
}

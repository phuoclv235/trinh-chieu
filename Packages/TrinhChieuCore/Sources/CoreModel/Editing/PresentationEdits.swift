import Foundation

/// Vị trí của một trang trong bộ trình chiếu: chỉ số đoạn và chỉ số trang trong đoạn.
public struct SlideLocation: Sendable, Hashable {
    public var group: Int
    public var slide: Int

    public init(group: Int, slide: Int) {
        self.group = group
        self.slide = slide
    }
}

/// Thao tác soạn thuần trên bộ trình chiếu (trình soạn T1.9). Mỗi hàm chỉ đổi giá trị; hoàn tác do
/// `DocumentEditor<Presentation>` lo. Mã không tìm thấy thì hàm không làm gì.
extension Presentation {
    // MARK: - Tạo mới

    /// Bộ trình chiếu trống loại `generic`: một đoạn có một trang với phần tử chữ ở ô `title`.
    public static func newGeneric(title: String, now: Date = Date()) -> Presentation {
        let slide = Slide(elements: [.text(TextElement(slot: .title, text: ""))])
        let group = SlideGroup(label: GroupLabel(kind: .custom), slides: [slide])
        return Presentation(kind: .generic, title: title, createdAt: now, modifiedAt: now, groups: [group])
    }

    // MARK: - Tra cứu

    /// Vị trí của trang `slideID`.
    public func location(ofSlide slideID: UUID) -> SlideLocation? {
        for (groupIndex, group) in groups.enumerated() {
            if let slideIndex = group.slides.firstIndex(where: { $0.id == slideID }) {
                return SlideLocation(group: groupIndex, slide: slideIndex)
            }
        }
        return nil
    }

    /// Trang `slideID`.
    public func slide(_ slideID: UUID) -> Slide? {
        location(ofSlide: slideID).map { groups[$0.group].slides[$0.slide] }
    }

    /// Tổng số trang của mọi đoạn.
    public var slideCount: Int {
        groups.reduce(0) { $0 + $1.slides.count }
    }

    /// Thứ tự hát mặc định: thứ tự tên "Mặc định", không có thì thứ tự đầu tiên.
    public var defaultArrangementIndex: Int? {
        arrangements.firstIndex { $0.name == Arrangement.defaultName } ?? (arrangements.isEmpty ? nil : 0)
    }

    // MARK: - Trang

    /// Thêm trang trống ngay sau `slideID` (theo bố cục của trang đầu đoạn). `slideID` là `nil` thì thêm vào cuối
    /// đoạn cuối; bộ trình chiếu chưa có đoạn nào thì tạo một đoạn. Trả mã trang mới.
    @discardableResult public mutating func addSlide(after slideID: UUID?) -> UUID {
        if let slideID, let location = location(ofSlide: slideID) {
            let slide = Slide.blank(like: groups[location.group].slides.first)
            groups[location.group].slides.insert(slide, at: location.slide + 1)
            return slide.id
        }
        guard let last = groups.indices.last else {
            let slide = Slide.blank(like: nil)
            let group = SlideGroup(label: GroupLabel(kind: kind == .song ? .verse : .custom), slides: [slide])
            groups.append(group)
            if let index = defaultArrangementIndex {
                arrangements[index].groupIDs.append(group.id)
            }
            return slide.id
        }
        let slide = Slide.blank(like: groups[last].slides.first)
        groups[last].slides.append(slide)
        return slide.id
    }

    /// Nhân đôi trang, bản sao đặt ngay sau. Trả mã trang mới.
    @discardableResult public mutating func duplicateSlide(_ slideID: UUID) -> UUID? {
        guard let location = location(ofSlide: slideID) else { return nil }
        let copy = groups[location.group].slides[location.slide].copyWithNewIDs()
        groups[location.group].slides.insert(copy, at: location.slide + 1)
        return copy.id
    }

    /// Bật hoặc tắt trang.
    public mutating func setSlideEnabled(_ slideID: UUID, _ enabled: Bool) {
        guard let location = location(ofSlide: slideID) else { return }
        groups[location.group].slides[location.slide].enabled = enabled
    }

    /// Tách trang thành hai tại dòng `line` (đếm từ 0) của chữ chính: các dòng trước ở lại, từ dòng `line` sang
    /// trang mới ngay sau, cùng bố cục. `line` phải nằm giữa (từ 1 tới số dòng trừ 1). Trả mã trang mới.
    @discardableResult public mutating func splitSlide(_ slideID: UUID, atLine line: Int) -> UUID? {
        guard let location = location(ofSlide: slideID) else { return nil }
        let original = groups[location.group].slides[location.slide]
        let lines = (original.primaryText ?? "").components(separatedBy: "\n")
        guard line > 0, line < lines.count else { return nil }
        var head = original
        head.setPrimaryText(lines[..<line].joined(separator: "\n"))
        var tail = original.copyWithNewIDs()
        tail.label = nil
        tail.notes = ""
        tail.setPrimaryText(lines[line...].joined(separator: "\n"))
        groups[location.group].slides[location.slide] = head
        groups[location.group].slides.insert(tail, at: location.slide + 1)
        return tail.id
    }

    /// Dòng tách mặc định của một trang `lineCount` dòng: khoảng giữa, ưu tiên ranh giới cặp dòng, nửa đầu không ít
    /// hơn nửa sau. `nil` khi trang dưới 2 dòng.
    public static func defaultSplitLine(lineCount: Int) -> Int? {
        guard lineCount >= 2 else { return nil }
        let half = (lineCount + 1) / 2
        if half % 2 == 1, half + 1 < lineCount {
            return half + 1
        }
        return half
    }

    /// Gộp trang với trang ngay sau trong cùng đoạn: chữ chính nối bằng xuống dòng, trang sau bị xoá. Trả `false`
    /// khi không có trang sau trong đoạn.
    @discardableResult public mutating func mergeSlideWithNext(_ slideID: UUID) -> Bool {
        guard let location = location(ofSlide: slideID) else { return false }
        let slides = groups[location.group].slides
        guard location.slide + 1 < slides.count else { return false }
        let first = slides[location.slide].primaryText ?? ""
        let second = slides[location.slide + 1].primaryText ?? ""
        let joined = [first, second].filter { !$0.isEmpty }.joined(separator: "\n")
        groups[location.group].slides[location.slide].setPrimaryText(joined)
        groups[location.group].slides.remove(at: location.slide + 1)
        return true
    }

    /// Xoá trang. Trang cuối cùng của đoạn thì xoá luôn đoạn (và gỡ đoạn khỏi mọi thứ tự hát).
    public mutating func deleteSlide(_ slideID: UUID) {
        guard let location = location(ofSlide: slideID) else { return }
        if groups[location.group].slides.count == 1 {
            deleteGroup(groups[location.group].id)
        } else {
            groups[location.group].slides.remove(at: location.slide)
        }
    }

    /// Chuyển trang sang đoạn `groupID` ở vị trí `index` (tính trên danh sách trang của đoạn đích trước khi chuyển).
    /// Đoạn nguồn hết trang thì bị xoá như ``deleteGroup(_:)``.
    public mutating func moveSlide(_ slideID: UUID, toGroup groupID: UUID, at index: Int) {
        guard let from = location(ofSlide: slideID), let target = groups.firstIndex(where: { $0.id == groupID })
        else { return }
        var destination = max(0, min(index, groups[target].slides.count))
        if from.group == target {
            if destination == from.slide || destination == from.slide + 1 { return }
            if destination > from.slide { destination -= 1 }
        }
        let slide = groups[from.group].slides.remove(at: from.slide)
        groups[target].slides.insert(slide, at: destination)
        if groups[from.group].slides.isEmpty {
            deleteGroup(groups[from.group].id)
        }
    }

    // MARK: - Đoạn

    /// Đổi nhãn đoạn.
    public mutating func setGroupLabel(_ groupID: UUID, _ label: GroupLabel) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].label = label
    }

    /// Đổi màu đoạn; `nil` là theo loại đoạn.
    public mutating func setGroupColor(_ groupID: UUID, _ color: RGBA?) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].color = color
    }

    /// Xoá đoạn và gỡ nó khỏi mọi thứ tự hát.
    public mutating func deleteGroup(_ groupID: UUID) {
        groups.removeAll { $0.id == groupID }
        for index in arrangements.indices {
            arrangements[index].groupIDs.removeAll { $0 == groupID }
        }
    }

    /// Đổi thứ tự gốc: đưa đoạn tới vị trí `index` (tính trên danh sách trước khi chuyển).
    public mutating func moveGroup(_ groupID: UUID, to index: Int) {
        guard let from = groups.firstIndex(where: { $0.id == groupID }) else { return }
        var destination = max(0, min(index, groups.count))
        if destination == from || destination == from + 1 { return }
        if destination > from { destination -= 1 }
        let group = groups.remove(at: from)
        groups.insert(group, at: destination)
    }

    // MARK: - Thứ tự hát

    /// Tạo thứ tự hát mới, chép từ thứ tự đang dùng (hoặc thứ tự gốc), rồi chọn nó. Trả mã mới.
    @discardableResult public mutating func addArrangement(name: String) -> UUID {
        let arrangement = Arrangement(name: name, groupIDs: orderedGroups().map(\.id))
        arrangements.append(arrangement)
        activeArrangementID = arrangement.id
        return arrangement.id
    }

    /// Đổi tên thứ tự hát. Tên rỗng thì bỏ qua.
    public mutating func renameArrangement(_ arrangementID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = arrangements.firstIndex(where: { $0.id == arrangementID }) else { return }
        arrangements[index].name = trimmed
    }

    /// Xoá thứ tự hát. Đang chọn thì chuyển sang thứ tự đầu tiên còn lại.
    public mutating func deleteArrangement(_ arrangementID: UUID) {
        arrangements.removeAll { $0.id == arrangementID }
        if activeArrangementID == arrangementID {
            activeArrangementID = arrangements.first?.id
        }
    }

    /// Chọn thứ tự hát đang dùng.
    public mutating func setActiveArrangement(_ arrangementID: UUID) {
        guard arrangements.contains(where: { $0.id == arrangementID }) else { return }
        activeArrangementID = arrangementID
    }

    /// Chỉ số thứ tự hát để sửa: thứ tự đang chọn; chưa có thứ tự nào thì tạo "Mặc định" theo thứ tự gốc.
    private mutating func editableArrangementIndex() -> Int {
        if let index = arrangements.firstIndex(where: { $0.id == activeArrangementID }) {
            return index
        }
        if arrangements.isEmpty {
            let arrangement = Arrangement(name: Arrangement.defaultName, groupIDs: groups.map(\.id))
            arrangements.append(arrangement)
            activeArrangementID = arrangement.id
            return 0
        }
        activeArrangementID = arrangements[0].id
        return 0
    }

    /// Thêm đoạn vào cuối thứ tự hát đang dùng (một đoạn được thêm nhiều lần).
    public mutating func appendToActiveArrangement(_ groupID: UUID) {
        guard groups.contains(where: { $0.id == groupID }) else { return }
        let index = editableArrangementIndex()
        arrangements[index].groupIDs.append(groupID)
    }

    /// Gỡ lần xuất hiện thứ `position` khỏi thứ tự hát đang dùng.
    public mutating func removeFromActiveArrangement(at position: Int) {
        let index = editableArrangementIndex()
        guard arrangements[index].groupIDs.indices.contains(position) else { return }
        arrangements[index].groupIDs.remove(at: position)
    }

    /// Chuyển lần xuất hiện thứ `from` tới vị trí `to` (tính trên danh sách trước khi chuyển) trong thứ tự hát đang
    /// dùng.
    public mutating func moveInActiveArrangement(from: Int, to: Int) {
        let index = editableArrangementIndex()
        var ids = arrangements[index].groupIDs
        guard ids.indices.contains(from) else { return }
        var destination = max(0, min(to, ids.count))
        if destination == from || destination == from + 1 { return }
        if destination > from { destination -= 1 }
        let id = ids.remove(at: from)
        ids.insert(id, at: destination)
        arrangements[index].groupIDs = ids
    }
}

extension Arrangement {
    /// Tên thứ tự hát tạo sẵn cho mỗi bài hát.
    public static let defaultName = "Mặc định"
}

import CoreModel
import Foundation
import Testing

@testable import TrinhChieu

@Suite("Trình soạn")
struct EditorTests {
    @Test("Nội dung kéo thả đọc lại đúng loại và mã")
    func dragPayloadRoundTrip() {
        let id = UUID()
        #expect(DragPayload(DragPayload.slide(id).string) == .slide(id))
        #expect(DragPayload(DragPayload.group(id).string) == .group(id))
        #expect(DragPayload("slide:không-phải-mã") == nil)
        #expect(DragPayload("ảnh:\(id.uuidString)") == nil)
    }

    @Test("Nguồn nội dung của trình soạn trải phẳng mọi đoạn theo thứ tự gốc")
    @MainActor func editorProviderFlattensGroups() {
        var song = Presentation.newSong(title: "Thử")
        let chorus = SlideGroup(label: GroupLabel(kind: .chorus), slides: [Slide()])
        song.groups.append(chorus)
        // Thứ tự hát chỉ có câu 1: trình soạn vẫn thấy cả điệp khúc.
        let provider = EditorContentProvider(base: InMemoryContentProvider(presentations: [song]), presentation: song)
        #expect(provider.sequence.slides.count == 2)
        let lookedUp = provider.sequence(for: .presentation(id: song.id, arrangementID: song.activeArrangementID))
        #expect(lookedUp?.slides.map(\.slide.id) == song.groups.flatMap { $0.slides.map(\.id) })
    }
}

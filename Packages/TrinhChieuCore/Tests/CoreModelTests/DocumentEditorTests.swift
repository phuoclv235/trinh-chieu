import Foundation
import Testing

@testable import CoreModel

/// Đồng hồ giả cho trình soạn.
@MainActor private final class EditorClock {
    var now = Date(timeIntervalSince1970: 1_000)

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor @Suite("DocumentEditor: hoàn tác và làm lại")
struct DocumentEditorTests {
    private func makeEditor(_ text: String = "") -> (DocumentEditor<String>, EditorClock) {
        let clock = EditorClock()
        let editor = DocumentEditor(document: text, now: { clock.now })
        return (editor, clock)
    }

    @Test("Áp thay đổi rồi hoàn tác, làm lại")
    func applyUndoRedo() {
        let (editor, _) = makeEditor("a")
        var changes: [String] = []
        editor.onChange = { changes.append($0) }
        #expect(!editor.canUndo)
        editor.apply({ $0 += "b" }, actionName: "Thêm chữ")
        #expect(editor.document == "ab")
        #expect(editor.canUndo)
        #expect(editor.undoActionName == "Thêm chữ")
        editor.undo()
        #expect(editor.document == "a")
        #expect(editor.canRedo)
        #expect(editor.redoActionName == "Thêm chữ")
        editor.redo()
        #expect(editor.document == "ab")
        #expect(!editor.canRedo)
        #expect(changes == ["ab", "a", "ab"])
    }

    @Test("Hai lần apply cùng coalescingKey trong vòng 1 giây gộp thành một bước")
    func coalescesWithinOneSecond() {
        let (editor, clock) = makeEditor()
        editor.apply({ $0 += "x" }, actionName: "Gõ chữ", coalescingKey: "typing")
        clock.advance(by: 0.5)
        editor.apply({ $0 += "y" }, actionName: "Gõ chữ", coalescingKey: "typing")
        clock.advance(by: 0.9)
        editor.apply({ $0 += "z" }, actionName: "Gõ chữ", coalescingKey: "typing")
        #expect(editor.document == "xyz")
        editor.undo()
        #expect(editor.document == "")
        #expect(!editor.canUndo)
    }

    @Test("Cách nhau từ 1 giây trở lên thì thành bước riêng")
    func doesNotCoalesceAfterOneSecond() {
        let (editor, clock) = makeEditor()
        editor.apply({ $0 += "x" }, actionName: "Gõ chữ", coalescingKey: "typing")
        clock.advance(by: 1)
        editor.apply({ $0 += "y" }, actionName: "Gõ chữ", coalescingKey: "typing")
        editor.undo()
        #expect(editor.document == "x")
    }

    @Test("Khác coalescingKey hoặc không có khoá thì không gộp")
    func differentKeysDoNotCoalesce() {
        let (editor, _) = makeEditor()
        editor.apply({ $0 += "x" }, actionName: "Gõ chữ", coalescingKey: "a")
        editor.apply({ $0 += "y" }, actionName: "Gõ chữ", coalescingKey: "b")
        editor.apply({ $0 += "z" }, actionName: "Dán")
        editor.apply({ $0 += "w" }, actionName: "Dán")
        editor.undo()
        #expect(editor.document == "xyz")
        editor.undo()
        editor.undo()
        #expect(editor.document == "x")
    }

    @Test("Sau hoàn tác, gõ tiếp không gộp vào bước cũ và xoá làm lại")
    func undoBreaksCoalescing() {
        let (editor, _) = makeEditor()
        editor.apply({ $0 += "x" }, actionName: "Gõ chữ", coalescingKey: "typing")
        editor.apply({ $0 += "y" }, actionName: "Gõ chữ", coalescingKey: "typing")
        editor.undo()
        #expect(editor.document == "")
        editor.apply({ $0 += "q" }, actionName: "Gõ chữ", coalescingKey: "typing")
        #expect(!editor.canRedo)
        editor.redo()
        #expect(editor.document == "q")
        editor.undo()
        #expect(editor.document == "")
    }

    @Test("Thay đổi không làm tài liệu khác đi thì không tạo bước")
    func noOpChangeIsIgnored() {
        let (editor, _) = makeEditor("a")
        editor.apply({ $0 += "" }, actionName: "Không gì")
        #expect(!editor.canUndo)
        editor.undo()
        editor.redo()
        #expect(editor.document == "a")
    }

    @Test("Giữ tối đa 200 bước")
    func keepsAtMostTwoHundredSteps() {
        let (editor, _) = makeEditor()
        for index in 0..<250 {
            editor.apply({ $0 = "\(index)" }, actionName: "Bước \(index)")
        }
        var steps = 0
        while editor.canUndo {
            editor.undo()
            steps += 1
        }
        #expect(steps == DocumentEditor<String>.maxUndoSteps)
        #expect(editor.document == "49")
    }

    @Test("Soạn được bộ trình chiếu")
    func editsPresentation() {
        let editor = DocumentEditor(document: Presentation.newSong(title: "A", now: Date(timeIntervalSince1970: 0)))
        editor.apply({ $0.title = "B" }, actionName: "Đổi tên")
        #expect(editor.document.title == "B")
        editor.undo()
        #expect(editor.document.title == "A")
    }
}

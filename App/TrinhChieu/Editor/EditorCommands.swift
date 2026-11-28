import CoreModel
import Foundation
import Importers
import LibraryStore
import MediaImport
import Observation
import UniformTypeIdentifiers

/// Bộ trình chiếu đang mở ở chế độ Soạn thảo: bản soạn có hoàn tác, trang đang chọn, giờ lưu gần nhất.
@MainActor @Observable final class PresentationEditing {
    /// Bản soạn; `nil` khi chưa mở bộ nào.
    fileprivate(set) var editor: DocumentEditor<Presentation>?
    /// Trang đang chọn ở danh sách trái (và trên khung vẽ). Đổi trang thì bỏ chọn phần tử.
    var selectedSlideID: UUID? {
        didSet {
            if selectedSlideID != oldValue { selectedElementID = nil }
        }
    }
    /// Phần tử đang chọn trên khung vẽ.
    var selectedElementID: UUID?
    /// Thẻ đang mở ở bảng thuộc tính bên phải.
    var inspectorTab: InspectorTab = .presentation
    /// Giờ lưu gần nhất, hiện "Đã lưu 9:41" trên thanh công cụ.
    fileprivate(set) var savedAt: Date?
    /// Tăng khi cần đưa con trỏ vào ô soạn lời (bài hát mới).
    fileprivate(set) var lyricsFocusRequest = 0
    /// Tăng khi bộ trình chiếu đổi không do gõ trong ô soạn lời (hoàn tác, thao tác ở danh sách): ô lời nạp lại văn
    /// bản kể cả khi đang có con trỏ.
    fileprivate(set) var lyricsRevision = 0
    /// Báo cáo của lần nhập gần nhất, hiện trong bảng kết quả.
    var importReport: EditorImportReport?
    /// Đang nhập tệp.
    fileprivate(set) var isImporting = false

    /// Bản thư viện ngay sau lần lưu gần nhất của trình soạn: thư viện khác bản này là đã đổi từ ngoài.
    @ObservationIgnored fileprivate var lastSaved: Presentation?
    /// Văn bản lời đang gõ, chưa hợp nhất (chờ dừng gõ 400 ms).
    @ObservationIgnored fileprivate var pendingLyrics: String?
    @ObservationIgnored fileprivate var lyricsTask: Task<Void, Never>?

    var presentation: Presentation? { editor?.document }

    /// Đóng thư viện: bỏ bản soạn cùng lịch sử hoàn tác.
    func reset() {
        lyricsTask?.cancel()
        lyricsTask = nil
        pendingLyrics = nil
        editor = nil
        selectedSlideID = nil
        selectedElementID = nil
        savedAt = nil
        lastSaved = nil
        importReport = nil
    }
}

/// Các thẻ của bảng thuộc tính (mẫu `design/editor.html`).
enum InspectorTab: Hashable, CaseIterable {
    case text
    case layout
    case background
    case presentation
}

/// Kết quả nhập theo tệp, cho bảng báo cáo.
struct EditorImportReport: Identifiable, Equatable {
    enum Status: Equatable {
        case success
        case warning
        case failure
    }

    struct Row: Identifiable, Equatable {
        let id = UUID()
        let filename: String
        let status: Status
        let message: String
    }

    let id = UUID()
    let rows: [Row]

    var successCount: Int { rows.filter { $0.status != .failure }.count }
}

/// Thao tác của chế độ Soạn thảo. Mọi sửa đổi đi qua `DocumentEditor<Presentation>` (một bước hoàn tác mỗi thao tác)
/// và lưu bằng `LibraryStore.save` (thư viện ghi đĩa sau 1 giây). Bộ đang lên màn đổi theo qua `contentDidChange`.
extension AppEnvironment {
    var editingPresentation: Presentation? { presentationEditing.presentation }

    /// Mẫu đang áp cho bộ đang soạn.
    var editingTheme: Theme? {
        guard let presentation = editingPresentation else { return nil }
        return content?.theme(presentation.themeID)
    }

    // MARK: - Mở, tạo

    /// Mở bộ trình chiếu trong trình soạn (hoặc đóng khi `nil`). Mở lại đúng bộ đang soạn thì giữ lịch sử hoàn tác.
    func openEditor(_ id: UUID?) {
        flushLyrics()
        guard let id, let presentation = library?.presentations[id] else {
            presentationEditing.editor = nil
            presentationEditing.selectedSlideID = nil
            presentationEditing.lastSaved = nil
            editingPresentationID = nil
            return
        }
        editingPresentationID = id
        if presentationEditing.editor?.document.id == id {
            return
        }
        attachEditor(presentation)
        presentationEditing.selectedSlideID = presentation.groups.first?.slides.first?.id
    }

    private func attachEditor(_ presentation: Presentation) {
        let editor = DocumentEditor(document: presentation)
        editor.onChange = { [weak self] updated in self?.saveEditing(updated) }
        presentationEditing.editor = editor
        presentationEditing.lastSaved = presentation
        presentationEditing.lyricsRevision &+= 1
    }

    private func saveEditing(_ presentation: Presentation) {
        guard let library else { return }
        library.save(presentation)
        presentationEditing.lastSaved = library.presentations[presentation.id]
        presentationEditing.savedAt = Date()
    }

    /// "Bài hát mới" (`⌘N`): lưu bài trống rồi mở, đưa con trỏ vào ô soạn lời.
    func createSong() {
        guard let library else { return }
        let song = Presentation.newSong(title: String(localized: "New song"))
        library.save(song)
        openEditor(song.id)
        presentationEditing.lyricsFocusRequest &+= 1
    }

    /// "Bộ trình chiếu trống": một trang có ô tiêu đề.
    func createBlankPresentation() {
        guard let library else { return }
        let presentation = Presentation.newGeneric(title: String(localized: "Untitled presentation"))
        library.save(presentation)
        openEditor(presentation.id)
    }

    /// Thư viện đổi: bộ đang soạn bị sửa từ ngoài (đồng bộ, sửa tay) thì lấy bản mới, bị xoá thì đóng trình soạn.
    func syncEditingPresentation() {
        guard let editor = presentationEditing.editor else { return }
        guard let stored = library?.presentations[editor.document.id] else {
            openEditor(nil)
            return
        }
        if stored != presentationEditing.lastSaved {
            attachEditor(stored)
            if let selected = presentationEditing.selectedSlideID, stored.location(ofSlide: selected) == nil {
                presentationEditing.selectedSlideID = stored.groups.first?.slides.first?.id
            }
        }
    }

    // MARK: - Sửa

    /// Áp một thay đổi thành một bước hoàn tác. Lời đang gõ dở được hợp nhất trước.
    func editPresentation(
        _ actionName: String, coalescingKey: String? = nil, _ change: (inout Presentation) -> Void
    ) {
        flushLyrics()
        presentationEditing.editor?.apply(change, actionName: actionName, coalescingKey: coalescingKey)
        presentationEditing.lyricsRevision &+= 1
        keepSelectionValid()
    }

    func undoEditing() {
        // Đang sửa chữ tại chỗ trên khung vẽ: ⌘Z (phím tắt của nút Hoàn tác) hoàn tác chữ vừa gõ trong ô gõ.
        if let undo = EditorCanvasView.activeTextUndoManager {
            undo.undo()
            return
        }
        flushLyrics()
        presentationEditing.editor?.undo()
        presentationEditing.lyricsRevision &+= 1
        keepSelectionValid()
    }

    func redoEditing() {
        if let undo = EditorCanvasView.activeTextUndoManager {
            undo.redo()
            return
        }
        flushLyrics()
        presentationEditing.editor?.redo()
        presentationEditing.lyricsRevision &+= 1
        keepSelectionValid()
    }

    private func keepSelectionValid() {
        guard let presentation = editingPresentation else { return }
        if let selected = presentationEditing.selectedSlideID, presentation.location(ofSlide: selected) != nil {
            return
        }
        presentationEditing.selectedSlideID = presentation.groups.first?.slides.first?.id
    }

    // MARK: - Ô soạn lời

    /// Văn bản lời của bộ đang soạn (`LyricsText.render`).
    var editingLyricsText: String {
        editingPresentation.map(LyricsText.render) ?? ""
    }

    /// Bạn gõ trong ô soạn lời: dừng gõ 400 ms thì hợp nhất vào bộ trình chiếu.
    func lyricsDidChange(_ text: String) {
        presentationEditing.pendingLyrics = text
        presentationEditing.lyricsTask?.cancel()
        presentationEditing.lyricsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushLyrics()
        }
    }

    /// Hợp nhất ngay văn bản lời đang chờ (một bước hoàn tác "Sửa lời").
    func flushLyrics() {
        presentationEditing.lyricsTask?.cancel()
        presentationEditing.lyricsTask = nil
        guard let text = presentationEditing.pendingLyrics, let editor = presentationEditing.editor else { return }
        presentationEditing.pendingLyrics = nil
        let maxLines = editingTheme?.lyrics.maxLinesPerSlide ?? LyricsText.defaultMaxLinesPerSlide
        let merged = LyricsMerge.merge(text: text, into: editor.document, maxLinesPerSlide: maxLines)
        editor.apply({ $0 = merged }, actionName: String(localized: "Edit lyrics"))
        keepSelectionValid()
    }

    /// "Chia trang theo mẫu": chia trang dài hơn số dòng tối đa của mẫu.
    func splitSlidesByTheme() {
        let maxLines = editingTheme?.lyrics.maxLinesPerSlide ?? LyricsText.defaultMaxLinesPerSlide
        editPresentation(String(localized: "Split slides")) { presentation in
            presentation = LyricsSplit.splitLongSlides(presentation, maxLinesPerSlide: maxLines)
        }
    }

    // MARK: - Lên màn

    /// "Lên màn" (`⌘↵`): đưa trang đang chọn của bộ đang soạn lên màn theo thứ tự hát đang dùng.
    func goLiveFromEditor() {
        flushLyrics()
        guard let presentation = editingPresentation else { return }
        let source = LiveSource.presentation(id: presentation.id, arrangementID: presentation.activeArrangementID)
        guard let sequence = sequence(for: source), !sequence.slides.isEmpty else { return }
        let index = presentationEditing.selectedSlideID.flatMap { sequence.index(ofSlide: $0) } ?? 0
        send(.selectItem(source))
        send(.goLive(source, slideIndex: index))
    }

    // MARK: - Nhập

    /// Loại tệp nhận khi nhập (`⌘I`, kéo thả): văn bản lời, OpenLyrics, PDF.
    static let importableTypes: [UTType] = [.plainText, .text, .xml, .pdf]

    /// Nhập nhiều tệp: PDF qua `PDFImporter`, còn lại qua `ImportRegistry`. Bộ đầu tiên nhập được mở trong trình soạn;
    /// kết quả từng tệp hiện trong bảng báo cáo.
    func importIntoEditor(_ urls: [URL]) async {
        guard let library, !urls.isEmpty, !presentationEditing.isImporting else { return }
        presentationEditing.isImporting = true
        defer { presentationEditing.isImporting = false }
        var rows: [EditorImportReport.Row] = []
        var firstID: UUID?
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let others = urls.filter { $0.pathExtension.lowercased() != "pdf" }
        if !others.isEmpty {
            let report = await ImportRegistry.standard.importFiles(at: others)
            for file in report.files {
                switch file.result {
                case .success(let outcome):
                    for presentation in outcome.presentations {
                        library.save(presentation)
                        firstID = firstID ?? presentation.id
                    }
                    let warnings = outcome.warnings.map(\.description)
                    let titles = outcome.presentations.map(\.title).joined(separator: ", ")
                    rows.append(
                        EditorImportReport.Row(
                            filename: file.filename, status: warnings.isEmpty ? .success : .warning,
                            message: ([titles] + warnings).filter { !$0.isEmpty }.joined(separator: "\n")))
                case .failure(let error):
                    let row = EditorImportReport.Row(filename: file.filename, status: .failure, message: error.message)
                    rows.append(row)
                }
            }
        }
        let canvas = editingTheme?.canvasSize ?? content?.theme(nil).canvasSize ?? .fullHD
        let work = FileManager.default.temporaryDirectory
        for url in pdfs {
            do {
                let result = try await PDFImporter(canvasSize: canvas).importPDF(at: url, workDirectory: work) { page in
                    try await library.importMedia(from: page)
                }
                library.save(result.presentation)
                firstID = firstID ?? result.presentation.id
                let message = String(format: String(localized: "%lld pages"), result.presentation.slideCount)
                rows.append(EditorImportReport.Row(filename: url.lastPathComponent, status: .success, message: message))
            } catch {
                let message = (error as? PDFImportError)?.message ?? error.localizedDescription
                rows.append(EditorImportReport.Row(filename: url.lastPathComponent, status: .failure, message: message))
            }
        }
        if let firstID {
            openEditor(firstID)
        }
        presentationEditing.importReport = EditorImportReport(rows: rows)
    }
}

import CoreModel
import Foundation
import LibraryIndex

extension LibraryStore {
    /// Đổi mẫu mặc định của thư viện (Cài đặt > Thư viện). Ghi `library.json` ngay, rồi phát thay đổi có mã thư
    /// viện, mẫu cũ và mẫu mới, để đệm nội dung dựa vào mẫu mặc định được dựng lại.
    public func setDefaultThemes(presentation: UUID?, scripture: UUID?) async throws {
        var updated = info
        updated.defaultThemeID = presentation
        updated.defaultScriptureThemeID = scripture
        guard updated != info else { return }
        let previous = info
        try await writeDataNow(try DocumentCoding.encode(updated), to: LibraryLayout.libraryFileName)
        info = updated
        let ids = [
            updated.id, previous.defaultThemeID, previous.defaultScriptureThemeID, presentation, scripture,
        ]
        emit(LibraryChange(reason: .saved, documentIDs: Set(ids.compactMap { $0 })))
    }

    /// Dựng lại chỉ mục tìm kiếm của thư viện từ đầu (bộ trình chiếu, mẫu, chương trình, media). Câu Kinh Thánh
    /// không đụng tới. Tìm kiếm vẫn chạy trong lúc dựng, kết quả đủ dần (``isIndexing``).
    public func rebuildIndex() {
        enqueueIndex { index in
            for kind in [IndexKind.presentation, .theme, .plan, .media] {
                try await index.removeAll(kind: kind)
            }
        }
        startIndexSynchronization()
    }
}

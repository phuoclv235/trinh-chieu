import CoreModel
import Foundation

/// Nhóm kết quả của Bảng lệnh (đặc tả T1.10). Thứ tự khai báo là thứ tự mặc định khi các nhóm khớp ngang nhau.
public enum PaletteGroup: String, Sendable, Hashable, CaseIterable {
    /// Mục dùng gần đây, chỉ hiện khi ô trống.
    case recent
    case scripture
    case songs
    /// Bộ trình chiếu không phải bài hát.
    case presentations
    case media
    /// Mục trong chương trình buổi nhóm đang mở.
    case planItems
    case commands
}

/// Lệnh chạy được từ Bảng lệnh. Giá trị thô ghi vào cài đặt (đếm số lần dùng), không đổi tên.
public enum PaletteCommandID: String, Sendable, Hashable, Codable, CaseIterable {
    case clearAll
    case clearText
    case clearBackground
    case toggleRehearsal
    case toggleFreeze
    case liveMode
    case editorMode
    case newSong
    case importFiles
    case openSettings
    case identifyScreens

    /// Bốn lệnh hay dùng khi chưa có số đếm: xoá màn là việc gấp nhất giữa buổi nhóm.
    public static let defaultFrequent: [PaletteCommandID] = [.clearAll, .clearText, .clearBackground, .toggleRehearsal]
}

/// Đích của một dòng: Bảng lệnh làm gì khi bạn bấm `Enter` hoặc `⌘Enter`.
public enum PaletteTarget: Sendable, Hashable, Codable {
    /// Địa chỉ Kinh Thánh đầy đủ. `translation` là mã bản dịch; `nil` khi chưa có bản dịch nào.
    case scripture(translation: String?, reference: String)
    /// Mới có tên sách: chọn thì điền `text` vào ô và chờ gõ tiếp.
    case bookCompletion(text: String)
    case presentation(id: UUID)
    case media(MediaID)
    case planItem(id: UUID)
    case command(PaletteCommandID)

    /// Có hành động phụ (`⌘Enter`) không.
    public var hasSecondaryAction: Bool {
        switch self {
        case .scripture(let translation, _): return translation != nil
        case .presentation, .media, .planItem: return true
        case .bookCompletion, .command: return false
        }
    }

    /// Đích này được ghi vào danh sách dùng gần đây không (lệnh được đếm riêng, gợi ý tên sách thì không ghi).
    public var isRecordable: Bool {
        switch self {
        case .scripture(let translation, _): return translation != nil
        case .presentation, .media, .planItem: return true
        case .bookCompletion, .command: return false
        }
    }

    /// Khoá ổn định để so trùng và làm `id` của dòng.
    public var key: String {
        switch self {
        case .scripture(let translation, let reference): return "scripture:\(translation ?? "-"):\(reference)"
        case .bookCompletion(let text): return "book:\(text)"
        case .presentation(let id): return "presentation:\(id.uuidString)"
        case .media(let id): return "media:\(id.rawValue)"
        case .planItem(let id): return "plan:\(id.uuidString)"
        case .command(let id): return "command:\(id.rawValue)"
        }
    }
}

/// Một lệnh đưa vào xếp hạng. Tên đã dịch sẵn ở ứng dụng; bộ xếp hạng tự gộp dấu để tìm không dấu.
public struct PaletteCommand: Sendable, Hashable {
    public var id: PaletteCommandID
    public var title: String
    /// Tên khác để tìm (ví dụ "xoa man", "clear"), không hiện ra.
    public var keywords: [String]
    /// Phím tắt hiện ở bên phải, ví dụ "F2".
    public var shortcut: String?

    public init(id: PaletteCommandID, title: String, keywords: [String] = [], shortcut: String? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.shortcut = shortcut
    }
}

/// Mục có sẵn không qua chỉ mục: mục chương trình buổi nhóm, mục dùng gần đây (lưu trong cài đặt).
public struct PaletteItem: Sendable, Hashable, Codable {
    public var target: PaletteTarget
    public var title: String
    public var subtitle: String?

    public init(target: PaletteTarget, title: String, subtitle: String? = nil) {
        self.target = target
        self.title = title
        self.subtitle = subtitle
    }
}

/// Ngữ cảnh Kinh Thánh cho dòng địa chỉ đầy đủ: bản dịch đang chọn và chữ của câu đầu.
public struct PaletteScriptureContext: Sendable, Hashable {
    public var translationCode: String
    /// "TT1925".
    public var abbreviation: String
    /// Chữ của đoạn (câu đầu trở đi); bộ xếp hạng cắt còn ``PaletteRanker/previewLength`` ký tự.
    public var previewText: String?

    public init(translationCode: String, abbreviation: String, previewText: String?) {
        self.translationCode = translationCode
        self.abbreviation = abbreviation
        self.previewText = previewText
    }
}

/// Một dòng kết quả.
public struct PaletteRow: Sendable, Hashable, Identifiable {
    public var group: PaletteGroup
    public var target: PaletteTarget
    public var title: String
    /// Chữ phụ cạnh tên, nhạt hơn: "(TT1925)".
    public var detail: String?
    /// Dòng dưới: 80 ký tự đầu của câu, tác giả, phụ đề mục.
    public var subtitle: String?
    /// Phím tắt của lệnh.
    public var shortcut: String?

    public var id: String { group.rawValue + "|" + target.key }

    public init(
        group: PaletteGroup, target: PaletteTarget, title: String, detail: String? = nil, subtitle: String? = nil,
        shortcut: String? = nil
    ) {
        self.group = group
        self.target = target
        self.title = title
        self.detail = detail
        self.subtitle = subtitle
        self.shortcut = shortcut
    }
}

/// Một nhóm kết quả.
public struct PaletteSection: Sendable, Hashable, Identifiable {
    public var group: PaletteGroup
    public var rows: [PaletteRow]

    public var id: PaletteGroup { group }

    public init(group: PaletteGroup, rows: [PaletteRow]) {
        self.group = group
        self.rows = rows
    }
}

/// Danh sách dùng gần đây và số lần dùng lệnh (lưu trong cài đặt ứng dụng).
public enum PaletteHistory {
    /// Số mục gần đây giữ lại.
    public static let recentLimit = 5

    /// Đưa `item` lên đầu, bỏ bản trùng đích, giữ tối đa ``recentLimit``. Đích không ghi được thì giữ nguyên.
    public static func recording(_ item: PaletteItem, in recents: [PaletteItem]) -> [PaletteItem] {
        guard item.target.isRecordable else { return recents }
        var result = [item]
        for existing in recents where existing.target != item.target {
            result.append(existing)
        }
        return Array(result.prefix(recentLimit))
    }

    /// Tăng số lần dùng của một lệnh.
    public static func counting(_ id: PaletteCommandID, in usage: [String: Int]) -> [String: Int] {
        var usage = usage
        usage[id.rawValue, default: 0] += 1
        return usage
    }

    /// `count` lệnh hay dùng nhất: theo số lần dùng giảm dần, bằng nhau thì theo ``PaletteCommandID/defaultFrequent``
    /// rồi theo thứ tự khai báo.
    public static func frequent(_ usage: [String: Int], count: Int = 4) -> [PaletteCommandID] {
        let all = PaletteCommandID.allCases
        func baseOrder(_ id: PaletteCommandID) -> Int {
            if let index = PaletteCommandID.defaultFrequent.firstIndex(of: id) { return index }
            return PaletteCommandID.defaultFrequent.count + (all.firstIndex(of: id) ?? all.count)
        }
        let sorted = all.sorted { lhs, rhs in
            let left = usage[lhs.rawValue] ?? 0
            let right = usage[rhs.rawValue] ?? 0
            if left != right { return left > right }
            return baseOrder(lhs) < baseOrder(rhs)
        }
        return Array(sorted.prefix(max(0, count)))
    }
}

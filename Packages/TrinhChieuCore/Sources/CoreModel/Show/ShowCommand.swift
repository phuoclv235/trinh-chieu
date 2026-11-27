import Foundation

// Tệp nguy hiểm: tên case là hợp đồng cho remote và nhật ký. Đổi tên một case là thay đổi phá vỡ.

/// Nguồn nội dung có thể lên màn.
public enum LiveSource: Sendable, Hashable, Codable {
    case planItem(planID: UUID, itemID: UUID)
    case presentation(id: UUID, arrangementID: UUID?)
    /// `reference` là chuỗi địa chỉ đã chuẩn hoá bởi `Scripture`.
    case scripture(translation: String, reference: String)
    case media(MediaID)

    private enum CodingKeys: String, CodingKey {
        case type
        case planID
        case itemID
        case id
        case arrangementID
        case translation
        case reference
        case mediaID
    }

    private enum Kind: String, Codable {
        case planItem
        case presentation
        case scripture
        case media
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .planItem:
            let planID = try container.decode(UUID.self, forKey: .planID)
            self = .planItem(planID: planID, itemID: try container.decode(UUID.self, forKey: .itemID))
        case .presentation:
            let id = try container.decode(UUID.self, forKey: .id)
            let arrangementID = try container.decodeIfPresent(UUID.self, forKey: .arrangementID)
            self = .presentation(id: id, arrangementID: arrangementID)
        case .scripture:
            let translation = try container.decode(String.self, forKey: .translation)
            let reference = try container.decode(String.self, forKey: .reference)
            self = .scripture(translation: translation, reference: reference)
        case .media:
            self = .media(try container.decode(MediaID.self, forKey: .mediaID))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .planItem(let planID, let itemID):
            try container.encode(Kind.planItem, forKey: .type)
            try container.encode(planID, forKey: .planID)
            try container.encode(itemID, forKey: .itemID)
        case .presentation(let id, let arrangementID):
            try container.encode(Kind.presentation, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(arrangementID, forKey: .arrangementID)
        case .scripture(let translation, let reference):
            try container.encode(Kind.scripture, forKey: .type)
            try container.encode(translation, forKey: .translation)
            try container.encode(reference, forKey: .reference)
        case .media(let mediaID):
            try container.encode(Kind.media, forKey: .type)
            try container.encode(mediaID, forKey: .mediaID)
        }
    }
}

/// Lệnh điều khiển trình chiếu. Mọi thao tác trực tiếp đi qua `ShowController.send(_:)`.
/// Mã hoá JSON với khoá phân biệt `"type"` bằng đúng tên case.
public enum ShowCommand: Sendable, Equatable, Codable {
    /// `nil` là không dùng chương trình.
    case loadPlan(planID: UUID?)
    /// Hiện lưới trang của nguồn, không lên màn.
    case selectItem(LiveSource)
    /// `slideIndex` là chỉ số trong `SlideSequence` của nguồn.
    case goLive(LiveSource, slideIndex: Int)
    case next
    case previous
    case clearLayer(LayerKind)
    case clearAll
    case setFreeze(Bool)
    case setRehearsal(Bool)
    /// Thư viện báo nội dung đổi; dựng lại cảnh nếu đang chiếu nội dung đó.
    case contentDidChange(ids: Set<UUID>)

    private enum CodingKeys: String, CodingKey {
        case type
        case planID
        case source
        case slideIndex
        case layer
        case enabled
        case ids
    }

    private enum Kind: String, Codable {
        case loadPlan
        case selectItem
        case goLive
        case next
        case previous
        case clearLayer
        case clearAll
        case setFreeze
        case setRehearsal
        case contentDidChange
    }

    /// Bộ mã hoá dùng cho remote và nhật ký: JSON một dòng, khoá sắp xếp.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .loadPlan:
            self = .loadPlan(planID: try container.decodeIfPresent(UUID.self, forKey: .planID))
        case .selectItem:
            self = .selectItem(try container.decode(LiveSource.self, forKey: .source))
        case .goLive:
            let source = try container.decode(LiveSource.self, forKey: .source)
            self = .goLive(source, slideIndex: try container.decode(Int.self, forKey: .slideIndex))
        case .next:
            self = .next
        case .previous:
            self = .previous
        case .clearLayer:
            self = .clearLayer(try container.decode(LayerKind.self, forKey: .layer))
        case .clearAll:
            self = .clearAll
        case .setFreeze:
            self = .setFreeze(try container.decode(Bool.self, forKey: .enabled))
        case .setRehearsal:
            self = .setRehearsal(try container.decode(Bool.self, forKey: .enabled))
        case .contentDidChange:
            self = .contentDidChange(ids: Set(try container.decode([UUID].self, forKey: .ids)))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .loadPlan(let planID):
            try container.encode(Kind.loadPlan, forKey: .type)
            try container.encodeIfPresent(planID, forKey: .planID)
        case .selectItem(let source):
            try container.encode(Kind.selectItem, forKey: .type)
            try container.encode(source, forKey: .source)
        case .goLive(let source, let slideIndex):
            try container.encode(Kind.goLive, forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(slideIndex, forKey: .slideIndex)
        case .next:
            try container.encode(Kind.next, forKey: .type)
        case .previous:
            try container.encode(Kind.previous, forKey: .type)
        case .clearLayer(let layer):
            try container.encode(Kind.clearLayer, forKey: .type)
            try container.encode(layer, forKey: .layer)
        case .clearAll:
            try container.encode(Kind.clearAll, forKey: .type)
        case .setFreeze(let enabled):
            try container.encode(Kind.setFreeze, forKey: .type)
            try container.encode(enabled, forKey: .enabled)
        case .setRehearsal(let enabled):
            try container.encode(Kind.setRehearsal, forKey: .type)
            try container.encode(enabled, forKey: .enabled)
        case .contentDidChange(let ids):
            try container.encode(Kind.contentDidChange, forKey: .type)
            // Sắp xếp để chuỗi JSON ổn định giữa các lần chạy.
            try container.encode(ids.sorted { $0.uuidString < $1.uuidString }, forKey: .ids)
        }
    }
}

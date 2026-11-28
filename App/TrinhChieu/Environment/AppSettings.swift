import Foundation
import Observation
import RenderEngine

/// Vai một màn được gán, nhận diện màn bằng UUID của `CGDisplayCreateUUIDFromDisplayID`: cắm lại hay đổi thứ tự cắm
/// thì vẫn đúng màn.
struct OutputAssignment: Codable, Equatable, Hashable, Sendable {
    var displayUUID: String
    var role: OutputRole
    /// Tên màn lúc gán, để báo "Màn ... đã bị rút ra" khi màn vắng mặt.
    var displayName: String
}

/// Toàn bộ cài đặt của ứng dụng, lưu một khoá `app.settings.v1` trong `UserDefaults`.
///
/// Đọc khoan dung: trường thiếu (cài đặt từ bản cũ) lấy giá trị mặc định, nên thêm trường mới không làm mất cài đặt cũ.
struct AppSettings: Codable, Equatable, Sendable {
    /// Thư mục thư viện. `nil` là mặc định `~/Documents/TrinhChieu`.
    var libraryPath: String?
    var outputAssignments: [OutputAssignment]
    /// `uniqueID` của thiết bị Core Audio cho âm thanh media; `nil` theo hệ thống.
    var audioOutputDeviceID: String?
    /// Mã bản dịch Kinh Thánh mặc định.
    var defaultTranslation: String?
    /// Hết trang thì sang mục kế (`ShowSettings.advanceToNextItem`).
    var advanceToNextItem: Bool
    /// Bạn đã đóng màn chào.
    var welcomeDismissed: Bool

    init(
        libraryPath: String? = nil, outputAssignments: [OutputAssignment] = [], audioOutputDeviceID: String? = nil,
        defaultTranslation: String? = nil, advanceToNextItem: Bool = true, welcomeDismissed: Bool = false
    ) {
        self.libraryPath = libraryPath
        self.outputAssignments = outputAssignments
        self.audioOutputDeviceID = audioOutputDeviceID
        self.defaultTranslation = defaultTranslation
        self.advanceToNextItem = advanceToNextItem
        self.welcomeDismissed = welcomeDismissed
    }

    /// Mỗi trường đọc riêng: một trường hỏng hoặc sai kiểu chỉ trường đó về mặc định, các trường khác giữ nguyên.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        libraryPath = field(.libraryPath, defaults.libraryPath)
        outputAssignments = field(.outputAssignments, defaults.outputAssignments)
        audioOutputDeviceID = field(.audioOutputDeviceID, defaults.audioOutputDeviceID)
        defaultTranslation = field(.defaultTranslation, defaults.defaultTranslation)
        advanceToNextItem = field(.advanceToNextItem, defaults.advanceToNextItem)
        welcomeDismissed = field(.welcomeDismissed, defaults.welcomeDismissed)
    }

    /// Thư mục thư viện mặc định.
    static var defaultLibraryURL: URL {
        let documents =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return documents.appendingPathComponent("TrinhChieu", isDirectory: true)
    }

    var libraryURL: URL {
        libraryPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultLibraryURL
    }

    /// Vai đang gán cho một màn.
    func role(forDisplay uuid: String) -> OutputRole? {
        outputAssignments.first { $0.displayUUID == uuid }?.role
    }

    /// Gán `role` cho màn `uuid` (`nil` là "Không dùng"). Mỗi vai chỉ một màn, mỗi màn chỉ một vai: màn đang giữ vai
    /// đó tự chuyển sang "Không dùng".
    mutating func assign(_ role: OutputRole?, toDisplay uuid: String, name: String) {
        outputAssignments.removeAll { $0.displayUUID == uuid || (role != nil && $0.role == role) }
        if let role {
            outputAssignments.append(OutputAssignment(displayUUID: uuid, role: role, displayName: name))
            outputAssignments.sort { $0.role.sortOrder < $1.role.sortOrder }
        }
    }
}

extension OutputRole {
    /// Đầu ra chính trước, màn hình nhắc sau.
    var sortOrder: Int {
        switch self {
        case .program: return 0
        case .stage: return 1
        }
    }
}

/// Giữ ``AppSettings`` và ghi xuống `UserDefaults` mỗi lần đổi.
@MainActor @Observable final class SettingsStore {
    static let key = "app.settings.v1"

    @ObservationIgnored private let defaults: UserDefaults

    var value: AppSettings {
        didSet {
            guard value != oldValue else { return }
            save()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = Self.load(from: defaults)
    }

    static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

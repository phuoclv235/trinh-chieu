import CoreModel
import Foundation

/// Ba mẫu trình bày tạo sẵn cho thư viện mới, đọc từ `Resources/default-themes/*.json` (thứ tự theo tên tệp).
///
/// Mã của các mẫu cố định, nên mọi thư viện mới có cùng mẫu: gói mang đi giữa hai thư viện nhận ra mẫu trùng.
public enum DefaultThemes {
    /// "Lời bài hát giữa màn": mẫu mặc định của bài hát.
    public static let lyricsCenterID = UUID(uuidString: "7C0A0001-0000-4000-8000-000000000001")!
    /// "Lời bài hát dưới màn": cho camera, Zoom.
    public static let lyricsLowerThirdID = UUID(uuidString: "7C0A0001-0000-4000-8000-000000000002")!
    /// "Kinh Thánh": mẫu mặc định của Kinh Thánh.
    public static let scriptureID = UUID(uuidString: "7C0A0001-0000-4000-8000-000000000003")!

    /// Đọc ba mẫu từ tài nguyên của gói.
    public static func load() throws -> [Theme] {
        guard let directory = Bundle.module.url(forResource: "default-themes", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        return try names.map { name in
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            return try DocumentCoding.decode(Theme.self, from: data)
        }
    }

    /// Ba mẫu tạo sẵn; đọc tài nguyên lỗi (gói hỏng) thì dùng mẫu tối thiểu để thư viện vẫn mở được.
    public static func make() -> [Theme] {
        guard let themes = try? load(), !themes.isEmpty else {
            return [Theme.fallback()]
        }
        return themes
    }
}

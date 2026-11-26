import Foundation

/// Tham số dòng lệnh của bản thử.
struct ProbeOptions: Sendable {
    enum Parsed {
        case success(ProbeOptions)
        case help
        case failure(String)
    }

    /// Thời gian đo (giây), không tính thời gian khởi động.
    var duration: Double = 600
    /// Thời gian khởi động trước khi bắt đầu đo (giây).
    var warmup: Double = 5
    /// Đổi chữ sau mỗi khoảng này (giây).
    var sceneInterval: Double = 2
    /// Thời lượng hoà tan (giây).
    var dissolve: Double = 0.35
    /// Chỉ số màn hình trong `NSScreen.screens`; rỗng là lấy tối đa 2 màn đầu.
    var screenIndices: [Int] = []
    var video1: URL?
    var video2: URL?
    var pictureInPicture = true
    var frameRate: Float = 60
    var frameLatency = 1
    var report: URL?
    var mediaDirectory: URL?

    static let usage = """
        Cách dùng: ProbeApp [tuỳ chọn]
          --duration <giây>       thời gian đo, mặc định 600 (10 phút)
          --warmup <giây>         khởi động trước khi đo, mặc định 5
          --interval <giây>       đổi chữ mỗi khoảng, mặc định 2
          --dissolve <giây>       thời lượng hoà tan, mặc định 0.35
          --screens <a,b>         chỉ số màn hình (xem danh sách in ra lúc chạy), mặc định 2 màn đầu
          --video1 <tệp>          video nền; mặc định tự tạo 1080p H.264
          --video2 <tệp>          video khung phụ; mặc định tự tạo 4K HEVC
          --no-pip                bỏ video khung phụ
          --fps <số>              tần số khung mong muốn, mặc định 60
          --frame-latency <1|2>   số khung trễ của display link, mặc định 1
          --report <tệp.md>       nơi ghi báo cáo, mặc định ./ket-qua-ban-thu-<thời điểm>.md
          --media-dir <thư mục>   nơi lưu video tự tạo, mặc định ~/Library/Caches/TrinhChieuProbe
        Bấm Esc trên màn đầu ra để dừng sớm (vẫn ghi báo cáo).
        """

    static func parse(_ arguments: [String]) -> Parsed {
        var options = ProbeOptions()
        var index = 0
        func value(_ flag: String) -> String? {
            guard index + 1 < arguments.count else { return nil }
            index += 1
            return arguments[index]
        }
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--help", "-h":
                return .help
            case "--no-pip":
                options.pictureInPicture = false
            case "--duration", "--warmup", "--interval", "--dissolve":
                guard let text = value(flag), let number = Double(text), number >= 0 else {
                    return .failure("Giá trị không hợp lệ cho \(flag)")
                }
                switch flag {
                case "--duration":
                    options.duration = number
                case "--warmup":
                    options.warmup = number
                case "--interval":
                    options.sceneInterval = max(0.1, number)
                default:
                    options.dissolve = number
                }
            case "--fps":
                guard let text = value(flag), let number = Float(text), number > 0 else {
                    return .failure("Giá trị không hợp lệ cho --fps")
                }
                options.frameRate = number
            case "--frame-latency":
                guard let text = value(flag), let number = Int(text), (1...3).contains(number) else {
                    return .failure("--frame-latency phải là 1, 2 hoặc 3")
                }
                options.frameLatency = number
            case "--screens":
                guard let text = value(flag) else { return .failure("Thiếu giá trị cho --screens") }
                let indices = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard !indices.isEmpty else { return .failure("Giá trị không hợp lệ cho --screens") }
                options.screenIndices = indices
            case "--video1", "--video2", "--report", "--media-dir":
                guard let text = value(flag) else { return .failure("Thiếu giá trị cho \(flag)") }
                let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
                switch flag {
                case "--video1":
                    options.video1 = url
                case "--video2":
                    options.video2 = url
                case "--report":
                    options.report = url
                default:
                    options.mediaDirectory = url
                }
            default:
                return .failure("Không hiểu tuỳ chọn \(flag)")
            }
            index += 1
        }
        return .success(options)
    }
}

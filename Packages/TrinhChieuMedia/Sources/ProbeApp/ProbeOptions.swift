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
    /// `nil` = theo tần số tối đa của từng màn (mặc định, `--fps native`).
    var frameRate: Float?
    /// Đưa view đầu ra vào chế độ toàn màn hình của AppKit, để thử đường trình chiếu trực tiếp.
    var fullScreenMode = false
    /// Đưa cửa sổ vào toàn màn hình gốc của macOS (`toggleFullScreen`, có Space riêng).
    var nativeFullScreen = false
    var frameLatency = 1
    /// Giữ một lời cố định, không đổi chữ.
    var staticText = false
    /// Bỏ cả hai video, vẽ nền màu đặc.
    var noVideo = false
    /// Mỗi màn một command queue riêng.
    var queuePerScreen = false
    /// Dùng `CADisplayLink` của NSView (luồng chính) và `nextDrawable()` thay `CAMetalDisplayLink` (chỉ để so sánh).
    var viewDisplayLink = false
    /// Phủ cửa sổ đen lên các màn không dùng để đo (thử giả thuyết ứng dụng khác làm lỡ nhịp).
    var blankOtherScreens = false
    var report: URL?
    var mediaDirectory: URL?

    static let usage = """
        Cách dùng: ProbeApp [tuỳ chọn]
          --duration <giây>       thời gian đo, mặc định 600 (10 phút)
          --warmup <giây>         khởi động trước khi đo, mặc định 5
          --interval <giây>       đổi chữ mỗi khoảng, mặc định 2 (cộng ngẫu nhiên 0 đến 1 chu kỳ khung)
          --dissolve <giây>       thời lượng hoà tan, mặc định 0.35
          --screens <a,b>         chỉ số màn hình (xem danh sách in ra lúc chạy), mặc định 2 màn đầu
          --video1 <tệp>          video nền; mặc định tự tạo 1080p H.264
          --video2 <tệp>          video khung phụ; mặc định tự tạo 4K HEVC
          --no-pip                bỏ video khung phụ
          --fps <số|native>       tần số khung mong muốn, mặc định native = theo từng màn
          --fullscreen            dùng enterFullScreenMode của AppKit (thử trình chiếu trực tiếp)
          --native-fullscreen     dùng toàn màn hình gốc của macOS (toggleFullScreen)
          --frame-latency <1|2>   số khung trễ của display link, mặc định 1
          --static-text           giữ một lời cố định, không đổi chữ
          --no-video              bỏ cả hai video, nền màu đặc
          --queue-per-screen      mỗi màn một command queue riêng
          --view-display-link     dùng CADisplayLink của NSView thay CAMetalDisplayLink (so sánh)
          --blank-other-screens   phủ cửa sổ đen lên các màn không dùng để đo
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
                // Giới hạn 24 giờ để mọi phép đổi sang số nguyên đều an toàn.
                guard let text = value(flag), let number = Double(text), number >= 0, number <= 86_400 else {
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
            case "--fullscreen":
                options.fullScreenMode = true
            case "--native-fullscreen":
                options.nativeFullScreen = true
            case "--static-text":
                options.staticText = true
            case "--no-video":
                options.noVideo = true
                options.pictureInPicture = false
            case "--queue-per-screen":
                options.queuePerScreen = true
            case "--view-display-link":
                options.viewDisplayLink = true
            case "--blank-other-screens":
                options.blankOtherScreens = true
            case "--fps":
                guard let text = value(flag) else { return .failure("Thiếu giá trị cho --fps") }
                if text == "native" {
                    options.frameRate = nil
                } else {
                    guard let number = Float(text), number > 0, number <= 240 else {
                        return .failure("Giá trị không hợp lệ cho --fps")
                    }
                    options.frameRate = number
                }
            case "--frame-latency":
                guard let text = value(flag), let number = Int(text), (1...3).contains(number) else {
                    return .failure("--frame-latency phải là 1, 2 hoặc 3")
                }
                options.frameLatency = number
            case "--screens":
                guard let text = value(flag) else { return .failure("Thiếu giá trị cho --screens") }
                let tokens = text.split(separator: ",", omittingEmptySubsequences: false)
                let indices = tokens.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                let valid = indices.count == tokens.count && Set(indices).count == indices.count
                guard !indices.isEmpty, valid, indices.allSatisfy({ $0 >= 0 }) else {
                    return .failure("--screens cần các chỉ số màn khác nhau, không âm, cách nhau bằng dấu phẩy")
                }
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
        if options.fullScreenMode && options.nativeFullScreen {
            return .failure("Chỉ chọn một trong --fullscreen và --native-fullscreen")
        }
        return .success(options)
    }
}

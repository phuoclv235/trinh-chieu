import Foundation

/// Ghi ra terminal cho công cụ dòng lệnh (bản thử không có giao diện để hiện thông báo).
enum Console {
    static func out(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

import Darwin
import Foundation

/// Lấy mẫu CPU và bộ nhớ của tiến trình mỗi giây.
@MainActor
final class ProcessSampler {
    struct Sample: Sendable {
        /// Phần trăm của một nhân CPU (có thể vượt 100 khi dùng nhiều nhân).
        var cpuPercent: Double
        /// Bộ nhớ thật tiến trình đang chiếm (phys_footprint, như Activity Monitor), MB.
        var footprintMB: Double
    }

    private(set) var samples: [Sample] = []
    private var lastCPU: Double = 0
    private var lastWall: Double = 0
    private var task: Task<Void, Never>?

    func start() {
        samples = []
        lastCPU = Self.cpuSeconds()
        lastWall = ProcessInfo.processInfo.systemUptime
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.takeSample()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func takeSample() {
        let cpu = Self.cpuSeconds()
        let wall = ProcessInfo.processInfo.systemUptime
        let elapsed = wall - lastWall
        guard elapsed > 0 else { return }
        samples.append(Sample(cpuPercent: (cpu - lastCPU) / elapsed * 100, footprintMB: Self.footprintMB()))
        lastCPU = cpu
        lastWall = wall
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    static func footprintMB() -> Double {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else { return 0 }
        return Double(info.ri_phys_footprint) / (1024 * 1024)
    }
}

/// Thông tin máy cho báo cáo.
enum SystemInfo {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { String(cString: $0) }
        }
    }

    static func integer(_ name: String) -> Int64 {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return value
    }

    static var summary: [(String, String)] {
        let memoryGB = Double(integer("hw.memsize")) / (1024 * 1024 * 1024)
        return [
            ("Model máy", string("hw.model") ?? "không rõ"),
            ("Chip", string("machdep.cpu.brand_string") ?? "không rõ"),
            ("RAM", String(format: "%.0f GB", memoryGB)),
            ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
        ]
    }
}

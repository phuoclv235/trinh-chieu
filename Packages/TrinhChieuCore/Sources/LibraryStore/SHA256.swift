import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif

/// SHA-256 tính theo luồng, viết bằng Swift thuần để chạy được trên Linux (không có CryptoKit).
/// Trên Mac, ``MediaHasher`` dùng CryptoKit cho nhanh; bản này vẫn được test trên cả hai nền tảng.
struct StreamingSHA256 {
    private static let roundConstants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5,
        0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
        0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc,
        0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
        0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
        0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3,
        0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5,
        0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
        0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    private var state: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]
    /// Phần chưa đủ một khối 64 byte.
    private var pending: [UInt8] = []
    private var byteCount: UInt64 = 0
    private var schedule = [UInt32](repeating: 0, count: 64)

    init() {
        pending.reserveCapacity(64)
    }

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { update($0) }
    }

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        byteCount &+= UInt64(bytes.count)
        var offset = 0
        if !pending.isEmpty {
            let take = min(64 - pending.count, bytes.count)
            pending.append(contentsOf: bytes[0..<take])
            offset = take
            guard pending.count == 64 else { return }
            let block = pending
            block.withUnsafeBytes { processBlock($0, at: 0) }
            pending.removeAll(keepingCapacity: true)
        }
        while offset + 64 <= bytes.count {
            processBlock(bytes, at: offset)
            offset += 64
        }
        if offset < bytes.count {
            pending.append(contentsOf: bytes[offset..<bytes.count])
        }
    }

    /// Kết thúc và trả 32 byte mã băm.
    mutating func finalize() -> [UInt8] {
        let bitLength = byteCount &* 8
        var tail = pending
        tail.append(0x80)
        while tail.count % 64 != 56 {
            tail.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            tail.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        tail.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                processBlock(buffer, at: offset)
                offset += 64
            }
        }
        pending.removeAll()
        var digest: [UInt8] = []
        digest.reserveCapacity(32)
        for word in state {
            for shift in stride(from: 24, through: 0, by: -8) {
                digest.append(UInt8(truncatingIfNeeded: word >> UInt32(shift)))
            }
        }
        return digest
    }

    private mutating func processBlock(_ bytes: UnsafeRawBufferPointer, at offset: Int) {
        for index in 0..<16 {
            let base = offset + index * 4
            let byte0 = UInt32(bytes[base]) << 24
            let byte1 = UInt32(bytes[base + 1]) << 16
            let byte2 = UInt32(bytes[base + 2]) << 8
            let byte3 = UInt32(bytes[base + 3])
            schedule[index] = byte0 | byte1 | byte2 | byte3
        }
        for index in 16..<64 {
            let w15 = schedule[index - 15]
            let w2 = schedule[index - 2]
            let sigma0 = Self.rotateRight(w15, 7) ^ Self.rotateRight(w15, 18) ^ (w15 >> 3)
            let sigma1 = Self.rotateRight(w2, 17) ^ Self.rotateRight(w2, 19) ^ (w2 >> 10)
            schedule[index] = schedule[index - 16] &+ sigma0 &+ schedule[index - 7] &+ sigma1
        }
        var a = state[0]
        var b = state[1]
        var c = state[2]
        var d = state[3]
        var e = state[4]
        var f = state[5]
        var g = state[6]
        var h = state[7]
        for index in 0..<64 {
            let sum1 = Self.rotateRight(e, 6) ^ Self.rotateRight(e, 11) ^ Self.rotateRight(e, 25)
            let choose = (e & f) ^ (~e & g)
            let temp1 = h &+ sum1 &+ choose &+ Self.roundConstants[index] &+ schedule[index]
            let sum0 = Self.rotateRight(a, 2) ^ Self.rotateRight(a, 13) ^ Self.rotateRight(a, 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = sum0 &+ majority
            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }
        state[0] = state[0] &+ a
        state[1] = state[1] &+ b
        state[2] = state[2] &+ c
        state[3] = state[3] &+ d
        state[4] = state[4] &+ e
        state[5] = state[5] &+ f
        state[6] = state[6] &+ g
        state[7] = state[7] &+ h
    }

    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}

/// Băm và chép media theo luồng, không nạp cả tệp vào bộ nhớ.
enum MediaHasher {
    static let chunkSize = 1 << 20

    /// Chữ hex thường của 32 byte mã băm.
    static func hex(_ digest: [UInt8]) -> String {
        let table = Array("0123456789abcdef")
        var text = ""
        text.reserveCapacity(digest.count * 2)
        for byte in digest {
            text.append(table[Int(byte >> 4)])
            text.append(table[Int(byte & 0x0F)])
        }
        return text
    }

    /// Đọc `source` theo khối, băm SHA-256; nếu có `destination` thì ghi từng khối sang đó cùng lúc (một lượt đọc).
    /// - Returns: mã băm dạng hex thường và số byte.
    static func sha256(of source: URL, copyingTo destination: URL? = nil) throws -> (hex: String, byteCount: Int) {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var output: FileHandle?
        if let destination {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
            }
            output = try FileHandle(forWritingTo: destination)
        }
        defer { try? output?.close() }
        var hasher = Hasher256()
        var total = 0
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(chunk)
            try output?.write(contentsOf: chunk)
            total += chunk.count
        }
        try output?.synchronize()
        return (hex(hasher.finalize()), total)
    }
}

/// Bộ băm dùng cho media: CryptoKit trên Mac, ``StreamingSHA256`` trên Linux.
struct Hasher256 {
    #if canImport(CryptoKit)
        private var hasher = SHA256()
    #else
        private var hasher = StreamingSHA256()
    #endif

    mutating func update(_ data: Data) {
        hasher.update(data: data)
    }

    mutating func finalize() -> [UInt8] {
        #if canImport(CryptoKit)
            return Array(hasher.finalize())
        #else
            return hasher.finalize()
        #endif
    }
}

extension StreamingSHA256 {
    /// Cùng tên với CryptoKit để ``Hasher256`` gọi thống nhất.
    mutating func update(data: Data) {
        update(data)
    }
}

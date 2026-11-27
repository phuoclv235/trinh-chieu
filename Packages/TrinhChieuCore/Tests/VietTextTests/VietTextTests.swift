import Foundation
import Testing

@testable import VietText

@Suite("VietText.fold: gộp dấu để so khớp")
struct VietTextFoldTests {
    @Test("Ví dụ bắt buộc trong đặc tả")
    func requiredExamples() {
        #expect(VietText.fold("Nguyễn") == "nguyen")
        #expect(VietText.fold("ĐẤNG") == "dang")
        #expect(VietText.fold("Giăng 3:16") == "giang 3:16")
        #expect(VietText.fold("Chúa Là Đá Muôn Đời") == "chua la da muon doi")
    }

    @Test("NFD và NFC cho cùng một kết quả")
    func nfdAndNfcFoldTheSame() {
        let samples = ["Nguyễn", "Đức Chúa Trời", "Thánh ca 123", "Sáng-thế Ký", "Ê-sai", "Phước hạnh thay"]
        for sample in samples {
            let nfc = sample.precomposedStringWithCanonicalMapping
            let nfd = sample.decomposedStringWithCanonicalMapping
            #expect(Array(nfc.unicodeScalars) != Array(nfd.unicodeScalars))
            #expect(VietText.fold(nfc) == VietText.fold(nfd))
        }
    }

    @Test("Chữ ư, ơ, ă, â, ê, ô (thường, hoa, có thanh) về chữ gốc")
    func modifiedVowelsFoldToBase() {
        #expect(VietText.fold("ư ơ ă â ê ô") == "u o a a e o")
        #expect(VietText.fold("Ư Ơ Ă Â Ê Ô") == "u o a a e o")
        #expect(VietText.fold("ừ ợ ẳ ẫ ế ộ") == "u o a a e o")
        #expect(VietText.fold("đ Đ") == "d d")
    }

    @Test("Tiếng Anh giữ nguyên, chỉ viết thường")
    func englishIsLowercasedOnly() {
        #expect(VietText.fold("Amazing Grace, How Sweet!") == "amazing grace, how sweet!")
        #expect(VietText.fold("abc-XYZ 42") == "abc-xyz 42")
    }

    @Test("Gộp khoảng trắng liên tiếp, bỏ khoảng trắng đầu cuối")
    func collapsesWhitespace() {
        #expect(VietText.fold("  Chúa \t\n  Giê-xu\u{00A0}\u{00A0}Christ  ") == "chua gie-xu christ")
        #expect(VietText.fold("") == "")
        #expect(VietText.fold(" \n\t ") == "")
    }

    @Test("Chữ hoa sinh dấu kết hợp khi viết thường cũng được bỏ dấu")
    func lowercasingMarksAreRemoved() {
        #expect(VietText.fold("İ") == "i")
    }
}

@Suite("VietText.foldLoose, normalize, queryTerms")
struct VietTextOtherTests {
    @Test("foldLoose bỏ dấu câu và gạch nối")
    func foldLooseDropsPunctuation() {
        #expect(VietText.foldLoose("Sáng-thế Ký") == "sang the ky")
        #expect(VietText.foldLoose("Giăng 3:16") == "giang 3 16")
        #expect(VietText.foldLoose("“Hãy yêu thương nhau!” — (Giăng 13:34)") == "hay yeu thuong nhau giang 13 34")
        #expect(VietText.foldLoose("--- ...") == "")
    }

    @Test("normalize: NFC, xuống dòng LF, bỏ ký tự điều khiển và BOM, giữ TAB")
    func normalizeForStorage() {
        let nfc = Array("Nguyễn".precomposedStringWithCanonicalMapping.unicodeScalars)
        let nfd = "Nguyễn".decomposedStringWithCanonicalMapping
        #expect(Array(VietText.normalize(nfd).unicodeScalars) == nfc)
        #expect(VietText.normalize("\u{FEFF}Dòng 1\r\nDòng 2\rDòng 3\nDòng 4") == "Dòng 1\nDòng 2\nDòng 3\nDòng 4")
        #expect(VietText.normalize("a\r\r\nb") == "a\n\nb")
        #expect(VietText.normalize("a\tb\u{0000}c\u{0007}d\u{001B}e\u{007F}f") == "a\tbcdef")
        #expect(VietText.normalize("x\u{FEFF}y") == "xy")
        #expect(VietText.normalize("") == "")
    }

    @Test("queryTerms: chia từ đã gộp, bỏ từ rỗng")
    func queryTermsSplitFoldedWords() {
        #expect(VietText.queryTerms("  Chúa   LÀ đá ") == ["chua", "la", "da"])
        #expect(VietText.queryTerms("Giăng 3:16") == ["giang", "3:16"])
        #expect(VietText.queryTerms("   ").isEmpty)
        #expect(VietText.queryTerms("").isEmpty)
    }
}

@Suite("VietText: chuỗi ngẫu nhiên")
struct VietTextFuzzTests {
    /// Bộ sinh số giả ngẫu nhiên có hạt giống, để lần chạy nào cũng như nhau.
    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Mọi chữ cái tiếng Việt (hoa và thường, đủ 5 thanh) dựng từ chữ gốc, dấu phụ và dấu thanh.
    static let vietnameseLetters: [Character] = {
        let vowels: [(base: String, modifiers: [String])] = [
            ("a", ["", "\u{0306}", "\u{0302}"]), ("e", ["", "\u{0302}"]), ("i", [""]),
            ("o", ["", "\u{0302}", "\u{031B}"]), ("u", ["", "\u{031B}"]), ("y", [""]),
        ]
        let tones = ["", "\u{0300}", "\u{0301}", "\u{0309}", "\u{0303}", "\u{0323}"]
        var letters: [Character] = ["đ", "Đ"]
        for vowel in vowels {
            for modifier in vowel.modifiers {
                for tone in tones {
                    for base in [vowel.base, vowel.base.uppercased()] {
                        letters.append(Character((base + modifier + tone).precomposedStringWithCanonicalMapping))
                    }
                }
            }
        }
        return letters
    }()

    static let asciiPrintable: [Character] = (0x20...0x7E).map { Character(Unicode.Scalar($0)!) } + ["\t", "\n"]

    @Test("10.000 chuỗi tiếng Việt và ASCII: không lỗi, kết quả gộp chỉ chứa ASCII")
    func vietnameseAndAsciiFoldToAscii() {
        var rng = SplitMix64(state: 2026)
        let alphabet = Self.vietnameseLetters + Self.asciiPrintable
        for _ in 0..<10_000 {
            let length = Int.random(in: 0...40, using: &rng)
            var text = String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
            if Bool.random(using: &rng) { text = text.decomposedStringWithCanonicalMapping }
            let folded = VietText.fold(text)
            let loose = VietText.foldLoose(text)
            #expect(folded.unicodeScalars.allSatisfy { $0.isASCII }, "fold(\(text.debugDescription))")
            #expect(loose.unicodeScalars.allSatisfy { $0.isASCII }, "foldLoose(\(text.debugDescription))")
            #expect(!folded.hasPrefix(" ") && !folded.hasSuffix(" ") && !folded.contains("  "))
            #expect(VietText.fold(folded) == folded)
            #expect(VietText.queryTerms(text).allSatisfy { !$0.isEmpty && !$0.contains(" ") })
        }
    }

    @Test("Ký tự Unicode bất kỳ: không lỗi, normalize ra NFC không có ký tự điều khiển lạ")
    func arbitraryUnicodeDoesNotCrash() {
        var rng = SplitMix64(state: 1925)
        for _ in 0..<2_000 {
            var scalars = String.UnicodeScalarView()
            for _ in 0..<Int.random(in: 0...24, using: &rng) {
                let value = UInt32.random(in: 0...0x2_FFFF, using: &rng)
                if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
            }
            let text = String(scalars)
            _ = VietText.fold(text)
            _ = VietText.foldLoose(text)
            _ = VietText.queryTerms(text)
            let normalized = VietText.normalize(text)
            let nfc = normalized.precomposedStringWithCanonicalMapping
            #expect(Array(normalized.unicodeScalars) == Array(nfc.unicodeScalars))
            #expect(
                normalized.unicodeScalars.allSatisfy {
                    $0 == "\n" || $0 == "\t" || $0.properties.generalCategory != .control
                }
            )
            #expect(!normalized.unicodeScalars.contains("\r") && !normalized.unicodeScalars.contains("\u{FEFF}"))
        }
    }
}

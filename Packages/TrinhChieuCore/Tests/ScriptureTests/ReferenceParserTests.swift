import Testing

@testable import Scripture

/// Kết quả mong đợi của một ca phân tích.
enum Expected: Sendable, CustomStringConvertible {
    /// Phân tích được, `canonical` đúng bằng chuỗi này.
    case canonical(String)
    /// Tên sách mơ hồ; ứng viên gồm các sách này (theo mã OSIS).
    case ambiguous([String])
    /// Mới có tên sách (mã OSIS).
    case incomplete(String)
    /// Không hiểu; thông điệp chứa đoạn chữ này.
    case invalid(String)

    var description: String {
        switch self {
        case .canonical(let text):
            return "canonical(\(text))"
        case .ambiguous(let books):
            return "ambiguous(\(books))"
        case .incomplete(let book):
            return "incomplete(\(book))"
        case .invalid(let text):
            return "invalid(\(text))"
        }
    }
}

let parser = ReferenceParser()

/// Bảng ca phân tích: chuỗi gõ và kết quả mong đợi.
let parseCases: [(input: String, expected: Expected)] = [
    // Ca bắt buộc trong đặc tả T1.2.
    ("gi 3 16", .canonical("Giăng 3:16")),
    ("Giăng 3:16-18", .canonical("Giăng 3:16-18")),
    ("giang3:16", .canonical("Giăng 3:16")),
    ("1 co 13", .canonical("I Cô-rinh-tô 13")),
    ("I Cô-rinh-tô 13:4-7", .canonical("I Cô-rinh-tô 13:4-7")),
    ("1co13:4", .canonical("I Cô-rinh-tô 13:4")),
    ("thi 23", .canonical("Thi-thiên 23")),
    ("Thi-thiên 119:105", .canonical("Thi-thiên 119:105")),
    ("ro 8:28; 12:1-2", .canonical("Rô-ma 8:28; 12:1-2")),
    ("mat 5:3,5,7", .canonical("Ma-thi-ơ 5:3, 5, 7")),
    ("khai 21:1-4", .canonical("Khải-huyền 21:1-4")),
    ("sa 1:1", .canonical("Sáng-thế Ký 1:1")),
    ("john 3:16", .canonical("Giăng 3:16")),
    ("a", .ambiguous(["Amos", "Obad", "Hag"])),
    ("1", .invalid("tên sách")),
    ("gi 3:16-2", .invalid("Câu cuối (2) nhỏ hơn câu đầu (16)")),
    // Dấu tách chương câu.
    ("gi 3.16", .canonical("Giăng 3:16")),
    ("gi 3,16", .canonical("Giăng 3:16")),
    ("gi 3:16 - 18", .canonical("Giăng 3:16-18")),
    ("giăng 3 : 16", .canonical("Giăng 3:16")),
    ("Giăng 3:16–18", .canonical("Giăng 3:16-18")),
    ("Giăng 3:16—18", .canonical("Giăng 3:16-18")),
    ("gi 3 16-18", .canonical("Giăng 3:16-18")),
    ("thi 23 1", .canonical("Thi-thiên 23:1")),
    ("  GIĂNG   3:16  ", .canonical("Giăng 3:16")),
    // Đoạn nhiều chương, nhiều đoạn.
    ("gi 3:16-4:2", .canonical("Giăng 3:16-4:2")),
    ("gi 3", .canonical("Giăng 3")),
    ("gi 3-4", .canonical("Giăng 3-4")),
    ("gi 3-4:2", .canonical("Giăng 3:1-4:2")),
    ("Giăng 3:16; 4:1-3", .canonical("Giăng 3:16; 4:1-3")),
    ("gi 3:16,18", .canonical("Giăng 3:16, 18")),
    ("gi 3:16-18, 20", .canonical("Giăng 3:16-18, 20")),
    ("gi 3:16, 4:1", .canonical("Giăng 3:16; 4:1")),
    ("gi 3:16; 5", .canonical("Giăng 3:16; 5")),
    ("giăng 3:16; rô-ma 5:8", .canonical("Giăng 3:16; Rô-ma 5:8")),
    ("gi 3:16;", .canonical("Giăng 3:16")),
    ("Thi 119:105-112", .canonical("Thi-thiên 119:105-112")),
    // Alias bắt buộc.
    ("giang 1:1", .canonical("Giăng 1:1")),
    ("tt 23", .canonical("Thi-thiên 23")),
    ("ro 12:1", .canonical("Rô-ma 12:1")),
    ("cv 2:38", .canonical("Công-vụ các Sứ-đồ 2:38")),
    ("kh 22:20", .canonical("Khải-huyền 22:20")),
    ("he 11:1", .canonical("Hê-bơ-rơ 11:1")),
    ("xuat 20:1-17", .canonical("Xuất Ê-díp-tô Ký 20:1-17")),
    // Sách có số thứ tự.
    ("ii co 5:17", .canonical("II Cô-rinh-tô 5:17")),
    ("2 cô-rinh-tô 5:17", .canonical("II Cô-rinh-tô 5:17")),
    ("1 giang 1:9", .canonical("I Giăng 1:9")),
    ("3 gi 1:2", .canonical("III Giăng 1:2")),
    ("iii giăng 2", .canonical("III Giăng 2")),
    ("1 sa 17", .canonical("I Sa-mu-ên 17")),
    ("2 vua 5", .canonical("II Các Vua 5")),
    ("1 phi 5:7", .canonical("I Phi-e-rơ 5:7")),
    ("icorinhto 13", .canonical("I Cô-rinh-tô 13")),
    // Tên đầy đủ, không dấu, tiếng Anh.
    ("rô-ma 8:28", .canonical("Rô-ma 8:28")),
    ("roma 12:1", .canonical("Rô-ma 12:1")),
    ("romans 8:28", .canonical("Rô-ma 8:28")),
    ("Rom 8:28", .canonical("Rô-ma 8:28")),
    ("psalm 23", .canonical("Thi-thiên 23")),
    ("Gen 1:1", .canonical("Sáng-thế Ký 1:1")),
    ("1 corinthians 13:4", .canonical("I Cô-rinh-tô 13:4")),
    ("isa 53:5", .canonical("Ê-sai 53:5")),
    ("Phi-líp 4:13", .canonical("Phi-líp 4:13")),
    ("phi 4:13", .canonical("Phi-líp 4:13")),
    ("châm 3:5-6", .canonical("Châm-ngôn 3:5-6")),
    ("e-sai 53", .canonical("Ê-sai 53")),
    ("nhã ca 2", .canonical("Nhã-ca 2")),
    ("ca 3:22-23", .canonical("Ca-thương 3:22-23")),
    ("đa 6", .canonical("Đa-ni-ên 6")),
    ("dan 1", .canonical("Dân-số Ký 1")),
    ("Sáng-thế Ký 1:1-3", .canonical("Sáng-thế Ký 1:1-3")),
    // Khớp tiền tố theo bảng ưu tiên.
    ("ma 1:1", .canonical("Ma-thi-ơ 1:1")),
    ("es 53", .canonical("Ê-sai 53")),
    ("truyen 3:1", .canonical("Truyền-đạo 3:1")),
    ("e-xơ 1", .ambiguous(["Ezra", "Esth"])),
    // Chưa đủ.
    ("giăng", .incomplete("John")),
    ("gi", .incomplete("John")),
    ("1 co", .incomplete("1Cor")),
    // Không hợp lệ.
    ("", .invalid("tên sách")),
    ("3:16", .invalid("tên sách")),
    ("xyz 3:16", .invalid("không tìm thấy sách")),
    ("gi 0:1", .invalid("bắt đầu từ 1")),
    ("gi 3:0", .invalid("bắt đầu từ 1")),
    ("gi 4-3", .invalid("Chương cuối (3) nhỏ hơn chương đầu (4)")),
    ("gi 3:16-3:10", .invalid("Câu cuối (10) nhỏ hơn câu đầu (16)")),
    ("gi 3:16abc", .invalid("chưa hiểu")),
    ("gi 3::16", .invalid("chưa hiểu")),
    ("gi 3:16-", .invalid("chưa hiểu")),
    ("gi 3 16 18", .invalid("chưa hiểu")),
    ("gi 3:16; rô-ma", .invalid("Thiếu số chương sau “Rô-ma”")),
    ("gi 3:16;; 4", .invalid("chưa hiểu")),
    ("gi 1234", .invalid("chưa hiểu")),
]

@Suite("ReferenceParser: phân tích địa chỉ câu")
struct ReferenceParserTests {
    @Test("Bảng ca phân tích có ít nhất 60 ca")
    func caseTableIsLargeEnough() {
        #expect(parseCases.count >= 60)
    }

    @Test("Mọi ca trong bảng cho đúng kết quả")
    func allCases() {
        for (input, expected) in parseCases {
            let result = parser.parse(input)
            let comment = Comment(rawValue: "“\(input)” mong đợi \(expected), được \(result)")
            switch expected {
            case .canonical(let text):
                guard case .reference(let reference) = result else {
                    Issue.record(comment)
                    continue
                }
                #expect(reference.canonical == text, comment)
            case .ambiguous(let books):
                guard case .ambiguousBook(let candidates, _) = result else {
                    Issue.record(comment)
                    continue
                }
                #expect(Set(candidates.map { $0.osis }) == Set(books), comment)
            case .incomplete(let book):
                #expect(result == .incomplete(book: parser.catalog.book(osis: book)!), comment)
            case .invalid(let fragment):
                guard case .invalid(let reason) = result else {
                    Issue.record(comment)
                    continue
                }
                #expect(reason.contains(fragment), comment)
            }
        }
    }

    @Test("Chuỗi chuẩn hoá phân tích lại ra đúng các đoạn")
    func canonicalRoundTrips() {
        for (input, expected) in parseCases {
            guard case .canonical = expected, case .reference(let reference) = parser.parse(input) else { continue }
            #expect(parser.parse(reference.canonical) == .reference(reference), "“\(input)”")
        }
    }

    @Test("Cấu trúc đoạn: một câu, nhiều câu, cả chương, nhiều chương, vắt chương")
    func rangeStructure() {
        #expect(ranges("gi 3:16") == [.verse("John", 3, 16)])
        #expect(ranges("gi 3:16-18") == [.verses("John", 3, 16, 18)])
        #expect(ranges("thi 23") == [.chapters("Ps", 23, 23)])
        #expect(ranges("gi 3-4") == [.chapters("John", 3, 4)])
        let across = VerseRange(book: "John", startChapter: 3, startVerse: 16, endChapter: 4, endVerse: 2)
        #expect(ranges("gi 3:16-4:2") == [across])
        #expect(ranges("mat 5:3,5,7") == [.verse("Matt", 5, 3), .verse("Matt", 5, 5), .verse("Matt", 5, 7)])
        #expect(ranges("ro 8:28; 12:1-2") == [.verse("Rom", 8, 28), .verses("Rom", 12, 1, 2)])
        #expect(ranges("giăng 3:16; rô-ma 5:8") == [.verse("John", 3, 16), .verse("Rom", 5, 8)])
    }

    @Test("Tên sách mơ hồ giữ lại phần chương câu đã gõ")
    func ambiguousKeepsRest() {
        guard case .ambiguousBook(let candidates, let rest) = parser.parse("e-xơ 1:2; 3") else {
            Issue.record("“e-xơ” phải mơ hồ giữa E-xơ-ra và Ê-xơ-tê")
            return
        }
        #expect(candidates.map { $0.osis } == ["Ezra", "Esth"])
        #expect(rest == "1:2; 3")
    }

    @Test("Gợi ý sách khi đang gõ: khớp đúng trước, rồi theo bảng ưu tiên")
    func bookCandidates() {
        #expect(parser.bookCandidates("gi").first?.osis == "John")
        #expect(parser.bookCandidates("ma").map { $0.osis }.prefix(2) == ["Matt", "Mark"])
        #expect(parser.bookCandidates("ma", limit: 1).count == 1)
        #expect(parser.bookCandidates("1 co").first?.osis == "1Cor")
        #expect(parser.bookCandidates("").isEmpty)
        #expect(parser.bookCandidates("zzz").isEmpty)
    }

    private func ranges(_ input: String) -> [VerseRange] {
        guard case .reference(let reference) = parser.parse(input) else { return [] }
        return reference.ranges
    }
}

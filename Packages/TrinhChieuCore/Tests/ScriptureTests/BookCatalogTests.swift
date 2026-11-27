import Foundation
import Testing

@testable import Scripture

@Suite("BookCatalog: danh mục 66 sách")
struct BookCatalogTests {
    let catalog = BookCatalog.standard

    @Test("Đủ 66 sách theo thứ tự quy điển Tin Lành, mã OSIS không trùng")
    func sixtySixBooks() {
        #expect(catalog.books.count == 66)
        #expect(catalog.books.map { $0.ordinal } == Array(1...66))
        #expect(Set(catalog.books.map { $0.osis }).count == 66)
        #expect(catalog.books.first?.osis == "Gen")
        #expect(catalog.books[38].osis == "Mal")
        #expect(catalog.books[39].osis == "Matt")
        #expect(catalog.books.last?.osis == "Rev")
    }

    @Test("Tên đầy đủ và viết tắt theo bảng trong đặc tả")
    func namesMatchSpecification() {
        let expected: [String: (String, String)] = [
            "Gen": ("Sáng-thế Ký", "Sáng"), "Exod": ("Xuất Ê-díp-tô Ký", "Xuất"),
            "Deut": ("Phục-truyền Luật-lệ Ký", "Phục"), "Judg": ("Các Quan Xét", "Quan"),
            "1Kgs": ("I Các Vua", "1 Vua"), "Ps": ("Thi-thiên", "Thi"), "Ezek": ("Ê-xê-chi-ên", "Êxê"),
            "John": ("Giăng", "Gi"), "Acts": ("Công-vụ các Sứ-đồ", "Công"), "1Cor": ("I Cô-rinh-tô", "1 Cô"),
            "Phlm": ("Phi-lê-môn", "Phlm"), "3John": ("III Giăng", "3 Gi"), "Rev": ("Khải-huyền", "Khải"),
        ]
        for (osis, names) in expected {
            let book = catalog.book(osis: osis)
            #expect(book?.nameVi == names.0, "\(osis)")
            #expect(book?.shortVi == names.1, "\(osis)")
        }
    }

    @Test("Tên lưu dạng NFC")
    func namesAreNFC() {
        for book in catalog.books {
            #expect(book.nameVi == book.nameVi.precomposedStringWithCanonicalMapping, "\(book.osis)")
            #expect(book.shortVi == book.shortVi.precomposedStringWithCanonicalMapping, "\(book.osis)")
        }
    }

    @Test("Bảng ưu tiên dùng nhiều: Giăng 1 tới Khải-huyền 15, các sách khác 100 + thứ tự")
    func priorities() {
        let top = [
            "John", "Ps", "Rom", "Matt", "Isa", "Luke", "Gen", "Acts", "Prov", "Heb", "Eph", "Phil", "Mark", "Jas",
            "Rev",
        ]
        for (index, osis) in top.enumerated() {
            #expect(catalog.book(osis: osis)?.priority == index + 1, "\(osis)")
        }
        for book in catalog.books where !top.contains(book.osis) {
            #expect(book.priority == 100 + book.ordinal, "\(book.osis)")
        }
    }

    @Test("Khoá gõ: số thứ tự La Mã và Ả Rập về cùng một khoá")
    func ordinalKeys() {
        #expect(BookCatalog.keys(forName: "I Cô-rinh-tô", includesRoman: true) == ["1corinhto", "icorinhto"])
        #expect(BookCatalog.keys(forName: "1 Cô", includesRoman: false) == ["1co"])
        #expect(BookCatalog.inputKey("ii  cô") == "2co")
        #expect(BookCatalog.inputKey("Sáng-thế Ký") == "sangtheky")
        #expect(catalog.book(osis: "1Cor")?.numberPrefix == 1)
        #expect(catalog.book(osis: "John")?.numberPrefix == nil)
    }
}

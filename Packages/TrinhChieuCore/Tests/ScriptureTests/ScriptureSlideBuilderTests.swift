import CoreModel
import Foundation
import Testing

@testable import Scripture

@Suite("ScriptureSlideBuilder: chia câu thành trang")
struct ScriptureSlideBuilderTests {
    let builder = ScriptureSlideBuilder()

    /// Câu dài đúng 600 ký tự, có dấu phẩy mỗi 10 ký tự.
    static let longText: String = {
        let text = String(repeating: "Chúa yêu, ", count: 59) + "Amen Chúa."
        precondition(text.count == 600)
        return text
    }()

    static func bodyText(_ slide: Slide) -> String? {
        text(slide, slot: .body)
    }

    static func referenceText(_ slide: Slide) -> String? {
        text(slide, slot: .reference)
    }

    static func text(_ slide: Slide, slot: ThemeSlotKind) -> String? {
        for element in slide.elements {
            if case .text(let text) = element, text.slot == slot { return text.text }
        }
        return nil
    }

    func makeSlides(
        _ ref: String, verses: [Verse], limit: Int = 220, showReference: Bool = true,
        numbers: VerseNumberStyle = .superscript
    ) -> [Slide] {
        let options = ScriptureLayoutOptions(
            maxCharactersPerSlide: limit, showReference: showReference, verseNumbers: numbers
        )
        return builder.slides(
            for: reference(ref), verses: verses, translationCode: "thu3", translationName: "TT1925", options: options
        )
    }

    @Test("Câu dài 600 ký tự, giới hạn 220: ra 3 trang, không cắt giữa từ")
    func longVerseSplitsIntoThreeSlides() throws {
        let verse = Verse(book: "John", chapter: 3, verse: 16, text: Self.longText)
        let slides = makeSlides("gi 3:16", verses: [verse])
        #expect(slides.count == 3)
        let bodies = slides.compactMap { Self.bodyText($0) }
        #expect(bodies.count == 3)
        for body in bodies {
            #expect(body.count <= 220, "\(body.count) ký tự")
        }
        // Nối lại bằng khoảng trắng ra đúng câu gốc: mọi chỗ cắt đều nằm ở khoảng trắng.
        #expect(bodies.joined(separator: " ") == "¹⁶\u{202F}" + Self.longText)
        // Ưu tiên ranh giới vế câu: mỗi phần trước kết thúc bằng dấu phẩy.
        #expect(bodies.dropLast().allSatisfy { $0.hasSuffix(",") })
        #expect(slides.map { Self.referenceText($0) } == Array(repeating: "Giăng 3:16 (TT1925)", count: 3))
    }

    @Test("id trang tất định giữa hai lần chạy, khác nhau giữa các trang")
    func deterministicIDs() {
        let verse = Verse(book: "John", chapter: 3, verse: 16, text: Self.longText)
        let first = makeSlides("gi 3:16", verses: [verse])
        let second = makeSlides("gi 3:16", verses: [verse])
        #expect(first.map { $0.id } == second.map { $0.id })
        #expect(first.map { $0.elements.map { $0.id } } == second.map { $0.elements.map { $0.id } })
        #expect(Set(first.map { $0.id }).count == first.count)
        #expect(first[0].id == UUID(hashing: "scripture:thu3:John.3.16:0"))
        #expect(first[1].id == UUID(hashing: "scripture:thu3:John.3.16:1"))
    }

    @Test("Gom câu ngắn liên tiếp vào một trang, địa chỉ ghi riêng câu trên trang")
    func groupsShortVerses() {
        let verses = (16...18).map { Verse(book: "John", chapter: 3, verse: $0, text: FakeBible.text("John", 3, $0)) }
        let slides = makeSlides("gi 3:16-18", verses: verses)
        #expect(slides.count == 1)
        #expect(Self.referenceText(slides[0]) == "Giăng 3:16–18 (TT1925)")
        #expect(slides[0].label == "Giăng 3:16–18")
        let body = Self.bodyText(slides[0]) ?? ""
        #expect(body.hasPrefix("¹⁶\u{202F}Lời thử John 3:16"))
        #expect(body.contains(" ¹⁷\u{202F}Lời thử John 3:17"))
        #expect(body.contains(" ¹⁸\u{202F}"))

        let narrow = makeSlides("gi 3:16-18", verses: verses, limit: 130)
        #expect(narrow.count == 2)
        #expect(narrow.map { Self.referenceText($0) } == ["Giăng 3:16–17 (TT1925)", "Giăng 3:18 (TT1925)"])
        for slide in narrow {
            #expect((Self.bodyText(slide) ?? "").count <= 130)
        }
    }

    @Test("Sang chương không liền kề hoặc sách khác thì sang trang mới; vắt chương liền kề thì gom")
    func breaksBetweenPassages() {
        let romans = [
            Verse(book: "Rom", chapter: 8, verse: 28, text: "Câu thử một."),
            Verse(book: "Rom", chapter: 12, verse: 1, text: "Câu thử hai."),
        ]
        let split = makeSlides("ro 8:28; 12:1", verses: romans)
        #expect(split.map { Self.referenceText($0) } == ["Rô-ma 8:28 (TT1925)", "Rô-ma 12:1 (TT1925)"])

        let matthew = [3, 5, 7].map { Verse(book: "Matt", chapter: 5, verse: $0, text: "Câu thử.") }
        let together = makeSlides("mat 5:3,5,7", verses: matthew)
        #expect(together.map { Self.referenceText($0) } == ["Ma-thi-ơ 5:3, 5, 7 (TT1925)"])

        let across = [
            Verse(book: "John", chapter: 3, verse: 36, text: "Câu cuối chương."),
            Verse(book: "John", chapter: 4, verse: 1, text: "Câu đầu chương."),
        ]
        #expect(makeSlides("gi 3:36-4:1", verses: across).map { Self.referenceText($0) } == ["Giăng 3:36–4:1 (TT1925)"])

        let books = [
            Verse(book: "John", chapter: 3, verse: 16, text: "Câu một."),
            Verse(book: "Rom", chapter: 5, verse: 8, text: "Câu hai."),
        ]
        #expect(makeSlides("gi 3:16; ro 5:8", verses: books).count == 2)
    }

    @Test("Tắt địa chỉ và số câu theo tuỳ chọn")
    func options() {
        let verses = [Verse(book: "Ps", chapter: 23, verse: 1, text: "Câu  thử\nxuống dòng.")]
        let plain = makeSlides("thi 23:1", verses: verses, showReference: false, numbers: .none)
        #expect(plain.count == 1)
        #expect(Self.bodyText(plain[0]) == "Câu thử xuống dòng.")
        #expect(Self.referenceText(plain[0]) == nil)
        #expect(makeSlides("thi 23:1", verses: []).isEmpty)

        let settings = Theme.fallback().scripture
        let options = ScriptureLayoutOptions(settings: settings)
        #expect(options.maxCharactersPerSlide == settings.maxCharactersPerSlide)
        #expect(options.showReference == settings.showReference)
        #expect(options.verseNumbers == settings.verseNumbers)
    }

    @Test("Dùng tên viết tắt của bản dịch khi truyền TranslationInfo")
    func translationInfoOverload() {
        let verse = Verse(book: "John", chapter: 3, verse: 16, text: "Câu thử.")
        let slides = builder.slides(
            for: reference("gi 3:16"), verses: [verse], translation: FakeBible.info, options: ScriptureLayoutOptions()
        )
        #expect(Self.referenceText(slides[0]) == "Giăng 3:16 (THU)")
        #expect(slides[0].id == UUID(hashing: "scripture:thu3:John.3.16:0"))
    }

    @Test("Số chỉ số trên")
    func superscriptDigits() {
        #expect(ScriptureSlideBuilder.superscript(16) == "¹⁶")
        #expect(ScriptureSlideBuilder.superscript(150) == "¹⁵⁰")
        #expect(ScriptureSlideBuilder.superscript(789) == "⁷⁸⁹")
    }
}

@Suite("TextSplitter: tách câu dài")
struct TextSplitterTests {
    @Test("Ưu tiên ranh giới vế câu hơn khoảng trắng gần giữa")
    func prefersClauseBoundary() {
        let parts = TextSplitter.split("Một hai ba bốn năm. Sáu bảy tám chín mười một hai", limit: 30)
        #expect(parts == ["Một hai ba bốn năm.", "Sáu bảy tám chín mười một hai"])
    }

    @Test("Không có ranh giới vế câu vừa giới hạn thì tách ở khoảng trắng")
    func fallsBackToSpace() {
        let text = "Một hai ba bốn năm sáu bảy tám chín mười, một hai"
        let parts = TextSplitter.split(text, limit: 30)
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0.count <= 30 })
        #expect(parts.joined(separator: " ") == text)
    }

    @Test("Ranh giới vế câu tính cả ngoặc kép đóng")
    func clauseWithClosingQuote() {
        let parts = TextSplitter.split("Ngài phán: “Hãy đến cùng Ta.” Rồi họ đi theo Ngài ngay", limit: 32)
        #expect(parts.first == "Ngài phán: “Hãy đến cùng Ta.”")
    }

    @Test("Chữ ngắn hơn giới hạn giữ nguyên; một từ dài hơn giới hạn thì đành cắt cứng")
    func edgeCases() {
        #expect(TextSplitter.split("Ngắn.", limit: 30) == ["Ngắn."])
        let word = String(repeating: "a", count: 25)
        let parts = TextSplitter.split(word, limit: 10)
        #expect(parts.joined() == word)
        #expect(parts.allSatisfy { $0.count <= 10 })
    }
}

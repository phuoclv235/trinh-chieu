import Foundation

/// Ô mẫu: khung và kiểu chữ cho một vai trò (thân, tiêu đề, địa chỉ câu).
public struct ThemeSlot: Sendable, Hashable, Codable {
    public var frame: PixelRect
    public var style: TextStyle

    public init(frame: PixelRect, style: TextStyle) {
        self.frame = frame
        self.style = style
    }
}

/// Ba ô mẫu của một mẫu trình bày.
public struct ThemeSlots: Sendable, Hashable, Codable {
    public var body: ThemeSlot
    public var title: ThemeSlot
    public var reference: ThemeSlot

    public init(body: ThemeSlot, title: ThemeSlot, reference: ThemeSlot) {
        self.body = body
        self.title = title
        self.reference = reference
    }

    public subscript(kind: ThemeSlotKind) -> ThemeSlot {
        get {
            switch kind {
            case .body:
                return body
            case .title:
                return title
            case .reference:
                return reference
            }
        }
        set {
            switch kind {
            case .body:
                body = newValue
            case .title:
                title = newValue
            case .reference:
                reference = newValue
            }
        }
    }
}

/// Thiết lập chia trang lời bài hát.
public struct LyricsSettings: Sendable, Hashable, Codable {
    public var maxLinesPerSlide: Int

    public init(maxLinesPerSlide: Int) {
        self.maxLinesPerSlide = maxLinesPerSlide
    }
}

/// Vị trí địa chỉ câu Kinh Thánh trên trang.
public enum ReferencePosition: String, Sendable, Hashable, Codable, CaseIterable {
    case bottom
    case top
}

/// Cách hiện số câu Kinh Thánh.
public enum VerseNumberStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case superscript
    case none
}

/// Thiết lập chia trang Kinh Thánh.
public struct ScriptureSettings: Sendable, Hashable, Codable {
    public var maxCharactersPerSlide: Int
    public var showReference: Bool
    public var referencePosition: ReferencePosition
    public var verseNumbers: VerseNumberStyle

    public init(
        maxCharactersPerSlide: Int, showReference: Bool, referencePosition: ReferencePosition,
        verseNumbers: VerseNumberStyle
    ) {
        self.maxCharactersPerSlide = maxCharactersPerSlide
        self.showReference = showReference
        self.referencePosition = referencePosition
        self.verseNumbers = verseNumbers
    }
}

/// Mẫu trình bày: hình thức áp cho nội dung.
public struct Theme: Sendable, Hashable, Codable, Identifiable {
    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var canvasSize: PixelSize
    public var background: SlideBackground
    public var slots: ThemeSlots
    public var lyrics: LyricsSettings
    public var scripture: ScriptureSettings
    public var transition: TransitionSpec

    public init(
        schemaVersion: Int = DocumentMigration.currentSchemaVersion, id: UUID = UUID(), name: String,
        canvasSize: PixelSize, background: SlideBackground, slots: ThemeSlots, lyrics: LyricsSettings,
        scripture: ScriptureSettings, transition: TransitionSpec
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.canvasSize = canvasSize
        self.background = background
        self.slots = slots
        self.lyrics = lyrics
        self.scripture = scripture
        self.transition = transition
    }

    /// Mẫu tối thiểu dùng khi thư viện chưa có mẫu nào: nền đen, chữ trắng giữa màn, khung vẽ 1920x1080.
    /// Mẫu mặc định thật của thư viện tạo ở T1.5.
    public static func fallback(id: UUID = UUID(), name: String = "Mẫu cơ bản") -> Theme {
        let body = TextStyle(fontWeight: 600, fontSize: 72, autoFit: AutoFit(mode: .shrink, minScale: 0.5))
        let title = TextStyle(fontWeight: 600, fontSize: 48)
        let reference = TextStyle(fontSize: 40, alignment: .right)
        let slots = ThemeSlots(
            body: ThemeSlot(frame: PixelRect(x: 120, y: 140, width: 1680, height: 800), style: body),
            title: ThemeSlot(frame: PixelRect(x: 120, y: 60, width: 1680, height: 80), style: title),
            reference: ThemeSlot(frame: PixelRect(x: 120, y: 960, width: 1680, height: 60), style: reference)
        )
        let scripture = ScriptureSettings(
            maxCharactersPerSlide: 220, showReference: true, referencePosition: .bottom, verseNumbers: .superscript
        )
        return Theme(
            id: id, name: name, canvasSize: .fullHD, background: .color(.black), slots: slots,
            lyrics: LyricsSettings(maxLinesPerSlide: 4), scripture: scripture,
            transition: TransitionSpec(kind: .dissolve, duration: 0.35)
        )
    }
}

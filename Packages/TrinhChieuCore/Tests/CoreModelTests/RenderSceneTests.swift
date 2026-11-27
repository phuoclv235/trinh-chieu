import Foundation
import Testing

@testable import CoreModel

@Suite("RenderScene: Codable cho đồng bộ nhiều máy")
struct RenderSceneTests {
    static func sampleScenes() -> [RenderScene] {
        let canvas = PixelSize.fullHD
        let full = PixelRect(size: canvas)
        let style = ResolvedTextStyle(TextStyle(fontWeight: 600, fontSize: 76, shadow: TextShadow.none))
        let text = TextBlock(
            string: "ĐIỆP KHÚC\nHallelujah", style: style, autoFit: AutoFit(mode: .shrink, minScale: 0.6), maxLines: 4
        )
        let video = VideoRef(
            media: MediaRef(id: "99aa88bb77cc"), loop: true, muted: true, playbackID: fixedID(7),
            startedAt: Date(timeIntervalSince1970: 1_764_151_200.5)
        )
        let moving = RenderItem.video(video, frame: full, fit: .fill)
        let background = RenderLayer(kind: .background, contentID: fixedID(1), items: [moving])
        let band = PixelRect(x: 0, y: 900, width: 1920, height: 180)
        let picture = PixelRect(x: 100, y: 100, width: 640, height: 360)
        let items: [RenderItem] = [
            .color(RGBA(red: 0, green: 0, blue: 0, alpha: 128), frame: band),
            .image(MediaRef(id: "0f1e2d3c4b5a"), frame: picture, fit: .fit),
            .text(text, frame: PixelRect(x: 120, y: 140, width: 1680, height: 800)),
        ]
        let slide = RenderLayer(kind: .slide, contentID: fixedID(2), items: items)
        let dissolve = TransitionSpec(kind: .dissolve, duration: 0.35)
        return [
            RenderScene.empty(canvas: canvas),
            RenderScene(revision: 42, canvasSize: canvas, layers: [background, slide], transition: dissolve),
            RenderScene(revision: UInt64.max, canvasSize: PixelSize(width: 1280, height: 720), layers: [slide]),
        ]
    }

    @Test("Mã hoá rồi giải mã mọi cảnh mẫu ra giá trị bằng nhau")
    func scenesRoundTrip() throws {
        for scene in Self.sampleScenes() {
            let data = try DocumentCoding.encode(scene)
            #expect(try DocumentCoding.decode(RenderScene.self, from: data) == scene)
            let compact = try JSONEncoder().encode(scene)
            #expect(try JSONDecoder().decode(RenderScene.self, from: compact) == scene)
        }
        let publication = ScenePublication(program: Self.sampleScenes()[1], stage: Self.sampleScenes()[2])
        let data = try JSONEncoder().encode(publication)
        #expect(try JSONDecoder().decode(ScenePublication.self, from: data) == publication)
    }

    @Test("Cảnh không chứa đường dẫn tệp")
    func scenesContainNoFilePaths() throws {
        for scene in Self.sampleScenes() {
            let json = String(decoding: try DocumentCoding.encode(scene), as: UTF8.self)
            #expect(!json.contains("file:"))
            #expect(!json.contains("/Users/"))
        }
    }

    @Test("Cảnh trống là nền đen phủ cả khung vẽ, chuyển cảnh tức thì")
    func emptySceneIsBlack() {
        let scene = RenderScene.empty(canvas: PixelSize(width: 1280, height: 720))
        #expect(scene.revision == 0)
        #expect(scene.transition == .cut)
        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].kind == .background)
        #expect(scene.layers[0].items == [.color(.black, frame: PixelRect(x: 0, y: 0, width: 1280, height: 720))])
    }

    @Test("RenderItem lạ thì báo lỗi")
    func unknownItemFails() {
        let json = #"{"type":"hologram","frame":[0,0,1,1]}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RenderItem.self, from: Data(json.utf8))
        }
    }

    @Test("ResolvedTextStyle lấy đủ trường vẽ từ TextStyle")
    func resolvedStyleFromTextStyle() {
        let style = TextStyle(fontFamily: "Inter", fontWeight: 500, fontSize: 30, color: .black, alignment: .right)
        let resolved = ResolvedTextStyle(style)
        #expect(resolved.fontFamily == "Inter")
        #expect(resolved.fontWeight == 500)
        #expect(resolved.fontSize == 30)
        #expect(resolved.color == .black)
        #expect(resolved.alignment == .right)
        #expect(resolved.lineHeight == style.lineHeight)
    }
}

@Suite("Nhật ký và log")
struct LoggingTests {
    @Test("LogSink trong bộ nhớ giữ đúng thứ tự")
    func inMemoryLogSink() {
        let sink = InMemoryLogSink()
        sink.log(.info, "Bắt đầu", category: "show")
        sink.log(LogEntry(level: .error, category: "media", message: "Mất tệp"))
        NullLogSink().log(.debug, "bỏ qua", category: "x")
        #expect(sink.entries.map(\.message) == ["Bắt đầu", "Mất tệp"])
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.warning < LogLevel.error)
        #expect(LogLevel.allCases.sorted() == [.debug, .info, .warning, .error])
    }

    @MainActor @Test("Nhật ký buổi nhóm trong bộ nhớ ghi theo thứ tự")
    func inMemoryServiceLog() {
        let log = InMemoryServiceLog()
        let now = Date(timeIntervalSince1970: 0)
        log.record(ServiceLogEvent(at: now, type: .freeze, enabled: true))
        log.record(ServiceLogEvent(at: now, type: .clearAll))
        #expect(log.events.map(\.type) == [.freeze, .clearAll])
    }
}

import CoreGraphics
import CoreModel
import Foundation
import Testing

@testable import RenderEngine

/// So ảnh dựng với ảnh chuẩn `Fixtures/golden/<tên>.png`.
///
/// - `TRINHCHIEU_UPDATE_GOLDEN=1` (qua `scripts/update-golden.sh`): ghi đè ảnh chuẩn, không so.
/// - Ảnh lệch hoặc thiếu: ghi ảnh thật vào `TRINHCHIEU_GOLDEN_OUTPUT` (mặc định thư mục tạm) để xem.
/// - Thư mục ảnh chuẩn còn trống (chưa dựng lần đầu trên Mac): chỉ kiểm tính chất, bỏ qua bước so.
enum Golden {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/golden", isDirectory: true)

    /// Sai số trung bình phải dưới 1%.
    static let meanTolerance = 0.01
    /// Không điểm ảnh nào lệch quá 8% trên một kênh (8% của 255).
    static let channelTolerance = 20

    static var updating: Bool {
        ProcessInfo.processInfo.environment["TRINHCHIEU_UPDATE_GOLDEN"] == "1"
    }

    static var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["TRINHCHIEU_GOLDEN_OUTPUT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("TrinhChieuGolden", isDirectory: true)
    }

    static var hasReferenceImages: Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.contains { $0.hasSuffix(".png") }
    }

    static func check(_ name: String, _ image: CGImage, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = directory.appendingPathComponent("\(name).png")
        if updating {
            try PNG.write(image, to: url)
            return
        }
        let actualURL = outputDirectory.appendingPathComponent("\(name).png")
        guard let golden = PNG.read(url) else {
            try PNG.write(image, to: actualURL)
            if hasReferenceImages {
                Issue.record(
                    "Thiếu ảnh chuẩn \(name).png. Chạy scripts/update-golden.sh. Ảnh thật: \(actualURL.path)",
                    sourceLocation: sourceLocation
                )
            }
            return
        }
        guard let difference = PixelImage(image).difference(to: PixelImage(golden)) else {
            try PNG.write(image, to: actualURL)
            Issue.record(
                "Ảnh \(name) khác kích thước ảnh chuẩn. Ảnh thật: \(actualURL.path)",
                sourceLocation: sourceLocation
            )
            return
        }
        if difference.mean >= meanTolerance || difference.max > channelTolerance {
            try PNG.write(image, to: actualURL)
            let mean = String(format: "%.3f%%", difference.mean * 100)
            let detail = "trung bình \(mean), lớn nhất \(difference.max)/255"
            Issue.record(
                "Ảnh \(name) lệch ảnh chuẩn: \(detail). Ảnh thật: \(actualURL.path)",
                sourceLocation: sourceLocation
            )
        }
    }
}

/// Ảnh mẫu cho test: 800x400 (2:1), nửa trái đỏ, nửa phải xanh dương. Test tự tạo, không lưu trong repo.
enum TestMedia {
    static let splitID: MediaID = "anh-hai-mau"
    static let missingID: MediaID = "anh-khong-co"

    static let locator: DictionaryMediaLocator = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrinhChieuRenderTests-\(ProcessInfo.processInfo.processIdentifier)")
        let url = directory.appendingPathComponent("hai-mau.png")
        let image = PNG.makeSplitImage(width: 800, height: 400, left: SceneKit.red, right: SceneKit.blue)
        try? PNG.write(image, to: url)
        return DictionaryMediaLocator(urls: [splitID: url])
    }()
}

@Suite("Test ảnh (renderOffscreen 960x540)", .enabled(if: hasMetal))
struct GoldenSceneTests {
    static let size = PixelSize(width: 960, height: 540)
    static let verse = TextRendererTests.verse

    private func render(
        _ name: String,
        _ scene: RenderScene,
        after previous: RenderScene? = nil,
        at time: Double = 0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> PixelImage {
        let image = try await RenderEngine.renderOffscreen(
            scene,
            after: previous,
            size: Self.size,
            at: time,
            mediaLocator: TestMedia.locator
        )
        #expect(image.width == 960, sourceLocation: sourceLocation)
        #expect(image.height == 540, sourceLocation: sourceLocation)
        try Golden.check(name, image, sourceLocation: sourceLocation)
        return PixelImage(image)
    }

    private func textScene(_ layer: RenderLayer) -> RenderScene {
        SceneKit.scene([SceneKit.background(SceneKit.navy), layer])
    }

    // MARK: - Màu và lớp

    @Test("Cảnh trống: đen toàn màn")
    func emptyScene() async throws {
        let image = try await render("nen-den", .empty(canvas: SceneKit.canvas))
        #expect(image.color(0, 0).isClose(to: .black))
        #expect(image.color(480, 270).isClose(to: .black))
        #expect(image.color(959, 539).isClose(to: .black))
    }

    @Test("Nền một màu phủ kín")
    func solidBackground() async throws {
        let image = try await render("nen-mau", SceneKit.scene([SceneKit.background(SceneKit.navy)]))
        #expect(image.color(0, 0).isClose(to: SceneKit.navy))
        #expect(image.color(959, 539).isClose(to: SceneKit.navy))
    }

    @Test("Lớp màu bán trong suốt trộn với lớp dưới")
    func translucentLayer() async throws {
        let overlay = RenderLayer(
            kind: .slide,
            contentID: SceneKit.id(50),
            items: [
                .color(
                    RGBA(red: 0, green: 0, blue: 0, alpha: 128),
                    frame: PixelRect(x: 480, y: 270, width: 960, height: 540)
                )
            ]
        )
        let image = try await render("lop-trong-suot", SceneKit.scene([SceneKit.background(.white), overlay]))
        #expect(image.color(480, 270).isClose(to: RGBA(red: 127, green: 127, blue: 127), tolerance: 3))
        #expect(image.color(100, 100).isClose(to: .white))
        #expect(image.color(860, 470).isClose(to: .white))
    }

    // MARK: - Chữ

    @Test("Chữ tiếng Việt nhiều dấu chồng, 4 dòng, giữa khung")
    func vietnameseFourLines() async throws {
        let image = try await render("chu-viet-4-dong", textScene(SceneKit.text(Self.verse)))
        let ink = try #require(image.inkBounds(background: SceneKit.navy))
        #expect(ink.minX >= 50)
        #expect(ink.maxX <= 910)
        #expect(ink.minY >= 50)
        #expect(ink.maxY <= 490)
        #expect(abs(ink.midY - 270) < 30)
        #expect(abs(ink.midX - 480) < 30)
    }

    @Test("Co chữ khi tràn: vẫn nằm trong khung")
    func shrinkWhenOverflowing() async throws {
        let long = Array(repeating: Self.verse, count: 3).joined(separator: "\n")
        let layer = SceneKit.text(long, autoFit: AutoFit(mode: .shrink, minScale: 0.3))
        let image = try await render("chu-co-khi-tran", textScene(layer))
        let ink = try #require(image.inkBounds(background: SceneKit.navy))
        #expect(ink.minY >= 50)
        #expect(ink.maxY <= 490)
    }

    @Test("Co tới minScale vẫn tràn: cắt dòng cuối, không tràn khỏi khung")
    func truncateLastLine() async throws {
        let long = Array(repeating: Self.verse, count: 6).joined(separator: "\n")
        let layer = SceneKit.text(long, autoFit: AutoFit(mode: .shrink, minScale: 0.9))
        let image = try await render("chu-cat-dong-cuoi", textScene(layer))
        let ink = try #require(image.inkBounds(background: SceneKit.navy))
        #expect(ink.minY >= 50)
        #expect(ink.maxY <= 490)
    }

    @Test("maxLines = 2 chỉ vẽ 2 dòng")
    func maxTwoLines() async throws {
        let image = try await render("chu-toi-da-2-dong", textScene(SceneKit.text(Self.verse, maxLines: 2)))
        let ink = try #require(image.inkBounds(background: SceneKit.navy))
        #expect(ink.height < 140)
    }

    @Test("Căn trái, căn trên")
    func alignTopLeft() async throws {
        let style = SceneKit.style(alignment: .left, vertical: .top)
        let image = try await render("chu-can-trai-tren", textScene(SceneKit.text(Self.verse, style: style)))
        let ink = try #require(image.inkBounds(background: SceneKit.navy))
        #expect(ink.minX >= 55 && ink.minX <= 80)
        #expect(ink.minY >= 50 && ink.minY <= 90)
    }

    @Test("Căn phải, căn dưới")
    func alignBottomRight() async throws {
        let style = SceneKit.style(alignment: .right, vertical: .bottom)
        let image = try await render("chu-can-phai-duoi", textScene(SceneKit.text(Self.verse, style: style)))
        let ink = try #require(image.inkBounds(background: SceneKit.navy))
        #expect(ink.maxX >= 880 && ink.maxX <= 905)
        #expect(ink.maxY >= 440 && ink.maxY <= 485)
    }

    @Test("Giãn dòng và giãn chữ làm khối chữ to ra")
    func lineAndLetterSpacing() async throws {
        let normal = try await render("chu-viet-4-dong", textScene(SceneKit.text(Self.verse)))
        let style = SceneKit.style(lineHeight: 1.6, letterSpacing: 8)
        let spaced = try await render("chu-gian-dong-gian-chu", textScene(SceneKit.text(Self.verse, style: style)))
        let normalInk = try #require(normal.inkBounds(background: SceneKit.navy))
        let spacedInk = try #require(spaced.inkBounds(background: SceneKit.navy))
        #expect(spacedInk.height > normalInk.height + 40)
        #expect(spacedInk.width > normalInk.width + 40)
    }

    @Test("Viền chữ màu đen bao ngoài nét")
    func strokedText() async throws {
        let style = SceneKit.style(stroke: TextStroke(color: .black, width: 6))
        let image = try await render("chu-vien", textScene(SceneKit.text(Self.verse, style: style)))
        var dark = 0
        for y in 0..<image.height {
            for x in 0..<image.width where image.color(x, y).distance(to: .black) <= 30 {
                dark += 1
            }
        }
        #expect(dark > 500)
    }

    // MARK: - Ảnh

    private func imageScene(fit: ContentFit) -> RenderScene {
        let background = RenderLayer(
            kind: .background,
            contentID: SceneKit.id(10),
            items: [
                .color(SceneKit.green, frame: PixelRect(size: SceneKit.canvas)),
                .image(MediaRef(id: TestMedia.splitID), frame: PixelRect(size: SceneKit.canvas), fit: fit),
            ]
        )
        return SceneKit.scene([background])
    }

    @Test("Ảnh fit: giữ tỉ lệ, chừa hai dải nền trên dưới")
    func imageFit() async throws {
        let image = try await render("anh-fit", imageScene(fit: .fit))
        #expect(image.color(480, 10).isClose(to: SceneKit.green))
        #expect(image.color(480, 530).isClose(to: SceneKit.green))
        #expect(image.color(240, 270).isClose(to: SceneKit.red))
        #expect(image.color(720, 270).isClose(to: SceneKit.blue))
    }

    @Test("Ảnh fill: phủ kín, cắt hai bên")
    func imageFill() async throws {
        let image = try await render("anh-fill", imageScene(fit: .fill))
        #expect(image.color(5, 5).isClose(to: SceneKit.red))
        #expect(image.color(954, 534).isClose(to: SceneKit.blue))
        #expect(image.color(240, 2).isClose(to: SceneKit.red))
    }

    @Test("Ảnh stretch: kéo giãn phủ kín")
    func imageStretch() async throws {
        let image = try await render("anh-stretch", imageScene(fit: .stretch))
        #expect(image.color(240, 2).isClose(to: SceneKit.red))
        #expect(image.color(720, 537).isClose(to: SceneKit.blue))
    }

    @Test("Ảnh mất: không vẽ gì thay, lớp dưới vẫn hiện")
    func missingImage() async throws {
        let background = RenderLayer(
            kind: .background,
            contentID: SceneKit.id(11),
            items: [
                .color(SceneKit.navy, frame: PixelRect(size: SceneKit.canvas)),
                .image(MediaRef(id: TestMedia.missingID), frame: PixelRect(size: SceneKit.canvas), fit: .fill),
            ]
        )
        let image = try await render("anh-mat", SceneKit.scene([background]))
        #expect(image.color(480, 270).isClose(to: SceneKit.navy))
    }

    // MARK: - Tỉ lệ khung vẽ

    @Test("Khung 4:3 trên đầu ra 16:9: nằm giữa, hai bên tô màu nền")
    func fourByThreeOnSixteenByNine() async throws {
        let canvas = PixelSize(width: 1440, height: 1080)
        let content = RenderLayer(
            kind: .slide,
            contentID: SceneKit.id(60),
            items: [.color(.white, frame: PixelRect(size: canvas))]
        )
        let scene = SceneKit.scene([SceneKit.background(SceneKit.green, canvas: canvas), content], canvas: canvas)
        let image = try await render("ti-le-4-3-tren-16-9", scene)
        #expect(image.color(60, 270).isClose(to: SceneKit.green))
        #expect(image.color(900, 270).isClose(to: SceneKit.green))
        #expect(image.color(480, 270).isClose(to: .white))
        #expect(image.color(125, 270).isClose(to: .white))
    }

    @Test("Khung 4:3 có nền ảnh: phần thừa tô đen")
    func fourByThreeImageBackground() async throws {
        let canvas = PixelSize(width: 1440, height: 1080)
        let background = RenderLayer(
            kind: .background,
            contentID: SceneKit.id(61),
            items: [.image(MediaRef(id: TestMedia.splitID), frame: PixelRect(size: canvas), fit: .fill)]
        )
        let image = try await render("ti-le-4-3-nen-anh", SceneKit.scene([background], canvas: canvas))
        #expect(image.color(60, 270).isClose(to: .black))
        #expect(image.color(200, 270).isClose(to: SceneKit.red))
        #expect(image.color(760, 270).isClose(to: SceneKit.blue))
    }

    @Test("Khung 4:3, nền màu đang hoà tan: phần thừa đổi màu cùng nhịp")
    func letterboxFollowsDissolve() async throws {
        let canvas = PixelSize(width: 1440, height: 1080)
        let from = SceneKit.scene([SceneKit.background(SceneKit.red, id: 1, canvas: canvas)], canvas: canvas)
        let to = SceneKit.scene(
            [SceneKit.background(SceneKit.blue, id: 2, canvas: canvas)],
            canvas: canvas,
            transition: TransitionSpec(kind: .dissolve, duration: 1)
        )
        let image = try await render("ti-le-4-3-hoa-tan", to, after: from, at: 0.5)
        let middle = RGBA(red: 128, green: 0, blue: 128)
        #expect(image.color(60, 270).isClose(to: middle, tolerance: 3))
        #expect(image.color(480, 270).isClose(to: middle, tolerance: 3))
    }

    // MARK: - Chuyển cảnh

    private let dissolve = TransitionSpec(kind: .dissolve, duration: 1)

    @Test("Hoà tan ở t = 0.5: trộn đều hai nền")
    func dissolveHalfway() async throws {
        let from = SceneKit.scene([SceneKit.background(SceneKit.red, id: 1)])
        let to = SceneKit.scene([SceneKit.background(SceneKit.blue, id: 2)], transition: dissolve)
        let image = try await render("hoa-tan-giua", to, after: from, at: 0.5)
        #expect(image.color(480, 270).isClose(to: RGBA(red: 128, green: 0, blue: 128), tolerance: 3))
    }

    @Test("Hoà tan ở t = 0: còn nguyên cảnh cũ; hết thời lượng: toàn cảnh mới")
    func dissolveEnds() async throws {
        let from = SceneKit.scene([SceneKit.background(SceneKit.red, id: 1)])
        let to = SceneKit.scene([SceneKit.background(SceneKit.blue, id: 2)], transition: dissolve)
        let start = try await render("hoa-tan-bat-dau", to, after: from, at: 0)
        let end = try await render("hoa-tan-xong", to, after: from, at: 1.5)
        #expect(start.color(480, 270).isClose(to: SceneKit.red))
        #expect(end.color(480, 270).isClose(to: SceneKit.blue))
    }

    @Test("Cắt: hiện cảnh mới ngay")
    func cutIsImmediate() async throws {
        let from = SceneKit.scene([SceneKit.background(SceneKit.red, id: 1)])
        let to = SceneKit.scene([SceneKit.background(SceneKit.blue, id: 2)])
        let image = try await render("cat-ngay", to, after: from, at: 0)
        #expect(image.color(480, 270).isClose(to: SceneKit.blue))
    }

    @Test("Đổi chữ trên cùng nền: nền không hoà tan, không nháy")
    func textChangeKeepsBackground() async throws {
        let background = SceneKit.background(SceneKit.navy, id: 1)
        let from = SceneKit.scene([background, SceneKit.text("Hãy hát mừng Đức Giê-hô-va", id: 100)])
        let to = SceneKit.scene(
            [background, SceneKit.text("hỡi cả trái đất", id: 101)],
            transition: dissolve
        )
        let image = try await render("hoa-tan-chi-doi-chu", to, after: from, at: 0.5)
        #expect(image.color(5, 5).isClose(to: SceneKit.navy, tolerance: 0))
        #expect(image.color(954, 534).isClose(to: SceneKit.navy, tolerance: 0))
        #expect(image.inkBounds(background: SceneKit.navy) != nil)
    }

    @Test("Lớp chữ biến mất với hoà tan: mờ dần")
    func layerFadesOut() async throws {
        let background = SceneKit.background(SceneKit.navy, id: 1)
        let from = SceneKit.scene([background, SceneKit.text("A-men", id: 100)])
        let to = SceneKit.scene([background], transition: dissolve)
        let image = try await render("lop-bien-mat", to, after: from, at: 0.5)
        var brightest = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                brightest = max(brightest, Int(image.color(x, y).red))
            }
        }
        #expect(brightest > 100)
        #expect(brightest < 200)
    }
}

import CoreGraphics
import Foundation
import Metal
import Testing

@testable import RenderEngine

@Test("RenderEngine: khung chạy được")
func renderEngineFrameworkRuns() {
    #expect(RenderEngineModule.name == "RenderEngine")
}

@Test("RenderEngine: shader được đóng vào bundle")
func renderEngineShadersAreBundled() {
    // `swift build` chép tệp .metal vào bundle, còn Xcode biên dịch thành default.metallib.
    let metallib = Bundle.module.url(forResource: "default", withExtension: "metallib")
    let source = Bundle.module.url(forResource: "Compose", withExtension: "metal")
    #expect(metallib != nil || source != nil)
}

@Suite("CanvasLayout")
struct CanvasLayoutTests {
    @Test("Khung 16:9 trên màn 16:9 phủ kín, không lề")
    func sameAspect() {
        let layout = CanvasLayout(
            canvasSize: CGSize(width: 1920, height: 1080),
            targetSize: CGSize(width: 3840, height: 2160)
        )
        #expect(layout.scale == 2)
        #expect(layout.offset == .zero)
        let rect = layout.pixelRect(CGRect(x: 10, y: 20, width: 30, height: 40))
        #expect(rect == CGRect(x: 20, y: 40, width: 60, height: 80))
    }

    @Test("Khung 16:9 trên màn 16:10 căn giữa theo chiều dọc")
    func letterbox() {
        let layout = CanvasLayout(
            canvasSize: CGSize(width: 1920, height: 1080),
            targetSize: CGSize(width: 1920, height: 1200)
        )
        #expect(layout.scale == 1)
        #expect(layout.offset == CGPoint(x: 0, y: 60))
        let size = layout.pixelSize(CGSize(width: 1680, height: 640))
        #expect(size.width == 1680)
        #expect(size.height == 640)
    }

    @Test("fill giữ tỉ lệ: video 16:9 vào khung vuông cắt hai bên")
    func fillCropsSides() {
        let video = CGSize(width: 1920, height: 1080)
        let uv = fillUVRect(textureSize: video, frameSize: CGSize(width: 100, height: 100))
        #expect(abs(uv.width - 1080.0 / 1920.0) < 0.0001)
        #expect(uv.height == 1)
        #expect(abs(uv.minX - (1 - uv.width) / 2) < 0.0001)
        #expect(uv.minY == 0)
    }

    @Test("Bố cục QuadParams khớp shader (48 byte)")
    func quadParamsLayout() {
        #expect(MemoryLayout<QuadParams>.stride == 48)
    }
}

@Suite("SceneMailbox")
struct SceneMailboxTests {
    @Test("Chỉ giữ cảnh mới nhất, số hiệu tăng dần")
    func keepsLatest() {
        let mailbox = SceneMailbox<String>()
        #expect(mailbox.latest() == nil)
        #expect(mailbox.post("một", at: 1) == 1)
        #expect(mailbox.post("hai", at: 2) == 2)
        let latest = mailbox.latest()
        #expect(latest?.scene == "hai")
        #expect(latest?.revision == 2)
        #expect(latest?.postedAt == 2)
    }

    @Test("Gửi đồng thời từ nhiều luồng không mất số hiệu")
    func concurrentPosts() async {
        let mailbox = SceneMailbox<Int>()
        await withTaskGroup(of: Void.self) { group in
            for value in 0..<200 {
                group.addTask {
                    _ = mailbox.post(value)
                }
            }
        }
        #expect(mailbox.latest()?.revision == 200)
    }
}

@Suite("FrameStats")
struct FrameStatsTests {
    @Test("Đếm khung rớt: khoảng cách hơn 1.5 chu kỳ và khung không lên màn")
    func countsDrops() {
        let period = 1.0 / 60
        let stats = FrameStats(label: "thu", nominalPeriod: period)
        stats.recordPresented(100, now: 100)  // chưa ghi: bị bỏ qua
        stats.startRecording(at: 100)
        var time = 100.0
        for _ in 0..<10 {
            time += period
            stats.recordPresented(time, now: time)
        }
        time += period * 2  // trễ một khung
        stats.recordPresented(time, now: time)
        stats.recordPresented(0, now: time + period)  // không lên màn
        time += period * 2  // khoảng trống của khung không lên màn: không đếm lần hai
        stats.recordPresented(time, now: time)
        stats.recordSceneLatency(0.02)
        stats.recordGPUTime(0.003)
        stats.stopRecording(at: time)

        let snapshot = stats.snapshot(now: time)
        #expect(snapshot.framesPresented == 12)
        #expect(snapshot.lateFrames == 1)
        #expect(snapshot.framesNotPresented == 1)
        #expect(snapshot.droppedFrames == 2)
        #expect(snapshot.dropsPerMinute == [2])
        #expect(snapshot.sceneLatencies == [0.02])
        #expect(snapshot.gpuTimes == [0.003])
    }

    @Test("Khoảng dừng dài đếm đủ số nhịp bị bỏ lỡ")
    func longPauseCountsEveryMissedRefresh() {
        let period = 1.0 / 60
        let stats = FrameStats(label: "thu", nominalPeriod: period)
        stats.startRecording(at: 10)
        stats.recordPresented(10 + period, now: 10 + period)
        stats.recordPresented(10 + period * 6, now: 10 + period * 6)  // bỏ lỡ 4 nhịp
        let snapshot = stats.snapshot(now: 11)
        #expect(snapshot.lateFrames == 4)
        #expect(snapshot.droppedFrames == 4)
    }

    @Test("Khung không lên màn giữa khoảng dừng dài: vẫn đếm phần nhịp còn lại")
    func notPresentedInsideLongPause() {
        let period = 1.0 / 60
        let stats = FrameStats(label: "thu", nominalPeriod: period)
        stats.startRecording(at: 10)
        stats.recordPresented(10 + period, now: 10 + period)
        stats.recordPresented(0, now: 10 + period * 2)  // không lên màn
        stats.recordPresented(10 + period * 6, now: 10 + period * 6)  // tổng cộng bỏ lỡ 4 nhịp
        let snapshot = stats.snapshot(now: 11)
        #expect(snapshot.framesNotPresented == 1)
        #expect(snapshot.lateFrames == 3)
        #expect(snapshot.droppedFrames == 4)
    }

    @Test("Khoảng dừng vắt qua ranh giới phút: nhịp bỏ lỡ xếp vào đúng phút")
    func pauseAcrossMinuteBoundary() {
        let period = 1.0 / 60
        let stats = FrameStats(label: "thu", nominalPeriod: period)
        stats.startRecording(at: 0)
        let before = 60 - period * 1.5
        stats.recordPresented(before, now: before)
        stats.recordPresented(before + period * 5, now: before + period * 5)  // bỏ lỡ 4 nhịp
        let snapshot = stats.snapshot(now: 61)
        #expect(snapshot.dropsPerMinute == [1, 3])
    }

    @Test("Ghi ba mốc thời gian và nhật ký khung rớt")
    func frameTimingAndDropLog() {
        let period = 1.0 / 60
        let stats = FrameStats(label: "thu", nominalPeriod: period)
        stats.startRecording(at: 10)
        stats.recordFrameTiming(callback: 10, target: 10.03, presented: 10.04)
        stats.recordFrameTiming(callback: 10.1, target: 10.13, presented: 0)  // không lên màn
        stats.recordPresented(10 + period, now: 10 + period)
        stats.recordPresented(0, now: 10.5)
        stats.recordPresented(10 + period * 5, now: 10 + period * 5)  // khoảng 4 chu kỳ, trừ 1 khung không lên
        let snapshot = stats.snapshot(now: 11)
        #expect(snapshot.callToTarget.count == 2)
        #expect(snapshot.targetToPresented.count == 1)
        #expect(abs(snapshot.pipelineLatencies[0] - 0.04) < 1e-9)
        #expect(snapshot.dropEvents.count == 2)
        #expect(snapshot.dropEvents[0].kind == .notPresented)
        #expect(snapshot.dropEvents[1].kind == .late)
        #expect(snapshot.dropEvents[1].count == 2)
    }

    @Test("Ghi thời gian lần gọi vẽ, lần gọi lâu và chuỗi đường ống theo 10 giây")
    func callbackTimingAndBuckets() {
        let stats = FrameStats(label: "thu", nominalPeriod: 1.0 / 60)
        stats.startRecording(at: 100)
        stats.recordCallback(start: 100.0, encodeEnd: 100.001, end: 100.002)
        stats.recordCallback(start: 100.016, encodeEnd: 100.017, end: 100.026)  // lâu 10 ms
        stats.recordFrameTiming(callback: 100.0, target: 100.033, presented: 100.033)
        stats.recordFrameTiming(callback: 112.0, target: 112.05, presented: 112.05)
        let snapshot = stats.snapshot(now: 113)
        #expect(snapshot.callbackDurations.count == 2)
        #expect(snapshot.callbackIntervals.count == 1)
        #expect(abs(snapshot.callbackIntervals[0] - 0.016) < 1e-9)
        #expect(snapshot.slowCallbacks.count == 1)
        #expect(abs(snapshot.slowCallbacks[0].commit - 0.009) < 1e-9)
        #expect(snapshot.callToTargetBuckets.count == 2)
        #expect(snapshot.recordingStart == 100)
    }

    @Test("Phân vị theo hạng gần nhất")
    func percentile() {
        let values = (1...100).map(Double.init)
        #expect(Percentile.value(values, 0.95) == 95)
        #expect(Percentile.value(values, 0.99) == 99)
        #expect(Percentile.value([], 0.5) == 0)
        #expect(Percentile.mean([1, 2, 3]) == 2)
    }
}

@Suite("TextRasterizer")
struct TextRasterizerTests {
    let style = TextStyle(fontSize: 72, strokeWidthPercent: 4)

    @Test("Dấu chồng ở dòng trên cùng không bị cắt")
    func stackedDiacriticsNotClipped() throws {
        let text = ["Ẩn náu nơi Đấng Chí Cao,", "Người, Đấng, muôn", "Ở dưới bóng Đấng Toàn Năng,", "Ngài"]
            .joined(separator: "\n")
        let bitmap = TextRasterizer.rasterize(text, style: style, width: 1680, height: 640, scale: 1)
        let rows = try #require(bitmap.inkRows())
        // Có khoảng trống phía trên và phía dưới: không nét nào chạm mép ảnh.
        #expect(rows.lowerBound > 0)
        #expect(rows.upperBound < bitmap.height - 1)
    }

    @Test("Dấu của chữ hoa vẽ cao hơn đỉnh chữ hoa không dấu")
    func diacriticDrawnAboveCapital() throws {
        let plain = TextRasterizer.rasterize("A", style: style, width: 400, height: 300, scale: 1)
        let marked = TextRasterizer.rasterize("Ẩ", style: style, width: 400, height: 300, scale: 1)
        let plainRows = try #require(plain.inkRows())
        let markedRows = try #require(marked.inkRows())
        let plainHeight = plainRows.upperBound - plainRows.lowerBound
        let markedHeight = markedRows.upperBound - markedRows.lowerBound
        #expect(markedHeight > plainHeight)
        #expect(markedRows.lowerBound > 0)
    }

    @Test("Viền nằm ngoài nét: phần tô trắng không bị viền ăn vào")
    func strokeOutsideGlyph() {
        let text = "Ẩn náu nơi Đấng Chí Cao, Người"
        let plainStyle = TextStyle(fontSize: 72, strokeWidthPercent: 0)
        let plain = TextRasterizer.rasterize(text, style: plainStyle, width: 1400, height: 200, scale: 1)
        let stroked = TextRasterizer.rasterize(text, style: style, width: 1400, height: 200, scale: 1)
        let plainFill = Self.opaqueWhitePixels(plain)
        let strokedFill = Self.opaqueWhitePixels(stroked)
        #expect(plainFill > 0)
        // Phần tô gần như giữ nguyên (sai khác do khử răng cưa ở mép).
        #expect(Double(strokedFill) >= Double(plainFill) * 0.9)
        // Có viền đen bao ngoài.
        #expect(Self.opaqueDarkPixels(stroked) > plainFill / 10)
    }

    private static func opaqueWhitePixels(_ bitmap: BGRABitmap) -> Int {
        var count = 0
        for index in stride(from: 0, to: bitmap.pixels.count, by: 4)
        where bitmap.pixels[index + 3] == 255 && bitmap.pixels[index + 2] >= 250 {
            count += 1
        }
        return count
    }

    private static func opaqueDarkPixels(_ bitmap: BGRABitmap) -> Int {
        var count = 0
        for index in stride(from: 0, to: bitmap.pixels.count, by: 4)
        where bitmap.pixels[index + 3] == 255 && bitmap.pixels[index + 2] <= 5 {
            count += 1
        }
        return count
    }

    @Test("Chuỗi tổ hợp (NFD) cho cùng ảnh với chuỗi dựng sẵn (NFC)")
    func normalizesToNFC() {
        let composed = "Người"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        let first = TextRasterizer.rasterize(composed, style: style, width: 400, height: 200, scale: 1)
        let second = TextRasterizer.rasterize(decomposed, style: style, width: 400, height: 200, scale: 1)
        #expect(first.pixels == second.pixels)
    }
}

@Suite("GPU", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct GPUTests {
    @Test("Hoà tan ở t = 0.5 trộn đều hai texture")
    func dissolveHalfway() throws {
        let gpu = try GPUContext()
        let compositor = try Compositor(gpu: gpu)
        let red = try #require(Self.solidTexture(gpu: gpu, bgra: [0, 0, 255, 255]))
        let blue = try #require(Self.solidTexture(gpu: gpu, bgra: [255, 0, 0, 255]))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 8,
            height: 8,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let target = try #require(gpu.device.makeTexture(descriptor: descriptor))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        let commandBuffer = try #require(gpu.commandQueue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
        compositor.drawDissolve(
            encoder,
            from: red,
            to: blue,
            t: 0.5,
            rect: CGRect(x: 0, y: 0, width: 8, height: 8),
            targetSize: CGSize(width: 8, height: 8)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixel = [UInt8](repeating: 0, count: 4)
        target.getBytes(&pixel, bytesPerRow: 8 * 4, from: MTLRegionMake2D(4, 4, 1, 1), mipmapLevel: 0)
        // BGRA: xanh dương và đỏ mỗi bên khoảng một nửa.
        #expect(abs(Int(pixel[0]) - 128) <= 2)
        #expect(pixel[1] <= 2)
        #expect(abs(Int(pixel[2]) - 128) <= 2)
        #expect(pixel[3] == 255)
    }

    private static func solidTexture(gpu: GPUContext, bgra: [UInt8]) -> (any MTLTexture)? {
        let pixels = Array([[UInt8]](repeating: bgra, count: 4 * 4).joined())
        let bitmap = BGRABitmap(width: 4, height: 4, bytesPerRow: 16, pixels: pixels)
        return TextRasterizer.makeTexture(bitmap, device: gpu.device)
    }
}

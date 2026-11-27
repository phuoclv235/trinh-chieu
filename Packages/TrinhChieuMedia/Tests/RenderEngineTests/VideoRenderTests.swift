import AVFoundation
import CoreGraphics
import CoreModel
import CoreVideo
import Foundation
import Testing

@testable import RenderEngine

/// Tệp video mẫu 2 giây do test tự tạo bằng `AVAssetWriter`: giây đầu màu đỏ, giây sau màu xanh dương.
enum TestVideo {
    static let id: MediaID = "video-hai-giay"
    static let missingID: MediaID = "video-khong-co"
    static let size = (width: 320, height: 180)
    static let framesPerSecond: Int32 = 30

    /// Tạo tệp (một lần cho mọi test) rồi trả bộ tìm media có cả ảnh mẫu lẫn video.
    static func locator() async throws -> DictionaryMediaLocator {
        let url = try await shared.url()
        var urls = TestMedia.locator.urls
        urls[id] = url
        return DictionaryMediaLocator(urls: urls)
    }

    private static let shared = Maker()

    private actor Maker {
        private var made: URL?

        func url() async throws -> URL {
            if let made { return made }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TrinhChieuVideoTest-\(UUID().uuidString).mov")
            try await TestVideo.write(to: url)
            made = url
            return url
        }
    }

    static func write(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let total = Int(framesPerSecond) * 2
        for index in 0..<total {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let color = index < Int(framesPerSecond) ? SceneKit.red : SceneKit.blue
            guard let buffer = makeBuffer(color: color, pool: adaptor.pixelBufferPool) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let time = CMTime(value: CMTimeValue(index), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    private static func makeBuffer(color: RGBA, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        } else {
            CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = color.blue
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.red
                pixels[offset + 3] = 255
            }
        }
        return buffer
    }

    static func ref(_ media: MediaID = id, loop: Bool = true) -> VideoRef {
        VideoRef(
            media: MediaRef(id: media),
            loop: loop,
            muted: true,
            playbackID: SceneKit.id(900),
            startedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func scene(_ media: MediaID = id, loop: Bool = true) -> RenderScene {
        let video = RenderLayer(
            kind: .background,
            contentID: SceneKit.id(2),
            items: [.video(ref(media, loop: loop), frame: PixelRect(size: SceneKit.canvas), fit: .fill)]
        )
        return SceneKit.scene([video, SceneKit.text("Video", id: 100)])
    }
}

@Suite("Video trong renderOffscreen", .enabled(if: hasMetal))
struct VideoRenderTests {
    static let size = PixelSize(width: 960, height: 540)

    private func render(_ scene: RenderScene, at time: Double) async throws -> PixelImage {
        let locator = try await TestVideo.locator()
        let image = try await RenderEngine.renderOffscreen(scene, size: Self.size, at: time, mediaLocator: locator)
        return PixelImage(image)
    }

    @Test("Video ở 0.5 giây: khung đỏ của giây đầu, chữ vẫn vẽ trên nền video")
    func firstSecond() async throws {
        let image = try await render(TestVideo.scene(), at: 0.5)
        #expect(image.color(20, 20).isVideoRed)
        #expect(image.color(940, 520).isVideoRed)
        #expect(image.inkBounds(background: image.color(20, 20)) != nil)
    }

    @Test("Video ở 1.0 giây: khung xanh của giây sau")
    func atOneSecond() async throws {
        let image = try await render(TestVideo.scene(), at: 1.0)
        #expect(image.color(20, 20).isVideoBlue)
    }

    @Test("Video lặp ở 2.5 giây quay lại khung đỏ; không lặp thì giữ khung cuối")
    func loopAndHold() async throws {
        let looped = try await render(TestVideo.scene(loop: true), at: 2.5)
        #expect(looped.color(20, 20).isVideoRed)
        let held = try await render(TestVideo.scene(loop: false), at: 2.5)
        #expect(held.color(20, 20).isVideoBlue)
    }

    @Test("Tệp video không có: không crash, không vẽ gì thay thế, các lớp khác vẫn hiện")
    func missingVideo() async throws {
        let background = SceneKit.background(SceneKit.navy, id: 1)
        var scene = TestVideo.scene(TestVideo.missingID)
        scene.layers.insert(background, at: 0)
        scene.layers[1].kind = .slide
        scene.layers[2].kind = .overlay
        let image = try await render(scene, at: 0.5)
        #expect(image.color(20, 20).isClose(to: SceneKit.navy))
        #expect(image.inkBounds(background: SceneKit.navy) != nil)
    }
}

@Suite("SourceHealth")
struct SourceHealthTests {
    @Test("Mỗi vấn đề báo một lần mỗi chu kỳ; lấy xong thì xoá")
    func drainOnce() {
        let health = SourceHealth()
        health.report(.videoFailed(TestVideo.missingID), message: "Không tìm thấy tệp video")
        health.report(.videoFailed(TestVideo.missingID), message: "Không tìm thấy tệp video")
        health.report(.textTruncated, message: "Chữ tràn")
        let first = health.drain()
        #expect(first.count == 2)
        #expect(first.first?.issue == .videoFailed(TestVideo.missingID))
        #expect(health.drain().isEmpty)
    }
}

extension RGBA {
    /// Màu đỏ sau khi qua mã hoá H.264 (YUV làm lệch vài chục mức trên mỗi kênh): kênh đỏ trội hẳn.
    var isVideoRed: Bool { red > 200 && green < 70 && blue < 70 }
    /// Màu xanh dương sau khi qua mã hoá H.264.
    var isVideoBlue: Bool { blue > 200 && red < 70 && green < 70 }
}

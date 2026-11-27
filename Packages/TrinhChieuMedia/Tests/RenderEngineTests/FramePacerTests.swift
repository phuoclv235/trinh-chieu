import CoreGraphics
import CoreModel
import Testing

@testable import RenderEngine

@Suite("FramePacer: vẽ theo nhu cầu dạng giữ ấm")
struct FramePacerTests {
    @Test("Cảnh đổi thì vẽ mỗi nhịp; đứng yên thì vẽ tới khi khung đứng yên lên màn, rồi mỗi 4 nhịp")
    func keepWarmAfterConfirmation() throws {
        let pacer = FramePacer()
        #expect(pacer.tick(active: true)?.settled == false)
        // Khung đứng yên chưa lên màn: vẫn vẽ mỗi nhịp.
        let first = try #require(pacer.tick(active: false))
        #expect(first.settled)
        #expect(pacer.tick(active: false) != nil)
        // Khung không lên màn thì chưa tính.
        pacer.presented(first, presentedTime: 0)
        #expect(pacer.tick(active: false) != nil)
        pacer.presented(first, presentedTime: 12.5)
        #expect(pacer.isSettled)
        let ticks = (0..<8).map { _ in pacer.tick(active: false) }
        #expect(ticks.map { $0 != nil } == [false, false, false, true, false, false, false, true])
        #expect(ticks[3]?.afterGap == true)
    }

    @Test("Khung đứng yên của lần đổi cũ lên màn muộn không xác nhận lần đổi mới")
    func staleConfirmationIgnored() throws {
        let pacer = FramePacer()
        _ = pacer.tick(active: true)
        let old = try #require(pacer.tick(active: false))
        _ = pacer.tick(active: true)
        pacer.presented(old, presentedTime: 3)
        #expect(!pacer.isSettled)
        #expect(pacer.tick(active: false) != nil)
    }

    @Test("Cảnh đổi trong lúc giữ ấm thì vẽ ngay ở nhịp đó")
    func activeInterruptsKeepWarm() throws {
        let pacer = FramePacer()
        let still = try #require(pacer.tick(active: false))
        pacer.presented(still, presentedTime: 1)
        #expect(pacer.tick(active: false) == nil)
        let changed = pacer.tick(active: true)
        #expect(changed?.settled == false)
        #expect(changed?.afterGap == true)
        #expect(!pacer.isSettled)
    }
}

@Suite("VideoPlayerPool: cỡ giải mã")
struct VideoDecodeSizeTests {
    private func size(_ video: CGSize, _ frame: CGSize, _ fit: ContentFit) -> CGSize {
        VideoPlayerPool.decodeSize(video: video, frame: frame, fit: fit)
    }

    @Test("Giải mã ở cỡ vẽ, giữ tỉ lệ, không lớn hơn cỡ gốc, số chẵn")
    func decodeSize() {
        let uhd = CGSize(width: 3840, height: 2160)
        let hd = CGSize(width: 1280, height: 720)
        let fourThree = CGSize(width: 1024, height: 768)
        #expect(size(uhd, CGSize(width: 1920, height: 1080), .fill) == CGSize(width: 1920, height: 1080))
        // Khung 4:3 phủ kín thì theo chiều cao; nằm trọn thì theo chiều ngang.
        #expect(size(uhd, fourThree, .fill) == CGSize(width: 1366, height: 768))
        #expect(size(uhd, fourThree, .fit) == CGSize(width: 1024, height: 576))
        // Khung lớn hơn video: giữ cỡ gốc.
        #expect(size(hd, uhd, .fill) == hd)
        #expect(size(uhd, CGSize(width: 1000, height: 1000), .stretch) == CGSize(width: 1000, height: 1000))
    }
}

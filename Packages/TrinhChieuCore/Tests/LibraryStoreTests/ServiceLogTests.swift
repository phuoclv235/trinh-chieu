import CoreModel
import Foundation
import Testing

@testable import LibraryStore

@Suite("LibraryStore: nhật ký buổi nhóm")
@MainActor
struct ServiceLogTests {
    @Test("Ghi nhật ký theo lô: chưa tới hạn thì chưa ghi, flush ghi đủ sự kiện vào logs/<ngày>-<uuid>.json")
    func writesInBatches() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: testConfiguration(clock: clock))
        let planID = UUID()
        store.beginServiceLog(planID: planID)
        let sink: any ServiceLogSink = store
        let events = [
            ServiceLogEvent(at: clock.now, type: .goLive, itemID: UUID(), presentationID: UUID(), slideID: UUID()),
            ServiceLogEvent(at: clock.now.addingTimeInterval(1.5), type: .clearLayer, layer: .slide),
        ]
        for event in events {
            sink.record(event)
        }
        #expect(store.serviceLogTask != nil)
        let logs = dir.url.appendingPathComponent("logs")
        #expect(try FileManager.default.contentsOfDirectory(atPath: logs.path).isEmpty)

        await store.flush()
        let names = try FileManager.default.contentsOfDirectory(atPath: logs.path)
        #expect(names.count == 1)
        let name = try #require(names.first)
        let day = FileTimestamp.day(from: clock.now, timeZone: TimeZone(secondsFromGMT: 7 * 3_600)!)
        #expect(name.hasPrefix(day + "-"))
        let log = try DocumentCoding.decode(ServiceLog.self, from: Data(contentsOf: logs.appendingPathComponent(name)))
        #expect(log.planID == planID)
        #expect(log.events.count == 2)
        #expect(log.events.map(\.type) == [.goLive, .clearLayer])

        // Nhật ký mới: nhật ký cũ đã ghi xong, tệp mới riêng.
        store.beginServiceLog(planID: nil)
        sink.record(ServiceLogEvent(at: clock.now, type: .freeze, enabled: true))
        await store.close()
        #expect(try FileManager.default.contentsOfDirectory(atPath: logs.path).count == 2)
    }

    @Test("Ghi theo lô tự chạy sau chu kỳ")
    func batchTimerFires() async throws {
        let dir = try TemporaryDirectory()
        let clock = FakeClock()
        var configuration = testConfiguration(clock: clock)
        configuration.serviceLogInterval = .milliseconds(10)
        let store = try await LibraryStore.open(
            at: dir.url, fileWatcher: NoFileWatching(), configuration: configuration)
        store.record(ServiceLogEvent(at: clock.now, type: .rehearsal, enabled: true))
        let timer = try #require(store.serviceLogTask)
        await timer.value
        #expect(store.serviceLogTask == nil)
        #expect(store.serviceLog?.hasUnwrittenEvents == false)
        await store.close()
        let logs = try FileManager.default.contentsOfDirectory(atPath: dir.url.appendingPathComponent("logs").path)
        #expect(logs.count == 1)
    }
}

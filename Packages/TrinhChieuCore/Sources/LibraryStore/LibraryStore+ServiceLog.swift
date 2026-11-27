import CoreModel
import Foundation

/// Nhật ký buổi nhóm đang ghi.
struct ServiceLogState {
    var log: ServiceLog
    /// `logs/<yyyy-mm-dd>-<uuid>.json`.
    var relativePath: String
    /// Có sự kiện chưa ghi xuống đĩa.
    var hasUnwrittenEvents: Bool
}

extension LibraryStore: ServiceLogSink {
    /// Ghi một sự kiện vào nhật ký buổi nhóm hiện tại (chưa có thì mở nhật ký mới). Đĩa được ghi theo lô mỗi
    /// 5 giây và khi ``flush()``.
    public func record(_ event: ServiceLogEvent) {
        if serviceLog == nil {
            beginServiceLog(planID: nil, startedAt: event.at)
        }
        serviceLog?.log.events.append(event)
        serviceLog?.hasUnwrittenEvents = true
        scheduleServiceLogWrite()
    }

    /// Mở nhật ký mới cho một chương trình buổi nhóm; nhật ký trước được ghi nốt.
    public func beginServiceLog(planID: UUID?) {
        beginServiceLog(planID: planID, startedAt: configuration.now())
    }

    /// Nhật ký buổi nhóm đang ghi, nếu có.
    public var currentServiceLog: ServiceLog? {
        serviceLog?.log
    }

    private func beginServiceLog(planID: UUID?, startedAt: Date) {
        writeServiceLogNow()
        let day = FileTimestamp.day(from: startedAt, timeZone: configuration.timeZone)
        let path = "\(LibraryLayout.logsDirectory)/\(day)-\(UUID().uuidString).json"
        serviceLog = ServiceLogState(
            log: ServiceLog(planID: planID, startedAt: startedAt), relativePath: path, hasUnwrittenEvents: false)
    }

    private func scheduleServiceLogWrite() {
        guard serviceLogTask == nil else { return }
        let interval = configuration.serviceLogInterval
        serviceLogTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            self?.serviceLogTask = nil
            self?.writeServiceLogNow()
        }
    }

    /// Ghi nhật ký hiện tại nếu có sự kiện chưa ghi (cả tệp, nguyên tử).
    func writeServiceLogNow() {
        serviceLogTask?.cancel()
        serviceLogTask = nil
        guard var state = serviceLog, state.hasUnwrittenEvents else { return }
        do {
            let data = try DocumentCoding.encode(state.log)
            state.hasUnwrittenEvents = false
            serviceLog = state
            let path = state.relativePath
            writeData(data, to: path) { [weak self] in
                guard self?.serviceLog?.relativePath == path else { return }
                self?.serviceLog?.hasUnwrittenEvents = true
            }
        } catch {
            reportWriteFailure(state.relativePath, error: error)
        }
    }
}

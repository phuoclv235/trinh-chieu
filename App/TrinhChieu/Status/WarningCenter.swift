import CoreModel
import Foundation
import LibraryStore
import Observation
import RenderEngine

/// Một cảnh báo trên thanh cảnh báo dưới thanh công cụ. Lỗi chỉ hiện ở màn điều khiển, không bao giờ lên đầu ra.
struct AppWarning: Identifiable, Equatable {
    enum Source: Hashable {
        case library(UUID)
        case render(RenderIssue)
        case outputMissing(String)
        case outputBlocked(String)
        case outputFailed(String)
    }

    enum Remedy: Equatable {
        /// "Chọn lại màn hình": mở Cài đặt > Đầu ra.
        case chooseScreens
        /// "Mở tệp lỗi trong Finder".
        case revealInFinder(URL)
    }

    let id: Source
    let message: String
    let remedy: Remedy?
}

/// Gom cảnh báo từ thư viện (`loadProblems`), lõi dựng hình (nguồn lỗi, phông thiếu, chữ tràn) và đầu ra (màn bị
/// rút, màn đang chứa cửa sổ chính). Cảnh báo đầu ra tự biến mất khi màn cắm lại.
@MainActor @Observable final class WarningCenter {
    /// Cảnh báo của lõi dựng hình, mới nhất cuối.
    private(set) var renderWarnings: [RenderWarning] = []
    /// Cảnh báo đầu ra bạn đã ẩn; hiện lại khi tình trạng đổi.
    private var dismissedOutputs: Set<Source> = []

    typealias Source = AppWarning.Source

    /// Nhận cảnh báo mới mỗi giây từ `RenderEngine.statistics`.
    func ingest(_ warnings: [RenderWarning]) {
        for warning in warnings {
            // Màn bị rút đã có cảnh báo riêng theo tên màn (từ `OutputRouter`), rõ hơn mã đầu ra.
            if case .outputDetached = warning.issue {
                continue
            }
            renderWarnings.removeAll { $0.issue == warning.issue }
            renderWarnings.append(warning)
        }
        if renderWarnings.count > 20 {
            renderWarnings.removeFirst(renderWarnings.count - 20)
        }
    }

    /// Mọi cảnh báo đang có, đầu ra trước (khẩn nhất), rồi thư viện, rồi nguồn.
    func warnings(library: LibraryStore?, outputs: OutputRouter) -> [AppWarning] {
        var result: [AppWarning] = []
        for assignment in outputs.missing {
            let source = Source.outputMissing(assignment.displayUUID)
            guard !dismissedOutputs.contains(source) else { continue }
            let format = String(localized: "Screen \"%@\" (%@) is disconnected.")
            result.append(
                AppWarning(
                    id: source,
                    message: String(format: format, assignment.displayName, assignment.role.localizedName),
                    remedy: .chooseScreens))
        }
        for assignment in outputs.blocked {
            let source = Source.outputBlocked(assignment.displayUUID)
            guard !dismissedOutputs.contains(source) else { continue }
            let format = String(localized: "Screen \"%@\" holds the main window; %@ waits for it to move.")
            result.append(
                AppWarning(
                    id: source,
                    message: String(format: format, assignment.displayName, assignment.role.localizedName),
                    remedy: .chooseScreens))
        }
        for (uuid, _) in outputs.attachFailures.sorted(by: { $0.key < $1.key }) {
            let source = Source.outputFailed(uuid)
            guard !dismissedOutputs.contains(source) else { continue }
            let name = outputs.displays.first { $0.uuid == uuid }?.name ?? uuid
            let format = String(localized: "Cannot show output on screen \"%@\".")
            result.append(AppWarning(id: source, message: String(format: format, name), remedy: .chooseScreens))
        }
        if let library {
            for problem in library.loadProblems {
                let url = library.root.appendingPathComponent(problem.relativePath)
                let exists = FileManager.default.fileExists(atPath: url.path)
                result.append(
                    AppWarning(
                        id: .library(problem.id),
                        message: problem.message,
                        remedy: .revealInFinder(exists ? url : library.root)))
            }
        }
        for warning in renderWarnings.reversed() {
            var remedy: AppWarning.Remedy?
            switch warning.issue {
            case .imageFailed(let id), .videoFailed(let id):
                remedy = library?.mediaURL(id).map(AppWarning.Remedy.revealInFinder)
            case .textTruncated, .fontMissing, .outputDetached:
                remedy = nil
            }
            result.append(AppWarning(id: .render(warning.issue), message: warning.message, remedy: remedy))
        }
        return result
    }

    /// Ẩn một cảnh báo.
    func dismiss(_ warning: AppWarning, library: LibraryStore?) {
        switch warning.id {
        case .library(let id):
            library?.dismissProblem(id)
        case .render(let issue):
            renderWarnings.removeAll { $0.issue == issue }
        case .outputMissing, .outputBlocked, .outputFailed:
            dismissedOutputs.insert(warning.id)
        }
    }

    /// Quên các cảnh báo đầu ra đã ẩn mà tình trạng đã hết, để lần sau xảy ra lại thì hiện lại.
    func pruneDismissed(outputs: OutputRouter) {
        let active = Set(
            outputs.missing.map { Source.outputMissing($0.displayUUID) }
                + outputs.blocked.map { Source.outputBlocked($0.displayUUID) }
                + outputs.attachFailures.keys.map { Source.outputFailed($0) })
        dismissedOutputs.formIntersection(active)
    }
}

extension OutputRole {
    /// Tên vai trên giao diện.
    var localizedName: String {
        switch self {
        case .program: return String(localized: "Main output")
        case .stage: return String(localized: "Stage display")
        }
    }
}

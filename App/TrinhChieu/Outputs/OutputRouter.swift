import AppKit
import CoreGraphics
import Observation
import RenderEngine
import os

/// Gắn đầu ra theo cài đặt và giữ chúng đúng màn: cắm, rút, đổi sắp xếp màn, kéo cửa sổ chính sang màn khác.
@MainActor @Observable final class OutputRouter {
    /// Các màn đang cắm, theo thứ tự hiển thị.
    private(set) var displays: [DisplayDescriptor] = []
    /// Vai đang có hình trên một màn thật.
    private(set) var attached: [OutputRole: DisplayDescriptor] = [:]
    private(set) var missing: [OutputAssignment] = []
    private(set) var blocked: [OutputAssignment] = []
    /// Gắn đầu ra lỗi (ví dụ không tạo được vòng vẽ): mã màn → lời báo.
    private(set) var attachFailures: [String: String] = [:]
    /// Màn đang chứa cửa sổ chính.
    private(set) var controlDisplayUUID: String?

    @ObservationIgnored private weak var engine: RenderEngine?
    @ObservationIgnored private var assignments: @MainActor () -> [OutputAssignment] = { [] }
    @ObservationIgnored private var current: [OutputID: OutputPlanner.Target] = [:]
    @ObservationIgnored private var screens: [String: NSScreen] = [:]
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private weak var mainWindow: NSWindow?
    @ObservationIgnored private let logger = Logger(subsystem: "app.trinhchieu.TrinhChieu", category: "Outputs")

    init() {
        readScreens()
    }

    /// Bắt đầu gắn đầu ra. `assignments` đọc cài đặt mới nhất mỗi lần tính lại.
    func start(engine: RenderEngine, assignments: @escaping @MainActor () -> [OutputAssignment]) {
        self.assignments = assignments
        guard self.engine == nil else {
            refresh()
            return
        }
        self.engine = engine
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensDidChange() }
            })
        refresh()
    }

    /// Theo dõi màn chứa cửa sổ chính (gọi khi cửa sổ xuất hiện).
    func observeMainWindow(_ window: NSWindow) {
        guard window !== mainWindow else { return }
        mainWindow = window
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        refresh()
    }

    /// Màn đang cắm theo UUID.
    func screen(for uuid: String) -> NSScreen? {
        screens[uuid]
    }

    /// Vẽ số lớn lên từng màn trong 3 giây, đúng số thứ tự trong Cài đặt.
    func identifyScreens() {
        let ordered = displays.compactMap { screens[$0.uuid] }
        engine?.identifyScreens(ordered, duration: 3)
    }

    /// Tính lại và gắn, gỡ cho khớp cài đặt.
    func refresh() {
        readScreens()
        controlDisplayUUID = mainWindow?.screen.flatMap(Self.uuid(of:))
        guard let engine else { return }
        let plan = OutputPlanner.plan(
            assignments: assignments(), displays: displays, controlDisplayUUID: controlDisplayUUID,
            attached: Set(current.keys))
        for (id, target) in current where plan.outputs[id] != target {
            engine.detachOutput(id)
            current[id] = nil
            logger.info("Gỡ đầu ra \(id.rawValue, privacy: .public)")
        }
        var failures: [String: String] = [:]
        for (id, target) in plan.outputs where current[id] == nil {
            guard let screen = screens[target.display.uuid] else { continue }
            do {
                try engine.attachDisplayOutput(id: id, screen: screen, role: target.role)
                current[id] = target
                logger.info(
                    "Gắn \(target.role.rawValue, privacy: .public) lên \(target.display.name, privacy: .public)")
            } catch {
                failures[target.display.uuid] = String(describing: error)
                logger.error("Gắn đầu ra lỗi: \(String(describing: error), privacy: .public)")
            }
        }
        attachFailures = failures
        missing = plan.missing
        blocked = plan.blocked
        var roles: [OutputRole: DisplayDescriptor] = [:]
        for target in current.values {
            roles[target.role] = target.display
        }
        attached = roles
    }

    /// Gỡ mọi đầu ra (khi thoát).
    func stop() {
        for id in current.keys {
            engine?.detachOutput(id)
        }
        current.removeAll()
        attached.removeAll()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Bên trong

    private func screensDidChange() {
        refresh()
        // Danh sách màn của AppKit có khi cập nhật chậm hơn thông báo một nhịp khi cắm màn qua bộ chuyển: tính lại
        // thêm một lần sau 1 giây.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.refresh()
        }
    }

    private func readScreens() {
        var map: [String: NSScreen] = [:]
        var list: [DisplayDescriptor] = []
        for screen in NSScreen.screens {
            guard let descriptor = Self.descriptor(for: screen) else { continue }
            map[descriptor.uuid] = screen
            list.append(descriptor)
        }
        screens = map
        let ordered = OutputPlanner.ordered(list)
        if ordered != displays {
            displays = ordered
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    static func uuid(of screen: NSScreen) -> String? {
        displayID(of: screen).flatMap(uuid(ofDisplay:))
    }

    static func uuid(ofDisplay id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    private static func descriptor(for screen: NSScreen) -> DisplayDescriptor? {
        guard let id = displayID(of: screen), let uuid = uuid(ofDisplay: id) else { return nil }
        let mode = CGDisplayCopyDisplayMode(id)
        return DisplayDescriptor(
            uuid: uuid,
            displayID: id,
            name: screen.localizedName,
            frame: screen.frame,
            pixelWidth: mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor),
            pixelHeight: mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor),
            refreshRate: screen.maximumFramesPerSecond,
            isBuiltIn: CGDisplayIsBuiltin(id) != 0
        )
    }
}

import CoreGraphics
import Foundation
import RenderEngine
import Testing

@testable import TrinhChieu

@Suite("Gắn đầu ra theo màn")
struct OutputPlannerTests {
    private func display(_ uuid: String, x: CGFloat, name: String? = nil) -> DisplayDescriptor {
        DisplayDescriptor(
            uuid: uuid, displayID: UInt32(abs(x) / 100), name: name ?? uuid,
            frame: CGRect(x: x, y: 0, width: 1920, height: 1080), pixelWidth: 1920, pixelHeight: 1080,
            refreshRate: 60, isBuiltIn: false)
    }

    private let assignments = [
        OutputAssignment(displayUUID: "LED", role: .program, displayName: "LED"),
        OutputAssignment(displayUUID: "STAGE", role: .stage, displayName: "Bục giảng"),
    ]

    @Test("Nghiệm thu 2: đổi thứ tự cắm màn vẫn gắn đúng vai theo UUID")
    func rolesFollowDisplayUUID() {
        let first = OutputPlanner.plan(
            assignments: assignments,
            displays: [display("MAC", x: 0), display("LED", x: 2000), display("STAGE", x: 4000)],
            controlDisplayUUID: "MAC")
        let swapped = OutputPlanner.plan(
            assignments: assignments,
            displays: [display("STAGE", x: 2000), display("MAC", x: 0), display("LED", x: 4000)],
            controlDisplayUUID: "MAC")
        for plan in [first, swapped] {
            #expect(plan.outputs[OutputPlanner.outputID(forDisplay: "LED")]?.role == .program)
            #expect(plan.outputs[OutputPlanner.outputID(forDisplay: "STAGE")]?.role == .stage)
            #expect(plan.missing.isEmpty)
        }
    }

    @Test("Nghiệm thu 3: rút màn thì vai vào danh sách vắng; cắm lại thì gắn lại")
    func unpluggedScreenIsMissingThenReattached() {
        let unplugged = OutputPlanner.plan(
            assignments: assignments, displays: [display("MAC", x: 0), display("LED", x: 2000)],
            controlDisplayUUID: "MAC")
        #expect(unplugged.missing.map(\.displayUUID) == ["STAGE"])
        #expect(unplugged.outputs.count == 1)

        let replugged = OutputPlanner.plan(
            assignments: assignments,
            displays: [display("MAC", x: 0), display("LED", x: 2000), display("STAGE", x: 4000)],
            controlDisplayUUID: "MAC")
        #expect(replugged.missing.isEmpty)
        #expect(replugged.outputs.count == 2)
    }

    @Test("Màn đang chứa cửa sổ chính: không gắn mới, nhưng không gỡ đầu ra đang chạy")
    func controlScreenBlocksOnlyNewAttachments() {
        let displays = [display("LED", x: 0), display("STAGE", x: 2000)]
        let blocked = OutputPlanner.plan(assignments: assignments, displays: displays, controlDisplayUUID: "LED")
        #expect(blocked.blocked.map(\.displayUUID) == ["LED"])
        #expect(blocked.outputs[OutputPlanner.outputID(forDisplay: "LED")] == nil)

        let running = OutputPlanner.plan(
            assignments: assignments, displays: displays, controlDisplayUUID: "LED",
            attached: [OutputPlanner.outputID(forDisplay: "LED")])
        #expect(running.blocked.isEmpty)
        #expect(running.outputs[OutputPlanner.outputID(forDisplay: "LED")]?.role == .program)
    }

    @Test("Thứ tự màn: trái sang phải")
    func orderedLeftToRight() {
        let ordered = OutputPlanner.ordered([display("C", x: 4000), display("A", x: -1920), display("B", x: 0)])
        #expect(ordered.map(\.uuid) == ["A", "B", "C"])
    }
}

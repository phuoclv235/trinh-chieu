import CoreModel
import Foundation
import Testing

@testable import RenderEngine

/// Nguồn giả: cùng `contentID` nhưng khác `version` là "cùng nội dung, dựng lại".
private struct FakeSource: LayerSource {
    let contentID: UUID
    var version = 0
}

private typealias Slot = LayerSlot<FakeSource, String>

private let dissolve = TransitionSpec(kind: .dissolve, duration: 1)
private let sourceA = FakeSource(contentID: SceneKit.id(1))
private let sourceB = FakeSource(contentID: SceneKit.id(2))
private let sourceC = FakeSource(contentID: SceneKit.id(3))

private func name(_ source: FakeSource) -> String {
    "\(source.contentID.uuidString.suffix(1))v\(source.version)"
}

@Suite("LayerSlot")
struct LayerSlotTests {
    @Test("Cắt: thay ngay")
    func cutReplaces() {
        var slot = Slot()
        slot.update(source: sourceA, spec: .cut, time: 0, resolve: name)
        slot.update(source: sourceB, spec: .cut, time: 1, resolve: name)
        guard case .steady(let content) = slot.plan(at: 1) else {
            Issue.record("Phải hiện ổn định")
            return
        }
        #expect(content == "2v0")
        #expect(slot.transition == nil)
    }

    @Test("Hoà tan: giữa chừng trộn đều, hết thời lượng thì hiện lớp mới")
    func dissolveProgresses() {
        var slot = Slot()
        slot.update(source: sourceA, spec: .cut, time: 0, resolve: name)
        slot.update(source: sourceB, spec: dissolve, time: 10, resolve: name)
        guard case .dissolve(let from, let to, let t) = slot.plan(at: 10.5) else {
            Issue.record("Phải đang hoà tan")
            return
        }
        #expect(from == "1v0")
        #expect(to == "2v0")
        #expect(abs(t - 0.5) < 1e-9)
        guard case .dissolve(_, _, let early) = slot.plan(at: 10.25) else {
            Issue.record("Phải đang hoà tan")
            return
        }
        // Hàm êm: đầu chậm hơn tuyến tính.
        #expect(early < 0.25)
        slot.finishTransitionIfDone(at: 11)
        #expect(slot.transition == nil)
        guard case .steady(let content) = slot.plan(at: 11) else {
            Issue.record("Phải hiện ổn định")
            return
        }
        #expect(content == "2v0")
    }

    @Test("Lớp mới chưa dựng xong: giữ lớp cũ, không vẽ lớp trống; dựng xong mới bắt đầu hoà tan")
    func holdsOldLayerUntilReady() {
        var slot = Slot()
        slot.update(source: sourceA, spec: .cut, time: 0, resolve: name)
        slot.update(source: sourceB, spec: dissolve, time: 1) { _ in nil }
        guard case .steady(let held) = slot.plan(at: 1) else {
            Issue.record("Phải giữ lớp cũ")
            return
        }
        #expect(held == "1v0")
        slot.update(source: sourceB, spec: dissolve, time: 2, resolve: name)
        guard case .dissolve(_, _, let t) = slot.plan(at: 2) else {
            Issue.record("Phải bắt đầu hoà tan khi dựng xong")
            return
        }
        #expect(t == 0)
    }

    @Test("Cùng contentID, nội dung dựng lại: thay tại chỗ, không chuyển cảnh")
    func sameContentIDNoTransition() {
        var slot = Slot()
        slot.update(source: sourceA, spec: .cut, time: 0, resolve: name)
        var changed = sourceA
        changed.version = 1
        slot.update(source: changed, spec: dissolve, time: 1, resolve: name)
        #expect(slot.transition == nil)
        guard case .steady(let content) = slot.plan(at: 1) else {
            Issue.record("Phải hiện ổn định")
            return
        }
        #expect(content == "1v1")
    }

    @Test("Lớp biến mất khỏi cảnh: hoà tan ra trống rồi rảnh")
    func layerRemoved() {
        var slot = Slot()
        slot.update(source: sourceA, spec: .cut, time: 0, resolve: name)
        slot.update(source: nil, spec: dissolve, time: 1, resolve: name)
        guard case .dissolve(let from, let to, _) = slot.plan(at: 1.5) else {
            Issue.record("Phải đang hoà tan")
            return
        }
        #expect(from == "1v0")
        #expect(to == nil)
        slot.update(source: nil, spec: dissolve, time: 2, resolve: name)
        #expect(slot.isIdle)
        guard case .nothing = slot.plan(at: 2) else {
            Issue.record("Không còn gì để vẽ")
            return
        }
    }

    @Test("Cảnh mới đến giữa lúc hoà tan: xuất phát từ lớp đang tới")
    func retargetMidTransition() {
        var slot = Slot()
        slot.update(source: sourceA, spec: .cut, time: 0, resolve: name)
        slot.update(source: sourceB, spec: dissolve, time: 1, resolve: name)
        slot.update(source: sourceC, spec: dissolve, time: 1.5, resolve: name)
        guard case .dissolve(let from, let to, let t) = slot.plan(at: 1.5) else {
            Issue.record("Phải đang hoà tan")
            return
        }
        #expect(from == "2v0")
        #expect(to == "3v0")
        #expect(t == 0)
    }

    @Test("Cảnh đầu tiên với hoà tan: hiện dần từ trống")
    func firstSceneFadesIn() {
        var slot = Slot()
        slot.update(source: sourceA, spec: dissolve, time: 0, resolve: name)
        guard case .dissolve(let from, let to, _) = slot.plan(at: 0.5) else {
            Issue.record("Phải đang hoà tan")
            return
        }
        #expect(from == nil)
        #expect(to == "1v0")
    }

    @Test("Hoà tan thời lượng 0 coi như cắt")
    func zeroDurationDissolveIsCut() {
        var slot = Slot()
        slot.update(source: sourceA, spec: .cut, time: 0, resolve: name)
        slot.update(source: sourceB, spec: TransitionSpec(kind: .dissolve, duration: 0), time: 1, resolve: name)
        #expect(slot.transition == nil)
    }

    @Test("smoothstep: 0, 0.5, 1 giữ nguyên; ngoài đoạn bị kẹp")
    func smoothstepValues() {
        #expect(smoothstep(0) == 0)
        #expect(smoothstep(0.5) == 0.5)
        #expect(smoothstep(1) == 1)
        #expect(smoothstep(-1) == 0)
        #expect(smoothstep(2) == 1)
    }
}

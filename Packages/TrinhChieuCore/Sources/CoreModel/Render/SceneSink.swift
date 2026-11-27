import Foundation

/// Hai cảnh xuất cùng lúc: đầu ra chính và màn hình nhắc.
public struct ScenePublication: Sendable, Equatable, Codable {
    /// Đầu ra chính.
    public var program: RenderScene
    /// Màn hình nhắc.
    public var stage: RenderScene

    public init(program: RenderScene, stage: RenderScene) {
        self.program = program
        self.stage = stage
    }
}

/// Biến `ShowState` thành cảnh. Bản thật (`SceneResolver`) làm ở T1.5.
public protocol SceneResolving: Sendable {
    @MainActor func resolve(state: ShowState, provider: any ShowContentProvider, now: Date) -> ScenePublication
}

/// Nơi nhận cảnh: lõi dựng hình (đầu ra) và giao diện (xem trước).
@MainActor public protocol SceneSink: AnyObject {
    /// Giao cảnh cho các đầu ra (chính và màn hình nhắc).
    func publishToOutputs(_ publication: ScenePublication)
    /// Giao cảnh cho ô xem trước trên màn điều khiển.
    func publishToPreview(_ publication: ScenePublication)
}

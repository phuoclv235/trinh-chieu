import Foundation
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
    let source = Bundle.module.url(forResource: "Placeholder", withExtension: "metal")
    #expect(metallib != nil || source != nil)
}

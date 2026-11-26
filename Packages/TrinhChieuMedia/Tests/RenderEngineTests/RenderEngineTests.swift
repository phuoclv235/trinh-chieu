import Foundation
import Testing

@testable import RenderEngine

@Test("RenderEngine: khung chạy được")
func renderEngineFrameworkRuns() {
    #expect(RenderEngineModule.name == "RenderEngine")
}

@Test("RenderEngine: shader được đóng vào bundle")
func renderEngineShadersAreBundled() {
    #expect(Bundle.module.url(forResource: "default", withExtension: "metallib") != nil)
}

import Testing

@testable import Scripture

@Test("Scripture: khung chạy được")
func scriptureFrameworkRuns() {
    #expect(ScriptureModule.name == "Scripture")
}

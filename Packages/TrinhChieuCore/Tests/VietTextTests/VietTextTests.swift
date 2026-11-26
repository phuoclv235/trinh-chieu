import Testing

@testable import VietText

@Test("VietText: khung chạy được")
func vietTextFrameworkRuns() {
    #expect(VietTextModule.name == "VietText")
}

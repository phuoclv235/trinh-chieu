import Testing

@testable import CoreModel

@Test("CoreModel: khung chạy được")
func coreModelFrameworkRuns() {
    #expect(CoreModelModule.name == "CoreModel")
}

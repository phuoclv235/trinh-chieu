import Testing

@testable import Importers

@Test("Importers: khung chạy được")
func importersFrameworkRuns() {
    #expect(ImportersModule.name == "Importers")
}

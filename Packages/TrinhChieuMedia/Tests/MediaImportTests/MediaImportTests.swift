import Testing

@testable import MediaImport

@Test("MediaImport: khung chạy được")
func mediaImportFrameworkRuns() {
    #expect(MediaImportModule.name == "MediaImport")
}

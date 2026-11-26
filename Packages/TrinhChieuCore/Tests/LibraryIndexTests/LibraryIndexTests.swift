import Testing

@testable import LibraryIndex

@Test("LibraryIndex: khung chạy được")
func libraryIndexFrameworkRuns() {
    #expect(LibraryIndexModule.name == "LibraryIndex")
}

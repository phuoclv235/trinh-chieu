import Testing

@testable import LibraryStore

@Test("LibraryStore: khung chạy được")
func libraryStoreFrameworkRuns() {
    #expect(LibraryStoreModule.name == "LibraryStore")
}

import Testing
@testable import NakedPantree

@Suite("App target")
struct PlaceholderTests {
    @Test("RootView constructs without crashing")
    func rootViewConstructs() {
        _ = RootView()
    }
}

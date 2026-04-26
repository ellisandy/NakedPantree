import Testing
@testable import NakedPantreeDomain

@Suite("NakedPantreeDomain")
struct NakedPantreeDomainTests {
    @Test("Module is wired up")
    func moduleIsWiredUp() {
        #expect(NakedPantreeDomain.moduleVersion == "0.1.0")
    }
}

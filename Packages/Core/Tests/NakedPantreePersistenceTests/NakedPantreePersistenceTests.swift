import Testing
@testable import NakedPantreePersistence

@Suite("NakedPantreePersistence")
struct NakedPantreePersistenceTests {
    @Test("Module is wired up and depends on Domain")
    func moduleIsWiredUp() {
        #expect(NakedPantreePersistence.moduleVersion == "0.1.0")
        #expect(NakedPantreePersistence.dependsOnDomainVersion == "0.1.0")
    }
}

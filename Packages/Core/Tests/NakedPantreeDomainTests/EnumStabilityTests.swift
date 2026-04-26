import Testing
@testable import NakedPantreeDomain

/// Raw values are part of the persistence contract: renaming any of them
/// silently breaks decoding of older CloudKit records. These tests pin the
/// raw strings down — round-trip alone wouldn't catch a `pantry → pantries`
/// rename, hence the hardcoded expectations. See `AGENTS.md` §2.
@Suite("LocationKind raw-value stability")
struct LocationKindStabilityTests {
    @Test("Known cases use the contract raw values")
    func knownCasesHaveExpectedRawValues() {
        #expect(LocationKind.pantry.rawValue == "pantry")
        #expect(LocationKind.fridge.rawValue == "fridge")
        #expect(LocationKind.freezer.rawValue == "freezer")
        #expect(LocationKind.dryGoods.rawValue == "dryGoods")
        #expect(LocationKind.other.rawValue == "other")
    }

    @Test("init(rawValue:) maps known raws to their canonical case")
    func initFromKnownRawValues() {
        #expect(LocationKind(rawValue: "pantry") == .pantry)
        #expect(LocationKind(rawValue: "fridge") == .fridge)
        #expect(LocationKind(rawValue: "freezer") == .freezer)
        #expect(LocationKind(rawValue: "dryGoods") == .dryGoods)
        #expect(LocationKind(rawValue: "other") == .other)
    }

    @Test("init(rawValue:) preserves unknown values via the catch-all")
    func unknownRawValueRoundTrips() {
        let future = LocationKind(rawValue: "freezerOutside")
        #expect(future == .unknown("freezerOutside"))
        #expect(future.rawValue == "freezerOutside")
    }

    @Test("knownRawValues exposes exactly the contract raws")
    func knownRawValuesIsAuthoritative() {
        #expect(
            LocationKind.knownRawValues
                == ["pantry", "fridge", "freezer", "dryGoods", "other"]
        )
    }
}

@Suite("Unit raw-value stability")
struct UnitStabilityTests {
    @Test("Known cases use the contract raw values")
    func knownCasesHaveExpectedRawValues() {
        #expect(Unit.count.rawValue == "count")
        #expect(Unit.gram.rawValue == "gram")
        #expect(Unit.kilogram.rawValue == "kilogram")
        #expect(Unit.ounce.rawValue == "ounce")
        #expect(Unit.pound.rawValue == "pound")
        #expect(Unit.milliliter.rawValue == "milliliter")
        #expect(Unit.liter.rawValue == "liter")
        #expect(Unit.fluidOunce.rawValue == "fluidOunce")
        #expect(Unit.package.rawValue == "package")
    }

    @Test("init(rawValue:) maps known raws to their canonical case")
    func initFromKnownRawValues() {
        #expect(Unit(rawValue: "count") == .count)
        #expect(Unit(rawValue: "gram") == .gram)
        #expect(Unit(rawValue: "kilogram") == .kilogram)
        #expect(Unit(rawValue: "ounce") == .ounce)
        #expect(Unit(rawValue: "pound") == .pound)
        #expect(Unit(rawValue: "milliliter") == .milliliter)
        #expect(Unit(rawValue: "liter") == .liter)
        #expect(Unit(rawValue: "fluidOunce") == .fluidOunce)
        #expect(Unit(rawValue: "package") == .package)
    }

    @Test("init(rawValue:) preserves unknown values via the catch-all")
    func unknownRawValueRoundTrips() {
        let future = Unit(rawValue: "tablespoon")
        #expect(future == .unknown("tablespoon"))
        #expect(future.rawValue == "tablespoon")
    }

    @Test("knownRawValues exposes exactly the contract raws")
    func knownRawValuesIsAuthoritative() {
        #expect(
            Unit.knownRawValues
                == [
                    "count", "gram", "kilogram", "ounce", "pound",
                    "milliliter", "liter", "fluidOunce", "package",
                ]
        )
    }
}

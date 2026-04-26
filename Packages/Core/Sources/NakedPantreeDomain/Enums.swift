import Foundation

/// The kind of physical storage a `Location` represents.
///
/// Stored as `String` on `Location.kindRaw` so a forward-incompatible client
/// adding a new value won't crash older builds — the unknown raw is preserved
/// via `unknown(String)`. See `ARCHITECTURE.md` §4.
public enum LocationKind: Sendable, Hashable {
    case pantry
    case fridge
    case freezer
    case dryGoods
    case other
    case unknown(String)

    /// Raw values that are part of the persistence contract. Renaming any of
    /// these breaks decoding of existing CloudKit records — see the
    /// stability tests in `LocationKindStabilityTests`.
    public static let knownRawValues: [String] = [
        "pantry", "fridge", "freezer", "dryGoods", "other",
    ]

    public var rawValue: String {
        switch self {
        case .pantry: "pantry"
        case .fridge: "fridge"
        case .freezer: "freezer"
        case .dryGoods: "dryGoods"
        case .other: "other"
        case .unknown(let raw): raw
        }
    }

    /// Maps every known raw to its canonical case; anything else is preserved
    /// via `.unknown(rawValue)` so older clients don't crash on a value a
    /// newer client wrote. Construction is total — there is no failure mode.
    public init(rawValue: String) {
        switch rawValue {
        case "pantry": self = .pantry
        case "fridge": self = .fridge
        case "freezer": self = .freezer
        case "dryGoods": self = .dryGoods
        case "other": self = .other
        default: self = .unknown(rawValue)
        }
    }
}

/// The unit a `quantity` is expressed in.
///
/// Stored as `String` on `Item.unitRaw`. New units are an additive schema
/// change — see `ARCHITECTURE.md` §10. The `unknown(String)` catch-all
/// preserves any value a newer client may write.
public enum Unit: Sendable, Hashable {
    case count
    case gram
    case kilogram
    case ounce
    case pound
    case milliliter
    case liter
    case fluidOunce
    case package
    case unknown(String)

    public static let knownRawValues: [String] = [
        "count", "gram", "kilogram", "ounce", "pound",
        "milliliter", "liter", "fluidOunce", "package",
    ]

    public var rawValue: String {
        switch self {
        case .count: "count"
        case .gram: "gram"
        case .kilogram: "kilogram"
        case .ounce: "ounce"
        case .pound: "pound"
        case .milliliter: "milliliter"
        case .liter: "liter"
        case .fluidOunce: "fluidOunce"
        case .package: "package"
        case .unknown(let raw): raw
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "count": self = .count
        case "gram": self = .gram
        case "kilogram": self = .kilogram
        case "ounce": self = .ounce
        case "pound": self = .pound
        case "milliliter": self = .milliliter
        case "liter": self = .liter
        case "fluidOunce": self = .fluidOunce
        case "package": self = .package
        default: self = .unknown(rawValue)
        }
    }
}

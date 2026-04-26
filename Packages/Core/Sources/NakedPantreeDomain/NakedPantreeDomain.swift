import Foundation

/// The domain module hosts value types, enums, and repository protocols for
/// Naked Pantree. It must not import `CoreData` or `UIKit` — concrete
/// persistence lives in `NakedPantreePersistence`, and UI lives in the app
/// target. See `AGENTS.md` §2.
public enum NakedPantreeDomain {
    public static let moduleVersion = "0.1.0"
}

import Foundation
import NakedPantreeDomain

/// The persistence module hosts the `NSPersistentCloudKitContainer` setup,
/// `NSManagedObject` subclasses, and concrete repository implementations
/// that conform to protocols declared in `NakedPantreeDomain`.
///
/// Real Core Data wiring lands in Phase 1 (see `ROADMAP.md`).
public enum NakedPantreePersistence {
    public static let moduleVersion = "0.1.0"
    public static let dependsOnDomainVersion = NakedPantreeDomain.moduleVersion
}

import Foundation

/// Compose a per-view scope (location id, item id, etc.) with the
/// `RemoteChangeMonitor.changeToken` so SwiftUI's `.task(id:)` re-runs
/// on either: a navigation change *or* a CloudKit-mirrored remote
/// import. Either field changing alone is enough to retrigger the
/// reload — the struct just lets `.task(id:)` accept both at once.
struct ReloadKey: Hashable {
    let scope: UUID?
    let token: UUID
}

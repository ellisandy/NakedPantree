import NakedPantreeDomain
import SwiftUI

/// Two-section sidebar from `ARCHITECTURE.md` §7. Smart Lists are the
/// fixed top section; Locations is data-driven from `LocationRepository`.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(\.repositories) private var repositories

    @State private var locations: [Location] = []
    @State private var loadError: Error?

    var body: some View {
        List(selection: $selection) {
            Section("Smart Lists") {
                ForEach(SmartList.allCases) { list in
                    Label(list.title, systemImage: list.systemImage)
                        .tag(SidebarSelection.smartList(list))
                }
            }

            Section("Locations") {
                if locations.isEmpty {
                    Text("No locations yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locations) { location in
                        Label(location.name, systemImage: location.kind.systemImage)
                            .tag(SidebarSelection.location(location.id))
                    }
                }
            }
        }
        .navigationTitle("Naked Pantree")
        .task {
            await reload()
        }
    }

    private func reload() async {
        do {
            let house = try await repositories.household.currentHousehold()
            locations = try await repositories.location.locations(in: house.id)
        } catch {
            loadError = error
        }
    }
}

extension LocationKind {
    /// SF Symbol used in sidebar rows. Tokens here are functional, not
    /// brand-styled — full design pass for Locations icons is a Phase 6
    /// polish item per `DESIGN_GUIDELINES.md`.
    var systemImage: String {
        switch self {
        case .pantry: "shippingbox"
        case .fridge: "refrigerator"
        case .freezer: "snowflake"
        case .dryGoods: "bag"
        case .other: "square.grid.2x2"
        case .unknown: "questionmark.square"
        }
    }
}

#Preview {
    @Previewable @State var selection: SidebarSelection? = .smartList(.allItems)
    NavigationSplitView {
        SidebarView(selection: $selection)
    } detail: {
        Text("Detail")
    }
    .environment(\.repositories, .makePreview())
}

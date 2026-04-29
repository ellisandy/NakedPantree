import NakedPantreeDomain
import PhotosUI
import SwiftUI
import UIKit

/// Detail column. Read-only by default; tap Edit to open the item form,
/// or use the photo menu to attach a new photo.
struct ItemDetailView: View {
    let itemID: Item.ID?

    @Environment(\.repositories) private var repositories
    @Environment(\.remoteChangeMonitor) private var remoteChangeMonitor
    @State private var item: Item?
    @State private var photos: [ItemPhoto] = []
    @State private var formMode: ItemFormView.Mode?
    @State private var pickerSelection: PhotosPickerItem?
    @State private var isPresentingLibraryPicker = false
    @State private var isPresentingCamera = false
    @State private var isSavingPhoto = false
    @State private var photoErrorMessage: String?
    @State private var pagerStartIndex: Int?
    @State private var quantityModel: QuantityStepperModel?

    var body: some View {
        Group {
            if let item {
                detail(for: item)
            } else if itemID == nil {
                ContentUnavailableView(
                    "Pick an item",
                    systemImage: "sidebar.right",
                    description: Text("Item details will show here.")
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(item?.name ?? "")
        .toolbar {
            if let item {
                // `.topBarTrailing` (vs the original `.secondaryAction`):
                // iOS collapses lone `.secondaryAction` items into an
                // overflow that never renders when only one primary
                // sits beside it — so the photo menu was invisible.
                // `.topBarTrailing` keeps both buttons inline on the
                // navigation bar.
                ToolbarItem(placement: .topBarTrailing) {
                    photoMenu(for: item)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        formMode = .edit(item)
                    }
                }
            }
        }
        .sheet(item: $formMode) { mode in
            ItemFormView(mode: mode) {
                Task { await reload() }
            }
        }
        .sheet(item: pagerItemBinding) { startIndex in
            PhotoPagerView(
                photos: photos,
                initialIndex: startIndex.value
            ) { photo in
                Task { await deletePhoto(photo) }
            }
        }
        .sheet(isPresented: $isPresentingCamera) {
            // The camera sheet ignores safe areas so the live preview
            // fills the screen edge-to-edge — `UIImagePickerController`
            // handles its own chrome.
            PhotoCaptureSheet { image in
                isPresentingCamera = false
                guard let image, let itemID else { return }
                Task { await saveCameraImage(image, itemID: itemID) }
            }
            .ignoresSafeArea()
        }
        // PhotosPicker presents reliably as a top-level modifier driven
        // by `isPresented`. Embedding the `PhotosPicker` view inside the
        // `Menu` swallows the trigger — the menu closes, the picker
        // never opens. State-driven presentation keeps the menu item as
        // a plain `Button` and lets the picker layer above the chrome.
        .photosPicker(
            isPresented: $isPresentingLibraryPicker,
            selection: $pickerSelection,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: pickerSelection) { _, newValue in
            guard let newValue, let itemID else { return }
            Task { await saveLibraryPick(newValue, itemID: itemID) }
        }
        .alert(
            "Couldn't save that photo.",
            isPresented: photoErrorBinding,
            presenting: photoErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .task(id: ReloadKey(scope: itemID, token: remoteChangeMonitor.changeToken)) {
            await reload()
        }
        .onDisappear {
            // Flush any pending debounced quantity write so leaving
            // the detail screen never strands the user's last tap.
            // The captured model holds its own state — fine to
            // outlive `self` view value here.
            if let quantityModel {
                Task { await quantityModel.flush() }
            }
        }
    }

    private var photoErrorBinding: Binding<Bool> {
        Binding(
            get: { photoErrorMessage != nil },
            set: { newValue in
                if !newValue { photoErrorMessage = nil }
            }
        )
    }

    @ViewBuilder
    private func detail(for item: Item) -> some View {
        Form {
            if let primary = photos.first, let uiImage = primary.uiImage {
                Section {
                    Button {
                        pagerStartIndex = 0
                    } label: {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .clipped()
                            .contentShape(Rectangle())
                            .accessibilityLabel(Text("Photo of \(item.name)"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("itemDetail.primaryPhoto")
                }
                .listRowInsets(EdgeInsets())
            }

            if photos.count >= 2 {
                Section {
                    photoStrip
                }
                .listRowInsets(EdgeInsets())
            }

            Section("Quantity") {
                if let quantityModel {
                    QuantityStepperControl(model: quantityModel, unit: item.unit)
                } else {
                    // Brief render before `.task` wires the model up —
                    // fall back to the read-only label so layout
                    // doesn't pop in.
                    Text("\(item.quantity) \(item.unit.displayLabel)")
                }
            }

            if let expiresAt = item.expiresAt {
                Section("Expires") {
                    Text(expiresAt, style: .date)
                }
            }

            if let notes = item.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            if isSavingPhoto {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Saving photo…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
    }

    /// Horizontal strip of secondary photos. The primary photo is
    /// already shown in the header section above, so the strip starts
    /// at index 1. Each tile uses `thumbnailData` (decoded ~256 px)
    /// rather than the full `imageData` — list-row decode of multiple
    /// 2048 px JPEGs would hitch on appearance per Phase 5 exit
    /// criterion #2.
    @ViewBuilder
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    if index >= 1 {
                        photoStripTile(for: photo, at: index)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func photoStripTile(for photo: ItemPhoto, at index: Int) -> some View {
        Button {
            pagerStartIndex = index
        } label: {
            Group {
                if let uiImage = photo.thumbnailUIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Thumbnail decode failed — show a neutral
                    // placeholder rather than a broken-image icon
                    // (this strip is meant to be glanceable, not a
                    // diagnostic surface).
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await makePrimary(photo) }
            } label: {
                Label("Make Primary", systemImage: "star")
            }
            Button(role: .destructive) {
                Task { await deletePhoto(photo) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("itemDetail.photoStrip.tile.\(index)")
    }

    /// Bridges the optional `Int` start index into a sheet-`item:`
    /// binding. The wrapper struct gives `Identifiable` conformance to
    /// the bare integer.
    private var pagerItemBinding: Binding<PagerStartIndex?> {
        Binding(
            get: {
                guard let index = pagerStartIndex else { return nil }
                return PagerStartIndex(value: index)
            },
            set: { newValue in
                pagerStartIndex = newValue?.value
            }
        )
    }

    @ViewBuilder
    private func photoMenu(for item: Item) -> some View {
        Menu {
            // Plain Button → state flag → top-level `.photosPicker`
            // modifier. PhotosPicker is the modern, out-of-process
            // library path — no `NSPhotoLibraryUsageDescription`
            // needed because the user picks in a separate process
            // and only the chosen asset crosses the boundary.
            Button {
                isPresentingLibraryPicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
            // Camera capture requires `NSCameraUsageDescription` in
            // Info.plist (added in this PR). Older simulators report
            // camera unavailable; recent ones with macOS Continuity
            // Camera report it available. Either way the menu reflects
            // device capability accurately.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    isPresentingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
        } label: {
            Label("Add Photo", systemImage: "plus.viewfinder")
        }
        .disabled(isSavingPhoto)
        .accessibilityIdentifier("itemDetail.addPhoto")
    }

    private func reload() async {
        guard let itemID else {
            item = nil
            photos = []
            quantityModel = nil
            return
        }
        do {
            let fetched = try await repositories.item.item(id: itemID)
            item = fetched
            photos = try await repositories.photo.photos(for: itemID)
            if let fetched {
                rebindQuantityModel(for: fetched)
            } else {
                quantityModel = nil
            }
        } catch {
            item = nil
            photos = []
            quantityModel = nil
        }
    }

    /// Lazily creates the stepper model on first load and afterwards
    /// just resets its baseline to the freshly-fetched quantity. We
    /// don't recreate the model on every reload — re-creating it
    /// would clobber whatever optimistic value the user just tapped
    /// in if the reload fires mid-debounce.
    @MainActor
    private func rebindQuantityModel(for fetched: Item) {
        if let existing = quantityModel {
            // If the user is mid-burst and their optimistic value
            // hasn't drained to the repo yet, keep the in-flight
            // value — the next debounce will write it. Otherwise
            // accept the freshly-fetched canonical quantity (e.g.
            // from a CloudKit push or an edit-form save).
            if !existing.hasPendingWrite {
                existing.reset(to: fetched.quantity)
            }
        } else {
            let repository = repositories.item
            quantityModel = QuantityStepperModel(
                initialQuantity: fetched.quantity,
                persist: { newQuantity in
                    // Issue #118: use the partial-update API so a
                    // long-press burst can't race an edit-form save
                    // and overwrite `name` / `expiresAt`. The previous
                    // shape did fetch-modify-save of the whole `Item`,
                    // which read stale fields in the window between a
                    // form save and the stepper persist.
                    // `updateQuantity` is atomic at the repository
                    // layer — it touches only the quantity column. If
                    // the row was deleted between debounce schedule
                    // and persist, the implementation no-ops (same
                    // shape as `update(_:)`'s missing-row semantics)
                    // and the detail view's reload catches up.
                    try await repository.updateQuantity(
                        id: fetched.id,
                        quantity: newQuantity
                    )
                },
                onPersistFailure: {
                    Task { await reload() }
                }
            )
        }
    }

}

/// Photo-attachment side-effects. Lives in an extension so the main
/// struct body stays under SwiftLint's `type_body_length` ceiling —
/// these are independent of the rest of the detail screen's state and
/// only touch the photo repository plus a couple of `@State` flags.
extension ItemDetailView {
    fileprivate func saveCameraImage(_ image: UIImage, itemID: Item.ID) async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do {
            _ = try await savePhotoFromUIImage(
                image,
                itemID: itemID,
                nextSortOrder: Int16(photos.count),
                repository: repositories.photo
            )
            await reload()
        } catch {
            photoErrorMessage = "Try again."
        }
    }

    /// Deletes a photo and reloads. The repository handles the row
    /// removal; promote-on-primary-delete falls out for free because
    /// the strip resorts by sortOrder ascending — the next photo
    /// (lowest remaining sortOrder) becomes `photos.first` on the
    /// next reload.
    fileprivate func deletePhoto(_ photo: ItemPhoto) async {
        do {
            try await repositories.photo.delete(id: photo.id)
            await reload()
        } catch {
            photoErrorMessage = "Try again."
        }
    }

    /// Promotes a non-primary photo to the primary slot. The promote
    /// service writes a single row with `currentMin - 1` so reorder
    /// stays an O(1) write rather than an N-row renumber pass.
    fileprivate func makePrimary(_ photo: ItemPhoto) async {
        do {
            _ = try await makePhotoPrimary(
                photo,
                among: photos,
                repository: repositories.photo
            )
            await reload()
        } catch {
            photoErrorMessage = "Try again."
        }
    }

    fileprivate func saveLibraryPick(_ selection: PhotosPickerItem, itemID: Item.ID) async {
        isSavingPhoto = true
        defer {
            isSavingPhoto = false
            // Drop the selection back to nil so re-picking the same
            // asset triggers `.onChange` again instead of being
            // dropped as a duplicate.
            pickerSelection = nil
        }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw PhotoSaveError.invalidImageData
            }
            _ = try await savePhotoFromData(
                data,
                itemID: itemID,
                nextSortOrder: Int16(photos.count),
                repository: repositories.photo
            )
            await reload()
        } catch {
            photoErrorMessage = "Try again."
        }
    }
}

extension ItemPhoto {
    /// Decoded `UIImage` for the persisted full-resolution data, or
    /// `nil` if the bytes couldn't be parsed (corruption, schema
    /// mismatch from a version skew, etc.). Used for the primary
    /// header in the detail view.
    fileprivate var uiImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }

    /// Decoded thumbnail for strip-row display. Reading the smaller
    /// inline blob keeps strip appearance hitch-free even with a
    /// five-photo item per Phase 5 exit criterion #2.
    fileprivate var thumbnailUIImage: UIImage? {
        guard let thumbnailData else { return nil }
        return UIImage(data: thumbnailData)
    }
}

/// Identifiable wrapper so the `pagerStartIndex` `Int?` can drive a
/// `sheet(item:)` modifier — the modifier's identity-based reset
/// behavior is exactly what we want when the user taps a different
/// strip tile (sheet re-presents at the new index instead of staying
/// stuck on the old one).
private struct PagerStartIndex: Identifiable, Hashable {
    let value: Int
    var id: Int { value }
}

#Preview("Empty") {
    NavigationStack {
        ItemDetailView(itemID: nil)
    }
    .environment(\.repositories, .makePreview())
}

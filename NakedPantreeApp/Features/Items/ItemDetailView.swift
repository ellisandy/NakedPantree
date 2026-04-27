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
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()
                        .accessibilityLabel(Text("Photo of \(item.name)"))
                }
                .listRowInsets(EdgeInsets())
            }

            Section("Quantity") {
                Text("\(item.quantity) \(item.unit.displayLabel)")
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
            return
        }
        do {
            item = try await repositories.item.item(id: itemID)
            photos = try await repositories.photo.photos(for: itemID)
        } catch {
            item = nil
            photos = []
        }
    }

    private func saveCameraImage(_ image: UIImage, itemID: Item.ID) async {
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

    private func saveLibraryPick(_ selection: PhotosPickerItem, itemID: Item.ID) async {
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
    /// mismatch from a version skew, etc.). The thumbnail field could
    /// be substituted here if `imageData` reads start to dominate
    /// detail-view appearance time — measure first.
    fileprivate var uiImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}

#Preview("Empty") {
    NavigationStack {
        ItemDetailView(itemID: nil)
    }
    .environment(\.repositories, .makePreview())
}

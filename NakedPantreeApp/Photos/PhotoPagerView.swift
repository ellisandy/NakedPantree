import NakedPantreeDomain
import SwiftUI
import UIKit

/// Full-screen pager for an item's photos, presented as a sheet from
/// the detail view. Swipe between photos via SwiftUI's paging
/// `TabView` style; tap **Delete** to remove the current photo, **Done**
/// to dismiss.
///
/// Eager full-resolution decode is intentional for v1.0 — the pager is
/// a foreground, user-driven surface where the responsiveness of
/// "swipe and the next photo is already there" beats lazy memory
/// reclamation. A 5-photo item holds ~10 MB of decoded `UIImage` while
/// the pager is open. If real-device perf in 5.4 shows this hurts,
/// move to per-page `.onAppear` decode + `.onDisappear` release.
struct PhotoPagerView: View {
    let photos: [ItemPhoto]
    let initialIndex: Int
    let onDelete: (ItemPhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(photos: [ItemPhoto], initialIndex: Int, onDelete: @escaping (ItemPhoto) -> Void) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDelete = onDelete
        // `@State`'s initial value is captured once at construction;
        // subsequent renders honor the in-flight value, not the param.
        // That's the desired behavior here — the user's swipes update
        // `currentIndex` and we don't want re-rendering with the same
        // `initialIndex` to snap back.
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    pageContent(for: photo)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if photos.indices.contains(currentIndex) {
                    ToolbarItem(placement: .destructiveAction) {
                        Button {
                            let photo = photos[currentIndex]
                            // Dismiss before the delete callback fires
                            // — the parent reloads `photos` and the
                            // pager re-opens with stale data otherwise.
                            dismiss()
                            onDelete(photo)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("photoPager.delete")
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        guard photos.count > 1, photos.indices.contains(currentIndex) else { return "" }
        return "\(currentIndex + 1) of \(photos.count)"
    }

    @ViewBuilder
    private func pageContent(for photo: ItemPhoto) -> some View {
        if let uiImage = photo.fullResolutionUIImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Photo"))
        } else {
            // Decode failed — corrupted blob or schema skew. Plain
            // text per voice rules (failures aren't a personality
            // moment).
            Text("This photo can't be loaded.")
                .foregroundStyle(.white)
        }
    }
}

extension ItemPhoto {
    /// Decoded full-resolution `UIImage` for the persisted `imageData`.
    /// `nil` when the bytes can't be parsed. Named so it's distinct
    /// from the `thumbnailUIImage` accessor used in the strip.
    fileprivate var fullResolutionUIImage: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }
}

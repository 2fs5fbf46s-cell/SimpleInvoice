import SwiftUI
import PhotosUI

struct PhotosImportButton: View {
    let onPick: (Data, String) -> Void

    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: 0,        // 0 = unlimited
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("Select Photos", systemImage: "photo.on.rectangle.angled")
        }
        .onChange(of: selection) { _, newItems in
            guard !newItems.isEmpty else { return }

            Task {
                for item in newItems {
                    do {
                        // Get image data
                        if let data = try await item.loadTransferable(type: Data.self) {
                            let name = suggestedFileName(for: item)
                            onPick(data, name)
                        }
                    } catch {
                        // silently ignore a single failed item
                        continue
                    }
                }
                // Clear after import so you can pick again
                selection.removeAll()
            }
        }
    }

    private func suggestedFileName(for item: PhotosPickerItem) -> String {
        // Use a stable default name; PhotosPickerItem doesn't expose the original filename reliably
        let stamp = Int(Date().timeIntervalSince1970)
        return "Photo-\(stamp)-\(UUID().uuidString.prefix(6)).jpg"
    }
}

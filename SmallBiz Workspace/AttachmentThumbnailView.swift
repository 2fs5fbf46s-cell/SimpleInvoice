import SwiftUI
import QuickLookThumbnailing

/// A square, readable preview of an attached file — the photo itself, or the
/// first page of a PDF/document — rendered by QuickLook, so every file type
/// the app can attach gets a real thumbnail through one code path.
struct AttachmentThumbnailView: View {
    let file: FileItem?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage? = nil
    @State private var didFail = false

    private static let requestSide: CGFloat = 220

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if didFail {
                    Image(systemName: "doc")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: file?.relativePath) { await load() }
    }

    private func load() async {
        guard let file, let url = try? AppFileStore.absoluteURL(forRelativePath: file.relativePath) else {
            didFail = true
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: Self.requestSide, height: Self.requestSide),
            scale: displayScale,
            representationTypes: .thumbnail
        )
        do {
            image = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        } catch {
            didFail = true
        }
    }
}

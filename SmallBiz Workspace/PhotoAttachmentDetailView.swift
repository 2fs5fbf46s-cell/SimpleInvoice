//
//  PhotoAttachmentDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Full-size photo + a caption field, opened by tapping an image attachment
/// on a Job. Non-image attachments keep going straight to QuickLook — this
/// view exists specifically so a job photo can carry its own note (e.g.
/// "cracked pipe, north wall") separate from the job's own Notes field.
struct PhotoAttachmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var attachment: JobAttachment

    @State private var captionDraft: String = ""
    @State private var pendingSaveTask: Task<Void, Never>? = nil
    @State private var uiImage: UIImage? = nil
    @State private var loadError: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        if let uiImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else if loadError != nil {
                            ContentUnavailableView(
                                "Photo Unavailable",
                                systemImage: "photo.badge.exclamationmark",
                                description: Text(loadError ?? "")
                            )
                            .frame(height: 240)
                        } else {
                            ProgressView()
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.headline)

                        TextEditor(text: $captionDraft)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onChange(of: captionDraft) { _, newValue in
                                scheduleSave(newValue)
                            }

                        Text("Changes save automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(attachment.file?.displayName.isEmpty == false ? attachment.file!.displayName : "Photo")
            .navigationBarTitleDisplayMode(.inline)
            .sbwNavigationBarBackdrop()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        pendingSaveTask?.cancel()
                        saveNow()
                        dismiss()
                    }
                }
            }
            .onAppear {
                captionDraft = attachment.notes
                loadImage()
            }
        }
    }

    private func loadImage() {
        guard let file = attachment.file else {
            loadError = "This attachment's file record is missing."
            return
        }
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            uiImage = UIImage(contentsOfFile: url.path)
            if uiImage == nil {
                loadError = "Could not load this image."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func scheduleSave(_ value: String) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            attachment.notes = value
            saveNow()
        }
    }

    private func saveNow() {
        attachment.notes = captionDraft
        try? modelContext.save()
    }
}

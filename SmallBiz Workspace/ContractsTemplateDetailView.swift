//
//  ContractTemplateDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractTemplateDetailView: View {
    @Environment(\.modelContext) private var modelContext

    // ✅ CRITICAL: @Bindable so edits persist with SwiftData
    @Bindable var template: ContractTemplate

    // Autosave throttle
    @State private var saveWorkItem: DispatchWorkItem? = nil

    // ✅ Show real save errors
    @State private var saveError: String? = nil

    var body: some View {
        Form {
            Section("Template Info") {
                TextField("Template Name", text: $template.name)
                    .textInputAutocapitalization(.words)

                TextField("Category", text: $template.category)
                    .textInputAutocapitalization(.words)

                Toggle("Built-in (locked)", isOn: $template.isBuiltIn)
                    .disabled(true)
            }

            Section("Template Body") {
                TextEditor(text: $template.body)
                    .frame(minHeight: 280)
                    .font(.body)
                    .textInputAutocapitalization(.sentences)
            }

            Section {
                Text("Changes auto-save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)

        // Autosave edits
        .onChange(of: template.name) { _, _ in scheduleSave() }
        .onChange(of: template.category) { _, _ in scheduleSave() }
        .onChange(of: template.body) { _, _ in scheduleSave() }

        // Safety save when leaving screen
        .onDisappear { forceSaveNow() }

        // Error alert
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var displayTitle: String {
        let t = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Template" : t
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()

        let work = DispatchWorkItem {
            do {
                try modelContext.save()
            } catch {
                saveError = error.localizedDescription
            }
        }

        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func forceSaveNow() {
        saveWorkItem?.cancel()
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

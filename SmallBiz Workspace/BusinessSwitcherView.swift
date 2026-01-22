//
//  BusinessSwitcherView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import SwiftUI
import SwiftData

struct BusinessSwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var businesses: [Business]

    @State private var newBusinessName: String = ""

    var body: some View {
        Form {
            Section("Active Business") {
                if let id = activeBiz.activeBusinessID,
                   let active = businesses.first(where: { $0.id == id }) {
                    Text(active.name).font(.headline)
                } else {
                    Text("None selected").foregroundStyle(.secondary)
                }
            }

            Section("Businesses") {
                if businesses.isEmpty {
                    Text("No businesses yet").foregroundStyle(.secondary)
                } else {
                    ForEach(businesses) { b in
                        Button {
                            activeBiz.setActiveBusiness(b.id)
                        } label: {
                            HStack {
                                Text(b.name)
                                Spacer()
                                if b.id == activeBiz.activeBusinessID {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                }
            }

            Section("Add Business") {
                TextField("Business name", text: $newBusinessName)
                Button("Create") {
                    let name = newBusinessName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }

                    let created = Business(name: name, isActive: true)
                    modelContext.insert(created)
                    try? modelContext.save()

                    activeBiz.setActiveBusiness(created.id)
                    newBusinessName = ""
                }
            }
        }
        .navigationTitle("Businesses")
        .onAppear {
            try? activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        }
    }
}

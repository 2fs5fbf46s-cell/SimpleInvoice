//
//  AppLockGateView.swift
//  SmallBiz Workspace
//

import SwiftUI

struct AppLockGateView<Content: View>: View {
    @EnvironmentObject private var lock: AppLockManager
    let content: () -> Content

    @State private var didAttemptAutoUnlock = false

    var body: some View {
        Group {
            if lock.isUnlocked {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))

                    Text("App Locked")
                        .font(.title2).bold()

                    Button("Unlock") {
                        Task { await lock.unlockIfNeeded() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        // ✅ Runs once per view lifetime (prevents repeated prompts)
        .task {
            guard !didAttemptAutoUnlock else { return }
            didAttemptAutoUnlock = true
            await lock.unlockIfNeeded()
        }
    }
}

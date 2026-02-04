//
//  AppTabView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/18/26.
//

import Foundation
import SwiftUI

enum AppTab: Hashable {
    case dashboard, invoices, create, clients, more
}

struct AppTabView: View {
    @State private var tab: AppTab = .dashboard
    @State private var showCreateSheet = false

    // MUST be @State so NavigationStack(path:) can push.
    @State private var morePath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {

            NavigationStack {
                DashboardView()
            }
            .tag(AppTab.dashboard)
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }

            NavigationStack {
                InvoiceListView()
            }
            .tag(AppTab.invoices)
            .tabItem { Label("Invoices", systemImage: "doc.plaintext") }

            // Center "+"
            Color.clear
                .tag(AppTab.create)
                .tabItem { Label("Create", systemImage: "plus.circle.fill") }

            NavigationStack {
                ClientListView()
            }
            .tag(AppTab.clients)
            .tabItem { Label("Clients", systemImage: "person.2") }

            // MoreView already contains NavigationStack(path:)
            MoreView(path: $morePath)
                .tag(AppTab.more)
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .background(
            TabBarReselectObserver { reselectedIndex in
                // Tab order: dashboard(0), invoices(1), create(2), clients(3), more(4)
                if reselectedIndex == 4 {
                    // Re-tapping the already-selected More tab pops to root.
                    morePath = NavigationPath()
                }
            }
            .frame(width: 0, height: 0)
        )
        .tint(SBWTheme.brandBlue)

        .onChange(of: tab) { _, newValue in
            if newValue == .more {
                // Switch to More = start at root
                morePath = NavigationPath()
            }

            if newValue == .create {
                tab = .dashboard
                showCreateSheet = true
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateMenuSheet()
        }
    }
}

// MARK: - Tab bar reselection observer (detects tapping the already-selected tab item)

private struct TabBarReselectObserver: UIViewControllerRepresentable {
    var onReselect: (Int) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let tabBarController = uiViewController.tabBarController else { return }

        // Install delegate once.
        if context.coordinator.tabBarController !== tabBarController {
            context.coordinator.tabBarController = tabBarController
            tabBarController.delegate = context.coordinator
        }

        context.coordinator.onReselect = onReselect
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        weak var tabBarController: UITabBarController?
        var lastSelectedIndex: Int?
        var onReselect: ((Int) -> Void)?

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let idx = tabBarController.selectedIndex

            // If the same tab item is tapped again, consider it a reselection.
            if let last = lastSelectedIndex, last == idx {
                onReselect?(idx)
            }

            lastSelectedIndex = idx
        }
    }
}

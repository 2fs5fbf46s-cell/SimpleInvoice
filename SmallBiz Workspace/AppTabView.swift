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

            NavigationStack {
                MoreView()
            }
            .tag(AppTab.more)
            .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .onChange(of: tab) { _, newValue in
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

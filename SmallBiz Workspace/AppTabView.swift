//
//  AppTabView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/18/26.
//

import Foundation
import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case dashboard, invoices, create, clients, more
}

struct AppTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var invoices: [Invoice]
    @Query private var contracts: [Contract]

    @State private var tab: AppTab = .dashboard
    @State private var showCreateSheet = false
    @State private var deepLinkedEstimate: Invoice? = nil
    @State private var deepLinkedInvoice: Invoice? = nil
    @State private var deepLinkedContract: Contract? = nil
    @State private var deepLinkedBookingRequest: BookingRequestItem? = nil
    @State private var showBookingAdminSheet = false
    @State private var toastDismissTask: Task<Void, Never>? = nil

    // MUST be @State so NavigationStack(path:) can push.
    @State private var morePath = NavigationPath()
    @ObservedObject private var portalReturn = PortalReturnRouter.shared
    @ObservedObject private var notificationRouter = NotificationRouter.shared

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
        .overlay(alignment: .bottom) {
            if let message = notificationRouter.toastMessage {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
        .sheet(item: $deepLinkedEstimate, onDismiss: {
            portalReturn.consumeEstimateRequest()
        }) { estimate in
            NavigationStack {
                InvoiceDetailView(invoice: estimate)
            }
        }
        .sheet(item: $deepLinkedInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(invoice: invoice)
            }
        }
        .sheet(item: $deepLinkedContract) { contract in
            NavigationStack {
                ContractDetailView(contract: contract)
            }
        }
        .sheet(item: $deepLinkedBookingRequest) { request in
            NavigationStack {
                BookingDetailView(request: request)
            }
        }
        .sheet(isPresented: $showBookingAdminSheet) {
            NavigationStack {
                BookingsListView()
            }
        }
        .onChange(of: portalReturn.requestedEstimateID) { _, id in
            routeToEstimate(id: id)
        }
        .onChange(of: notificationRouter.pendingPayload) { _, payload in
            routeFromNotification(payload)
        }
        .onChange(of: notificationRouter.toastMessage) { _, message in
            guard message != nil else {
                toastDismissTask?.cancel()
                toastDismissTask = nil
                return
            }
            toastDismissTask?.cancel()
            toastDismissTask = Task {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                await MainActor.run {
                    notificationRouter.toastMessage = nil
                }
            }
        }
        .onChange(of: invoices.count) { _, _ in
            if let requested = portalReturn.requestedEstimateID {
                EstimateDecisionSync.applyPendingDecisions(in: modelContext)
                routeToEstimate(id: requested)
            }
        }
        .task {
            EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            if let requested = portalReturn.requestedEstimateID {
                routeToEstimate(id: requested)
            }
        }
    }

    private func routeToEstimate(id: UUID?) {
        guard let id else { return }
        guard let invoice = invoices.first(where: { $0.id == id }) else { return }
        tab = .invoices
        deepLinkedEstimate = invoice
    }

    private func routeFromNotification(_ payload: NotificationRoutePayload?) {
        guard let payload else { return }
        let effectivePayload = payloadFromDeepLinkIfNeeded(payload)

        if let bizID = UUID(uuidString: effectivePayload.businessId),
           activeBiz.activeBusinessID != bizID {
            activeBiz.setActiveBusiness(bizID)
        }

        if let invoiceID = effectivePayload.invoiceId,
           let id = UUID(uuidString: invoiceID),
           let invoice = invoices.first(where: { $0.id == id }) {
            tab = .invoices
            deepLinkedInvoice = invoice
            notificationRouter.consumePendingPayload()
            return
        }

        if let contractID = effectivePayload.contractId,
           let id = UUID(uuidString: contractID),
           let contract = contracts.first(where: { $0.id == id }) {
            tab = .more
            deepLinkedContract = contract
            notificationRouter.consumePendingPayload()
            return
        }

        if let bookingRequestID = effectivePayload.bookingRequestId {
            Task { await routeToBookingRequest(payload: effectivePayload, requestId: bookingRequestID) }
            return
        }

        let eventKey = effectivePayload.event.lowercased()
        if eventKey.contains("booking") {
            tab = .more
            showBookingAdminSheet = true
            notificationRouter.consumePendingPayload()
            return
        }

        if notificationRouter.openFallbackIfPossible(effectivePayload) {
            notificationRouter.consumePendingPayload()
            return
        }

        notificationRouter.showToast("Notification opened, but no matching screen was found.")
        notificationRouter.consumePendingPayload()
    }

    private func payloadFromDeepLinkIfNeeded(_ payload: NotificationRoutePayload) -> NotificationRoutePayload {
        guard payload.invoiceId == nil, payload.contractId == nil, payload.bookingRequestId == nil else { return payload }
        guard let deepLink = payload.deepLink, let url = URL(string: deepLink) else { return payload }
        guard (url.scheme ?? "").lowercased() == "sbw" else { return payload }

        let host = (url.host ?? "").lowercased()
        let parts = url.path.split(separator: "/").map(String.init)
        let primary = host.isEmpty ? (parts.first?.lowercased() ?? "") : host
        let targetID = host.isEmpty ? (parts.dropFirst().first ?? parts.first) : parts.first
        let business = payload.businessId

        switch primary {
        case "invoice":
            return NotificationRoutePayload(
                notificationId: payload.notificationId,
                event: payload.event,
                businessId: business,
                invoiceId: targetID,
                deepLink: payload.deepLink,
                portalURL: payload.portalURL
            ) ?? payload
        case "contract":
            return NotificationRoutePayload(
                notificationId: payload.notificationId,
                event: payload.event,
                businessId: business,
                contractId: targetID,
                deepLink: payload.deepLink,
                portalURL: payload.portalURL
            ) ?? payload
        case "booking", "booking-request":
            return NotificationRoutePayload(
                notificationId: payload.notificationId,
                event: payload.event,
                businessId: business,
                bookingRequestId: targetID,
                deepLink: payload.deepLink,
                portalURL: payload.portalURL
            ) ?? payload
        default:
            return payload
        }
    }

    @MainActor
    private func routeToBookingRequest(payload: NotificationRoutePayload, requestId: String) async {
        do {
            let results = try await PortalBackend.shared.fetchBookingRequests(
                businessId: payload.businessId,
                status: "all"
            )
            guard let dto = results.first(where: { $0.requestId == requestId }) else {
                if notificationRouter.openFallbackIfPossible(payload) == false {
                    showBookingAdminSheet = true
                    tab = .more
                    notificationRouter.showToast("Opened bookings admin. Request \(requestId) was not found.")
                }
                notificationRouter.consumePendingPayload()
                return
            }

            let item = BookingRequestItem(
                requestId: dto.requestId,
                businessId: dto.businessId,
                slug: dto.slug,
                clientName: dto.clientName,
                clientEmail: dto.clientEmail,
                clientPhone: dto.clientPhone,
                requestedStart: dto.requestedStart,
                requestedEnd: dto.requestedEnd,
                serviceType: dto.serviceType,
                notes: dto.notes,
                status: dto.status,
                createdAtMs: dto.createdAtMs
            )

            tab = .more
            deepLinkedBookingRequest = item
            notificationRouter.consumePendingPayload()
        } catch {
            if notificationRouter.openFallbackIfPossible(payload) == false {
                showBookingAdminSheet = true
                tab = .more
                notificationRouter.showToast("Opened bookings admin. Push route failed: \(error.localizedDescription)")
            }
            notificationRouter.consumePendingPayload()
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

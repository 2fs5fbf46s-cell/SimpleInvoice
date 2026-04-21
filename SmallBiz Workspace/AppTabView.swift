//
//  AppTabView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/18/26.
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import UIKit

enum AppTab: Hashable {
    case dashboard, invoices, create, clients, more
}

private enum AppTabRouteDestination: Hashable {
    case setupPayments
}

struct AppTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var invoices: [Invoice]
    @Query private var contracts: [Contract]

    @State private var tab: AppTab = .dashboard
    @State private var lastSelectedTab: AppTab = .dashboard
    @State private var showCreateSheet = false
    @State private var deepLinkedEstimate: Invoice? = nil
    @State private var deepLinkedInvoice: Invoice? = nil
    @State private var deepLinkedContract: Contract? = nil
    @State private var deepLinkedBookingRequest: BookingRequestItem? = nil
    @State private var showBookingAdminSheet = false
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var coachMarkFrames: [String: CGRect] = [:]
    @State private var isWalkthroughPresented = false
    @State private var walkthroughStepIndex = 0
    @State private var walkthroughValidationTask: Task<Void, Never>? = nil

    // MUST be @State so NavigationStack(path:) can push.
    @State private var dashboardPath = NavigationPath()
    @State private var invoicesPath = NavigationPath()
    @State private var clientsPath = NavigationPath()
    @State private var morePath = NavigationPath()
    @State private var dashboardResetID = UUID()
    @State private var invoicesResetID = UUID()
    @State private var clientsResetID = UUID()
    @State private var moreResetID = UUID()
    @ObservedObject private var portalReturn = PortalReturnRouter.shared
    @ObservedObject private var notificationRouter = NotificationRouter.shared

    var body: some View {
        TabView(selection: $tab) {

            NavigationStack(path: $dashboardPath) {
                DashboardView()
            }
            .id(dashboardResetID)
            .tag(AppTab.dashboard)
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }

            NavigationStack(path: $invoicesPath) {
                InvoiceListView(businessID: activeBiz.activeBusinessID)
            }
            .id(invoicesResetID)
            .tag(AppTab.invoices)
            .tabItem { Label("Invoices", systemImage: "doc.plaintext") }

            // Center "+"
            Color.clear
                .tag(AppTab.create)
                .tabItem { Label("Create", systemImage: "plus.circle.fill") }

            NavigationStack(path: $clientsPath) {
                ClientListView(businessID: activeBiz.activeBusinessID)
            }
            .id(clientsResetID)
            .tag(AppTab.clients)
            .tabItem { Label("Clients", systemImage: "person.2") }

            NavigationStack(path: $morePath) {
                MoreView()
                    .navigationDestination(for: AppTabRouteDestination.self) { destination in
                        switch destination {
                        case .setupPayments:
                            SetupPaymentsView()
                        }
                    }
            }
            .id(moreResetID)
            .tag(AppTab.more)
            .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .coordinateSpace(name: CoachMarksOverlay.coordinateSpaceName)
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
        .overlay(alignment: .bottom) {
            walkthroughTabTargetMarkers
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
        .overlay {
            if isWalkthroughPresented {
                CoachMarksOverlay(
                    steps: WalkthroughSteps.core,
                    currentIndex: walkthroughStepIndex,
                    frames: coachMarkFrames,
                    onBack: { walkthroughBackTapped() },
                    onNext: { walkthroughNextTapped() },
                    onSkip: { walkthroughSkipTapped() },
                    onDone: { walkthroughDoneTapped() }
                )
                .zIndex(20)
            }
        }
        .background(
            TabBarReselectObserver { reselectedIndex in
                if let reselectedTab = tabForIndex(reselectedIndex) {
                    resetPath(for: reselectedTab)
                }
            }
            .frame(width: 0, height: 0)
        )
        .tint(SBWTheme.brandBlue)

        .onChange(of: tab) { _, newValue in
            if newValue == .create {
                tab = lastSelectedTab
                showCreateSheet = true
                return
            }

            resetPath(for: newValue)
            lastSelectedTab = newValue
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateMenuSheet()
        }
        .sheet(item: $deepLinkedEstimate, onDismiss: {
            portalReturn.consumeEstimateRequest()
        }) { estimate in
            NavigationStack {
                InvoiceOverviewView(invoice: estimate)
            }
        }
        .sheet(item: $deepLinkedInvoice) { invoice in
            NavigationStack {
                InvoiceOverviewView(invoice: invoice)
            }
        }
        .sheet(item: $deepLinkedContract) { contract in
            NavigationStack {
                ContractSummaryView(contract: contract)
            }
        }
        .sheet(item: $deepLinkedBookingRequest) { request in
            NavigationStack {
                BookingOverviewView(request: request)
            }
        }
        .sheet(isPresented: $showBookingAdminSheet) {
            NavigationStack {
                BookingsListView(businessID: activeBiz.activeBusinessID)
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
        .onPreferenceChange(CoachMarkFramePreferenceKey.self) { newValue in
            coachMarkFrames = newValue
        }
        .onChange(of: walkthroughStepIndex) { _, _ in
            scheduleWalkthroughValidation()
        }
        .onChange(of: isWalkthroughPresented) { _, isPresented in
            if isPresented {
                scheduleWalkthroughValidation()
            } else {
                walkthroughValidationTask?.cancel()
                walkthroughValidationTask = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WalkthroughState.runRequestNotification)) { _ in
            startWalkthrough(force: true)
        }
        .onReceive(AppRouteCenter.shared.publisher) { route in
            handleAppRoute(route)
        }
        .task {
            EstimateDecisionSync.applyPendingDecisions(in: modelContext)
            if let requested = portalReturn.requestedEstimateID {
                routeToEstimate(id: requested)
            }
            if OnboardingState.isComplete && !WalkthroughState.isComplete {
                startWalkthrough(force: false)
            }
        }
    }

    private func tabForIndex(_ index: Int) -> AppTab? {
        switch index {
        case 0: return .dashboard
        case 1: return .invoices
        case 2: return .create
        case 3: return .clients
        case 4: return .more
        default: return nil
        }
    }

    private func resetPath(for tab: AppTab) {
        switch tab {
        case .dashboard:
            dashboardPath = NavigationPath()
            dashboardResetID = UUID()
        case .invoices:
            invoicesPath = NavigationPath()
            invoicesResetID = UUID()
        case .clients:
            clientsPath = NavigationPath()
            clientsResetID = UUID()
        case .more:
            morePath = NavigationPath()
            moreResetID = UUID()
        case .create:
            break
        }
    }

    private var walkthroughTabTargetMarkers: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / 5
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: width, height: 56)
                    .coachMark(id: "walkthrough.tab.dashboard")
                Color.clear
                    .frame(width: width, height: 56)
                    .coachMark(id: "walkthrough.tab.invoices")
                Color.clear
                    .frame(width: width, height: 56)
                    .coachMark(id: "walkthrough.tab.create")
                Color.clear
                    .frame(width: width, height: 56)
                    .coachMark(id: "walkthrough.tab.clients")
                Color.clear
                    .frame(width: width, height: 56)
                    .coachMark(id: "walkthrough.tab.more")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 62)
    }

    @MainActor
    private func startWalkthrough(force: Bool) {
        guard !isWalkthroughPresented else { return }
        guard force || !WalkthroughState.isComplete else { return }
        isWalkthroughPresented = true
        walkthroughStepIndex = 0
        showCreateSheet = false
        selectTabForWalkthrough(.dashboard)
    }

    @MainActor
    private func walkthroughBackTapped() {
        guard walkthroughStepIndex > 0 else { return }
        walkthroughStepIndex -= 1
    }

    @MainActor
    private func walkthroughNextTapped() {
        guard walkthroughStepIndex < WalkthroughSteps.core.count - 1 else {
            walkthroughDoneTapped()
            return
        }
        walkthroughStepIndex += 1
    }

    @MainActor
    private func walkthroughSkipTapped() {
        WalkthroughState.markComplete()
        isWalkthroughPresented = false
    }

    @MainActor
    private func walkthroughDoneTapped() {
        WalkthroughState.markComplete()
        isWalkthroughPresented = false
        Haptics.success()
    }

    @MainActor
    private func scheduleWalkthroughValidation() {
        walkthroughValidationTask?.cancel()
        guard isWalkthroughPresented else { return }
        guard WalkthroughSteps.core.indices.contains(walkthroughStepIndex) else {
            walkthroughDoneTapped()
            return
        }

        let index = walkthroughStepIndex
        let step = WalkthroughSteps.core[index]
        if let routeTab = step.routeTab {
            selectTabForWalkthrough(routeTab)
        }

        walkthroughValidationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            guard isWalkthroughPresented else { return }
            guard walkthroughStepIndex == index else { return }

            if coachMarkFrames[step.targetCoachMarkId] == nil {
                if walkthroughStepIndex < WalkthroughSteps.core.count - 1 {
                    walkthroughStepIndex += 1
                } else {
                    walkthroughDoneTapped()
                }
            }
        }
    }

    @MainActor
    private func selectTabForWalkthrough(_ destination: AppTab) {
        guard destination != .create else {
            return
        }

        if tab == destination {
            resetPath(for: destination)
            lastSelectedTab = destination
            return
        }

        tab = destination
    }

    @MainActor
    private func handleAppRoute(_ route: AppRoute) {
        switch route {
        case .clientsRoot:
            routeToTabRoot(.clients)
        case .invoicesRoot:
            routeToTabRoot(.invoices)
        case .moreRoot:
            routeToTabRoot(.more)
        case .paymentsSetup:
            routeToTabRoot(.more)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard tab == .more else { return }
                if !morePath.isEmpty {
                    morePath = NavigationPath()
                }
                morePath.append(AppTabRouteDestination.setupPayments)
            }
        case .openAppSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    @MainActor
    private func routeToTabRoot(_ destination: AppTab) {
        if tab == destination {
            resetPath(for: destination)
            lastSelectedTab = destination
            return
        }
        tab = destination
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
                createdAtMs: dto.createdAtMs,
                bookingTotalAmountCents: dto.bookingTotalAmountCents,
                depositAmountCents: dto.depositAmountCents,
                depositInvoiceId: dto.depositInvoiceId,
                depositPaidAtMs: dto.depositPaidAtMs,
                finalInvoiceId: dto.finalInvoiceId
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

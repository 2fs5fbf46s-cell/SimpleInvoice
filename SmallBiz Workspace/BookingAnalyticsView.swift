import SwiftUI
import SwiftData

struct BookingAnalyticsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.modelContext) private var modelContext

    @State private var selectedWindow: Int = 30
    @State private var isLoading = false
    @State private var analytics: BookingAnalyticsDTO? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    Picker("Window", selection: $selectedWindow) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)
                }

                if isLoading && analytics == nil {
                    HStack {
                        Spacer()
                        ProgressView("Loading analytics…")
                        Spacer()
                    }
                } else if let analytics {
                    Section("Requests") {
                        metricCard(title: "Total Requests", value: "\(analytics.totalRequests)")
                        metricCard(title: "Pending", value: "\(analytics.pendingCount)")
                        metricCard(title: "Deposit Requested", value: "\(analytics.depositRequestedCount)")
                        metricCard(title: "Deposit Paid", value: "\(analytics.depositPaidCount)")
                        metricCard(title: "Approved", value: "\(analytics.approvedCount)")
                        metricCard(title: "Declined", value: "\(analytics.declinedCount)")
                    }

                    Section("Amounts") {
                        metricCard(title: "Deposit Revenue", value: currency(fromCents: analytics.depositsTotalCents))
                        metricCard(title: "Booking Totals", value: currency(fromCents: analytics.totalsTotalCents))
                        metricCard(title: "Remaining Balance", value: currency(fromCents: analytics.remainingTotalCents))
                    }

                    Section("Conversion Rates") {
                        metricCard(title: "Approved Rate", value: percent(analytics.conversionRates.approved))
                        metricCard(title: "Declined Rate", value: percent(analytics.conversionRates.declined))
                        metricCard(title: "Deposit Requested Rate", value: percent(analytics.conversionRates.depositRequested))
                        metricCard(title: "Deposit Paid Rate", value: percent(analytics.conversionRates.depositPaid))
                    }
                } else {
                    ContentUnavailableView(
                        "No Analytics Yet",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Analytics will appear once booking activity exists for the selected window.")
                    )
                    .overlay(alignment: .center) {
                        if errorMessage != nil {
                            Button("Retry") {
                                Task { await loadAnalytics() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Booking Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadAnalytics() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await loadAnalytics()
        }
        .onChange(of: selectedWindow) { _, _ in
            Task { await loadAnalytics() }
        }
        .refreshable {
            await loadAnalytics()
        }
        .alert("Booking Analytics Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SBWTheme.cardStroke, lineWidth: 1)
                )
                .padding(.vertical, 2)
        )
    }

    private func currency(fromCents cents: Int) -> String {
        let amount = Double(max(0, cents)) / 100.0
        return amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    private func percent(_ ratio: Double) -> String {
        let normalized = min(max(ratio, 0), 1)
        return normalized.formatted(.percent.precision(.fractionLength(1)))
    }

    @MainActor
    private func loadAnalytics() async {
        guard !isLoading else { return }
        do {
            try activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
        } catch {
            // keep non-fatal
        }
        guard let businessId = activeBiz.activeBusinessID else {
            analytics = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            analytics = try await PortalBackend.shared.fetchBookingAnalytics(
                businessId: businessId,
                windowDays: selectedWindow
            )
            errorMessage = nil
        } catch {
            analytics = nil
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
import SwiftUI

struct SetupPaymentsDiagnosticsView: View {
    let businessId: UUID?

    @State private var isTestingAdmin = false
    @State private var isTestingStripe = false
    @State private var isTestingPayPalPartner = false

    @State private var adminResult = "Not run"
    @State private var stripeResult = "Not run"
    @State private var payPalPartnerResult = "Not run"

    var body: some View {
        List {
            Section("Admin") {
                diagnosticRow(
                    title: "Test Admin Backend Auth",
                    status: adminResult,
                    isLoading: isTestingAdmin
                ) {
                    Task { await runAdminTest() }
                }
            }

            Section("Stripe") {
                diagnosticRow(
                    title: "Test Stripe Endpoints",
                    status: stripeResult,
                    isLoading: isTestingStripe
                ) {
                    Task { await runStripeTest() }
                }
            }

            Section("PayPal") {
                diagnosticRow(
                    title: "Test PayPal Partner Availability",
                    status: payPalPartnerResult,
                    isLoading: isTestingPayPalPartner
                ) {
                    Task { await runPayPalPartnerTest() }
                }
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func diagnosticRow(title: String, status: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Last result: \(status)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Run", action: action)
                .buttonStyle(.bordered)
                .disabled(isLoading)
        }
        .padding(.vertical, 4)
    }

    private func runAdminTest() async {
        guard !isTestingAdmin else { return }
        isTestingAdmin = true
        defer { isTestingAdmin = false }
        let result = await PortalPaymentsAPI.shared.testAdminBackendAuth()
        adminResult = result.status
    }

    private func runStripeTest() async {
        guard !isTestingStripe else { return }
        isTestingStripe = true
        defer { isTestingStripe = false }

        guard let businessId else {
            stripeResult = "No business selected"
            return
        }

        do {
            let status = try await PortalPaymentsAPI.shared.fetchStripeConnectStatus(businessId: businessId)
            if status.chargesEnabled && status.payoutsEnabled && !status.actionRequired {
                stripeResult = "OK (active)"
            } else {
                stripeResult = "OK (action required)"
            }
        } catch {
            if case PortalBackendError.http(let code, _, _) = error, code == 401 {
                stripeResult = "Unauthorized"
                return
            }
            stripeResult = "Error"
        }
    }

    private func runPayPalPartnerTest() async {
        guard !isTestingPayPalPartner else { return }
        isTestingPayPalPartner = true
        defer { isTestingPayPalPartner = false }

        guard let businessId else {
            payPalPartnerResult = "No business selected"
            return
        }

        let available = await PortalPaymentsAPI.shared.isPayPalPartnerConnectAvailable(businessId: businessId)
        payPalPartnerResult = available ? "Available" : "Unavailable"
    }
}
#endif

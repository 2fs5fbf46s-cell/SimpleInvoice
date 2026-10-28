//
//  TapToPayViews.swift
//  SmallBiz Workspace
//

import MessageUI
import ProximityReader
import SwiftData
import SwiftUI

// MARK: - The button

/// The one way into a Tap to Pay payment. Apple requires it to look the same
/// whether or not Tap to Pay is set up — never greyed out (5.3) — with this
/// symbol (5.5) and this name (5.4, English).
struct TapToPayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Tap to Pay on iPhone", systemImage: "wave.3.right.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(Color(.systemBackground))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Takes a contactless card or digital wallet payment on this iPhone")
    }
}

// MARK: - Collect Payment

/// Checkout for one invoice: what's being paid, a tip when it settles the
/// invoice, and Tap to Pay first among the ways to pay (5.2).
struct CollectPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reader = TapToPayReader.shared

    @Bindable var invoice: Invoice
    let business: Business?
    let profile: BusinessProfile?
    var onSendLink: (() -> Void)? = nil
    var onRecordPayment: (() -> Void)? = nil

    private enum Stage: Equatable {
        case entry
        case setUp
        case collecting
        case result(TapToPayOutcome)
    }

    private enum Tip: Hashable {
        case none, percent(Int), custom
    }

    @State private var stage: Stage = .entry
    @State private var payBalance = true
    @State private var otherAmountText = ""
    @State private var tip: Tip = .none
    @State private var customTipText = ""

    private var balanceCents: Int { invoice.balanceDueCents }
    private var amountCents: Int {
        payBalance ? balanceCents : min(InvoiceAmountParser.cents(from: otherAmountText), balanceCents)
    }
    private var tipsOffered: Bool {
        TapToPayCharge.allowsTip(amountCents: amountCents, balanceDueCents: balanceCents, tipsEnabled: business?.tipsEnabled ?? false)
    }
    private var tipCents: Int {
        guard tipsOffered else { return 0 }
        switch tip {
        case .none: return 0
        case .percent(let percent): return TapToPayCharge.tipCents(percent: percent, of: amountCents)
        case .custom: return min(max(InvoiceAmountParser.cents(from: customTipText), 0), amountCents)
        }
    }
    private var clientName: String {
        let name = (invoice.client?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Client" : name
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .entry:
                    entry
                case .setUp:
                    TapToPaySetupFlow(business: business, profile: profile) { ready in
                        if ready { startCollecting() } else { stage = .entry }
                    }
                case .collecting:
                    TapToPayWorkingView(status: reader.status, processing: true)
                case .result(let outcome):
                    TapToPayResultView(
                        outcome: outcome,
                        balanceAfterCents: invoice.balanceDueCents,
                        client: invoice.client,
                        onTryAgain: { stage = .entry },
                        onDone: { dismiss() }
                    )
                }
            }
            .navigationTitle(stage == .entry ? "Collect Payment" : "Tap to Pay on iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage == .entry || stage == .setUp {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(stage == .collecting)
    }

    private var entry: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    Text("\(invoice.invoiceNumber) · \(clientName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(InvoicePaymentService.currency(amountCents + tipCents))
                        .font(.scaledSystem(size: 40, weight: .bold, relativeTo: .largeTitle))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if tipCents > 0 {
                        Text("Includes \(InvoicePaymentService.currency(tipCents)) tip")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        chip("Balance \(InvoicePaymentService.currency(balanceCents))", selected: payBalance) { payBalance = true }
                        chip("Other amount", selected: !payBalance) { payBalance = false }
                    }
                    if !payBalance {
                        TextField("Amount", text: $otherAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        if InvoiceAmountParser.cents(from: otherAmountText) > balanceCents {
                            Text("That's more than the \(InvoicePaymentService.currency(balanceCents)) still owed.")
                                .font(.caption)
                                .foregroundStyle(SBWTheme.attention)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(card)

                if tipsOffered {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TIP")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            chip("No tip", selected: tip == .none) { tip = .none }
                            ForEach(TapToPayCharge.tipPercents, id: \.self) { percent in
                                chip("\(percent)%", selected: tip == .percent(percent)) { tip = .percent(percent) }
                            }
                            chip("Custom", selected: tip == .custom) { tip = .custom }
                        }
                        if tip == .custom {
                            TextField("Tip amount", text: $customTipText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(card)
                }

                TapToPayButton { tapToPay() }
                    .disabled(amountCents <= 0)

                VStack(spacing: 0) {
                    if let onSendLink {
                        otherWay("Send a payment link", icon: "link") { dismiss(); onSendLink() }
                        Divider().padding(.leading, 44)
                    }
                    if let onRecordPayment {
                        otherWay("Record cash, check or other", icon: "banknote") { dismiss(); onRecordPayment() }
                    }
                }
                .background(card)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(Capsule().fill(selected ? Color.primary : Color(.tertiarySystemFill)))
                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func otherWay(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 20).foregroundStyle(SBWTheme.brand)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tapToPay() {
        if case .ready = reader.status { startCollecting() } else { stage = .setUp }
    }

    private func startCollecting() {
        stage = .collecting
        let amount = amountCents
        let tip = tipCents
        Task {
            let outcome = await reader.collect(
                invoice: invoice,
                amountCents: amount,
                tipCents: tip,
                business: business,
                profile: profile,
                context: modelContext
            )
            stage = outcome == .canceled ? .entry : .result(outcome)
        }
    }
}

// MARK: - Getting ready / processing

/// Shown while Apple configures this iPhone (3.9.1, 5.7) and while a payment
/// is being confirmed (5.8). Apple's own tap screen covers it in between.
struct TapToPayWorkingView: View {
    let status: TapToPayReader.Status
    var processing = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "wave.3.right.circle")
                .font(.scaledSystem(size: 56, relativeTo: .largeTitle))
                .foregroundStyle(SBWTheme.brand)
                .symbolEffect(.pulse)
            if case .preparing(let progress) = status {
                Text("Getting Tap to Pay on iPhone ready")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("This iPhone is being set up to accept payments. It's quickest the first time it's done on Wi-Fi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 240)
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } else {
                Text(processing ? "Processing payment…" : "Getting ready…")
                    .font(.title3.weight(.semibold))
                ProgressView()
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Result and receipt

/// Approved, declined or timed out, said plainly (5.9), with a receipt the
/// client can get either way (5.10).
struct TapToPayResultView: View {
    let outcome: TapToPayOutcome
    let balanceAfterCents: Int
    let client: Client?
    let onTryAgain: () -> Void
    let onDone: () -> Void

    @State private var composer: Composer?

    private enum Composer: Identifiable {
        case text, email
        var id: Self { self }
    }

    private var receipt: TapToPayReceipt? {
        switch outcome {
        case .approved(let receipt), .declined(let receipt, _): return receipt
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            mark
            if let receipt {
                Text(InvoicePaymentService.currency(receipt.totalCents))
                    .font(.scaledSystem(size: 34, weight: .bold, relativeTo: .largeTitle))
                        .fontDesign(.rounded)
                    .monospacedDigit()
            }
            Text(title).font(.title2.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 12)

            if let receipt {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SEND A RECEIPT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button { composer = .text } label: { Label("Text", systemImage: "message") }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!MFMessageComposeViewController.canSendText())
                        Button { composer = .email } label: { Label("Email", systemImage: "envelope") }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!MFMailComposeViewController.canSendMail())
                    }
                    ShareLink(item: receipt.text, subject: Text("Receipt from \(receipt.businessName)")) {
                        Label("Share…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }

            if case .approved = outcome {
                Button("Done", action: onDone).sbwProminentButton()
            } else {
                Button("Try Again", action: onTryAgain).sbwProminentButton()
                Button("Close", action: onDone).buttonStyle(.borderless)
            }
        }
        .padding(16)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .sheet(item: $composer) { kind in
            if let receipt {
                switch kind {
                case .text: TapToPayMessageComposer(recipient: client?.phone ?? "", body: receipt.text)
                case .email:
                    TapToPayMailComposer(
                        recipient: client?.email ?? "",
                        subject: "Receipt from \(receipt.businessName)",
                        body: receipt.text
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        let approved: Bool = { if case .approved = outcome { return true } else { return false } }()
        Image(systemName: approved ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.scaledSystem(size: 64, relativeTo: .largeTitle))
            .foregroundStyle(approved ? SBWTheme.success : Color.red)
            .symbolEffect(.bounce, value: approved)
    }

    private var title: String {
        switch outcome {
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .timedOut: return "Timed Out"
        case .canceled: return "Canceled"
        case .failed: return "Payment Didn't Go Through"
        }
    }

    private var detail: String {
        switch outcome {
        case .approved(let receipt):
            let card = receipt.card.map { "\($0) · " } ?? ""
            return balanceAfterCents == 0
                ? "\(card)Invoice \(receipt.invoiceNumber) is paid in full."
                : "\(card)\(InvoicePaymentService.currency(balanceAfterCents)) is still owed on invoice \(receipt.invoiceNumber)."
        case .declined(_, let reason):
            return "\(reason) The client wasn't charged."
        case .timedOut:
            return "No card was read in time. The client wasn't charged."
        case .canceled:
            return "The client wasn't charged."
        case .failed(let message):
            return message
        }
    }
}

private struct TapToPayMessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: TapToPayMessageComposer
        init(_ parent: TapToPayMessageComposer) { self.parent = parent }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        if !recipient.isEmpty { vc.recipients = [recipient] }
        vc.body = body
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
}

private struct TapToPayMailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: TapToPayMailComposer
        init(_ parent: TapToPayMailComposer) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        if !recipient.isEmpty { vc.setToRecipients([recipient]) }
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}

// MARK: - Setup

/// Whatever this iPhone still needs before it can take a payment — an
/// address for Stripe, location access (explained first, never at the last
/// second), Apple's terms — then Apple's how-to right after the terms (4.2).
/// Used by checkout, Settings and the announcement alike.
struct TapToPaySetupFlow: View {
    let business: Business?
    let profile: BusinessProfile?
    let onFinished: (Bool) -> Void

    @ObservedObject private var reader = TapToPayReader.shared
    @State private var step: Step = .working
    @State private var address = TapToPayAddress()
    @State private var savingAddress = false
    @State private var showHowTo = false
    @Environment(\.openURL) private var openURL

    private enum Step: Equatable {
        case working, location, locationDenied, address, message(String)
    }

    var body: some View {
        Group {
            switch step {
            case .working:
                TapToPayWorkingView(status: reader.status)
            case .location:
                explainer(
                    icon: "location.circle",
                    title: "Allow location for card payments",
                    text: "Stripe needs to know where in-person payments happen, to reduce fraud and disputes. SmallBiz Workspace only checks it while you take a payment.",
                    button: "Continue"
                ) { Task { await setUp() } }
            case .locationDenied:
                explainer(
                    icon: "location.slash",
                    title: "Location is off for SmallBiz Workspace",
                    text: "Tap to Pay on iPhone needs it while you take a payment. Turn it on in Settings › SmallBiz Workspace › Location › While Using the App.",
                    button: "Open Settings"
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .address:
                addressForm
            case .message(let text):
                explainer(icon: "exclamationmark.circle", title: "Tap to Pay on iPhone isn't ready", text: text, button: "Try Again") {
                    Task { await advance() }
                }
            }
        }
        .task { await advance() }
        .sheet(isPresented: $showHowTo, onDismiss: { onFinished(true) }) {
            TapToPayHowToView()
        }
    }

    private func advance() async {
        step = .working
        _ = await reader.prepare(business: business, profile: profile)
        await route(afterSetUp: false)
    }

    private func setUp() async {
        step = .working
        let ready = await reader.setUp(business: business, profile: profile)
        if ready, reader.termsJustAccepted {
            reader.termsJustAccepted = false
            if await !TapToPayEducation.present() {
                showHowTo = true
                return
            }
        }
        await route(afterSetUp: true)
    }

    private func route(afterSetUp: Bool) async {
        switch reader.status {
        case .ready:
            onFinished(true)
        case .needsAddress:
            address = TapToPayAddress.parse(profile?.address ?? "") ?? TapToPayAddress()
            step = .address
        case .needsLocationPermission(let denied):
            step = denied ? .locationDenied : .location
        case .notSetUp, .checking, .preparing:
            // Apple's terms were canceled: back to wherever this started.
            if afterSetUp { onFinished(false) } else { await setUp() }
        case .needsStripe:
            step = .message("Finish setting up Stripe in Business › Payment Methods to take card payments.")
        case .unsupported(let text), .problem(let text):
            step = .message(text)
        }
    }

    private var addressForm: some View {
        Form {
            Section {
                TextField("Street", text: $address.line1).textContentType(.streetAddressLine1)
                TextField("Suite or unit (optional)", text: $address.line2).textContentType(.streetAddressLine2)
                TextField("City", text: $address.city).textContentType(.addressCity)
                HStack {
                    TextField("State", text: $address.state).textContentType(.addressState)
                    TextField("ZIP", text: $address.postalCode)
                        .textContentType(.postalCode)
                        .keyboardType(.numberPad)
                }
            } header: {
                Text("Where you do business")
            } footer: {
                Text("Stripe uses it to set Tap to Pay on iPhone up for your region. Clients see your business name on the tap screen, not your address.")
            }
            Section {
                Button {
                    Task {
                        savingAddress = true
                        address.state = TapToPayAddress.stateCode(address.state) ?? address.state
                        let saved = await reader.saveAddress(address, profile: profile)
                        savingAddress = false
                        if saved { await advance() } else { await route(afterSetUp: false) }
                    }
                } label: {
                    if savingAddress { ProgressView() } else { Text("Continue") }
                }
                .disabled(!address.isComplete || savingAddress)
            }
        }
    }

    private func explainer(icon: String, title: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon).font(.scaledSystem(size: 52, relativeTo: .largeTitle)).foregroundStyle(SBWTheme.brand)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button(button, action: action).sbwProminentButton()
        }
        .padding(24)
    }
}

// MARK: - Merchant education

/// Apple's own how-to for taking payments (4.1): current and localized by
/// Apple, iOS 18 and later.
enum TapToPayEducation {
    @MainActor
    static func present() async -> Bool {
        guard #available(iOS 18.0, *), let presenter = topViewController() else { return false }
        do {
            let discovery = ProximityReaderDiscovery()
            let content = try await discovery.content(for: .payment(.howToTap))
            try await discovery.presentContent(content, from: presenter)
            return true
        } catch {
            SBWLog.ui.problem("Tap to Pay how-to unavailable: \(error)")
            return false
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Where Apple's how-to isn't available (iOS 17): the same points, briefly.
struct TapToPayHowToView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                point("wave.3.right.circle", "Contactless cards",
                      "When the tap screen comes up, the client holds their card flat against the top of your iPhone until it's read.")
                point("iphone.radiowaves.left.and.right", "Apple Pay and other wallets",
                      "The client holds their phone or watch near the top of your iPhone, the same way.")
                point("lock.circle", "PIN entry",
                      "Some cards ask for a PIN. The client enters it on your iPhone's screen; VoiceOver and other accessibility options are available there.")
                point("creditcard.trianglebadge.exclamationmark", "If a card can't be read",
                      "Ask for another contactless card or a digital wallet, or send a payment link instead.")
            }
            .navigationTitle("How to Accept Payments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(SBWTheme.brand).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

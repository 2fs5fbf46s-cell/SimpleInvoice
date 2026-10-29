//
//  TapToPayReader.swift
//  SmallBiz Workspace
//

import Combine
import CoreLocation
import StripeTerminal
import SwiftData
import SwiftUI
import UserNotifications

/// Tap to Pay on iPhone, through Stripe Terminal.
///
/// One reader per app: this iPhone, connected to the active business's own
/// Stripe account. `prepare` runs on every launch and foreground so the tap
/// screen comes up within a second at checkout (Apple 1.5, 5.6); it only
/// connects quietly when Apple says the terms are already accepted — whether
/// they are is always asked of Apple, never remembered here (1.6). Apple's
/// terms are presented only when the owner asks to set up (3.5).
@MainActor
final class TapToPayReader: NSObject, ObservableObject {
    static let shared = TapToPayReader()

    enum Status: Equatable {
        /// Not looked at yet.
        case checking
        /// This iPhone or its iOS can't (1.1, 1.4).
        case unsupported(String)
        /// No Stripe account that can take card payments.
        case needsStripe
        /// No Terminal location yet, and the profile's address isn't a full one.
        case needsAddress
        /// Stripe requires location access for in-person payments.
        case needsLocationPermission(denied: Bool)
        /// Apple's terms haven't been accepted for this business.
        case notSetUp
        /// Apple is configuring this iPhone; progress 0…1 when it reports it (3.9.1).
        case preparing(Double?)
        case ready
        case problem(String)
    }

    @Published private(set) var status: Status = .checking
    /// Set when Apple's terms were accepted during setup, so the screen that
    /// ran setup shows Apple's how-to next (4.2).
    @Published var termsJustAccepted = false

    private var businessID: UUID?
    private var locationID: String?
    private var inFlight: Task<Bool, Never>?
    private var didStartTerminal = false
    /// "" once checked and supported.
    private var supportMessage: String?
    private let locationManager = CLLocationManager()
    private var permissionWaiters: [CheckedContinuation<Void, Never>] = []

    static var isSimulated: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Worth showing the Tap to Pay button and settings at all: the business
    /// takes card payments through Stripe, on an iPhone that can.
    static func isOffered(for business: Business?) -> Bool {
        guard let business, business.stripeChargesEnabled else { return false }
        return deviceSupportMessage() == nil
    }

    /// Nil when this iPhone can use Tap to Pay; otherwise what to tell the
    /// owner (1.1, 1.4). Asked once: the hardware and iOS don't change while
    /// the app runs.
    static func deviceSupportMessage() -> String? {
        if let checked = shared.supportMessage { return checked.isEmpty ? nil : checked }
        startTerminal()
        var message = ""
        if case .failure = Terminal.shared.supportsReaders(of: .tapToPay, discoveryMethod: .tapToPay, simulated: isSimulated) {
            message = "Tap to Pay on iPhone needs an iPhone XS or later on a current version of iOS. If this iPhone is supported, update it in Settings › General › Software Update."
        }
        shared.supportMessage = message
        return message.isEmpty ? nil : message
    }

    /// The launch and foreground warm-up (1.5), for a business that takes
    /// card payments. Runs alongside the other services, not ahead of them.
    static func warmUp(context: ModelContext, businessID: UUID?) {
        guard let businessID else { return }
        let business = try? context.fetch(FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })).first
        guard isOffered(for: business) else { return }
        let profile = try? context.fetch(FetchDescriptor<BusinessProfile>(predicate: #Predicate { $0.businessID == businessID })).first
        Task { await shared.prepare(business: business, profile: profile) }
    }

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    /// Stripe's SDK needs its token provider before anything touches `Terminal.shared`.
    static func startTerminal() {
        guard !shared.didStartTerminal else { return }
        shared.didStartTerminal = true
        Terminal.initWithTokenProvider(TapToPayConnectionTokens.shared)
    }

    // MARK: - Getting ready

    /// Gets this iPhone ready for the active business. Quiet (the launch and
    /// foreground warm-up) unless `userInitiated`, which may ask for location
    /// access and present Apple's terms.
    @discardableResult
    func prepare(business: Business?, profile: BusinessProfile?, userInitiated: Bool = false) async -> Bool {
        if let inFlight {
            let ready = await inFlight.value
            if ready || !userInitiated { return ready }
        }
        let task = Task { await self.runPrepare(business: business, profile: profile, userInitiated: userInitiated) }
        inFlight = task
        let ready = await task.value
        inFlight = nil
        return ready
    }

    private func runPrepare(business: Business?, profile: BusinessProfile?, userInitiated: Bool) async -> Bool {
        Self.startTerminal()
        if let message = Self.deviceSupportMessage() {
            status = .unsupported(message)
            return false
        }
        guard let business, business.stripeChargesEnabled else {
            status = .needsStripe
            return false
        }

        if businessID != business.id {
            // Another business is another Stripe account: drop the old reader.
            if Terminal.shared.connectedReader != nil {
                try? await Terminal.shared.disconnectReader()
            }
            businessID = business.id
            locationID = nil
        }
        if Terminal.shared.connectedReader != nil {
            status = .ready
            return true
        }

        do {
            if locationID == nil {
                locationID = try await TapToPayAPI.existingLocationID()
            }
            if locationID == nil {
                guard let address = TapToPayAddress.parse(profile?.address ?? "") else {
                    status = .needsAddress
                    return false
                }
                locationID = try await TapToPayAPI.saveLocation(displayName: Self.merchantName(profile), address: address)
            }
        } catch {
            status = .problem(error.localizedDescription)
            return false
        }

        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined where userInitiated:
            // The screen calling this has already explained why (Apple's pre-alert).
            await requestLocationPermission()
            guard [.authorizedWhenInUse, .authorizedAlways].contains(locationManager.authorizationStatus) else {
                status = .needsLocationPermission(denied: true)
                return false
            }
        case .notDetermined:
            status = .needsLocationPermission(denied: false)
            return false
        default:
            status = .needsLocationPermission(denied: true)
            return false
        }

        if !userInitiated, !Self.isSimulated {
            switch await accountLinked() {
            case .some(true): break
            case .some(false):
                status = .notSetUp
                return false
            case .none:
                break // Couldn't ask; connecting will say.
            }
        }

        return await connect(profile: profile, presentTerms: userInitiated)
    }

    /// Tap to Pay set up for this business, from any button — Settings,
    /// checkout, the announcement. Presents Apple's terms when needed.
    @discardableResult
    func setUp(business: Business?, profile: BusinessProfile?) async -> Bool {
        await prepare(business: business, profile: profile, userInitiated: true)
    }

    /// Saves a Terminal location from an address the owner typed in.
    func saveAddress(_ address: TapToPayAddress, profile: BusinessProfile?) async -> Bool {
        do {
            locationID = try await TapToPayAPI.saveLocation(displayName: Self.merchantName(profile), address: address)
            return true
        } catch {
            status = .problem(error.localizedDescription)
            return false
        }
    }

    private func accountLinked() async -> Bool? {
        await withCheckedContinuation { continuation in
            Terminal.shared.isTapToPayAccountLinked(nil) { linked, error in
                continuation.resume(returning: error == nil ? linked?.boolValue : nil)
            }
        }
    }

    private func connect(profile: BusinessProfile?, presentTerms: Bool) async -> Bool {
        guard let locationID else { return false }
        if case .preparing = status {} else { status = .preparing(nil) }
        do {
            let discovery = try TapToPayDiscoveryConfigurationBuilder().setSimulated(Self.isSimulated).build()
            let connection = try TapToPayConnectionConfigurationBuilder(delegate: self, locationId: locationID)
                .setMerchantDisplayName(Self.merchantName(profile))
                .setTosAcceptancePermitted(presentTerms)
                .setAutoReconnectOnUnexpectedDisconnect(true)
                .build()
            _ = try await Terminal.shared.easyConnect(
                TapToPayEasyConnectConfiguration(discoveryConfiguration: discovery, connectionConfiguration: connection)
            )
            status = .ready
            return true
        } catch {
            status = Self.status(afterConnectError: error)
            return false
        }
    }

    static func status(afterConnectError error: Error) -> Status {
        let nsError = error as NSError
        guard nsError.domain == ErrorDomain else { return .problem(error.localizedDescription) }
        switch ErrorCode.Code(rawValue: nsError.code) {
        case .tapToPayReaderTOSNotYetAccepted, .tapToPayReaderTOSAcceptanceCanceled:
            return .notSetUp
        case .tapToPayReaderTOSAcceptanceRequiresiCloudSignIn:
            return .problem("Sign in to iCloud in Settings with the Apple Account for your business, then try again. Apple needs it to accept the Tap to Pay on iPhone terms.")
        case .passcodeNotEnabled:
            return .problem("Set a passcode for this iPhone in Settings › Face ID & Passcode to use Tap to Pay on iPhone.")
        case .unsupportedMobileDeviceConfiguration:
            return .unsupported("Update iOS to use Tap to Pay on iPhone: Settings › General › Software Update.")
        case .tapToPayReaderMerchantBlocked, .tapToPayReaderInvalidMerchant, .tapToPayReaderAccountDeactivated:
            return .problem("Stripe can't use Tap to Pay on iPhone for this account right now. Check your Stripe account, or contact Stripe support.")
        case .locationServicesDisabled:
            return .needsLocationPermission(denied: true)
        default:
            return .problem(nsError.localizedDescription)
        }
    }

    private static func merchantName(_ profile: BusinessProfile?) -> String {
        let name = (profile?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "In-person payments" : name
    }

    // MARK: - Location permission

    private func requestLocationPermission() async {
        await withCheckedContinuation { continuation in
            permissionWaiters.append(continuation)
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Taking a payment

    /// One tap, start to finish: asks the server for the charge, brings up
    /// Apple's tap screen, records the result on the invoice. The server
    /// records it in the portal's ledger under the same id, so the activity
    /// pull never adds it twice.
    func collect(
        invoice: Invoice,
        amountCents: Int,
        tipCents: Int,
        business: Business?,
        profile: BusinessProfile?,
        context: ModelContext
    ) async -> TapToPayOutcome {
        // Keeps going if the owner leaves mid-payment, so the result still
        // gets recorded and, if it wasn't approved, they hear about it (5.12).
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Tap to Pay payment")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        if Terminal.shared.connectedReader == nil {
            guard await setUp(business: business, profile: profile) else {
                if case .problem(let message) = status { return .failed(message) }
                if case .unsupported(let message) = status { return .failed(message) }
                return .canceled
            }
        }

        var receipt = TapToPayReceipt(
            businessName: Self.merchantName(profile),
            invoiceNumber: invoice.invoiceNumber,
            amountCents: amountCents,
            tipCents: tipCents,
            currencyCode: business?.currencyCode ?? "USD",
            card: nil,
            date: .now,
            approved: false,
            receiptURL: nil
        )

        let start: TapToPayAPI.PaymentStart
        do {
            start = try await TapToPayAPI.startPayment(
                invoiceID: invoice.id,
                invoiceNumber: invoice.invoiceNumber,
                currencyCode: receipt.currencyCode,
                amountCents: amountCents,
                tipCents: tipCents,
                balanceDueCents: invoice.balanceDueCents
            )
        } catch {
            return .failed(error.localizedDescription)
        }

        let outcome: TapToPayOutcome
        do {
            let intent = try await Terminal.shared.retrievePaymentIntent(clientSecret: start.clientSecret)
            _ = try await Terminal.shared.processPaymentIntent(intent)
            let result = try? await completeWithRetry(start.paymentIntentId)
            receipt.approved = true
            receipt.card = TapToPayReceipt.cardDescription(brand: result?.brand, last4: result?.last4)
            receipt.receiptURL = result?.receiptUrl.flatMap(URL.init(string:))
            record(start: start, on: invoice, context: context)
            outcome = .approved(receipt)
        } catch {
            outcome = Self.outcome(afterPaymentError: error, receipt: receipt)
        }

        // Not .inactive: that's Apple's tap screen in front, not the owner leaving.
        if UIApplication.shared.applicationState == .background {
            Self.notifyIfMissed(outcome, invoiceID: invoice.id, businessID: business?.id, paymentIntentID: start.paymentIntentId)
        }
        return outcome
    }

    private func completeWithRetry(_ paymentIntentID: String) async throws -> TapToPayAPI.PaymentResult {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await TapToPayAPI.completePayment(paymentIntentID: paymentIntentID)
            } catch {
                lastError = error
                try? await Task.sleep(for: .seconds(attempt + 1))
            }
        }
        // The webhook records it on the server anyway; the app has it locally.
        throw lastError ?? TapToPayAPI.ServerError(code: "COMPLETE_FAILED")
    }

    private func record(start: TapToPayAPI.PaymentStart, on invoice: Invoice, context: ModelContext) {
        do {
            try InvoicePaymentService.record(
                on: invoice,
                amountCents: start.amountCents,
                paidAt: .now,
                method: "card",
                note: "Tap to Pay on iPhone",
                source: "tap_to_pay",
                externalId: start.paymentIntentId,
                tipCents: start.tipCents,
                context: context
            )
            try context.save()
        } catch {
            SBWLog.ui.problem("Tap to Pay payment \(start.paymentIntentId) taken but not saved: \(error)")
        }
        Task { await InvoicePaymentService.publishIfSent(invoice, context: context) }
    }

    static func outcome(afterPaymentError error: Error, receipt: TapToPayReceipt) -> TapToPayOutcome {
        if let confirm = error as? ConfirmPaymentIntentError, confirm.declineCode != nil || confirm.apiError != nil {
            return .declined(receipt, reason: declineMessage(confirm.declineCode))
        }
        let nsError = error as NSError
        guard nsError.domain == ErrorDomain else { return .failed(error.localizedDescription) }
        switch ErrorCode.Code(rawValue: nsError.code) {
        case .canceled:
            return .canceled
        case .cardReadTimedOut:
            return .timedOut
        case .declinedByStripeAPI, .declinedByReader, .cardNotSupported:
            return .declined(receipt, reason: declineMessage(nil))
        default:
            return .failed(nsError.localizedDescription)
        }
    }

    static func declineMessage(_ code: String?) -> String {
        switch code {
        case "insufficient_funds": return "The card was declined for insufficient funds."
        case "expired_card": return "The card has expired."
        case "online_or_offline_pin_required", "offline_pin_required":
            return "This card needs a PIN that Tap to Pay on iPhone can't take. Ask for another card or a digital wallet."
        default: return "The card was declined. Ask for another card or a digital wallet."
        }
    }

    /// Apple 5.12: an outcome the owner didn't see because they'd left the app.
    /// The server sends a declined one too, if the app was closed for good;
    /// the shared id means they only ever see one. Tapping opens the invoice.
    static func notifyIfMissed(_ outcome: TapToPayOutcome, invoiceID: UUID, businessID: UUID?, paymentIntentID: String) {
        let body: String
        switch outcome {
        case .approved: return
        case .declined(let receipt, _):
            body = "\(InvoicePaymentService.currency(receipt.totalCents)) on invoice \(receipt.invoiceNumber) was declined. Open the invoice to try again."
        case .timedOut, .canceled, .failed:
            body = "A Tap to Pay on iPhone payment didn't go through. Open the invoice to try again."
        }
        let content = UNMutableNotificationContent()
        content.title = "Payment not approved"
        content.body = body
        content.sound = .default
        var userInfo: [String: String] = ["type": "invoice_card_declined", "invoiceId": invoiceID.uuidString]
        if let businessID { userInfo["businessId"] = businessID.uuidString }
        content.userInfo = userInfo
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "tap-to-pay-\(paymentIntentID)", content: content, trigger: nil)
        )
    }
}

// MARK: - Stripe delegates

extension TapToPayReader: TapToPayReaderDelegate {
    nonisolated func reader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        Task { @MainActor in self.status = .preparing(0) }
    }

    nonisolated func reader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        Task { @MainActor in self.status = .preparing(Double(progress)) }
    }

    nonisolated func reader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {}
    nonisolated func reader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {}
    nonisolated func reader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {}

    nonisolated func tapToPayReaderDidAcceptTermsOfService(_ reader: Reader) {
        Task { @MainActor in self.termsJustAccepted = true }
    }

    nonisolated func reader(_ reader: Reader, didStartReconnect cancelable: Cancelable, disconnectReason: DisconnectReason) {
        Task { @MainActor in self.status = .preparing(nil) }
    }

    nonisolated func readerDidSucceedReconnect(_ reader: Reader) {
        Task { @MainActor in self.status = .ready }
    }

    nonisolated func readerDidFailReconnect(_ reader: Reader) {
        // Reconnects on the next foreground or tap.
        Task { @MainActor in self.status = .notSetUp }
    }

    nonisolated func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {
        Task { @MainActor in
            if case .ready = self.status { self.status = .checking }
        }
    }
}

extension TapToPayReader: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            let waiters = self.permissionWaiters
            self.permissionWaiters = []
            waiters.forEach { $0.resume() }
        }
    }
}

/// Fetches Stripe Terminal connection tokens from the backend. Never cached:
/// the SDK asks whenever it needs one.
final class TapToPayConnectionTokens: NSObject, ConnectionTokenProvider {
    static let shared = TapToPayConnectionTokens()

    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        Task {
            do {
                completion(try await TapToPayAPI.connectionToken(), nil)
            } catch {
                completion(nil, error)
            }
        }
    }
}

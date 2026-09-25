//
//  BookingDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UIKit

/// One screen per booking, the same shape as the other record screens: who
/// and when, how to reach them, and a Next step card with a way forward from
/// every state — answer a request, chase or settle a deposit, open the job,
/// reschedule or cancel.
///
/// It replaces a screen where asking for a deposit was a dead end (no
/// approve, decline, resend or "mark paid" after it), Approve and Deny fired
/// on one tap, a mistyped deposit silently became $100, and Create buttons
/// made a new job or a $0 invoice on every tap. Debug IDs are gone too.
struct BookingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var booking: BookingRequestItem
    private let requestId: String
    private let onChange: (BookingRequestItem) -> Void

    @State private var working = false
    @State private var job: Job? = nil
    @State private var jobRoute: Job? = nil
    @State private var notice: String? = nil
    @State private var errorText: String? = nil

    @State private var confirmConfirm = false
    @State private var showDecline = false
    @State private var showCancel = false
    @State private var confirmWaive = false
    @State private var confirmMarkPaid = false
    @State private var showDepositSheet = false
    @State private var showReschedule = false
    @State private var showPrice = false
    @State private var note = ""

    init(request: BookingRequestItem, onStatusChange: @escaping (BookingRequestItem) -> Void = { _ in }) {
        _booking = State(initialValue: request)
        self.requestId = request.requestId
        self.onChange = onStatusChange
    }

    private var businessID: UUID? { UUID(uuidString: booking.businessId) }
    private var firstName: String {
        booking.customerName.split(separator: " ").first.map(String.init) ?? booking.customerName
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                contactRow
                nextStepCard
                detailsCard
                if booking.stage != .declined { paymentCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Booking")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .navigationDestination(item: $jobRoute) { JobDetailView(job: $0) }
        .modifier(BookingDialogs(
            booking: booking,
            firstName: firstName,
            confirmConfirm: $confirmConfirm,
            showDecline: $showDecline,
            showCancel: $showCancel,
            confirmWaive: $confirmWaive,
            confirmMarkPaid: $confirmMarkPaid,
            note: $note,
            notice: $notice,
            errorText: $errorText,
            onConfirm: { confirm(waiveDeposit: false) },
            onWaive: { confirm(waiveDeposit: true) },
            onDecline: decline,
            onCancel: cancel,
            onMarkPaid: markPaid
        ))
        .sheet(isPresented: $showDepositSheet) {
            BookingDepositSheet(booking: booking) { updated in
                apply(updated)
                notice = "Deposit request sent to \(booking.clientEmail ?? firstName)."
            }
        }
        .sheet(isPresented: $showReschedule) {
            BookingRescheduleSheet(booking: booking) { start, end in
                reschedule(start: start, end: end)
            }
        }
        .sheet(isPresented: $showPrice) {
            BookingPriceSheet(booking: booking) { cents in
                setPrice(cents)
            }
        }
        .task { await refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(booking.customerName)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Text("\(booking.serviceName) · \(booking.whenText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(booking.stage.label)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Capsule().fill(booking.stage.foreground.opacity(0.15)))
                .foregroundStyle(booking.stage.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contactRow: some View {
        let digits = (booking.clientPhone ?? "").filter { $0.isNumber || $0 == "+" }
        let email = (booking.clientEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack {
            contactButton("Call", icon: "phone.fill", url: digits.isEmpty ? nil : URL(string: "tel:\(digits)"))
            contactButton("Text", icon: "message.fill", url: digits.isEmpty ? nil : URL(string: "sms:\(digits)"))
            contactButton("Email", icon: "envelope.fill", url: email.contains("@") ? URL(string: "mailto:\(email)") : nil)
        }
        .buttonStyle(.borderless)
        .bookingCard()
    }

    private func contactButton(_ title: String, icon: String, url: URL?) -> some View {
        Button { if let url { openURL(url) } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(url != nil ? SBWTheme.brandBlue : Color.secondary.opacity(0.5))
        }
        .disabled(url == nil)
    }

    // MARK: - Next step

    private var nextStepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next step")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SBWTheme.brandBlue)

            switch booking.stage {
            case .needsAnswer:
                stepTitle(
                    "Reply to \(firstName)'s request",
                    detail: requestedText + " Confirming emails \(firstName) and puts the job on your calendar."
                )
                HStack(spacing: 10) {
                    Button { confirmConfirm = true } label: { Label("Confirm", systemImage: "checkmark") }
                        .sbwProminentButton(SBWTheme.brandGreen)
                    Button { showDepositSheet = true } label: { Label("Ask for Deposit", systemImage: "dollarsign") }
                        .buttonStyle(.bordered)
                }
                .disabled(working)
                HStack(spacing: 16) {
                    Button("Suggest another time") { showReschedule = true }
                    Button("Decline", role: .destructive) { note = ""; showDecline = true }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)

            case .awaitingDeposit:
                stepTitle("Waiting on \(firstName)'s deposit", detail: depositWaitingText)
                HStack(spacing: 10) {
                    Button { showDepositSheet = true } label: { Label("Resend Link", systemImage: "paperplane") }
                        .sbwProminentButton()
                    Button { confirmMarkPaid = true } label: { Label("Mark Paid", systemImage: "banknote") }
                        .buttonStyle(.bordered)
                }
                .disabled(working)
                HStack(spacing: 16) {
                    Button("Confirm without it") { confirmWaive = true }
                    Button("Decline", role: .destructive) { note = ""; showDecline = true }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)

            case .confirmed:
                if booking.isPast() {
                    stepTitle("Bill for \(booking.serviceName.lowercased())", detail: "The booking has happened. Invoice it from the job; any deposit paid comes off.")
                } else {
                    stepTitle("Confirmed for \(booking.whenText)", detail: confirmedText)
                }
                HStack(spacing: 10) {
                    if let job {
                        Button { jobRoute = job } label: { Label("Open Job", systemImage: "wrench.and.screwdriver") }
                            .sbwProminentButton()
                    } else {
                        Button { makeJob() } label: { Label("Create Job", systemImage: "plus") }
                            .sbwProminentButton()
                    }
                    if !booking.isPast() {
                        Button { showReschedule = true } label: { Label("Reschedule", systemImage: "calendar") }
                            .buttonStyle(.bordered)
                    }
                }
                .disabled(working)
                if !booking.isPast() {
                    Button("Cancel booking", role: .destructive) { note = ""; showCancel = true }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }

            case .declined:
                stepTitle(
                    "Declined\(dateText(booking.declinedAtMs).map { " \($0)" } ?? "")",
                    detail: "\(firstName) was emailed. Nothing else to do."
                )
            case .canceled:
                stepTitle(
                    "Canceled\(dateText(booking.cancelledAtMs).map { " \($0)" } ?? "")",
                    detail: job == nil ? "\(firstName) was emailed." : "\(firstName) was emailed, and the job is canceled."
                )
            }
        }
        .bookingCard()
    }

    private func stepTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func dateText(_ ms: Int?) -> String? {
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    private var requestedText: String {
        dateText(booking.createdAtMs).map { "Requested \($0)." } ?? ""
    }

    private var depositWaitingText: String {
        let amount = booking.depositAmountCents.map(InvoicePaymentService.currency) ?? "A deposit"
        let when = dateText(booking.depositRequestedAtMs).map { " asked \($0)" } ?? ""
        return "\(amount)\(when). The booking is confirmed and \(firstName) is emailed as soon as it's paid."
    }

    private var confirmedText: String {
        if booking.depositPaid, let cents = booking.depositAmountCents, cents > 0 {
            return "\(InvoicePaymentService.currency(cents)) deposit paid."
        }
        if (booking.depositWaivedAtMs ?? 0) > 0 { return "Confirmed without the deposit." }
        return ""
    }

    // MARK: - Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").font(.headline)
            row("Service", booking.serviceName)
            row("When", booking.whenText)
            if let email = booking.clientEmail, !email.isEmpty { row("Email", email) }
            if let phone = booking.clientPhone, !phone.isEmpty { row("Phone", phone) }
            if let requested = dateText(booking.createdAtMs) { row("Requested", requested) }
            let notes = (booking.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                Divider()
                Text("Their note").font(.caption).foregroundStyle(.secondary)
                Text(notes).font(.subheadline).textSelection(.enabled)
            }
        }
        .bookingCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var paymentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Payment").font(.headline)
                Spacer()
                if booking.stage != .canceled {
                    Button(booking.bookingTotalAmountCents == nil ? "Set Price" : "Change Price") { showPrice = true }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
            }
            row("Price", booking.bookingTotalAmountCents.map(InvoicePaymentService.currency) ?? "Not set")
            if let deposit = booking.depositAmountCents, deposit > 0 {
                row("Deposit", "\(InvoicePaymentService.currency(deposit)) · \(booking.depositPaid ? "paid" : ((booking.depositWaivedAtMs ?? 0) > 0 ? "not needed" : "not paid yet"))")
            }
            if let total = booking.bookingTotalAmountCents, total > 0 {
                let paid = booking.depositPaid ? (booking.depositAmountCents ?? 0) : 0
                row("Still owed", InvoicePaymentService.currency(max(0, total - paid)))
            }
        }
        .bookingCard()
    }

    // MARK: - Actions

    private func apply(_ updated: BookingRequestItem?) {
        guard let updated else { return }
        booking = updated
        onChange(updated)
    }

    private func refresh() async {
        if let businessID,
           let dtos = try? await PortalBackend.shared.fetchBookingRequests(businessId: businessID),
           let fresh = dtos.first(where: { $0.requestId == booking.requestId }) {
            apply(BookingRequestItem(dto: fresh))
        }
        job = BookingWorkSetup.job(for: booking, in: modelContext)
        if job == nil, let businessID, booking.stage == .confirmed, !booking.isPast() {
            job = await BookingWorkSetup.ensureJob(for: booking, businessID: businessID, context: modelContext)
        }
    }

    private func perform(_ action: @escaping () async throws -> BookingRequestItem?, then: @escaping (BookingRequestItem) async -> Void) {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                if let updated = try await action() {
                    apply(updated)
                    await then(updated)
                } else {
                    await refresh()
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func confirm(waiveDeposit: Bool) {
        perform({ try await BookingActions.confirm(booking, waiveDeposit: waiveDeposit) }) { updated in
            if let businessID {
                job = await BookingWorkSetup.ensureJob(for: updated, businessID: businessID, context: modelContext)
            }
            Haptics.success()
            notice = "Confirmed. \(firstName) is emailed\(job == nil ? "" : ", and the job is on your calendar")."
        }
    }

    private func decline() {
        let message = note.trimmingCharacters(in: .whitespacesAndNewlines)
        perform({ try await BookingActions.decline(booking, message: message) }) { _ in
            notice = "Declined. \(firstName) is emailed."
        }
    }

    private func cancel() {
        let message = note.trimmingCharacters(in: .whitespacesAndNewlines)
        perform({ try await BookingActions.cancel(booking, message: message) }) { _ in
            if let job {
                await JobLifecycle.cancel(job)
                try? modelContext.save()
            }
            notice = "Canceled. \(firstName) is emailed\(job == nil ? "" : ", and the job is off your calendar")."
        }
    }

    private func markPaid() {
        perform({ try await BookingActions.markDepositPaid(booking) }) { updated in
            if let businessID {
                job = await BookingWorkSetup.ensureJob(for: updated, businessID: businessID, context: modelContext)
            }
            Haptics.success()
            notice = "Deposit marked paid and the booking is confirmed. \(firstName) is emailed."
        }
    }

    private func reschedule(start: Date, end: Date) {
        perform({ try await BookingActions.reschedule(booking, start: start, end: end) }) { updated in
            if let job { await BookingWorkSetup.reschedule(job, to: updated, context: modelContext) }
            notice = "Moved to \(updated.whenText). \(firstName) is emailed the new time."
        }
    }

    private func setPrice(_ cents: Int) {
        guard let businessID else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await PortalBackend.shared.setBookingTotal(businessId: businessID, requestId: booking.requestId, totalAmountCents: cents)
                await refresh()
                if let job {
                    BookingWorkSetup.sync(job, with: booking)
                    try? modelContext.save()
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func makeJob() {
        guard let businessID else { return }
        UserDefaults.standard.removeObject(forKey: "sbw.booking.jobMade.\(booking.requestId)")
        Task {
            job = await BookingWorkSetup.ensureJob(for: booking, businessID: businessID, context: modelContext)
            if let job { jobRoute = job }
        }
    }
}

// MARK: - Dialogs

private struct BookingDialogs: ViewModifier {
    let booking: BookingRequestItem
    let firstName: String
    @Binding var confirmConfirm: Bool
    @Binding var showDecline: Bool
    @Binding var showCancel: Bool
    @Binding var confirmWaive: Bool
    @Binding var confirmMarkPaid: Bool
    @Binding var note: String
    @Binding var notice: String?
    @Binding var errorText: String?
    let onConfirm: () -> Void
    let onWaive: () -> Void
    let onDecline: () -> Void
    let onCancel: () -> Void
    let onMarkPaid: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Confirm \(firstName)'s booking?", isPresented: $confirmConfirm, titleVisibility: .visible) {
                Button("Confirm Booking") { onConfirm() }
                Button("Not Yet", role: .cancel) {}
            } message: {
                Text("\(booking.serviceName), \(booking.whenText). \(firstName) gets a confirmation email, and the job goes on your calendar.")
            }
            .confirmationDialog("Confirm without the deposit?", isPresented: $confirmWaive, titleVisibility: .visible) {
                Button("Confirm Without Deposit") { onWaive() }
                Button("Keep Waiting", role: .cancel) {}
            } message: {
                Text("\(firstName) gets a confirmation email. The deposit link stays open if they still want to pay it.")
            }
            .confirmationDialog("Mark the deposit paid?", isPresented: $confirmMarkPaid, titleVisibility: .visible) {
                Button("Mark Paid and Confirm") { onMarkPaid() }
                Button("Not Yet", role: .cancel) {}
            } message: {
                Text("For a deposit paid in cash or by check. The booking is confirmed and \(firstName) is emailed.")
            }
            .alert("Decline \(firstName)'s request?", isPresented: $showDecline) {
                TextField("Add a note (optional)", text: $note)
                Button("Decline", role: .destructive) { onDecline() }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text("\(firstName) gets an email saying you can't take it.")
            }
            .alert("Cancel this booking?", isPresented: $showCancel) {
                TextField("Add a note (optional)", text: $note)
                Button("Cancel Booking", role: .destructive) { onCancel() }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text("\(firstName) is emailed, and the job comes off your calendar.")
            }
            .alert("Done", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) { notice = nil }
            } message: {
                Text(notice ?? "")
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
    }
}

// MARK: - Sheets

/// Ask for (or resend) a deposit. The amount must be entered: a mistyped one
/// used to become $100 without a word.
private struct BookingDepositSheet: View {
    @Environment(\.dismiss) private var dismiss
    let booking: BookingRequestItem
    let onSent: (BookingRequestItem?) -> Void

    @State private var amountText: String
    @State private var byEmail: Bool
    @State private var byText = false
    @State private var sending = false
    @State private var errorText: String? = nil

    init(booking: BookingRequestItem, onSent: @escaping (BookingRequestItem?) -> Void) {
        self.booking = booking
        self.onSent = onSent
        _amountText = State(initialValue: booking.depositAmountCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _byEmail = State(initialValue: (booking.clientEmail ?? "").contains("@"))
    }

    private var cents: Int? { InvoiceAmountParser.cents(from: amountText) }
    private var hasPhone: Bool { !(booking.clientPhone ?? "").filter(\.isNumber).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Deposit")
                        Spacer()
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if let total = booking.bookingTotalAmountCents, total > 0 {
                        Text("The price is \(InvoicePaymentService.currency(total)). The booking is confirmed as soon as the deposit is paid.")
                    } else {
                        Text("The booking is confirmed as soon as the deposit is paid.")
                    }
                }
                Section("Send the link by") {
                    Toggle("Email", isOn: $byEmail).disabled(!(booking.clientEmail ?? "").contains("@"))
                    Toggle("Text", isOn: $byText).disabled(!hasPhone)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(booking.stage == .awaitingDeposit ? "Resend Deposit Link" : "Ask for a Deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Send") { send() }
                            .fontWeight(.semibold)
                            .disabled((cents ?? 0) <= 0 || (!byEmail && !byText))
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func send() {
        guard let cents, cents > 0, let businessID = UUID(uuidString: booking.businessId) else {
            errorText = "Enter the deposit amount."
            return
        }
        sending = true
        Task {
            defer { sending = false }
            do {
                _ = try await PortalBackend.shared.requestBookingDeposit(
                    businessId: businessID,
                    requestId: booking.requestId,
                    depositAmountCents: cents,
                    clientEmail: booking.clientEmail,
                    clientPhone: booking.clientPhone,
                    businessName: nil,
                    sendEmail: byEmail,
                    sendSms: byText
                )
                let fresh = try? await PortalBackend.shared.fetchBookingRequests(businessId: businessID)
                onSent(fresh?.first { $0.requestId == booking.requestId }.map(BookingRequestItem.init(dto:)))
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct BookingRescheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let booking: BookingRequestItem
    let onSave: (Date, Date) -> Void

    @State private var start: Date
    @State private var end: Date

    init(booking: BookingRequestItem, onSave: @escaping (Date, Date) -> Void) {
        self.booking = booking
        self.onSave = onSave
        let start = booking.start ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        _start = State(initialValue: start)
        _end = State(initialValue: booking.end ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Starts", selection: $start, in: Date.now...)
                        .onChange(of: start) { old, new in
                            end = end.addingTimeInterval(new.timeIntervalSince(old))
                        }
                    DatePicker("Ends", selection: $end, in: start...)
                } footer: {
                    Text("Was \(booking.whenText). \(booking.customerName) is emailed the new time.")
                }
            }
            .navigationTitle(booking.stage == .needsAnswer ? "Suggest Another Time" : "Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(start, end)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(end <= start)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct BookingPriceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let booking: BookingRequestItem
    let onSave: (Int) -> Void

    @State private var amountText: String

    init(booking: BookingRequestItem, onSave: @escaping (Int) -> Void) {
        self.booking = booking
        self.onSave = onSave
        _amountText = State(initialValue: booking.bookingTotalAmountCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
    }

    private var cents: Int? { InvoiceAmountParser.cents(from: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("What the booking costs in total. The job's invoice uses it, less any deposit paid.")
                }
            }
            .navigationTitle("Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let cents { onSave(cents) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled((cents ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}

private struct BookingCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
    }
}

private extension View {
    func bookingCard() -> some View { modifier(BookingCard()) }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension BookingDetailView: Equatable {
    static func == (lhs: BookingDetailView, rhs: BookingDetailView) -> Bool {
        lhs.requestId == rhs.requestId
    }
}

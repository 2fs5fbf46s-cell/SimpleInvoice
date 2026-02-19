import Foundation
import EventKit
import EventKitUI
import SwiftUI
import UIKit

enum CalendarEventServiceError: LocalizedError {
    case accessDenied
    case accessRestricted
    case missingCalendar
    case unableToSave
    case unableToOpenCalendar
    case invalidDates

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access is denied. Enable calendar access in Settings."
        case .accessRestricted:
            return "Calendar access is restricted on this device."
        case .missingCalendar:
            return "No writable calendar is available."
        case .unableToSave:
            return "Could not save the calendar event."
        case .unableToOpenCalendar:
            return "Could not open Calendar."
        case .invalidDates:
            return "Job dates are invalid for a calendar event."
        }
    }
}

@MainActor
final class CalendarEventService {
    static let shared = CalendarEventService()

    let eventStore = EKEventStore()

    private init() {}

    func requestAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            if status == .fullAccess || status == .writeOnly {
                return
            }
        }
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { ok, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        continuation.resume(returning: ok)
                    }
                }
            }
            if !granted {
                throw CalendarEventServiceError.accessDenied
            }
        case .denied:
            throw CalendarEventServiceError.accessDenied
        case .restricted:
            throw CalendarEventServiceError.accessRestricted
        @unknown default:
            throw CalendarEventServiceError.accessDenied
        }
    }

    func fetchEvent(by identifier: String?) -> EKEvent? {
        guard let identifier, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return eventStore.event(withIdentifier: identifier)
    }

    func createOrUpdateEvent(
        for job: Job,
        businessName: String?,
        clientName: String?,
        clientEmail: String?,
        clientPhone: String?
    ) async throws -> EKEvent {
        try await requestAccessIfNeeded()

        let start = job.startDate
        let end = job.endDate > start ? job.endDate : Calendar.current.date(byAdding: .hour, value: 1, to: start)
        guard let end else { throw CalendarEventServiceError.invalidDates }

        let resolvedTitle = resolvedTitle(job: job, clientName: clientName)
        let notes = buildNotes(
            job: job,
            businessName: businessName,
            clientName: clientName,
            clientEmail: clientEmail,
            clientPhone: clientPhone
        )
        let location = trimmed(job.locationName)

        let existing = fetchEvent(by: job.calendarEventId)
        let event = existing ?? EKEvent(eventStore: eventStore)
        guard let targetCalendar = eventStore.defaultCalendarForNewEvents ?? eventStore.calendars(for: .event).first else {
            throw CalendarEventServiceError.missingCalendar
        }

        event.calendar = targetCalendar
        event.title = resolvedTitle
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.location = location

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return event
        } catch {
            throw CalendarEventServiceError.unableToSave
        }
    }

    func openInCalendarApp(event: EKEvent) throws {
        let ref = event.startDate.timeIntervalSinceReferenceDate
        guard let url = URL(string: "calshow:\(ref)") else {
            throw CalendarEventServiceError.unableToOpenCalendar
        }
        guard UIApplication.shared.canOpenURL(url) else {
            throw CalendarEventServiceError.unableToOpenCalendar
        }
        UIApplication.shared.open(url)
    }

    private func resolvedTitle(job: Job, clientName: String?) -> String {
        let rawTitle = trimmed(job.title) ?? "Job"
        if let clientName {
            return "\(clientName) • \(rawTitle)"
        }
        return "Job: \(rawTitle)"
    }

    private func buildNotes(
        job: Job,
        businessName: String?,
        clientName: String?,
        clientEmail: String?,
        clientPhone: String?
    ) -> String {
        var lines: [String] = []

        if let businessName {
            lines.append("Business: \(businessName)")
        }
        if let clientName {
            lines.append("Client: \(clientName)")
        }
        if let clientEmail {
            lines.append("Client Email: \(clientEmail)")
        }
        if let clientPhone {
            lines.append("Client Phone: \(clientPhone)")
        }
        if let requestID = trimmed(job.sourceBookingRequestId) {
            lines.append("Booking Request ID: \(requestID)")
        }
        lines.append("Created from SmallBiz Workspace")

        if let jobNotes = trimmed(job.notes) {
            lines.append("")
            lines.append(jobNotes)
        }

        return lines.joined(separator: "\n")
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

struct EventViewControllerRepresentable: UIViewControllerRepresentable {
    let event: EKEvent
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> EKEventViewController {
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = false
        vc.allowsCalendarPreview = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            onDismiss()
        }
    }
}

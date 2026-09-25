//
//  JobLifecycle.swift
//  SmallBiz Workspace
//

import SwiftUI

/// Where a job is, as the owner sees it — one set of names for the list,
/// the job screen and its header. The same stage used to read "Booked",
/// "Scheduled" and "Requested" on different screens, and a canceled job was
/// both "CANCELED" and "CANCELLED".
enum JobDisplayStatus: Equatable {
    case needsScheduling
    case scheduled
    case inProgress
    case completed
    case canceled

    init(_ job: Job) {
        switch job.stage {
        case .booked: self = job.needsScheduling ? .needsScheduling : .scheduled
        case .inProgress: self = .inProgress
        case .completed: self = .completed
        case .canceled: self = .canceled
        }
    }

    var label: String {
        switch self {
        case .needsScheduling: return "Needs scheduling"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .canceled: return "Canceled"
        }
    }

    var foreground: Color {
        switch self {
        case .needsScheduling: return SBWTheme.attention
        case .scheduled: return SBWTheme.brand
        case .inProgress: return SBWTheme.success
        case .completed: return .secondary
        case .canceled: return .red
        }
    }
}

/// The stage changes behind Start, Complete, Cancel and Reopen, shared by the
/// job screen and the list's swipe actions so both record the same times.
@MainActor
enum JobLifecycle {
    static func start(_ job: Job) {
        job.stage = .inProgress
        job.status = "in_progress"
        job.startedAt = .now
        job.needsScheduling = false
        job.canceledAt = nil
    }

    static func complete(_ job: Job) {
        job.stage = .completed
        job.status = "completed"
        job.completedAt = .now
        if job.startedAt == nil { job.startedAt = job.completedAt }
        job.needsScheduling = false
    }

    /// Takes the job off the owner's calendar too — a canceled job that
    /// still shows up as an appointment is worse than no event at all.
    static func cancel(_ job: Job) async {
        job.stage = .canceled
        job.status = "canceled"
        job.canceledAt = .now
        let eventID = job.calendarEventId
        job.calendarEventId = nil
        try? await CalendarEventService.shared.removeEvent(identifier: eventID)
    }

    static func reopen(_ job: Job) {
        job.stage = .booked
        job.status = "scheduled"
        job.canceledAt = nil
        job.completedAt = nil
    }

    /// For correcting a mis-tap from the job's menu; keeps the timestamps
    /// consistent with the stage it lands on.
    static func setStage(_ job: Job, to stage: JobStage) {
        switch stage {
        case .booked:
            reopen(job)
            job.startedAt = nil
        case .inProgress:
            job.stage = .inProgress
            job.status = "in_progress"
            if job.startedAt == nil { job.startedAt = .now }
            job.completedAt = nil
            job.canceledAt = nil
            job.needsScheduling = false
        case .completed:
            complete(job)
        case .canceled:
            job.stage = .canceled
            job.status = "canceled"
            job.canceledAt = .now
        }
    }
}

/// What deleting a job takes with it, for the confirmation on the job screen
/// and the list. The job's estimates and invoices survive; only the link goes.
enum JobDeletion {
    static func impactMessage(for job: Job?) -> String {
        let count = job?.invoices?.count ?? 0
        switch count {
        case 0:
            return "This removes the job and its calendar event. This can't be undone."
        case 1:
            return "Its estimate or invoice stays, but loses its link to this job. This can't be undone."
        default:
            return "Its \(count) estimates and invoices stay, but lose their link to this job. This can't be undone."
        }
    }
}

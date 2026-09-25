//
//  NotificationSettingsView.swift
//  SmallBiz Workspace
//

import SwiftUI
import UIKit
import UserNotifications

/// What the owner is told about, and when.
///
/// The Notifications row used to open the notification history (with its
/// "Event", "Deep Link" and "Raw Data" fields), and the only switch anywhere
/// was the iPhone permission, buried on Business Profile. The server has
/// always kept a switch per alert and a daily recap, but no screen set them.
/// The history is behind the bell on Today now.
struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var settings: PortalBackend.AlertSettingsDTO? = nil
    @State private var loadError: String? = nil
    @State private var saveError: String? = nil
    @State private var recapTime = NotificationSettingsView.defaultRecapTime

    var body: some View {
        Form {
            permissionSection

            if let settings {
                Section {
                    toggle("An invoice is paid", \.invoicePaid, key: "invoice.paid", settings)
                    toggle("A contract is signed", \.contractSigned, key: "contract.signed", settings)
                    toggle("A booking is requested", \.bookingRequested, key: "booking.requested", settings)
                    toggle("An invoice is sent", \.invoiceSent, key: "invoice.sent", settings)
                } header: {
                    Text("Tell me when")
                } footer: {
                    Text("Each one also appears in the history behind the bell on Today, even when it's off here.")
                }

                Section {
                    Toggle("Daily recap", isOn: Binding(
                        get: { settings.dailySummary?.enabled ?? false },
                        set: { setRecap(enabled: $0) }
                    ))
                    if settings.dailySummary?.enabled == true {
                        DatePicker("Send at", selection: $recapTime, displayedComponents: .hourAndMinute)
                            .onChange(of: recapTime) { _, _ in setRecap(enabled: true) }
                    }
                } footer: {
                    Text("Bookings requested, invoices paid and contracts signed in the last day, once a day.")
                }
            } else if let loadError {
                Section {
                    Text(loadError).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                Section { ProgressView() }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermission() } }
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            switch permission {
            case .authorized, .provisional, .ephemeral:
                Label("Notifications are on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SBWTheme.success)
            case .denied:
                Label("Notifications are off for this app", systemImage: "bell.slash")
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            default:
                Label("Notifications aren't on yet", systemImage: "bell")
                Button("Turn On Notifications") { Task { await askPermission() } }
            }
        } footer: {
            if permission == .denied {
                Text("Nothing below reaches your phone until they're on in Settings.")
            }
        }
    }

    private func refreshPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func askPermission() async {
        if await NotificationManager.shared.requestAuthorization() {
            UIApplication.shared.registerForRemoteNotifications()
        }
        await refreshPermission()
    }

    // MARK: - Alerts

    private func toggle(
        _ title: String,
        _ path: WritableKeyPath<PortalBackend.AlertSettingsDTO.Toggles, Bool>,
        key: String,
        _ settings: PortalBackend.AlertSettingsDTO
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { settings.toggles[keyPath: path] },
            set: { value in
                self.settings?.toggles[keyPath: path] = value
                save(["toggles": [key: value]])
            }
        ))
    }

    private func setRecap(enabled: Bool) {
        let time = Self.hhmm(recapTime)
        let tz = TimeZone.current.identifier
        settings?.dailySummary = .init(enabled: enabled, timeLocalHHmm: time, tz: tz)
        save(["dailySummary": ["enabled": enabled, "timeLocalHHmm": time, "tz": tz]])
    }

    private func save(_ patch: [String: Any]) {
        let before = settings
        Task {
            do {
                settings = try await PortalBackend.shared.updateAlertSettings(patch)
            } catch {
                settings = before
                saveError = "That change didn't save. Check your connection and try again."
            }
        }
    }

    private func load() async {
        await refreshPermission()
        loadError = nil
        do {
            let loaded = try await PortalBackend.shared.fetchAlertSettings()
            settings = loaded
            if let hhmm = loaded.dailySummary?.timeLocalHHmm, let date = Self.date(fromHHmm: hhmm) {
                recapTime = date
            }
        } catch {
            loadError = "Couldn't load your alert settings. Check your connection."
        }
    }

    // MARK: - Time

    static var defaultRecapTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    }

    static func hhmm(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0)
    }

    static func date(fromHHmm value: String) -> Date? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now)
    }
}

extension NotificationSettingsView: Equatable {
    static func == (_: NotificationSettingsView, _: NotificationSettingsView) -> Bool { true }
}

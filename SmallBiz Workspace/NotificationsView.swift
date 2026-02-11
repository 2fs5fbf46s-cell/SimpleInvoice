import SwiftUI
import SwiftData

struct NotificationsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query(sort: \AppNotification.createdAtMs, order: .reverse)
    private var allNotifications: [AppNotification]

    @State private var selectedNotification: AppNotification?
    @State private var isRefreshing = false

    private var scopedNotifications: [AppNotification] {
        guard let businessId = activeBiz.activeBusinessID else { return [] }
        return allNotifications.filter { $0.businessId == businessId }
    }

    private var unreadCount: Int {
        scopedNotifications.filter { $0.readAtMs == nil }.count
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                headerCard

                if scopedNotifications.isEmpty {
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell",
                        description: Text("New alerts will appear here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(scopedNotifications) { item in
                        Button {
                            Task { await openNotification(item) }
                        } label: {
                            notificationRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await refreshInbox()
        }
        .task {
            await refreshInbox()
        }
        .sheet(item: $selectedNotification) { item in
            NotificationDetailView(item: item)
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            Text("Unread")
                .font(.subheadline.weight(.semibold))
            Text("\(unreadCount)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SBWTheme.brandBlue.opacity(0.16))
                .foregroundStyle(SBWTheme.brandBlue)
                .clipShape(Capsule())

            Spacer()

            Button("Mark All Read") {
                Task { await markAllReadTapped() }
            }
            .disabled(unreadCount == 0 || activeBiz.activeBusinessID == nil)
        }
        .padding(12)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SBWTheme.cardStroke, lineWidth: 1)
        )
    }

    private func notificationRow(_ item: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.readAtMs == nil ? SBWTheme.brandBlue : Color.clear)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Text(formattedTimestamp(ms: item.createdAtMs))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
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
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    @MainActor
    private func refreshInbox() async {
        guard !isRefreshing else { return }
        guard let businessId = activeBiz.activeBusinessID else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            _ = try await NotificationInboxService.shared.refresh(
                modelContext: modelContext,
                businessId: businessId
            )
        } catch {
            NotificationRouter.shared.showToast("Could not refresh notifications.")
        }
    }

    @MainActor
    private func openNotification(_ item: AppNotification) async {
        guard let businessId = activeBiz.activeBusinessID else { return }
        await NotificationInboxService.shared.markRead(
            item,
            modelContext: modelContext,
            businessId: businessId
        )

        if let deepLink = item.deepLink?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: deepLink) {
            NotificationRouter.shared.handleIncomingURL(url)
            return
        }

        selectedNotification = item
    }

    @MainActor
    private func markAllReadTapped() async {
        guard let businessId = activeBiz.activeBusinessID else { return }
        await NotificationInboxService.shared.markAllRead(
            notifications: scopedNotifications,
            modelContext: modelContext,
            businessId: businessId
        )
    }

    private func formattedTimestamp(ms: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct NotificationDetailView: View {
    let item: AppNotification

    var body: some View {
        NavigationStack {
            List {
                Section("Title") {
                    Text(item.title)
                }
                Section("Message") {
                    Text(item.body)
                }
                Section("Event") {
                    Text(item.eventType)
                }
                if let deepLink = item.deepLink, !deepLink.isEmpty {
                    Section("Deep Link") {
                        Text(deepLink)
                            .textSelection(.enabled)
                    }
                }
                if let raw = item.rawDataJson, !raw.isEmpty {
                    Section("Raw Data") {
                        Text(raw)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject private var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var stats = AdminDashboardStats.empty
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var lastUpdated: Date?

    /// Space reserved for the custom tab bar above the home indicator.
    private let tabBarClearance: CGFloat = 88
    private let cardSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 20

    var body: some View {
        NavigationView {
            Group {
                if appState.isAdminUser {
                    dashboardList
                } else {
                    unauthorizedState
                }
            }
            .background(SpectRoomBackground())
            .navigationTitle("dashboard.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("dashboard.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if appState.isAdminUser {
                        Button {
                            Task { await loadStats(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .task {
                await loadStats()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var dashboardList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: cardSpacing) {
                if let loadError, stats == .empty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundColor(SpectRoomTheme.text)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SpectRoomTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                    )
                }

                Text(
                    String(
                        format: "dashboard.updated".localized,
                        lastUpdated.map { Self.dashboardUpdatedTimestamp($0) } ?? "—"
                    )
                )
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

                ForEach(metricRows) { row in
                    Group {
                        if row.destinationTab != nil || row.restrictSheet != nil {
                            Button {
                                if let sheet = row.restrictSheet {
                                    appState.openAdminRestrict(sheet)
                                } else if let destinationTab = row.destinationTab {
                                    appState.requestedAdminTab = destinationTab
                                }
                            } label: {
                                metricCard(for: row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            metricCard(for: row)
                        }
                    }
                    if row.id == "support-pending" {
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, tabBarClearance)
        }
    }

    private func metricCard(for row: DashboardMetricRowModel) -> some View {
        HStack(spacing: 14) {
            Image(systemName: row.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            if isLoading && stats == .empty {
                ProgressView()
            } else {
                Text("\(row.value)")
                    .font(.title3.weight(.bold))
                    .foregroundColor(SpectRoomTheme.text)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
        )
    }

    private var unauthorizedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundColor(SpectRoomTheme.secondaryText)
            Text("admin.error.not.authorized".localized)
                .font(.headline)
                .foregroundColor(SpectRoomTheme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metricRows: [DashboardMetricRowModel] {
        [
            DashboardMetricRowModel(
                id: "total",
                title: "dashboard.metric.total.users".localized,
                subtitle: "dashboard.metric.total.users.subtitle".localized,
                value: stats.totalUsers,
                systemImage: "person.3.fill",
                destinationTab: AdminTab.profiles.rawValue
            ),
            DashboardMetricRowModel(
                id: "active",
                title: "dashboard.metric.active.users".localized,
                subtitle: "dashboard.metric.active.users.subtitle".localized,
                value: stats.activeUsers,
                systemImage: "person.2.fill",
                destinationTab: AdminTab.profiles.rawValue
            ),
            DashboardMetricRowModel(
                id: "online",
                title: "dashboard.metric.online.users".localized,
                subtitle: "dashboard.metric.online.users.subtitle".localized,
                value: stats.onlineUsers,
                systemImage: "circle.fill",
                destinationTab: AdminTab.profiles.rawValue
            ),
            DashboardMetricRowModel(
                id: "support-pending",
                title: "dashboard.metric.support.pending".localized,
                subtitle: "dashboard.metric.support.pending.subtitle".localized,
                value: stats.pendingSupportTickets,
                systemImage: "envelope.badge.fill",
                destinationTab: AdminTab.support.rawValue
            ),
            DashboardMetricRowModel(
                id: "pending",
                title: "dashboard.metric.pending.reports".localized,
                subtitle: "dashboard.metric.pending.reports.subtitle".localized,
                value: stats.pendingReports,
                systemImage: "shield.fill",
                restrictSheet: .reports
            ),
            DashboardMetricRowModel(
                id: "bans",
                title: "dashboard.metric.active.bans".localized,
                subtitle: "dashboard.metric.active.bans.subtitle".localized,
                value: stats.activeBans,
                systemImage: "person.crop.circle.badge.xmark",
                restrictSheet: .banned
            ),
            DashboardMetricRowModel(
                id: "freezes",
                title: "dashboard.metric.active.freezes".localized,
                subtitle: "dashboard.metric.active.freezes.subtitle".localized,
                value: stats.activeFreezes,
                systemImage: "snowflake",
                restrictSheet: .frozen
            )
        ]
    }

    private static func dashboardUpdatedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEE d MMM HH:mm"
        return formatter.string(from: date)
    }

    @MainActor
    private func loadStats(force: Bool = false) async {
        guard appState.isAdminUser else {
            isLoading = false
            return
        }

        if !force,
           let cache = appState.adminDashboardStatsCache,
           cache.stats != .empty {
            stats = cache.stats
            lastUpdated = cache.lastUpdated
            isLoading = false
            loadError = nil
            return
        }

        if isLoading && !force && stats != .empty { return }

        isLoading = true
        loadError = nil
        do {
            let result = try await FirebaseAuthService.shared.fetchAdminDashboardStats()
            stats = result
            lastUpdated = Date()
            appState.updateAdminDashboardStatsCache(stats: result, lastUpdated: lastUpdated ?? Date())
        } catch {
            loadError = error.localizedDescription
            print("⚠️ Dashboard stats failed: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

private struct DashboardMetricRowModel: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let value: Int
    let systemImage: String
    var destinationTab: Int? = nil
    var restrictSheet: AdminRestrictSheet? = nil
}

#Preview {
    AdminDashboardView()
        .environmentObject(AppStateManager.shared)
}

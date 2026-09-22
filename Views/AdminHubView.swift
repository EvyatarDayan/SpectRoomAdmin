import SwiftUI

struct AdminHubView: View {
    @EnvironmentObject private var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAdminReports = false
    @State private var showingAdminFrozenProfiles = false
    @State private var showingAdminBannedProfiles = false
    @State private var showingAdminDeletedProfiles = false

    /// Space reserved for the custom tab bar above the home indicator.
    private let tabBarClearance: CGFloat = 88
    private let cardSpacing: CGFloat = 10
    private let horizontalPadding: CGFloat = 20

    var body: some View {
        NavigationView {
            Group {
                if appState.isAdminUser {
                    adminCards
                } else {
                    unauthorizedState
                }
            }
            .background(SpectRoomBackground())
            .navigationTitle("admin.section.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("admin.section.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
            .sheet(isPresented: $showingAdminReports) {
                AdminReportsView()
                    .environmentObject(appState)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showingAdminFrozenProfiles) {
                AdminFrozenProfilesView()
                    .environmentObject(appState)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showingAdminBannedProfiles) {
                AdminBannedProfilesView()
                    .environmentObject(appState)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showingAdminDeletedProfiles) {
                AdminDeletedProfilesView()
                    .environmentObject(appState)
                    .interactiveDismissDisabled(true)
            }
            .onAppear { applyRequestedRestrictSheetIfNeeded() }
            .onChange(of: appState.requestedAdminRestrictSheet) { _ in
                applyRequestedRestrictSheetIfNeeded()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func applyRequestedRestrictSheetIfNeeded() {
        guard let sheet = appState.requestedAdminRestrictSheet else { return }
        appState.requestedAdminRestrictSheet = nil
        switch sheet {
        case .reports:
            showingAdminReports = true
        case .frozen:
            showingAdminFrozenProfiles = true
        case .banned:
            showingAdminBannedProfiles = true
        case .deleted:
            showingAdminDeletedProfiles = true
        }
    }

    private var adminCards: some View {
        VStack(spacing: cardSpacing) {
            adminCard(
                title: "admin.reports.button.title".localized,
                subtitle: "admin.reports.button.subtitle".localized,
                systemImage: "shield.fill",
                iconColor: .blue,
                badgeCount: appState.unseenAdminReportCount
            ) {
                showingAdminReports = true
            }

            adminCard(
                title: "admin.frozen.button.title".localized,
                subtitle: "admin.frozen.button.subtitle".localized,
                systemImage: "snowflake",
                iconColor: .blue
            ) {
                showingAdminFrozenProfiles = true
            }

            adminCard(
                title: "admin.banned.button.title".localized,
                subtitle: "admin.banned.button.subtitle".localized,
                systemImage: "person.crop.circle.badge.xmark",
                iconColor: .blue
            ) {
                showingAdminBannedProfiles = true
            }

            adminCard(
                title: "admin.deleted.button.title".localized,
                subtitle: "admin.deleted.button.subtitle".localized,
                systemImage: "trash.circle.fill",
                iconColor: .blue
            ) {
                showingAdminDeletedProfiles = true
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, tabBarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private func adminCard(
        title: String,
        subtitle: String,
        systemImage: String,
        iconColor: Color,
        badgeCount: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        UnreadCountBadge(count: badgeCount)
                            .offset(x: 6, y: -6)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AdminHubView()
        .environmentObject(AppStateManager.shared)
}

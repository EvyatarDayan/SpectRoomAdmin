import SwiftUI

struct AdminHubView: View {
    @EnvironmentObject private var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAdminAllProfiles = false
    @State private var showingAdminReports = false
    @State private var showingAdminFrozenProfiles = false
    @State private var showingAdminBannedProfiles = false

    /// Space reserved for the custom tab bar above the home indicator.
    private let tabBarClearance: CGFloat = 88
    private let cardSpacing: CGFloat = 16
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
            .sheet(isPresented: $showingAdminAllProfiles) {
                AdminAllProfilesView()
            }
            .sheet(isPresented: $showingAdminReports) {
                AdminReportsView()
            }
            .sheet(isPresented: $showingAdminFrozenProfiles) {
                AdminFrozenProfilesView()
            }
            .sheet(isPresented: $showingAdminBannedProfiles) {
                AdminBannedProfilesView()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var adminCards: some View {
        VStack(spacing: cardSpacing) {
            adminCard(
                title: "admin.all.profiles.button.title".localized,
                subtitle: "admin.all.profiles.button.subtitle".localized,
                systemImage: "person.3.fill",
                iconColor: .purple,
                iconPointSize: 22
            ) {
                showingAdminAllProfiles = true
            }

            adminCard(
                title: "admin.reports.button.title".localized,
                subtitle: "admin.reports.button.subtitle".localized,
                systemImage: "shield.fill",
                iconColor: .orange
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
                iconColor: .red
            ) {
                showingAdminBannedProfiles = true
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, tabBarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        iconPointSize: CGFloat = 28,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: iconPointSize, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 52, height: 52)
                    .background(iconColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AdminHubView()
        .environmentObject(AppStateManager.shared)
}

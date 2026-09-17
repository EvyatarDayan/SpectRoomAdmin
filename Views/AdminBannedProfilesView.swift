import SwiftUI

struct AdminBannedProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AdminBannedFilter = .banned
    @State private var bannedProfiles: [BannedProfile] = []
    @State private var historyProfiles: [BannedProfile] = []
    @State private var isLoading = true
    @State private var selectedProfile: BannedProfile?
    @State private var pendingConfirmation: BannedActionConfirmation?
    @State private var actionError: String?
    @State private var isPerformingAction = false

    private var displayedProfiles: [BannedProfile] {
        switch filter {
        case .banned: return bannedProfiles
        case .history: return historyProfiles
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    ForEach(AdminBannedFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if displayedProfiles.isEmpty {
                        emptyState
                    } else {
                        List(displayedProfiles) { profile in
                            Button {
                                selectedProfile = profile
                            } label: {
                                AdminBannedProfileRow(profile: profile)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(PlainListStyle())
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(SpectRoomBackground())
            .navigationTitle("admin.banned.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) { dismiss() }
                }
            }
            .overlay {
                if let selectedProfile {
                    AdminBannedProfileDetailOverlay(
                        profile: selectedProfile,
                        isPerformingAction: isPerformingAction,
                        onDismiss: { self.selectedProfile = nil },
                        onRemoveBan: {
                            Task { await removeBan(selectedProfile) }
                        },
                        onBanAgain: {
                            pendingConfirmation = .banAgain(selectedProfile)
                        }
                    )
                }
            }
            .alert(
                "admin.banned.confirm.title".localized,
                isPresented: Binding(
                    get: { pendingConfirmation != nil },
                    set: { if !$0 { pendingConfirmation = nil } }
                ),
                presenting: pendingConfirmation
            ) { confirmation in
                Button("common.cancel".localized, role: .cancel) {
                    pendingConfirmation = nil
                }
                Button(confirmation.confirmButtonTitle, role: confirmation.destructiveRole) {
                    Task { await performConfirmedAction(confirmation) }
                }
            } message: { confirmation in
                Text(confirmation.message)
            }
            .alert("admin.reports.action.error.title".localized, isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("common.ok".localized, role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .task { await loadProfiles() }
            .onChange(of: filter) { _, _ in
                selectedProfile = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .banned ? "person.crop.circle.badge.xmark" : "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundColor(.red)
            Text(filter.emptyTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SpectRoomTheme.text)
            Text(filter.emptyDescription)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadProfiles() async {
        isLoading = true
        defer { isLoading = false }

        var errors: [String] = []

        do {
            bannedProfiles = try await FirebaseAuthService.shared.fetchBannedProfilesForAdmin()
        } catch {
            bannedProfiles = []
            errors.append(error.localizedDescription)
        }

        do {
            historyProfiles = try await FirebaseAuthService.shared.fetchBanHistoryForAdmin()
        } catch {
            historyProfiles = []
            print("⚠️ Ban history load failed: \(error.localizedDescription)")
            if filter == .history {
                errors.append(error.localizedDescription)
            }
        }

        if let firstError = errors.first {
            actionError = firstError
        }
    }

    @MainActor
    private func performConfirmedAction(_ confirmation: BannedActionConfirmation) async {
        pendingConfirmation = nil
        switch confirmation {
        case .banAgain(let profile):
            await banAgain(profile)
        }
    }

    @MainActor
    private func removeBan(_ profile: BannedProfile) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.removeAccountBan(userId: profile.userId)
            selectedProfile = nil
            await loadProfiles()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func banAgain(_ profile: BannedProfile) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.banUserPermanently(
                userId: profile.userId,
                reportId: profile.reportId ?? "admin-ban-\(profile.userId)"
            )
            selectedProfile = nil
            filter = .banned
            await loadProfiles()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private enum AdminBannedFilter: String, CaseIterable, Identifiable {
    case banned, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .banned: return "admin.banned.filter.banned".localized
        case .history: return "admin.banned.filter.history".localized
        }
    }

    var emptyTitle: String {
        switch self {
        case .banned: return "admin.banned.empty".localized
        case .history: return "admin.banned.history.empty".localized
        }
    }

    var emptyDescription: String {
        switch self {
        case .banned: return "admin.banned.empty.description".localized
        case .history: return "admin.banned.history.empty.description".localized
        }
    }
}

private enum BannedActionConfirmation: Identifiable {
    case banAgain(BannedProfile)

    var id: String {
        switch self {
        case .banAgain(let profile): return "ban-again-\(profile.id)"
        }
    }

    var message: String {
        switch self {
        case .banAgain(let profile):
            return String(format: "admin.banned.confirm.ban.again.message".localized, profile.name)
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .banAgain: return "admin.banned.action.ban.again".localized
        }
    }

    var destructiveRole: ButtonRole? {
        switch self {
        case .banAgain: return .destructive
        }
    }
}

private struct AdminBannedProfileRow: View {
    let profile: BannedProfile

    private var statusColor: Color {
        profile.isCurrentlyBanned ? .red : .green
    }

    var body: some View {
        HStack(spacing: 12) {
            profilePhoto
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                Text(profile.status.localizationKey.localized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
                if let bannedAt = profile.bannedAt {
                    Text(String(
                        format: "admin.banned.since".localized,
                        ModerationNotice.formattedUnlockDate(bannedAt)
                    ))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                }
                if let endedAt = profile.endedAt, profile.isHistoryItem {
                    Text(String(
                        format: "admin.banned.ended".localized,
                        ModerationNotice.formattedUnlockDate(endedAt)
                    ))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .contentShape(Rectangle())
    }

    private var titleText: String {
        if let age = profile.age {
            return "\(profile.name), \(age)"
        }
        return profile.name
    }

    private var profilePhoto: some View {
        Group {
            if let photoURL = profile.photoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsPlaceholder
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var initialsPlaceholder: some View {
        Circle()
            .fill(Color.red.opacity(0.2))
            .overlay(
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.red)
            )
    }
}

private struct AdminBannedProfileDetailOverlay: View {
    let profile: BannedProfile
    let isPerformingAction: Bool
    let onDismiss: () -> Void
    let onRemoveBan: () -> Void
    let onBanAgain: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? Color.white : Color.black }
    private var primaryText: Color { isLight ? Color.black : Color.white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        profilePhoto
                        VStack(alignment: .leading, spacing: 4) {
                            Text(headlineText)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(primaryText)
                            if let email = profile.email, !email.isEmpty {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundColor(secondaryText)
                            }
                        }
                    }

                    detailRow(
                        title: "admin.banned.detail.status".localized,
                        value: profile.status.localizationKey.localized
                    )
                    if let bannedAt = profile.bannedAt {
                        detailRow(
                            title: "admin.banned.detail.banned.at".localized,
                            value: ModerationNotice.formattedUnlockDate(bannedAt)
                        )
                    }
                    if let endedAt = profile.endedAt, profile.isHistoryItem {
                        detailRow(
                            title: "admin.banned.detail.ended".localized,
                            value: ModerationNotice.formattedUnlockDate(endedAt)
                        )
                    }
                    if let reportId = profile.reportId, !reportId.isEmpty {
                        detailRow(
                            title: "admin.banned.detail.report".localized,
                            value: reportId
                        )
                    }

                    if isPerformingAction {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    } else if profile.isCurrentlyBanned {
                        HStack(spacing: 12) {
                            Button(action: onDismiss) {
                                Text("common.cancel".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button(action: onRemoveBan) {
                                Text("admin.banned.action.remove".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    } else {
                        HStack(spacing: 12) {
                            Button(action: onDismiss) {
                                Text("common.cancel".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button(action: onBanAgain) {
                                Text("admin.banned.action.ban.again".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.vertical, 40)
            }
        }
        .allowsHitTesting(true)
    }

    private var headlineText: String {
        if let age = profile.age {
            return "\(profile.name), \(age)"
        }
        return profile.name
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(secondaryText)
            Text(value)
                .font(.subheadline)
                .foregroundColor(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var profilePhoto: some View {
        Group {
            if let photoURL = profile.photoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsPlaceholder
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var initialsPlaceholder: some View {
        Circle()
            .fill(Color.red.opacity(0.2))
            .overlay(
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.red)
            )
    }
}

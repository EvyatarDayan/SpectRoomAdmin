import SwiftUI

struct AdminFrozenProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AdminFrozenFilter = .frozen
    @State private var frozenProfiles: [FrozenProfile] = []
    @State private var historyProfiles: [FrozenProfile] = []
    @State private var isLoading = true
    @State private var selectedProfile: FrozenProfile?
    @State private var profilePendingDuration: FrozenProfile?
    @State private var durationAction: FrozenDurationAction = .extend
    @State private var pendingConfirmation: FrozenActionConfirmation?
    @State private var actionError: String?
    @State private var isPerformingAction = false

    private var displayedProfiles: [FrozenProfile] {
        switch filter {
        case .frozen: return frozenProfiles
        case .history: return historyProfiles
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    ForEach(AdminFrozenFilter.allCases) { item in
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
                                AdminFrozenProfileRow(profile: profile)
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
            .navigationTitle("admin.frozen.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) { dismiss() }
                }
            }
            .overlay {
                if let selectedProfile, profilePendingDuration == nil {
                    AdminFrozenProfileDetailOverlay(
                        profile: selectedProfile,
                        isPerformingAction: isPerformingAction,
                        onDismiss: { self.selectedProfile = nil },
                        onRemoveFreeze: {
                            pendingConfirmation = .remove(selectedProfile)
                        },
                        onExtend: {
                            durationAction = .extend
                            profilePendingDuration = selectedProfile
                        },
                        onFreezeAgain: {
                            durationAction = .refreeze
                            profilePendingDuration = selectedProfile
                        }
                    )
                } else if let profilePendingDuration {
                    AdminFreezeDurationOverlay(
                        reportedName: profilePendingDuration.name,
                        onCancel: { self.profilePendingDuration = nil },
                        onConfirm: { duration in
                            let profile = profilePendingDuration
                            let action = durationAction
                            self.profilePendingDuration = nil
                            switch action {
                            case .extend:
                                pendingConfirmation = .extend(profile, duration)
                            case .refreeze:
                                pendingConfirmation = .refreeze(profile, duration)
                            }
                        }
                    )
                }
            }
            .alert(
                "admin.frozen.confirm.title".localized,
                isPresented: Binding(
                    get: { pendingConfirmation != nil },
                    set: { if !$0 { pendingConfirmation = nil } }
                ),
                presenting: pendingConfirmation
            ) { confirmation in
                Button("common.cancel".localized, role: .cancel) {
                    pendingConfirmation = nil
                }
                Button(confirmation.confirmButtonTitle) {
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
                profilePendingDuration = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .frozen ? "snowflake" : "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundColor(.blue)
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
            frozenProfiles = try await FirebaseAuthService.shared.fetchFrozenProfilesForAdmin()
        } catch {
            frozenProfiles = []
            errors.append(error.localizedDescription)
        }

        do {
            historyProfiles = try await FirebaseAuthService.shared.fetchFreezeHistoryForAdmin()
        } catch {
            historyProfiles = []
            // History often fails until moderationFreezes rules are published — don't block Frozen tab.
            print("⚠️ Freeze history load failed: \(error.localizedDescription)")
            if filter == .history {
                errors.append(error.localizedDescription)
            }
        }

        if let firstError = errors.first {
            actionError = firstError
        }
    }

    @MainActor
    private func performConfirmedAction(_ confirmation: FrozenActionConfirmation) async {
        pendingConfirmation = nil
        switch confirmation {
        case .remove(let profile):
            await removeFreeze(profile)
        case .extend(let profile, let duration):
            await extendFreeze(profile, duration: duration)
        case .refreeze(let profile, let duration):
            await freezeAgain(profile, duration: duration)
        }
    }

    @MainActor
    private func removeFreeze(_ profile: FrozenProfile) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.removeAccountFreeze(userId: profile.userId)
            selectedProfile = nil
            await loadProfiles()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func extendFreeze(_ profile: FrozenProfile, duration: ModerationFreezeDuration) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.extendAccountFreeze(
                userId: profile.userId,
                reportId: profile.reportId,
                duration: duration
            )
            selectedProfile = nil
            await loadProfiles()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func freezeAgain(_ profile: FrozenProfile, duration: ModerationFreezeDuration) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.freezeUserAccount(
                userId: profile.userId,
                duration: duration,
                reportId: profile.reportId,
                markReportActioned: false
            )
            selectedProfile = nil
            filter = .frozen
            await loadProfiles()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private enum AdminFrozenFilter: String, CaseIterable, Identifiable {
    case frozen, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frozen: return "admin.frozen.filter.frozen".localized
        case .history: return "admin.frozen.filter.history".localized
        }
    }

    var emptyTitle: String {
        switch self {
        case .frozen: return "admin.frozen.empty".localized
        case .history: return "admin.frozen.history.empty".localized
        }
    }

    var emptyDescription: String {
        switch self {
        case .frozen: return "admin.frozen.empty.description".localized
        case .history: return "admin.frozen.history.empty.description".localized
        }
    }
}

private enum FrozenDurationAction {
    case extend
    case refreeze
}

private enum FrozenActionConfirmation: Identifiable {
    case remove(FrozenProfile)
    case extend(FrozenProfile, ModerationFreezeDuration)
    case refreeze(FrozenProfile, ModerationFreezeDuration)

    var id: String {
        switch self {
        case .remove(let profile): return "remove-\(profile.id)"
        case .extend(let profile, let duration): return "extend-\(profile.id)-\(duration.rawValue)"
        case .refreeze(let profile, let duration): return "refreeze-\(profile.id)-\(duration.rawValue)"
        }
    }

    var message: String {
        switch self {
        case .remove(let profile):
            return String(format: "admin.frozen.confirm.remove.message".localized, profile.name)
        case .extend(let profile, let duration):
            return String(
                format: "admin.frozen.confirm.extend.message".localized,
                profile.name,
                duration.labelKey.localized
            )
        case .refreeze(let profile, let duration):
            return String(
                format: "admin.frozen.confirm.refreeze.message".localized,
                profile.name,
                duration.labelKey.localized
            )
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .remove: return "admin.frozen.action.remove".localized
        case .extend: return "admin.frozen.action.extend".localized
        case .refreeze: return "admin.frozen.action.refreeze".localized
        }
    }
}

private struct AdminFrozenProfileRow: View {
    let profile: FrozenProfile

    private var statusColor: Color {
        if profile.isCurrentlyFrozen { return .blue }
        switch profile.status {
        case .lifted: return .green
        case .expired: return .orange
        case .banned: return .red
        case .active: return .blue
        }
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
                if profile.isCurrentlyFrozen {
                    Text(String(format: "admin.frozen.until".localized, profile.unlockLabel))
                        .font(.caption)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                } else if let endedAt = profile.endedAt {
                    Text(String(
                        format: "admin.frozen.ended".localized,
                        ModerationNotice.formattedUnlockDate(endedAt)
                    ))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                } else {
                    Text(String(format: "admin.frozen.until".localized, profile.unlockLabel))
                        .font(.caption)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
                Text(String(format: "admin.frozen.hours".localized, profile.freezeHours))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
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
            .fill(Color.blue.opacity(0.2))
            .overlay(
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.blue)
            )
    }
}

private struct AdminFrozenProfileDetailOverlay: View {
    let profile: FrozenProfile
    let isPerformingAction: Bool
    let onDismiss: () -> Void
    let onRemoveFreeze: () -> Void
    let onExtend: () -> Void
    let onFreezeAgain: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? Color.white : Color.black }
    private var primaryText: Color { isLight ? Color.black : Color.white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }
    private var isHistory: Bool { profile.isHistoryItem }

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
                        title: "admin.frozen.detail.status".localized,
                        value: profile.status.localizationKey.localized
                    )
                    detailRow(
                        title: isHistory
                            ? "admin.frozen.detail.was.until".localized
                            : "admin.frozen.detail.until".localized,
                        value: profile.unlockLabel
                    )
                    detailRow(
                        title: "admin.frozen.detail.hours".localized,
                        value: String(format: "admin.frozen.hours".localized, profile.freezeHours)
                    )
                    if let endedAt = profile.endedAt, isHistory {
                        detailRow(
                            title: "admin.frozen.detail.ended".localized,
                            value: ModerationNotice.formattedUnlockDate(endedAt)
                        )
                    }
                    if let reportId = profile.reportId, !reportId.isEmpty {
                        detailRow(
                            title: "admin.frozen.detail.report".localized,
                            value: reportId
                        )
                    }

                    VStack(spacing: 10) {
                        if profile.isCurrentlyFrozen {
                            adminActionButton(
                                title: "admin.frozen.action.remove".localized,
                                subtitle: "admin.frozen.action.remove.subtitle".localized,
                                action: onRemoveFreeze
                            )
                            adminActionButton(
                                title: "admin.frozen.action.extend".localized,
                                subtitle: "admin.frozen.action.extend.subtitle".localized,
                                action: onExtend
                            )
                        } else if profile.status != .banned {
                            adminActionButton(
                                title: "admin.frozen.action.refreeze".localized,
                                subtitle: "admin.frozen.action.refreeze.subtitle".localized,
                                action: onFreezeAgain
                            )
                        }
                    }
                    .padding(.top, 4)
                    .disabled(isPerformingAction)
                    .opacity(isPerformingAction ? 0.6 : 1)

                    if isPerformingAction {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    Button(action: onDismiss) {
                        Text("common.got.it".localized)
                            .font(.body.weight(.medium))
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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

    private func adminActionButton(
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.systemGray6).opacity(isLight ? 1 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            .fill(Color.blue.opacity(0.2))
            .overlay(
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.blue)
            )
    }
}

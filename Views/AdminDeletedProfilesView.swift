import SwiftUI

struct AdminDeletedProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppStateManager
    @State private var filter: AdminDeletedFilter = .deleted
    @State private var deletedProfiles: [DeletedProfile] = []
    @State private var historyProfiles: [DeletedProfile] = []
    @State private var isLoading = true
    @State private var selectedProfile: DeletedProfile?
    @State private var pendingConfirmation: DeletedActionConfirmation?
    @State private var actionError: String?
    @State private var isPerformingAction = false
    @State private var searchText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        !trimmedSearch.isEmpty
    }

    private var displayedProfiles: [DeletedProfile] {
        let base: [DeletedProfile]
        switch filter {
        case .deleted: base = deletedProfiles
        case .history: base = historyProfiles
        }
        guard isSearchActive else { return base }
        let query = trimmedSearch.lowercased()
        return base.filter { profile in
            profile.name.lowercased().contains(query)
                || (profile.email?.lowercased().contains(query) ?? false)
                || profile.userId.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    ForEach(AdminDeletedFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

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
                                AdminDeletedProfileRow(profile: profile)
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
            .navigationTitle("admin.deleted.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await loadProfiles(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) { dismiss() }
                }
            }
            .overlay {
                if let selectedProfile {
                    AdminDeletedProfileDetailOverlay(
                        profile: selectedProfile,
                        isPerformingAction: isPerformingAction,
                        onDismiss: { self.selectedProfile = nil },
                        onUndelete: {
                            pendingConfirmation = .undelete(selectedProfile)
                        },
                        onDeleteAgain: {
                            pendingConfirmation = .deleteAgain(selectedProfile)
                        }
                    )
                }
            }
            .alert(
                "admin.deleted.confirm.title".localized,
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
            Image(systemName: isSearchActive ? "magnifyingglass" : (filter == .deleted ? "trash.circle" : "clock.arrow.circlepath"))
                .font(.system(size: 44))
                .foregroundColor(.purple)
            Text(isSearchActive ? "admin.restrict.search.empty".localized : filter.emptyTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SpectRoomTheme.text)
            Text(isSearchActive ? "admin.restrict.search.empty.description".localized : filter.emptyDescription)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SpectRoomTheme.secondaryText)
            TextField("admin.restrict.search.placeholder".localized, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .textContentType(.none)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @MainActor
    private func loadProfiles(forceRefresh: Bool = false) async {
        if !forceRefresh, let cache = appState.adminDeletedProfilesCache {
            deletedProfiles = cache.deleted
            historyProfiles = cache.history
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        var errors: [String] = []

        do {
            deletedProfiles = try await FirebaseAuthService.shared.fetchDeletedProfilesForAdmin()
        } catch {
            deletedProfiles = []
            errors.append(error.localizedDescription)
        }

        do {
            historyProfiles = try await FirebaseAuthService.shared.fetchDeleteHistoryForAdmin()
        } catch {
            historyProfiles = []
            print("⚠️ Delete history load failed: \(error.localizedDescription)")
            if filter == .history {
                errors.append(error.localizedDescription)
            }
        }

        if errors.isEmpty {
            appState.updateAdminDeletedProfilesCache(deleted: deletedProfiles, history: historyProfiles)
        }

        if let firstError = errors.first {
            actionError = firstError
        }
    }

    @MainActor
    private func performConfirmedAction(_ confirmation: DeletedActionConfirmation) async {
        pendingConfirmation = nil
        switch confirmation {
        case .undelete(let profile):
            await undelete(profile)
        case .deleteAgain(let profile):
            await deleteAgain(profile)
        }
    }

    @MainActor
    private func undelete(_ profile: DeletedProfile) async {
        guard profile.canUndelete else { return }
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.undeleteAdminUser(userId: profile.userId)
            selectedProfile = nil
            filter = .history
            await loadProfiles(forceRefresh: true)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteAgain(_ profile: DeletedProfile) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.hardDeleteAdminUser(userId: profile.userId)
            selectedProfile = nil
            filter = .deleted
            await loadProfiles(forceRefresh: true)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private enum AdminDeletedFilter: String, CaseIterable, Identifiable {
    case deleted, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deleted: return "admin.deleted.filter.deleted".localized
        case .history: return "admin.deleted.filter.history".localized
        }
    }

    var emptyTitle: String {
        switch self {
        case .deleted: return "admin.deleted.empty".localized
        case .history: return "admin.deleted.history.empty".localized
        }
    }

    var emptyDescription: String {
        switch self {
        case .deleted: return "admin.deleted.empty.description".localized
        case .history: return "admin.deleted.history.empty.description".localized
        }
    }
}

private enum DeletedActionConfirmation: Identifiable {
    case undelete(DeletedProfile)
    case deleteAgain(DeletedProfile)

    var id: String {
        switch self {
        case .undelete(let profile): return "undelete-\(profile.id)"
        case .deleteAgain(let profile): return "delete-again-\(profile.id)"
        }
    }

    var message: String {
        switch self {
        case .undelete(let profile):
            return String(format: "admin.deleted.confirm.undelete.message".localized, profile.name)
        case .deleteAgain(let profile):
            return String(format: "admin.deleted.confirm.delete.again.message".localized, profile.name)
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .undelete: return "admin.deleted.action.undelete".localized
        case .deleteAgain: return "admin.deleted.action.delete.again".localized
        }
    }

    var destructiveRole: ButtonRole? {
        switch self {
        case .undelete: return nil
        case .deleteAgain: return .destructive
        }
    }
}

private struct AdminDeletedProfileRow: View {
    let profile: DeletedProfile

    var body: some View {
        HStack(spacing: 12) {
            profilePhoto
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                Text(profile.displayEmail)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .lineLimit(1)
                if let deletedAt = profile.deletedAt {
                    Text(String(
                        format: "admin.deleted.since".localized,
                        ModerationNotice.formattedUnlockDate(deletedAt)
                    ))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                }
                if let restoredAt = profile.restoredAt, profile.isHistoryItem {
                    Text(String(
                        format: "admin.deleted.restored".localized,
                        ModerationNotice.formattedUnlockDate(restoredAt)
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
            .fill(Color.purple.opacity(0.2))
            .overlay(
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.purple)
            )
    }
}

private struct AdminDeletedProfileDetailOverlay: View {
    let profile: DeletedProfile
    let isPerformingAction: Bool
    let onDismiss: () -> Void
    let onUndelete: () -> Void
    let onDeleteAgain: () -> Void

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
                        Text(profile.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    detailRow(
                        title: "admin.deleted.detail.email".localized,
                        value: profile.displayEmail
                    )
                    detailRow(
                        title: "admin.deleted.detail.deleted.by".localized,
                        value: profile.deletedBy.localizationKey.localized
                    )
                    detailRow(
                        title: "admin.deleted.detail.status".localized,
                        value: profile.status.localizationKey.localized
                    )
                    if let deletedAt = profile.deletedAt {
                        detailRow(
                            title: "admin.deleted.detail.deleted.at".localized,
                            value: ModerationNotice.formattedUnlockDate(deletedAt)
                        )
                    }
                    detailRow(
                        title: "admin.deleted.detail.fully.deleted.at".localized,
                        value: profile.displayFullyDeletedAt
                    )
                    if let restoredAt = profile.restoredAt, profile.isHistoryItem {
                        detailRow(
                            title: "admin.deleted.detail.restored.at".localized,
                            value: ModerationNotice.formattedUnlockDate(restoredAt)
                        )
                    }

                    if isPerformingAction {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    } else if profile.isHistoryItem {
                        HStack(spacing: 12) {
                            Button(action: onDismiss) {
                                Text("common.close".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button(action: onDeleteAgain) {
                                Text("admin.deleted.action.delete.again".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.purple)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    } else {
                        HStack(spacing: 12) {
                            Button(action: onDismiss) {
                                Text("common.close".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button(action: onUndelete) {
                                Text("admin.deleted.action.undelete".localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(profile.canUndelete ? .white : secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(profile.canUndelete ? Color.green : Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!profile.canUndelete)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: 420)
                .background(panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
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
            .fill(Color.purple.opacity(0.2))
            .overlay(
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.purple)
            )
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(secondaryText)
            Text(value)
                .font(.body)
                .foregroundColor(primaryText)
        }
    }
}

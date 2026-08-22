import SwiftUI

struct AdminAllProfilesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var profiles: [AdminUserProfile] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isSearching = false
    @State private var hasMore = false
    @State private var lastDocumentId: String?
    @State private var selectedProfile: AdminUserProfile?
    @State private var loadError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var filterFrozen = false
    @State private var filterBanned = false

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        trimmedSearch.count >= 2
    }

    private var isStatusFilterActive: Bool {
        filterFrozen || filterBanned
    }

    /// Profiles after Freeze / Ban chips (OR when both selected).
    private var displayedProfiles: [AdminUserProfile] {
        guard isStatusFilterActive else { return profiles }
        return profiles.filter { profile in
            (filterFrozen && profile.isFrozen) || (filterBanned && profile.isBanned)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                filterBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let loadError, profiles.isEmpty {
                        errorState(loadError)
                    } else if displayedProfiles.isEmpty {
                        emptyState
                    } else {
                        profilesList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(SpectRoomBackground())
            .navigationTitle("admin.all.profiles.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) { dismiss() }
                }
            }
            .overlay {
                if let selectedProfile {
                    AdminUserDetailOverlay(
                        profile: selectedProfile,
                        onDismiss: { self.selectedProfile = nil },
                        onProfileUpdated: { updated in
                            applyProfileUpdate(updated)
                        }
                    )
                }
            }
            .alert("admin.reports.action.error.title".localized, isPresented: Binding(
                get: { loadError != nil && !profiles.isEmpty },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("common.ok".localized, role: .cancel) { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
            .task { await loadInitial() }
            .onChange(of: searchText) { _, _ in
                searchTask?.cancel()
                searchTask = Task { await handleSearchChange() }
            }
            .onChange(of: filterFrozen) { _, _ in
                Task { await ensureFilteredResults() }
            }
            .onChange(of: filterBanned) { _, _ in
                Task { await ensureFilteredResults() }
            }
        }
        // Block sheet swipe-down while a profile (or its messages thread) is open.
        .interactiveDismissDisabled(selectedProfile != nil)
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SpectRoomTheme.secondaryText)
            TextField("admin.all.profiles.search.placeholder".localized, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .textContentType(.none)
            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            } else if !searchText.isEmpty {
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

    private var filterBar: some View {
        HStack(spacing: 10) {
            filterChip(
                title: "admin.all.profiles.filter.freeze".localized,
                systemImage: "snowflake",
                isSelected: filterFrozen,
                selectedColor: .blue
            ) {
                filterFrozen.toggle()
            }
            filterChip(
                title: "admin.all.profiles.filter.ban".localized,
                systemImage: "person.crop.circle.badge.xmark",
                isSelected: filterBanned,
                selectedColor: .red
            ) {
                filterBanned.toggle()
            }
            Spacer(minLength: 0)
            if !isLoading {
                Text("\(displayedProfiles.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .monospacedDigit()
                    .accessibilityLabel("admin.all.profiles.title".localized)
                    .accessibilityValue("\(displayedProfiles.count)")
            }
        }
    }

    private func filterChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        selectedColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(isSelected ? .white : SpectRoomTheme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? selectedColor : SpectRoomTheme.card)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : SpectRoomTheme.secondaryText.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var profilesList: some View {
        List {
            ForEach(displayedProfiles) { profile in
                Button {
                    selectedProfile = profile
                } label: {
                    AdminAllProfileRow(profile: profile)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    if !isSearchActive, profile.id == displayedProfiles.last?.id {
                        Task {
                            if isStatusFilterActive {
                                await ensureFilteredResults()
                            } else {
                                await loadMore()
                            }
                        }
                    }
                }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await loadInitial()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 44))
                .foregroundColor(.blue)
            Text(emptyStateTitle)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(SpectRoomTheme.text)
            Text(emptyStateDescription)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundColor(SpectRoomTheme.secondaryText)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .padding(.horizontal, 24)
            Button("common.retry".localized) {
                Task { await loadInitial() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if isSearchActive || isStatusFilterActive {
            return "admin.all.profiles.search.empty".localized
        }
        return "admin.all.profiles.empty".localized
    }

    private var emptyStateDescription: String {
        if isStatusFilterActive && !isSearchActive {
            return "admin.all.profiles.filter.empty.description".localized
        }
        if isSearchActive {
            return "admin.all.profiles.search.empty.description".localized
        }
        return "admin.all.profiles.empty.description".localized
    }

    @MainActor
    private func ensureFilteredResults() async {
        guard isStatusFilterActive, !isSearchActive else { return }
        var pagesLoaded = 0
        while displayedProfiles.count < 15, hasMore, !isLoadingMore, pagesLoaded < 8 {
            pagesLoaded += 1
            await loadMore()
        }
    }

    @MainActor
    private func applyProfileUpdate(_ updated: AdminUserProfile) {
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        }
        if selectedProfile?.id == updated.id {
            selectedProfile = updated
        }
    }

    @MainActor

    private func loadInitial() async {
        if isSearchActive {
            await performSearch()
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let page = try await FirebaseAuthService.shared.fetchAdminUsersPage(limit: 25)
            profiles = page.users
            lastDocumentId = page.lastDocumentId
            hasMore = page.hasMore
        } catch {
            profiles = []
            lastDocumentId = nil
            hasMore = false
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isSearchActive, hasMore, !isLoadingMore, let lastDocumentId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await FirebaseAuthService.shared.fetchAdminUsersPage(
                limit: 25,
                startAfterDocumentId: lastDocumentId
            )
            let existingIds = Set(profiles.map(\.id))
            profiles.append(contentsOf: page.users.filter { !existingIds.contains($0.id) })
            self.lastDocumentId = page.lastDocumentId
            hasMore = page.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func handleSearchChange() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        guard trimmedSearch == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        if isSearchActive {
            await performSearch()
        } else if trimmedSearch.isEmpty {
            await loadInitial()
        }
    }

    @MainActor
    private func performSearch() async {
        let query = trimmedSearch
        guard query.count >= 2 else { return }
        guard !Task.isCancelled else { return }

        isSearching = true
        loadError = nil
        defer { isSearching = false }

        do {
            let results = try await FirebaseAuthService.shared.searchAdminUsers(query: query)
            guard !Task.isCancelled else { return }
            guard trimmedSearch == query else { return }
            profiles = results
            hasMore = false
            lastDocumentId = nil
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }
}

private struct AdminAllProfileRow: View {
    let profile: AdminUserProfile

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.titleText)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                if !profile.email.isEmpty {
                    Text(profile.email)
                        .font(.caption)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .lineLimit(1)
                }
                Text(profile.statusLabelKey.localized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SpectRoomTheme.card.opacity(0.9))
        .cornerRadius(12)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if profile.isDeleted || profile.isBanned { return .red }
        if profile.isFrozen { return .blue }
        if profile.isOnline { return .green }
        return SpectRoomTheme.secondaryText
    }

    private var avatar: some View {
        Group {
            if let photoURL = profile.photoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay(
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.blue)
            )
    }
}

private struct AdminUserDetailOverlay: View {
    let profile: AdminUserProfile
    let onDismiss: () -> Void
    let onProfileUpdated: (AdminUserProfile) -> Void

    @EnvironmentObject private var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentProfile: AdminUserProfile
    @State private var selectedTab: AdminUserDetailTab = .profile
    @State private var conversations: [AdminRecentConversation] = []
    @State private var isLoadingMessages = false
    @State private var messagesError: String?
    @State private var selectedConversation: AdminRecentConversation?
    @State private var isExportingMessages = false
    @State private var showingExportShareSheet = false
    @State private var exportFileURL: URL?
    @State private var showingExportEmptyAlert = false
    @State private var showingExportErrorAlert = false
    @State private var showingRestrictSheet = false
    @State private var restrictFollowUp: AdminProfileRestrictFollowUp?
    @State private var isPerformingRestrictAction = false
    @State private var restrictActionError: String?

    init(
        profile: AdminUserProfile,
        onDismiss: @escaping () -> Void,
        onProfileUpdated: @escaping (AdminUserProfile) -> Void
    ) {
        self.profile = profile
        self.onDismiss = onDismiss
        self.onProfileUpdated = onProfileUpdated
        _currentProfile = State(initialValue: profile)
    }


    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? .white : .black }
    private var primaryText: Color { isLight ? .black : .white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(20)

                Picker("", selection: $selectedTab) {
                    ForEach(AdminUserDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                Group {
                    switch selectedTab {
                    case .profile:
                        profileTab
                    case .messages:
                        messagesTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button(action: onDismiss) {
                    Text("common.done".localized)
                        .font(.body.weight(.medium))
                        .foregroundColor(primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 36)

            if let selectedConversation {
                AdminConversationThreadOverlay(
                    subjectProfile: profile,
                    conversation: selectedConversation,
                    onDismiss: { self.selectedConversation = nil }
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if showingRestrictSheet {
                AdminProfileRestrictOverlay(
                    isSubmitting: isPerformingRestrictAction,
                    onCancel: { showingRestrictSheet = false },
                    onSubmit: { action in
                        showingRestrictSheet = false
                        handleRestrictSelection(action)
                    }
                )
                .zIndex(2)
            }

            if case .warning = restrictFollowUp {
                AdminWarningComposeOverlay(
                    onCancel: { restrictFollowUp = nil },
                    onSubmit: { message in
                        restrictFollowUp = nil
                        Task { await performWarning(message: message) }
                    }
                )
                .zIndex(3)
            }

            if case .freeze = restrictFollowUp {
                AdminFreezeDurationOverlay(
                    reportedName: currentProfile.name,
                    onCancel: { restrictFollowUp = nil },
                    onConfirm: { duration in
                        restrictFollowUp = nil
                        Task { await performFreeze(duration: duration) }
                    }
                )
                .zIndex(3)
            }

            if case .ban = restrictFollowUp {
                AdminBanConfirmOverlay(
                    reportedName: currentProfile.name,
                    onCancel: { restrictFollowUp = nil },
                    onConfirm: {
                        restrictFollowUp = nil
                        Task { await performBan() }
                    }
                )
                .zIndex(3)
            }
        }
        .sheet(isPresented: $showingExportShareSheet, onDismiss: {
            exportFileURL = nil
        }) {
            if let exportFileURL {
                ActivityShareSheet(items: [exportFileURL])
            }
        }
        .alert("admin.all.profiles.export".localized, isPresented: $showingExportEmptyAlert) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("admin.all.profiles.export.empty".localized)
        }
        .alert("admin.all.profiles.export".localized, isPresented: $showingExportErrorAlert) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("admin.all.profiles.export.error".localized)
        }
        .alert("admin.reports.action.error.title".localized, isPresented: Binding(
            get: { restrictActionError != nil },
            set: { if !$0 { restrictActionError = nil } }
        )) {
            Button("common.ok".localized, role: .cancel) { restrictActionError = nil }
        } message: {
            Text(restrictActionError ?? "")
        }
        .task(id: profile.id) {
            await loadMessages()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(currentProfile.titleText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(primaryText)
                if !currentProfile.email.isEmpty {
                    Text(currentProfile.email)
                        .font(.subheadline)
                        .foregroundColor(secondaryText)
                }
                Text(currentProfile.statusLabelKey.localized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    exportMessages()
                } label: {
                    if isExportingMessages {
                        ProgressView()
                    } else {
                        Text("admin.all.profiles.export".localized)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .disabled(isExportingMessages || isPerformingRestrictAction)
                .buttonStyle(.plain)

                Button {
                    showingRestrictSheet = true
                } label: {
                    Text("admin.all.profiles.restrict".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                }
                .disabled(isPerformingRestrictAction || currentProfile.isDeleted)
                .buttonStyle(.plain)
            }
        }
    }

    private var profileTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !currentProfile.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(currentProfile.photos, id: \.self) { photo in
                                if let url = URL(string: photo) {
                                    CachedAsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.2)
                                    }
                                    .frame(width: 96, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                }

                detailRow(title: "admin.all.profiles.detail.user.id".localized, value: profile.id)
                if !currentProfile.gender.isEmpty {
                    detailRow(title: "admin.all.profiles.detail.gender".localized, value: currentProfile.gender)
                }
                if !currentProfile.locationDisplay.isEmpty {
                    detailRow(title: "admin.all.profiles.detail.location".localized, value: currentProfile.locationDisplay)
                }
                if !currentProfile.bio.isEmpty {
                    detailRow(title: "admin.all.profiles.detail.bio".localized, value: currentProfile.bio)
                }
                if !currentProfile.interests.isEmpty {
                    detailRow(
                        title: "admin.all.profiles.detail.interests".localized,
                        value: currentProfile.interests.joined(separator: ", ")
                    )
                }
                if !currentProfile.interestedIn.isEmpty {
                    detailRow(
                        title: "admin.all.profiles.detail.interested.in".localized,
                        value: currentProfile.interestedIn.joined(separator: ", ")
                    )
                }
                if !currentProfile.lookingFor.isEmpty {
                    detailRow(
                        title: "admin.all.profiles.detail.looking.for".localized,
                        value: currentProfile.lookingFor.joined(separator: ", ")
                    )
                }
                if let lastSeen = currentProfile.lastSeen {
                    detailRow(
                        title: "admin.all.profiles.detail.last.seen".localized,
                        value: ModerationNotice.formattedUnlockDate(lastSeen)
                    )
                }
                if let frozenUntil = currentProfile.frozenUntil, currentProfile.isFrozen {
                    detailRow(
                        title: "admin.all.profiles.detail.frozen.until".localized,
                        value: ModerationNotice.formattedUnlockDate(frozenUntil)
                    )
                }
                if let createdAt = currentProfile.createdAt {
                    detailRow(
                        title: "admin.all.profiles.detail.created".localized,
                        value: ModerationNotice.formattedUnlockDate(createdAt)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var messagesTab: some View {
        Group {
            if isLoadingMessages {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let messagesError {
                Text(messagesError)
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 34))
                        .foregroundColor(.blue)
                    Text("admin.all.profiles.messages.empty".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(primaryText)
                    Text("admin.all.profiles.messages.empty.description".localized)
                        .font(.caption)
                        .foregroundColor(secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(conversations) { conversation in
                    Button {
                        selectedConversation = conversation
                    } label: {
                        conversationRow(conversation)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func conversationRow(_ conversation: AdminRecentConversation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            partnerAvatar(conversation)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.partnerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(primaryText)
                    Spacer()
                    Text(conversation.createdAt.timeAgoDisplay())
                        .font(.caption2)
                        .foregroundColor(secondaryText)
                }
                Text(
                    (conversation.isOutgoing ? "admin.all.profiles.messages.outgoing".localized : "admin.all.profiles.messages.incoming".localized)
                    + ": "
                    + conversation.preview
                )
                .font(.caption)
                .foregroundColor(secondaryText)
                .lineLimit(3)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(secondaryText)
                .padding(.top, 4)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(isLight ? 1 : 0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
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

    private func avatar(size: CGFloat) -> some View {
        Group {
            if let photoURL = currentProfile.photoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initials(size: size)
                }
            } else {
                initials(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func initials(size: CGFloat) -> some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay(
                Text(String(currentProfile.name.prefix(1)).uppercased())
                    .font(size > 50 ? .title3.weight(.semibold) : .headline.weight(.semibold))
                    .foregroundColor(.blue)
            )
    }

    private func partnerAvatar(_ conversation: AdminRecentConversation) -> some View {
        Group {
            if let photoURL = conversation.partnerPhotoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay(Text(String(conversation.partnerName.prefix(1)).uppercased()))
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .overlay(Text(String(conversation.partnerName.prefix(1)).uppercased()))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    @MainActor
    private func exportMessages() {
        guard !isExportingMessages else { return }
        isExportingMessages = true
        Task {
            do {
                let fileURL = try await appState.exportAdminUserMessagesToFile(
                    userId: profile.id,
                    userName: currentProfile.name
                )
                await MainActor.run {
                    isExportingMessages = false
                    if let fileURL {
                        exportFileURL = fileURL
                        showingExportShareSheet = true
                    } else {
                        showingExportEmptyAlert = true
                    }
                }
            } catch {
                print("❌ Error exporting user messages: \(error)")
                await MainActor.run {
                    isExportingMessages = false
                    showingExportErrorAlert = true
                }
            }
        }
    }


    private func handleRestrictSelection(_ action: AdminProfileRestrictAction) {
        switch action {
        case .warn:
            restrictFollowUp = .warning
        case .freeze:
            restrictFollowUp = .freeze
        case .ban:
            restrictFollowUp = .ban
        }
    }

    @MainActor
    private func performWarning(message: String) async {
        await runRestrictAction {
            try await FirebaseAuthService.shared.issueWarningToUser(
                userId: profile.id,
                message: message
            )
        }
    }

    @MainActor
    private func performFreeze(duration: ModerationFreezeDuration) async {
        let freezeUntil = Date().addingTimeInterval(TimeInterval(duration.rawValue * 3600))
        await runRestrictAction {
            try await FirebaseAuthService.shared.freezeUserAccount(
                userId: profile.id,
                duration: duration,
                reportId: nil,
                markReportActioned: false
            )
            let updated = currentProfile.applyingFreeze(until: freezeUntil)
            currentProfile = updated
            onProfileUpdated(updated)
        }
    }

    @MainActor
    private func performBan() async {
        await runRestrictAction {
            try await FirebaseAuthService.shared.banUserPermanently(
                userId: profile.id,
                reportId: nil
            )
            let updated = currentProfile.applyingBan()
            currentProfile = updated
            onProfileUpdated(updated)
        }
    }

    @MainActor
    private func runRestrictAction(_ work: () async throws -> Void) async {
        guard !isPerformingRestrictAction else { return }
        isPerformingRestrictAction = true
        defer { isPerformingRestrictAction = false }
        do {
            try await work()
        } catch {
            restrictActionError = error.localizedDescription
        }
    }

    private func loadMessages() async {
        isLoadingMessages = true
        messagesError = nil
        defer { isLoadingMessages = false }
        do {
            conversations = try await FirebaseAuthService.shared.fetchAdminRecentConversations(for: profile.id)
        } catch {
            conversations = []
            messagesError = error.localizedDescription
        }
    }
}

private enum AdminUserDetailTab: String, CaseIterable, Identifiable {
    case profile, messages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "admin.all.profiles.tab.profile".localized
        case .messages: return "admin.all.profiles.tab.messages".localized
        }
    }
}

private struct AdminConversationMediaItem: Identifiable, Equatable {
    let message: AdminConversationMessage
    var id: String { message.id }
    var isImage: Bool { message.type == .image }
    var isVoice: Bool { message.type == .voice }
}

private struct AdminConversationThreadOverlay: View {
    let subjectProfile: AdminUserProfile
    let conversation: AdminRecentConversation
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var messages: [AdminConversationMessage] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingMediaGallery = false
    @State private var mediaViewerIndex: Int?
    @State private var mediaItems: [AdminConversationMediaItem] = []

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? .white : .black }
    private var primaryText: Color { isLight ? .black : .white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }

    private var threadMediaItems: [AdminConversationMediaItem] {
        messages
            .filter { $0.type == .image || $0.type == .voice }
            .map { AdminConversationMediaItem(message: $0) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(primaryText)
                    }
                    .buttonStyle(.plain)

                    partnerHeaderAvatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.partnerName)
                            .font(.headline)
                            .foregroundColor(primaryText)
                        Text(
                            String(
                                format: "admin.all.profiles.thread.with".localized,
                                subjectProfile.name
                            )
                        )
                        .font(.caption)
                        .foregroundColor(secondaryText)
                    }
                    Spacer()
                    Button {
                        openMediaGallery()
                    } label: {
                        Text("admin.all.profiles.thread.media".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundColor(secondaryText)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if messages.isEmpty {
                        Text("admin.all.profiles.thread.empty".localized)
                            .font(.subheadline)
                            .foregroundColor(secondaryText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    ForEach(messages) { message in
                                        messageBubble(message)
                                            .id(message.id)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .onAppear {
                                if let lastId = messages.last?.id {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button(action: onDismiss) {
                    Text("admin.all.profiles.thread.back".localized)
                        .font(.body.weight(.medium))
                        .foregroundColor(primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 28)

            if showingMediaGallery {
                AdminConversationMediaGalleryOverlay(
                    mediaItems: mediaItems.isEmpty ? threadMediaItems : mediaItems,
                    onDismiss: { showingMediaGallery = false },
                    onSelect: { index in
                        mediaViewerIndex = index
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }

            if let mediaViewerIndex, !(mediaItems.isEmpty ? threadMediaItems : mediaItems).isEmpty {
                let items = mediaItems.isEmpty ? threadMediaItems : mediaItems
                AdminConversationMediaViewerOverlay(
                    mediaItems: items,
                    selectedIndex: Binding(
                        get: { min(max(mediaViewerIndex, 0), items.count - 1) },
                        set: { self.mediaViewerIndex = $0 }
                    ),
                    onDismiss: { self.mediaViewerIndex = nil }
                )
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .task(id: conversation.partnerId) {
            await loadThread()
        }
    }

    private func openMediaGallery() {
        mediaItems = threadMediaItems
        showingMediaGallery = true
        Task {
            // Load a wider window so the gallery can include more media than the thread preview.
            do {
                let all = try await FirebaseAuthService.shared.fetchAdminConversationMessages(
                    subjectUserId: subjectProfile.id,
                    partnerId: conversation.partnerId,
                    limit: 100
                )
                let items = all
                    .filter { $0.type == .image || $0.type == .voice }
                    .map { AdminConversationMediaItem(message: $0) }
                await MainActor.run {
                    mediaItems = items
                }
            } catch {
                // Keep whatever we already have from the thread.
            }
        }
    }

    private var partnerHeaderAvatar: some View {
        Group {
            if let photoURL = conversation.partnerPhotoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.25))
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.25))
                    .overlay(
                        Text(String(conversation.partnerName.prefix(1)).uppercased())
                            .foregroundColor(primaryText)
                    )
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    @ViewBuilder
    private func messageBubble(_ message: AdminConversationMessage) -> some View {
        let isFromSubject = message.isFromSubject
        HStack {
            if isFromSubject { Spacer(minLength: 40) }

            VStack(alignment: isFromSubject ? .trailing : .leading, spacing: 4) {
                Text(
                    isFromSubject
                        ? subjectProfile.name
                        : conversation.partnerName
                )
                .font(.caption2.weight(.semibold))
                .foregroundColor(secondaryText)

                bubbleContent(message, isFromSubject: isFromSubject)

                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(secondaryText)
            }

            if !isFromSubject { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func bubbleContent(_ message: AdminConversationMessage, isFromSubject: Bool) -> some View {
        let bubbleColor = isFromSubject
            ? Color.blue.opacity(isLight ? 0.15 : 0.35)
            : Color(.systemGray5)

        switch message.type {
        case .image:
            Button {
                openMediaViewer(for: message)
            } label: {
                CachedAsyncImage(url: URL(string: message.content)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.gray.opacity(0.2)
                        ProgressView()
                    }
                }
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

        case .voice:
            VoiceMessagePlayerView(
                audioURL: URL(string: message.content),
                displayDuration: message.voiceDuration,
                accentColor: .blue,
                textColor: primaryText,
                baseColor: bubbleColor,
                waveColor: Color.gray.opacity(0.45),
                timestampText: nil,
                isOutgoing: isFromSubject
            )
            .frame(maxWidth: 240, alignment: isFromSubject ? .trailing : .leading)

        case .text, .system, .video:
            Text(message.content.isEmpty ? message.type.displayName : message.content)
                .font(.subheadline)
                .foregroundColor(primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func openMediaViewer(for message: AdminConversationMessage) {
        let items = threadMediaItems
        mediaItems = items
        if let index = items.firstIndex(where: { $0.id == message.id }) {
            mediaViewerIndex = index
        }
    }

    @MainActor
    private func loadThread() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            messages = try await FirebaseAuthService.shared.fetchAdminConversationMessages(
                subjectUserId: subjectProfile.id,
                partnerId: conversation.partnerId,
                limit: 20
            )
        } catch {
            messages = []
            loadError = error.localizedDescription
        }
    }
}

private struct AdminConversationMediaGalleryOverlay: View {
    let mediaItems: [AdminConversationMediaItem]
    let onDismiss: () -> Void
    let onSelect: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? .white : .black }
    private var primaryText: Color { isLight ? .black : .white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }

    private let gridSpacing: CGFloat = 10
    private let gridPadding: CGFloat = 16
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("admin.all.profiles.media.title".localized)
                        .font(.headline)
                        .foregroundColor(primaryText)
                    Spacer()
                    Button(action: onDismiss) {
                        Text("common.done".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                if mediaItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 36))
                            .foregroundColor(.blue)
                        Text("admin.all.profiles.media.empty".localized)
                            .font(.subheadline)
                            .foregroundColor(secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    onSelect(index)
                                } label: {
                                    mediaThumbnail(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(gridPadding)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 28)
        }
    }

    private func mediaThumbnail(_ item: AdminConversationMediaItem) -> some View {
        // Force equal square cells: width comes from the 3-column grid, height matches width.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let side = geo.size.width
                    ZStack {
                        Color(.systemGray5)
                        if item.isImage {
                            CachedAsyncImage(url: URL(string: item.message.content)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: side, height: side)
                            .clipped()
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                                Text("admin.all.profiles.media.voice".localized)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if let duration = item.message.voiceDuration, duration > 0 {
                                    Text(formattedDuration(duration))
                                        .font(.caption2)
                                        .foregroundColor(secondaryText)
                                }
                            }
                            .frame(width: side, height: side)
                            .padding(6)
                        }
                    }
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AdminConversationMediaViewerOverlay: View {
    let mediaItems: [AdminConversationMediaItem]
    @Binding var selectedIndex: Int
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Text("common.done".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if !mediaItems.isEmpty {
                        Text("\(selectedIndex + 1)/\(mediaItems.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                TabView(selection: $selectedIndex) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                        mediaPage(item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
    }

    @ViewBuilder
    private func mediaPage(_ item: AdminConversationMediaItem) -> some View {
        if item.isImage {
            CachedAsyncImage(url: URL(string: item.message.content)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
            .padding(.horizontal, 24)
        } else {
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white.opacity(0.9))
                Text("admin.all.profiles.media.voice".localized)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                VoiceMessagePlayerView(
                    audioURL: URL(string: item.message.content),
                    displayDuration: item.message.voiceDuration,
                    accentColor: .blue,
                    textColor: .white,
                    baseColor: Color.white.opacity(0.12),
                    waveColor: Color.white.opacity(0.35),
                    timestampText: nil,
                    isOutgoing: true
                )
                .frame(maxWidth: 280)
            }
            .padding(.horizontal, 24)
        }
    }
}



private enum AdminProfileRestrictAction: Equatable {
    case warn
    case freeze
    case ban
}

private enum AdminProfileRestrictFollowUp: Equatable {
    case warning
    case freeze
    case ban
}

private struct AdminProfileRestrictOverlay: View {
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: (AdminProfileRestrictAction) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAction: AdminProfileRestrictAction?

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? .white : .black }
    private var primaryText: Color { isLight ? .black : .white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }
    private var canSubmit: Bool { selectedAction != nil && !isSubmitting }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 12) {
                Text("admin.all.profiles.restrict.title".localized)
                    .font(.headline)
                    .foregroundColor(primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                optionRow(
                    title: "admin.reports.action.warn".localized,
                    subtitle: "admin.all.profiles.restrict.warn.subtitle".localized,
                    action: .warn
                )
                optionRow(
                    title: "admin.reports.action.freeze".localized,
                    subtitle: "admin.all.profiles.restrict.freeze.subtitle".localized,
                    action: .freeze
                )
                optionRow(
                    title: "admin.reports.action.ban".localized,
                    subtitle: "admin.all.profiles.restrict.ban.subtitle".localized,
                    action: .ban
                )

                if isSubmitting {
                    ProgressView()
                        .padding(.top, 4)
                }

                Button {
                    guard let selectedAction else { return }
                    onSubmit(selectedAction)
                } label: {
                    Text("common.submit".localized)
                        .font(.body.weight(.semibold))
                        .foregroundColor(canSubmit ? primaryText : secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.top, 8)

                Button(action: onCancel) {
                    Text("common.cancel".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private func optionRow(title: String, subtitle: String, action: AdminProfileRestrictAction) -> some View {
        let isSelected = selectedAction == action
        return Button {
            selectedAction = action
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .orange : secondaryText)
                    .padding(.top, 2)

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
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6).opacity(isLight ? 1 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}


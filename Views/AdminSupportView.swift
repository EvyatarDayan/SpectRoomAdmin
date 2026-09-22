import SwiftUI
import Photos

struct AdminSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppStateManager

    /// When `false`, this view is shown as a root tab (no Done button, tab-bar clearance).
    var showsDismissButton: Bool = true

    @State private var tickets: [SupportTicket] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var lastDocumentId: String?
    @State private var totalCount: Int?
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var filter: AdminSupportFilter = .open
    @State private var selectedTopic: AdminSupportTopicFilter?
    @State private var selectedTicket: SupportTicket?
    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var paginationArmedByBottomScroll = false

    private let tabBarClearance: CGFloat = 88
    private let pageSize = 25

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        !trimmedSearch.isEmpty
    }

    private var isTopicFilterActive: Bool {
        selectedTopic != nil
    }

    var body: some View {
        NavigationView {
            Group {
                if appState.isAdminUser {
                    supportContent
                } else {
                    unauthorizedState
                }
            }
            .background(SpectRoomBackground())
            .navigationTitle("admin.support.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("admin.support.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
                if appState.isAdminUser {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            Task { await loadInitial(forceRefresh: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading || isPerformingAction)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        AdminFiltersMenu(
                            options: Array(AdminSupportTopicFilter.allCases),
                            selection: $selectedTopic,
                            clearTitle: "admin.support.filter.all".localized,
                            clearSystemImage: "arrow.clockwise",
                            clearUsesFixedSystemImage: true,
                            onClear: {
                                Task { await loadInitial(forceRefresh: true) }
                            },
                            title: { $0.title },
                            systemImage: { $0.systemImage }
                        )
                    }
                }
                if showsDismissButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("common.done".localized) { dismiss() }
                    }
                }
            }
            .overlay {
                if let selectedTicket {
                    AdminSupportTicketDetailOverlay(
                        ticket: selectedTicket,
                        isPerformingAction: isPerformingAction,
                        onClose: { self.selectedTicket = nil },
                        onOpenProfileSearch: { email in
                            self.selectedTicket = nil
                            appState.openAllProfilesSearch(email)
                            if showsDismissButton {
                                dismiss()
                            }
                        },
                        onResolve: { message in
                            Task { await resolveTicket(selectedTicket, emailBody: message) }
                        },
                        onKeepPending: { message in
                            Task { await sendPendingTicketUpdate(selectedTicket, emailBody: message) }
                        }
                    )
                }
            }
            .alert("admin.reports.action.error.title".localized, isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("common.ok".localized, role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .task {
                guard appState.isAdminUser else {
                    isLoading = false
                    return
                }
                await loadInitial()
            }
            .onChange(of: filter) { _, _ in
                guard !isPerformingAction else { return }
                Task { await loadInitial() }
            }
            .onChange(of: selectedTopic) { _, newValue in
                // All (nil) is handled by onClear → force refresh.
                guard newValue != nil else { return }
                Task { await loadInitial() }
            }
            .onChange(of: searchText) { _, _ in
                searchTask?.cancel()
                searchTask = Task { await handleSearchChange() }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var supportContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $filter) {
                ForEach(AdminSupportFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 18)

            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if let totalCount {
                Text(ticketsCountText(for: totalCount))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tickets.isEmpty {
                    emptyState
                } else {
                    ticketsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ticketsCountText(for count: Int) -> String {
        if count == 1 {
            return "admin.support.count.one".localized
        }
        return String(format: "admin.support.count".localized, count)
    }

    private var ticketsList: some View {
        List {
            ForEach(Array(tickets.enumerated()), id: \.element.id) { index, ticket in
                Button {
                    selectedTicket = ticket
                } label: {
                    AdminSupportTicketRow(ticket: ticket)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    let nearEnd = index >= tickets.count - 3
                    guard nearEnd, paginationArmedByBottomScroll else { return }
                    guard hasMore, !isLoadingMore else { return }
                    Task { await loadMore() }
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
        .padding(.bottom, showsDismissButton ? 0 : tabBarClearance)
        .listPaginationScrollArming(
            isArmed: $paginationArmedByBottomScroll,
            direction: .towardBottom
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SpectRoomTheme.secondaryText)
            TextField("admin.support.search.placeholder".localized, text: $searchText)
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: (isSearchActive || isTopicFilterActive) ? "magnifyingglass" : "envelope.open")
                .font(.system(size: 40))
                .foregroundColor(.teal)
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundColor(SpectRoomTheme.text)
            Text(emptyStateDescription)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, showsDismissButton ? 0 : tabBarClearance)
    }

    private var emptyStateTitle: String {
        if isSearchActive || isTopicFilterActive {
            return "admin.support.search.empty".localized
        }
        return filter == .open
            ? "admin.support.empty.open".localized
            : "admin.support.empty.resolved".localized
    }

    private var emptyStateDescription: String {
        if isSearchActive {
            return "admin.support.search.empty.description".localized
        }
        if isTopicFilterActive {
            return "admin.support.topic.empty.description".localized
        }
        return filter == .open
            ? "admin.support.empty.open.description".localized
            : "admin.support.empty.resolved.description".localized
    }

    @MainActor
    private func handleSearchChange() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        guard trimmedSearch == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        await loadInitial()
    }

    @MainActor
    private func fetchPage(
        startAfterDocumentId: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> FirebaseAuthService.SupportTicketsPage {
        let status: FirebaseAuthService.AdminSupportTicketsStatusFilter =
            filter == .open ? .open : .resolved
        return try await FirebaseAuthService.shared.fetchSupportTicketsPage(
            status: status,
            topicAliases: selectedTopic?.aliases,
            searchQuery: isSearchActive ? trimmedSearch : nil,
            limit: pageSize,
            startAfterDocumentId: startAfterDocumentId,
            forceRefresh: forceRefresh
        )
    }

    @MainActor
    private func loadInitial(forceRefresh: Bool = false) async {
        isLoading = true
        paginationArmedByBottomScroll = false
        defer { isLoading = false }

        do {
            let page = try await fetchPage(forceRefresh: forceRefresh)
            tickets = page.tickets
            lastDocumentId = page.lastDocumentId
            hasMore = page.hasMore
            totalCount = page.totalCount
        } catch {
            tickets = []
            lastDocumentId = nil
            hasMore = false
            totalCount = nil
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard hasMore, !isLoadingMore, let lastDocumentId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(startAfterDocumentId: lastDocumentId)
            let existingIds = Set(tickets.map(\.id))
            tickets.append(contentsOf: page.tickets.filter { !existingIds.contains($0.id) })
            self.lastDocumentId = page.lastDocumentId
            hasMore = page.hasMore
            totalCount = page.totalCount
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func updateStatus(for ticket: SupportTicket, status: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await FirebaseAuthService.shared.updateSupportTicketStatus(
                ticketId: ticket.id,
                status: status
            )
            await loadInitial(forceRefresh: true)
            if let updated = tickets.first(where: { $0.id == ticket.id }) {
                selectedTicket = updated
            } else {
                selectedTicket = nil
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func resolveTicket(_ ticket: SupportTicket, emailBody: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        let reply = emailBody.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await FirebaseAuthService.shared.resolveSupportTicket(
                ticketId: ticket.id,
                emailBody: reply,
                humanTicketNumber: ticket.hasHumanTicketNumber ? ticket.ticketNumber : ticket.displayTicketNumber,
                keepPending: false
            )
            filter = .resolved
            selectedTicket = nil
            await loadInitial(forceRefresh: true)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func sendPendingTicketUpdate(_ ticket: SupportTicket, emailBody: String) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        let reply = emailBody.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await FirebaseAuthService.shared.resolveSupportTicket(
                ticketId: ticket.id,
                emailBody: reply,
                humanTicketNumber: ticket.hasHumanTicketNumber ? ticket.ticketNumber : ticket.displayTicketNumber,
                keepPending: true
            )
            filter = .open
            selectedTicket = nil
            await loadInitial(forceRefresh: true)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private enum AdminSupportFilter: String, CaseIterable, Identifiable {
    case open
    case resolved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "admin.support.filter.open".localized
        case .resolved: return "admin.support.filter.resolved".localized
        }
    }
}

/// Matches tickets whose topic was saved as a localized label (any app language).
private enum AdminSupportTopicFilter: CaseIterable, Identifiable {
    case safety
    case bug
    case feedback
    case accountBan
    case accountFreeze

    var id: Self { self }

    var title: String {
        switch self {
        case .safety: return "support.topic.safety".localized
        case .bug: return "support.topic.bug".localized
        case .feedback: return "support.topic.feedback".localized
        case .accountBan: return "support.topic.account.ban".localized
        case .accountFreeze: return "support.topic.account.freeze".localized
        }
    }

    var systemImage: String {
        switch self {
        case .safety: return "shield.fill"
        case .bug: return "ant.fill"
        case .feedback: return "bubble.left.fill"
        case .accountBan: return "person.crop.circle.badge.xmark"
        case .accountFreeze: return "snowflake"
        }
    }

    var aliases: Set<String> {
        switch self {
        case .safety:
            return ["safety", "säkerhet", "sicherheit", "seguridad", "sécurité"]
        case .bug:
            return ["bug", "bugg", "fehler", "error"]
        case .feedback:
            return ["feedback", "comentarios", "avis"]
        case .accountBan:
            return [
                "account ban",
                "bannissement de compte",
                "ban de cuenta",
                "account-ban",
                "kontoavstängning"
            ]
        case .accountFreeze:
            return [
                "account freeze",
                "account-freeze",
                "gel de compte",
                "congelación de cuenta",
                "kontosperre",
                "kontofrysning",
                "[account freeze] account freeze"
            ]
        }
    }

    func matches(_ topic: String) -> Bool {
        let normalized = topic
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return aliases.contains(normalized)
    }
}

private struct AdminSupportTicketRow: View {
    let ticket: SupportTicket
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ticket.topic)
                        .font(.headline)
                        .foregroundColor(SpectRoomTheme.text)
                        .lineLimit(1)
                    if ticket.hasImageAttachment {
                        Image(systemName: "photo")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Text(ticket.statusLabelKey.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ticket.isOpen ? .orange : .green)
                }
                Text(ticket.displaySenderLabel)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .lineLimit(1)
                Text(ticket.message)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .lineLimit(1)
                if let createdAt = ticket.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
        )
    }
}

private struct AdminSupportTicketDetailOverlay: View {
    let ticket: SupportTicket
    let isPerformingAction: Bool
    let onClose: () -> Void
    let onOpenProfileSearch: (String) -> Void
    let onResolve: (String) -> Void
    let onKeepPending: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingResolveEmailCompose = false
    @State private var showingAttachmentViewer = false

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? .white : .black }
    private var primaryText: Color { isLight ? .black : .white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("admin.support.detail.title".localized)
                            .font(.headline)
                            .foregroundColor(primaryText)

                        detailRow(title: "admin.support.detail.ticket".localized, value: ticket.displayTicketNumber)
                        detailRow(title: "admin.support.detail.topic".localized, value: ticket.topic)
                        detailRow(title: "admin.support.detail.from".localized, value: ticket.displayFromLabel)
                        if !ticket.userEmail.isEmpty {
                            emailLinkRow(title: "admin.support.detail.email".localized, email: ticket.userEmail)
                        }
                        if !ticket.userId.isEmpty {
                            detailRow(title: "admin.support.detail.user.id".localized, value: ticket.userId)
                        }
                        if let createdAt = ticket.createdAt {
                            detailRow(
                                title: "admin.support.detail.created".localized,
                                value: createdAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                        if let resolvedAt = ticket.resolvedAt, !ticket.isOpen {
                            detailRow(
                                title: "admin.support.detail.resolved".localized,
                                value: resolvedAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        }

                        messageBlock(
                            title: "admin.support.detail.message".localized,
                            text: ticket.message,
                            background: Color(.systemGray6).opacity(isLight ? 1 : 0.35)
                        )

                        if ticket.hasImageAttachment, let imageURL = ticket.imageURL {
                            attachmentPreview(urlString: imageURL)
                        }

                        if let adminReply = ticket.adminReply?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !adminReply.isEmpty,
                           !ticket.isOpen {
                            messageBlock(
                                title: "admin.support.detail.reply".localized,
                                text: adminReply,
                                background: Color.green.opacity(isLight ? 0.08 : 0.2)
                            )
                        }

                        if isPerformingAction {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                }

                HStack(spacing: 12) {
                    Button(action: onClose) {
                        Text("common.close".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPerformingAction)

                    Button {
                        showingResolveEmailCompose = true
                    } label: {
                        Text("admin.support.action.take".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPerformingAction)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 36)
            .padding(.bottom, 100)

            if showingResolveEmailCompose {
                AdminSupportResolveEmailOverlay(
                    email: ticket.userEmail,
                    onCancel: {
                        showingResolveEmailCompose = false
                    },
                    onResolve: { message in
                        showingResolveEmailCompose = false
                        onResolve(message)
                    },
                    onKeepPending: { message in
                        showingResolveEmailCompose = false
                        onKeepPending(message)
                    }
                )
                .zIndex(1)
            }

            if showingAttachmentViewer, let imageURL = ticket.imageURL {
                AdminSupportAttachmentViewerOverlay(
                    imageURL: imageURL,
                    onDismiss: { showingAttachmentViewer = false }
                )
                .zIndex(2)
            }
        }
        .onChange(of: ticket.id) { _, _ in
            showingResolveEmailCompose = false
            showingAttachmentViewer = false
        }
    }

    private func attachmentPreview(urlString: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("admin.support.detail.attachment".localized)
                .font(.caption.weight(.semibold))
                .foregroundColor(secondaryText)

            Button {
                showingAttachmentViewer = true
            } label: {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: URL(string: urlString)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                            .overlay { ProgressView().scaleEffect(0.7) }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("admin.support.detail.attachment.photo".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(primaryText)
                        Text("admin.support.detail.attachment.tap".localized)
                            .font(.caption)
                            .foregroundColor(secondaryText)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(secondaryText)
                }
                .padding(10)
                .background(Color(.systemGray6).opacity(isLight ? 1 : 0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func messageBlock(title: String, text: String, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(secondaryText)
            Text(text)
                .font(.body)
                .foregroundColor(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(12)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(secondaryText)
            Text(value)
                .font(.subheadline)
                .foregroundColor(primaryText)
                .textSelection(.enabled)
        }
    }

    private func emailLinkRow(title: String, email: String) -> some View {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(secondaryText)
            Button {
                onOpenProfileSearch(trimmed)
            } label: {
                Text(trimmed)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                    .underline()
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum AdminSupportActionChoice: String, CaseIterable, Identifiable {
    case resolved
    case keepPending

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .resolved: return "admin.support.status.resolved"
        case .keepPending: return "admin.support.action.keep.pending"
        }
    }

    var defaultEmailBody: String {
        switch self {
        case .resolved: return "admin.support.resolve.email.default".localized
        case .keepPending: return "admin.support.pending.email.default".localized
        }
    }
}

private struct AdminSupportResolveEmailOverlay: View {
    let email: String
    let onCancel: () -> Void
    let onResolve: (String) -> Void
    let onKeepPending: (String) -> Void

    @State private var selectedAction: AdminSupportActionChoice = .resolved
    @State private var message: String = AdminSupportActionChoice.resolved.defaultEmailBody

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canConfirm: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && trimmedEmail.contains("@")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text(
                    String(
                        format: "admin.support.resolve.email.title".localized,
                        trimmedEmail.isEmpty ? "—" : trimmedEmail
                    )
                )
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(SpectRoomTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AdminSupportActionChoice.allCases) { choice in
                        Button {
                            applyActionChoice(choice)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedAction == choice ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(selectedAction == choice ? .accentColor : SpectRoomTheme.secondaryText)
                                Text(choice.titleKey.localized)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(SpectRoomTheme.text)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                TextEditor(text: $message)
                    .frame(minHeight: 140, maxHeight: 200)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("common.close".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SpectRoomTheme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        switch selectedAction {
                        case .resolved:
                            onResolve(message)
                        case .keepPending:
                            onKeepPending(message)
                        }
                    } label: {
                        Text("common.send".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(canConfirm ? .white : SpectRoomTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canConfirm ? Color.accentColor : Color(.systemGray4))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConfirm)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 28)
        }
    }

    /// Swap in the matching default when the admin switches radios, unless they already edited.
    private func applyActionChoice(_ choice: AdminSupportActionChoice) {
        let previousDefault = selectedAction.defaultEmailBody
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedAction = choice
        if trimmed.isEmpty || trimmed == previousDefault.trimmingCharacters(in: .whitespacesAndNewlines) {
            message = choice.defaultEmailBody
        }
    }
}

private struct AdminSupportAttachmentViewerOverlay: View {
    let imageURL: String
    let onDismiss: () -> Void

    @State private var isSaving = false
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Text("common.done".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("common.save".localized) {
                        saveImage()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                CachedAsyncImage(url: URL(string: imageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 20)
            }

            if isSaving {
                ProgressView()
                    .tint(.white)
                    .padding(16)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
        }
        .alert("messages.image.saved".localized, isPresented: $showingSaveAlert) {
            Button("common.ok".localized) { }
        } message: {
            Text(saveSuccess ? "messages.image.saved.success".localized : "messages.image.saved.failed".localized)
        }
    }

    private func saveImage() {
        guard !isSaving, let url = URL(string: imageURL) else {
            saveSuccess = false
            showingSaveAlert = true
            return
        }

        isSaving = true
        Task {
            do {
                var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                if status == .notDetermined {
                    status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                }
                guard status == .authorized || status == .limited else {
                    await MainActor.run {
                        isSaving = false
                        saveSuccess = false
                        showingSaveAlert = true
                    }
                    return
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    throw NSError(domain: "AdminSupportAttachmentSave", code: 1)
                }

                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }

                await MainActor.run {
                    isSaving = false
                    saveSuccess = true
                    showingSaveAlert = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveSuccess = false
                    showingSaveAlert = true
                }
            }
        }
    }
}

#Preview {
    AdminSupportView()
        .environmentObject(AppStateManager.shared)
}

import SwiftUI

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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        AdminFiltersMenu(
                            options: Array(AdminSupportTopicFilter.allCases),
                            selection: $selectedTopic,
                            clearTitle: "admin.support.filter.all".localized,
                            clearSystemImage: "envelope",
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
                        onMarkResolved: {
                            Task { await updateStatus(for: selectedTicket, status: "resolved") }
                        },
                        onReopen: {
                            Task { await updateStatus(for: selectedTicket, status: "new") }
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
                Task { await loadInitial() }
            }
            .onChange(of: selectedTopic) { _, _ in
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
    private func fetchPage(startAfterDocumentId: String? = nil) async throws -> FirebaseAuthService.SupportTicketsPage {
        let status: FirebaseAuthService.AdminSupportTicketsStatusFilter =
            filter == .open ? .open : .resolved
        return try await FirebaseAuthService.shared.fetchSupportTicketsPage(
            status: status,
            topicAliases: selectedTopic?.aliases,
            searchQuery: isSearchActive ? trimmedSearch : nil,
            limit: pageSize,
            startAfterDocumentId: startAfterDocumentId
        )
    }

    @MainActor
    private func loadInitial() async {
        isLoading = true
        paginationArmedByBottomScroll = false
        defer { isLoading = false }

        do {
            let page = try await fetchPage()
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
            await loadInitial()
            if let updated = tickets.first(where: { $0.id == ticket.id }) {
                selectedTicket = updated
            } else {
                selectedTicket = nil
            }
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

    var id: Self { self }

    var title: String {
        switch self {
        case .safety: return "support.topic.safety".localized
        case .bug: return "support.topic.bug".localized
        case .feedback: return "support.topic.feedback".localized
        }
    }

    var systemImage: String {
        switch self {
        case .safety: return "shield.fill"
        case .bug: return "ant.fill"
        case .feedback: return "bubble.left.fill"
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.teal)
                .frame(width: 40, height: 40)
                .background(Color.teal.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ticket.topic)
                        .font(.headline)
                        .foregroundColor(SpectRoomTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(ticket.statusLabelKey.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ticket.isOpen ? .orange : .green)
                }
                Text(ticket.userName)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .lineLimit(1)
                Text(ticket.message)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .lineLimit(2)
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
    let onMarkResolved: () -> Void
    let onReopen: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? .white : .black }
    private var primaryText: Color { isLight ? .black : .white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("admin.support.detail.title".localized)
                        .font(.headline)
                        .foregroundColor(primaryText)
                    Spacer()
                    Text(ticket.statusLabelKey.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ticket.isOpen ? .orange : .green)
                }

                detailRow(title: "admin.support.detail.ticket".localized, value: ticket.displayTicketNumber)
                detailRow(title: "admin.support.detail.topic".localized, value: ticket.topic)
                detailRow(title: "admin.support.detail.from".localized, value: ticket.userName)
                if !ticket.userEmail.isEmpty {
                    detailRow(title: "admin.support.detail.email".localized, value: ticket.userEmail)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("admin.support.detail.message".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(secondaryText)
                    ScrollView {
                        Text(ticket.message)
                            .font(.body)
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(12)
                    .background(Color(.systemGray6).opacity(isLight ? 1 : 0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if isPerformingAction {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if ticket.isOpen {
                    Button(action: onMarkResolved) {
                        Text("admin.support.action.resolve".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onReopen) {
                        Text("admin.support.action.reopen".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onClose) {
                    Text("common.close".localized)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 36)
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
}

#Preview {
    AdminSupportView()
        .environmentObject(AppStateManager.shared)
}

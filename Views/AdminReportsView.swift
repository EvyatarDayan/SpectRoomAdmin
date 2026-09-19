import SwiftUI

struct AdminReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppStateManager
    @State private var reports: [UserReport] = []
    @State private var isLoading = true
    @State private var selectedReport: UserReport?
    @State private var filter: AdminReportFilter = .pending
    @State private var actionError: String?
    @State private var isPerformingAction = false
    @State private var pendingModerationStep: AdminReportModerationStep?

    private var filteredReports: [UserReport] {
        switch filter {
        case .pending:
            return reports.filter { $0.status.lowercased() == "pending" }
        case .actioned:
            return reports.filter {
                let status = $0.status.lowercased()
                return status == "actioned" || status == "dismissed" || status == "reviewed"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $filter) {
                    ForEach(AdminReportFilter.allCases) { item in
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
                    } else if filteredReports.isEmpty {
                        emptyState
                    } else {
                        List(filteredReports) { report in
                            Button {
                                selectedReport = report
                                appState.markAdminReportAsSeen(report.id)
                            } label: {
                                AdminReportRow(
                                    report: report,
                                    isNew: appState.isAdminReportUnseen(report.id)
                                )
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
            .navigationTitle("admin.reports.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        handleDoneTapped()
                    }
                }
            }
            .overlay {
                if let pendingModerationStep {
                    switch pendingModerationStep {
                    case .warning(let report):
                        AdminWarningComposeOverlay(
                            onCancel: { self.pendingModerationStep = nil },
                            onSubmit: { message in
                                self.pendingModerationStep = nil
                                Task { await performWarning(report, message: message) }
                            }
                        )
                    case .freeze(let report):
                        AdminFreezeDurationOverlay(
                            reportedName: report.reportedName,
                            onCancel: { self.pendingModerationStep = nil },
                            onConfirm: { duration in
                                self.pendingModerationStep = nil
                                Task { await performFreeze(report, duration: duration) }
                            }
                        )
                    case .ban(let report):
                        AdminBanConfirmOverlay(
                            reportedName: report.reportedName,
                            onCancel: { self.pendingModerationStep = nil },
                            onConfirm: {
                                self.pendingModerationStep = nil
                                Task { await performBan(report) }
                            }
                        )
                    }
                } else if let selectedReport {
                    AdminReportDetailOverlay(
                        report: selectedReport,
                        isPerformingAction: isPerformingAction,
                        onClose: { self.selectedReport = nil },
                        onOpenProfileSearch: { email in
                            self.selectedReport = nil
                            appState.openAllProfilesSearch(email)
                            dismiss()
                        },
                        onSubmit: { action in
                            handleSelectedAction(action, for: selectedReport)
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
            .task { await loadReports() }
        }
    }

    private func handleDoneTapped() {
        if pendingModerationStep != nil {
            pendingModerationStep = nil
            return
        }
        if selectedReport != nil {
            selectedReport = nil
            return
        }
        dismiss()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🛡️")
                .font(.system(size: 48))
            Text("admin.reports.empty".localized)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SpectRoomTheme.text)
                .multilineTextAlignment(.center)
            Text("admin.reports.empty.description".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleSelectedAction(_ action: AdminReportSelectedAction, for report: UserReport) {
        switch action {
        case .dismiss:
            Task { await performDismiss(report) }
        case .warn:
            pendingModerationStep = .warning(report)
        case .freeze:
            pendingModerationStep = .freeze(report)
        case .ban:
            pendingModerationStep = .ban(report)
        }
    }

    private func loadReports() async {
        isLoading = true
        do {
            reports = try await FirebaseAuthService.shared.fetchAllReportsForAdmin()
        } catch {
            actionError = error.localizedDescription
            reports = []
        }
        isLoading = false
    }

    private func performDismiss(_ report: UserReport) async {
        await runAction {
            try await FirebaseAuthService.shared.dismissReport(reportId: report.id)
            await refreshAfterAction()
        }
    }

    private func performWarning(_ report: UserReport, message: String) async {
        await runAction {
            try await FirebaseAuthService.shared.issueWarningForReport(
                reportId: report.id,
                reportedUserId: report.reportedUserId,
                message: message
            )
            await refreshAfterAction()
        }
    }

    private func performFreeze(_ report: UserReport, duration: ModerationFreezeDuration) async {
        await runAction {
            try await FirebaseAuthService.shared.freezeUserForReport(
                reportId: report.id,
                reportedUserId: report.reportedUserId,
                duration: duration
            )
            await refreshAfterAction()
        }
    }

    private func performBan(_ report: UserReport) async {
        await runAction {
            try await FirebaseAuthService.shared.banUserForReport(
                reportId: report.id,
                reportedUserId: report.reportedUserId
            )
            await refreshAfterAction()
        }
    }

    private func runAction(_ work: () async throws -> Void) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        do {
            try await work()
        } catch {
            actionError = error.localizedDescription
        }
        isPerformingAction = false
    }

    private func refreshAfterAction() async {
        do {
            reports = try await FirebaseAuthService.shared.fetchAllReportsForAdmin()
            selectedReport = nil
            pendingModerationStep = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private enum AdminReportModerationStep {
    case warning(UserReport)
    case freeze(UserReport)
    case ban(UserReport)
}

private enum AdminReportSelectedAction: Equatable {
    case dismiss
    case warn
    case freeze
    case ban
}

private enum AdminReportFilter: String, CaseIterable, Identifiable {
    case pending, actioned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "admin.reports.filter.pending".localized
        case .actioned: return "admin.reports.filter.actioned".localized
        }
    }
}

private struct AdminReportRow: View {
    let report: UserReport
    let isNew: Bool

    private var statusColor: Color {
        switch report.status.lowercased() {
        case "pending": return .orange
        case "actioned": return .red
        case "dismissed": return SpectRoomTheme.secondaryText
        case "reviewed": return .blue
        default: return SpectRoomTheme.secondaryText
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            profilePhoto
                .overlay(alignment: .topTrailing) {
                    if isNew {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(SpectRoomTheme.card, lineWidth: 2)
                            )
                            .offset(x: 2, y: -2)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(report.reportedName)
                        .font(.headline)
                        .foregroundColor(SpectRoomTheme.text)
                    if isNew {
                        Text("admin.reports.new".localized)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                Text(report.category)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                HStack(spacing: 0) {
                    Text(localizedStatus(report.status))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(statusColor)
                    if let createdAt = report.createdAt {
                        Text(" · \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
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

    private func localizedStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "pending": return "settings.reported.profiles.status.pending".localized
        case "reviewed": return "settings.reported.profiles.status.reviewed".localized
        case "dismissed": return "settings.reported.profiles.status.dismissed".localized
        case "actioned": return "settings.reported.profiles.status.actioned".localized
        default: return status.capitalized
        }
    }

    private var profilePhoto: some View {
        Group {
            if let photoURL = report.primaryPhotoURL, let url = URL(string: photoURL) {
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
            .fill(Color.orange.opacity(0.2))
            .overlay(
                Text(String(report.reportedName.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.orange)
            )
    }
}

private struct AdminReportDetailOverlay: View {
    let report: UserReport
    let isPerformingAction: Bool
    let onClose: () -> Void
    let onOpenProfileSearch: (String) -> Void
    let onSubmit: (AdminReportSelectedAction) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAction: AdminReportSelectedAction?

    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? Color.white : Color.black }
    private var primaryText: Color { isLight ? Color.black : Color.white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }
    private var isPending: Bool { report.status.lowercased() == "pending" }
    private let optionColor = Color.primary

    private var canSubmit: Bool { selectedAction != nil && !isPerformingAction }

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            avatarPhoto(urlString: report.reporterPhotoURL, name: report.displayReporterName)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(secondaryText)
                            avatarPhoto(urlString: report.primaryPhotoURL, name: report.reportedName)
                        }

                        Text(headlineText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .background(secondaryText.opacity(0.35))

                    emailLinkRow(
                        title: "admin.reports.detail.reporting.user".localized,
                        email: report.reporterEmail
                    )
                    emailLinkRow(
                        title: "admin.reports.detail.reported.user".localized,
                        email: report.reportedEmail
                    )

                    detailRow(title: "settings.reported.profiles.detail.category".localized, value: report.category)

                    if let details = report.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
                        detailRow(title: "settings.reported.profiles.detail.details".localized, value: details)
                    }

                    VStack(spacing: 10) {
                        if isPending {
                            selectableActionButton(
                                title: "admin.reports.action.dismiss".localized,
                                subtitle: "admin.reports.action.dismiss.subtitle".localized,
                                action: .dismiss
                            )
                        }
                        selectableActionButton(
                            title: "admin.reports.action.warn".localized,
                            subtitle: "admin.reports.action.warn.subtitle".localized,
                            action: .warn
                        )
                        selectableActionButton(
                            title: "admin.reports.action.freeze".localized,
                            subtitle: "admin.reports.action.freeze.subtitle".localized,
                            action: .freeze
                        )
                        selectableActionButton(
                            title: "admin.reports.action.ban".localized,
                            subtitle: "admin.reports.action.ban.subtitle".localized,
                            action: .ban
                        )
                    }
                    .padding(.top, 4)
                    .disabled(isPerformingAction)
                    .opacity(isPerformingAction ? 0.6 : 1)

                    if isPerformingAction {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        guard let selectedAction else { return }
                        onSubmit(selectedAction)
                    } label: {
                        Text("common.submit".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(canSubmit ? .white : secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? Color.orange : Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
                .padding(24)
            }
            .frame(maxWidth: 360)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.82)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    private var headlineText: String {
        String(
            format: "admin.reports.detail.headline.reporting".localized,
            report.displayReporterName,
            report.reportedName
        )
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(secondaryText)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emailLinkRow(title: String, email: String?) -> some View {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasEmail = !trimmed.isEmpty

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(secondaryText)

            if hasEmail {
                Button {
                    onOpenProfileSearch(trimmed)
                } label: {
                    Text(trimmed)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                        .underline()
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            } else {
                Text("admin.reports.detail.email.unavailable".localized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectableActionButton(
        title: String,
        subtitle: String,
        action: AdminReportSelectedAction
    ) -> some View {
        let isSelected = selectedAction == action
        return Button {
            selectedAction = action
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .orange : secondaryText)

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(optionColor.opacity(isSelected ? 0.10 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(optionColor.opacity(isSelected ? 0.45 : 0.20), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func avatarPhoto(urlString: String?, name: String) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsPlaceholder(for: name)
                }
            } else {
                initialsPlaceholder(for: name)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private func initialsPlaceholder(for name: String) -> some View {
        Circle()
            .fill(Color.orange.opacity(0.2))
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.orange)
            )
    }
}

struct AdminWarningComposeOverlay: View {
    let onCancel: () -> Void
    let onSubmit: (String) -> Void

    @State private var message: String = "admin.warning.default.message".localized

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text("admin.reports.warning.compose.title".localized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                Text("admin.reports.warning.compose.subtitle".localized)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .padding(.horizontal, 20)

                TextEditor(text: $message)
                    .frame(minHeight: 140, maxHeight: 200)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)

                Button {
                    onSubmit(message)
                } label: {
                    Text("common.submit".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(canSubmit ? .white : SpectRoomTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? Color.orange : Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.horizontal, 20)

                Button(action: onCancel) {
                    Text("common.cancel".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 28)
        }
    }
}

struct AdminBanConfirmOverlay: View {
    let reportedName: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text("admin.reports.ban.confirm.title".localized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                Text(String(format: "admin.reports.ban.confirm.message".localized, reportedName))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("common.cancel".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SpectRoomTheme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: onConfirm) {
                        Text("admin.reports.action.ban".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
    }
}

struct AdminFreezeDurationOverlay: View {
    let reportedName: String
    let onCancel: () -> Void
    let onConfirm: (ModerationFreezeDuration) -> Void

    @State private var selectedDuration: ModerationFreezeDuration?

    private var canSubmit: Bool { selectedDuration != nil }

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text("admin.reports.freeze.title".localized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                Text(String(format: "admin.reports.freeze.message".localized, reportedName))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    ForEach(ModerationFreezeDuration.allCases) { duration in
                        let isSelected = selectedDuration == duration
                        Button {
                            selectedDuration = duration
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? .orange : SpectRoomTheme.secondaryText)
                                Text(duration.labelKey.localized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(SpectRoomTheme.text)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 14)
                            .background(Color.primary.opacity(isSelected ? 0.10 : 0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(isSelected ? 0.45 : 0.20), lineWidth: isSelected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    guard let selectedDuration else { return }
                    onConfirm(selectedDuration)
                } label: {
                    Text("common.submit".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(canSubmit ? .white : SpectRoomTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? Color.orange : Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.horizontal, 20)

                Button(action: onCancel) {
                    Text("common.cancel".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
    }
}

struct SystemWarningOverlay: View {
    let title: String
    let message: String
    var acceptLabel: String = "admin.warning.popup.accept".localized
    var requiresCheckbox: Bool = true
    var secondaryLinkTitle: String? = nil
    var onSecondaryLink: (() -> Void)? = nil
    let onDismiss: () -> Void

    @State private var didAccept = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                if requiresCheckbox {
                    Button {
                        didAccept.toggle()
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: didAccept ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(didAccept ? .orange : SpectRoomTheme.secondaryText)
                                .frame(width: 22, height: 22)

                            Text(acceptLabel)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text("common.ok".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(didAccept ? .white : SpectRoomTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(didAccept ? Color.orange : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!didAccept)
                    .padding(.horizontal, 20)
                    .padding(.bottom, secondaryLinkTitle == nil ? 20 : 4)
                } else {
                    Button(action: onDismiss) {
                        Text(acceptLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, secondaryLinkTitle == nil ? 20 : 4)
                }

                if let secondaryLinkTitle, let onSecondaryLink {
                    Button(action: onSecondaryLink) {
                        Text(secondaryLinkTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.blue)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
        .allowsHitTesting(true)
    }
}

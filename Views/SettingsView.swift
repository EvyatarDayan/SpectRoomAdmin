//
//  SettingsView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import UserNotifications
import UIKit
import Foundation

struct SettingsView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var showingPermissionAlert = false
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("selectedLanguage") private var selectedLanguageCode: String = "en"
    @State private var showingLanguageModal = false
    @State private var showingBlockedUsers = false
    @State private var showingReportedProfiles = false
    @State private var showingPrivacySafety = false
    @State private var reportedProfilesCount = 0
    @State private var showingHelpSupport = false
    @State private var showingAbout = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var deleteConfirmationStep: DeleteAccountConfirmationStep = .sure
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var isExportingMessages = false
    @State private var showingExportShareSheet = false
    @State private var exportFileURL: URL?
    @State private var showingExportEmptyAlert = false
    @State private var showingExportErrorAlert = false
    @State private var showingSignOutConfirmation = false
    @State private var showingAdminReports = false
    @State private var showingAdminAllProfiles = false
    @State private var showingAdminFrozenProfiles = false
    @State private var showingAdminBannedProfiles = false
    
    var body: some View {
        NavigationView {
            List {
                if appState.isAdminUser {
                    Section("admin.section.title".localized) {
                        Button(action: {
                            showingAdminAllProfiles = true
                        }) {
                            HStack {
                                Image(systemName: "person.3.fill")
                                    .foregroundColor(.purple)
                                    .font(.body)
                                    .frame(width: 22, height: 22, alignment: .center)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("admin.all.profiles.button.title".localized)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .foregroundColor(SpectRoomTheme.text)
                                    Text("admin.all.profiles.button.subtitle".localized)
                                        .font(.caption)
                                        .foregroundColor(SpectRoomTheme.secondaryText)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .font(.caption)
                            }
                        }

                        Button(action: {
                            showingAdminReports = true
                        }) {
                            HStack {
                                Image(systemName: "shield.fill")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("admin.reports.button.title".localized)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .foregroundColor(SpectRoomTheme.text)
                                    Text("admin.reports.button.subtitle".localized)
                                        .font(.caption)
                                        .foregroundColor(SpectRoomTheme.secondaryText)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .font(.caption)
                            }
                        }

                        Button(action: {
                            showingAdminFrozenProfiles = true
                        }) {
                            HStack {
                                Image(systemName: "snowflake")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("admin.frozen.button.title".localized)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .foregroundColor(SpectRoomTheme.text)
                                    Text("admin.frozen.button.subtitle".localized)
                                        .font(.caption)
                                        .foregroundColor(SpectRoomTheme.secondaryText)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .font(.caption)
                            }
                        }

                        Button(action: {
                            showingAdminBannedProfiles = true
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                    .foregroundColor(.red)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("admin.banned.button.title".localized)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .foregroundColor(SpectRoomTheme.text)
                                    Text("admin.banned.button.subtitle".localized)
                                        .font(.caption)
                                        .foregroundColor(SpectRoomTheme.secondaryText)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .font(.caption)
                            }
                        }
                    }
                }

                // Preferences
                Section("settings.section.preferences".localized) {
                    HStack {
                        Image(systemName: "bell.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.notifications".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.notifications.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Toggle("", isOn: $notificationsEnabled)
                            .compactToggleStyle()
                            .onChange(of: notificationsEnabled) { enabled in
                                if enabled {
                                    Task {
                                        let granted = await NotificationService.shared.requestNotificationPermission()
                                        if granted {
                                            await FirebaseAuthService.shared.refreshFCMToken()
                                        } else {
                                            await MainActor.run {
                                                notificationsEnabled = false
                                                showingPermissionAlert = true
                                            }
                                        }
                                    }
                                } else {
                                    UserDefaults.standard.set(false, forKey: "notificationsEnabled")
                                }
                            }
                    }
                    
                    HStack {
                        Image(systemName: "moon.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.dark.mode".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.dark.mode.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Toggle("", isOn: $isDarkMode)
                            .compactToggleStyle()
                    }
                    
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.language".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.language.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text(currentLanguageFlag)
                                .font(.title3)
                            Text(currentLanguageName)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingLanguageModal = true
                    }
                }
                
                // Privacy & Safety
                Section("settings.section.privacy.safety".localized) {
                    HStack {
                        Image(systemName: "lock.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.privacy.settings".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.privacy.safety.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingPrivacySafety = true
                    }
                    
                    Button(action: {
                        showingBlockedUsers = true
                    }) {
                        HStack {
                            Image(systemName: "hand.raised.slash.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    String(
                                        format: "settings.blocked.users.button.title.count".localized,
                                        appState.blockedUsers.count
                                    )
                                )
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.blocked.users.button.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }

                    Button(action: {
                        showingReportedProfiles = true
                    }) {
                        HStack {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    String(
                                        format: "settings.reported.profiles.button.title.count".localized,
                                        reportedProfilesCount
                                    )
                                )
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.reported.profiles.button.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }
                }
                
                // Account & Data
                Section("settings.section.account.data".localized) {
                    Button(action: exportMessages) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.export.messages".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.export.messages.description".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            if isExportingMessages {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .font(.caption)
                            }
                        }
                    }
                    .disabled(isExportingMessages)
                    
                    Button(action: {
                        showingSignOutConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.sign.out".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.authentication.signout.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }
                    
                    Button(action: {
                        deleteConfirmationStep = .sure
                        deleteConfirmationText = ""
                        isDeletingAccount = false
                        deleteAccountErrorMessage = nil
                        showingDeleteAccountConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.delete.account.button".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(.red)
                                Text("settings.delete.account.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDeletingAccount)
                }
                
                // Support & About
                Section("settings.section.support.about".localized) {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.help.support".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.help.support.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingHelpSupport = true
                    }
                    
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.about.spectroom".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.about.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingAbout = true
                    }
                }
                
                // Development only — alone at the bottom
                #if DEBUG
                Section {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.reset.user.data".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.reset.user.data.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.resetAllAppState()
                    }
                }
                #endif
            }
            .padding(.bottom, 60)
            .scrollContentBackground(.hidden)
            .background(
                SpectRoomBackground()
            )
            .sheet(isPresented: $showingBlockedUsers) {
                BlockedUsersModal()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingReportedProfiles, onDismiss: {
                Task { await refreshReportedProfilesCount() }
            }) {
                ReportedProfilesModal()
            }
            .sheet(isPresented: $showingAdminReports) {
                AdminReportsView()
            }
            .sheet(isPresented: $showingAdminAllProfiles) {
                AdminAllProfilesView()
            }
            .sheet(isPresented: $showingAdminFrozenProfiles) {
                AdminFrozenProfilesView()
            }
            .sheet(isPresented: $showingAdminBannedProfiles) {
                AdminBannedProfilesView()
            }
            .sheet(isPresented: $showingHelpSupport) {
                HelpSupportView()
            }
            .navigationTitle("settings.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("settings.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
            .onAppear {
                checkNotificationPermission()
                Task { await refreshReportedProfilesCount() }
            }
            .alert("settings.notification.permission".localized, isPresented: $showingPermissionAlert) {
                Button("settings.settings.button".localized) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("settings.cancel".localized, role: .cancel) {
                    notificationsEnabled = false
                }
            } message: {
                Text("settings.notification.permission.message".localized)
            }
            .sheet(isPresented: $showingLanguageModal) {
                LanguageSelectionModal()
            }
            .sheet(isPresented: $showingPrivacySafety) {
                PrivacySafetyView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingExportShareSheet, onDismiss: {
                exportFileURL = nil
            }) {
                if let exportFileURL {
                    ActivityShareSheet(items: [exportFileURL])
                }
            }
            .alert("settings.export.messages".localized, isPresented: $showingExportEmptyAlert) {
                Button("common.ok".localized, role: .cancel) { }
            } message: {
                Text("settings.export.messages.empty".localized)
            }
            .alert("settings.export.messages".localized, isPresented: $showingExportErrorAlert) {
                Button("common.ok".localized, role: .cancel) { }
            } message: {
                Text("settings.export.messages.error".localized)
            }
            .overlay {
                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        onCancel: { showingSignOutConfirmation = false },
                        onConfirm: {
                            showingSignOutConfirmation = false
                            appState.signOut()
                        }
                    )
                } else if showingDeleteAccountConfirmation {
                    DeleteAccountConfirmationDialog(
                        step: $deleteConfirmationStep,
                        confirmationText: $deleteConfirmationText,
                        isDeleting: $isDeletingAccount,
                        errorMessage: $deleteAccountErrorMessage,
                        onCancel: {
                            showingDeleteAccountConfirmation = false
                            deleteConfirmationText = ""
                            deleteConfirmationStep = .sure
                            deleteAccountErrorMessage = nil
                        },
                        onConfirmDeletion: { password in
                            Task {
                                await MainActor.run { isDeletingAccount = true }
                                do {
                                    try await appState.deleteAccount(password: password)
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteConfirmationText = ""
                                        deleteAccountErrorMessage = nil
                                        deleteConfirmationStep = .success
                                    }
                                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                                    await MainActor.run {
                                        showingDeleteAccountConfirmation = false
                                        deleteConfirmationStep = .sure
                                        appState.signOut()
                                    }
                                } catch let error as SpectRoomAuthError {
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteAccountErrorMessage = error.errorDescription
                                            ?? "settings.delete.account.error".localized
                                    }
                                } catch {
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteAccountErrorMessage = "settings.delete.account.error".localized
                                    }
                                }
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var currentLanguageFlag: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.flag ?? "🇺🇸"
    }
    
    private var currentLanguageName: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.name ?? "English"
    }
    
    private func refreshReportedProfilesCount() async {
        do {
            let reports = try await FirebaseAuthService.shared.fetchMyReports()
            await MainActor.run {
                reportedProfilesCount = reports.count
            }
        } catch {
            print("⚠️ Failed to load reported profiles count: \(error.localizedDescription)")
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    notificationsEnabled = true
                case .denied, .notDetermined:
                    notificationsEnabled = false
                case .ephemeral:
                    notificationsEnabled = false
                @unknown default:
                    notificationsEnabled = false
                }
            }
        }
    }
    
    private func exportMessages() {
        guard !isExportingMessages else { return }
        isExportingMessages = true
        Task {
            do {
                let fileURL = try await appState.exportAllMessagesToFile()
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
                print("❌ Error exporting messages: \(error)")
                await MainActor.run {
                    isExportingMessages = false
                    showingExportErrorAlert = true
                }
            }
        }
    }
}



private struct BlockedUsersModal: View {
    @EnvironmentObject private var appState: AppStateManager
    @Environment(\.dismiss) private var dismiss
    @State private var pendingUnblockUser: BlockedUser?
    @State private var showingUnblockConfirmation = false
    
    var body: some View {
        NavigationView {
            Group {
                if appState.blockedUsers.isEmpty {
                    emptyBlockedUsersView
                } else {
                    List(appState.blockedUsers) { blocked in
                        BlockedUserRow(
                            blocked: blocked,
                            onRequestUnblock: {
                                pendingUnblockUser = blocked
                                showingUnblockConfirmation = true
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(SpectRoomBackground())
                }
            }
            .navigationTitle("settings.blocked.users.modal.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if showingUnblockConfirmation, let user = pendingUnblockUser {
                    UnblockConfirmationOverlay(
                        firstName: firstName(from: user.name),
                        onCancel: {
                            showingUnblockConfirmation = false
                            pendingUnblockUser = nil
                        },
                        onConfirm: {
                            showingUnblockConfirmation = false
                            appState.unblockUser(userId: user.id)
                            pendingUnblockUser = nil
                        }
                    )
                }
            }
        }
    }
    
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }

    private var emptyBlockedUsersView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("🚫")
                    .font(.system(size: 48))
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.red.opacity(0.14), radius: 12, y: 4)

                Text("settings.blocked.users.empty".localized)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)

                Text("settings.blocked.users.empty.description".localized)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpectRoomBackground())
    }
}

private struct ReportedProfilesModal: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [UserReport] = []
    @State private var isLoading = true
    @State private var selectedReport: UserReport?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SpectRoomBackground())
                } else if reports.isEmpty {
                    emptyReportedProfilesView
                } else {
                    List(reports) { report in
                        Button {
                            selectedReport = report
                        } label: {
                            ReportedProfileRow(report: report)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(SpectRoomBackground())
                }
            }
            .navigationTitle("settings.reported.profiles.modal.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if let selectedReport {
                    ReportDetailsOverlay(
                        report: selectedReport,
                        onDismiss: { self.selectedReport = nil }
                    )
                }
            }
            .task {
                await loadReports()
            }
        }
    }

    private func loadReports() async {
        isLoading = true
        do {
            reports = try await FirebaseAuthService.shared.fetchMyReports()
        } catch {
            print("⚠️ Failed to load reported profiles: \(error.localizedDescription)")
            reports = []
        }
        isLoading = false
    }

    private var emptyReportedProfilesView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("🚩")
                    .font(.system(size: 48))
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.orange.opacity(0.14), radius: 12, y: 4)

                Text("settings.reported.profiles.empty".localized)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)

                Text("settings.reported.profiles.empty.description".localized)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpectRoomBackground())
    }
}

private struct ReportedProfileRow: View {
    let report: UserReport

    var body: some View {
        HStack(spacing: 12) {
            profilePhoto

            VStack(alignment: .leading, spacing: 4) {
                Text(report.reportedName)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                Text(dateText)
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

    private var dateText: String {
        if let createdAt = report.createdAt {
            return String(
                format: "settings.reported.profiles.since".localized,
                createdAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return "settings.reported.profiles.no.date".localized
    }

    private var profilePhoto: some View {
        Group {
            if let photoURL = report.primaryPhotoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
                Text(String(report.reportedName.prefix(1)).uppercased())
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            )
    }
}

private struct ReportDetailsOverlay: View {
    let report: UserReport
    let onDismiss: () -> Void
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

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    profilePhoto

                    Text(headlineText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(
                        title: "settings.reported.profiles.detail.category".localized,
                        value: report.category
                    )

                    if let details = report.details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
                        detailRow(
                            title: "settings.reported.profiles.detail.details".localized,
                            value: details
                        )
                    }

                    detailRow(
                        title: "settings.reported.profiles.detail.status".localized,
                        value: localizedStatus(report.status)
                    )
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
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isLight ? Color.black.opacity(0.06) : Color.clear, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isLight ? 0.12 : 0), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
    }

    private var headlineText: String {
        if let createdAt = report.createdAt {
            let formattedDate = createdAt.formatted(
                Date.FormatStyle()
                    .day()
                    .month(.abbreviated)
                    .year()
                    .hour()
                    .minute()
            )
            return String(
                format: "settings.reported.profiles.detail.headline".localized,
                report.reportedName,
                formattedDate
            )
        }
        return String(
            format: "settings.reported.profiles.detail.headline.no.date".localized,
            report.reportedName
        )
    }

    private func localizedStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "pending":
            return "settings.reported.profiles.status.pending".localized
        case "reviewed":
            return "settings.reported.profiles.status.reviewed".localized
        case "dismissed":
            return "settings.reported.profiles.status.dismissed".localized
        case "actioned":
            return "settings.reported.profiles.status.actioned".localized
        default:
            return status.capitalized
        }
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

    private var profilePhoto: some View {
        Group {
            if let photoURL = report.primaryPhotoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsPlaceholder
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private var initialsPlaceholder: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay(
                Text(String(report.reportedName.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.blue)
            )
    }
}

private struct SignOutConfirmationOverlay: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text("settings.sign.out.confirm.title".localized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("common.cancel".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SpectRoomTheme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SpectRoomTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onConfirm) {
                        Text("settings.sign.out.confirm.yes".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                            )
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

private struct UnblockConfirmationOverlay: View {
    let firstName: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("settings.blocked.users.unblock.confirm.title".localized(with: firstName))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.text)
                        .padding(.bottom, 4)
                    
                    Text("settings.blocked.users.unblock.confirm.message".localized(with: firstName))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Button(action: onConfirm) {
                    Text("settings.blocked.users.unblock.action".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.green.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(SpectRoomTheme.background)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 36)
        }
    }
}

private struct BlockedUserRow: View {
    let blocked: BlockedUser
    let onRequestUnblock: () -> Void
    
    @State private var photoURL: String?
    
    var body: some View {
        HStack(spacing: 12) {
            profilePhoto
            
            VStack(alignment: .leading, spacing: 4) {
                Text(blocked.name)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                Text(dateText(for: blocked))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
            
            Spacer()
            
            Button("settings.blocked.users.unblock.action".localized, action: onRequestUnblock)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .task(id: blocked.id) {
            await loadPhoto()
        }
    }
    
    private var profilePhoto: some View {
        Group {
            if let photoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
                Text(String(blocked.name.prefix(1)).uppercased())
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            )
    }
    
    private func dateText(for blocked: BlockedUser) -> String {
        if let blockedAt = blocked.blockedAt {
            return String(
                format: "settings.blocked.users.since".localized,
                blockedAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return "settings.blocked.users.no.date".localized
    }
    
    private func loadPhoto() async {
        do {
            photoURL = try await FirebaseAuthService.shared.fetchUserProfilePhotoURL(for: blocked.id)
        } catch {
            photoURL = nil
        }
    }
}

private enum DeleteAccountConfirmationStep {
    case sure
    case enterPassword
    case success
}

private struct DeleteAccountConfirmationDialog: View {
    @Binding var step: DeleteAccountConfirmationStep
    @Binding var confirmationText: String
    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onCancel: () -> Void
    let onConfirmDeletion: (String) -> Void
    
    private var canConfirmPasswordStep: Bool {
        !confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDeleting
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    if step != .success && !isDeleting {
                        onCancel()
                    }
                }
            
            VStack(spacing: 0) {
                if step == .success {
                    Text("settings.delete.account.success.message".localized)
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 22)
                } else {
                    Text("settings.delete.account.confirm.title".localized)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                    
                    Group {
                        if step == .sure {
                            Text("settings.delete.account.confirm.message".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.top, 10)
                                .padding(.horizontal, 20)
                        } else {
                            VStack(spacing: 12) {
                                Text("settings.delete.account.type.message".localized)
                                    .font(.subheadline)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .multilineTextAlignment(.center)
                                
                                SecureField("settings.delete.account.type.placeholder".localized, text: $confirmationText)
                                    .textContentType(.password)
                                    .padding(10)
                                    .background(SpectRoomTheme.card)
                                    .cornerRadius(8)
                                    .disabled(isDeleting)
                                
                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                }
                                
                                if isDeleting {
                                    ProgressView()
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.top, 10)
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    Divider()
                        .padding(.top, 18)
                    
                    if step == .sure {
                        HStack(spacing: 0) {
                            Button("settings.cancel".localized, action: onCancel)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            
                            Divider()
                                .frame(height: 44)
                            
                            Button("settings.delete.account.confirm.yes".localized) {
                                step = .enterPassword
                                confirmationText = ""
                                errorMessage = nil
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                    } else {
                        HStack(spacing: 0) {
                            Button("settings.cancel".localized) {
                                guard !isDeleting else { return }
                                onCancel()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .disabled(isDeleting)
                            
                            Divider()
                                .frame(height: 44)
                            
                            Button("settings.delete.account.confirm.ok".localized) {
                                onConfirmDeletion(confirmationText)
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(canConfirmPasswordStep ? .red : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .disabled(!canConfirmPasswordStep)
                        }
                    }
                }
            }
            .frame(maxWidth: 300)
            .background(SpectRoomTheme.card)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.horizontal, 40)
        }
    }
}

private extension View {
    func compactToggleStyle() -> some View {
        scaleEffect(0.8, anchor: .trailing)
            .frame(width: 46, height: 28, alignment: .trailing)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppStateManager.shared)
}

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
    @State private var showingPrivacySafety = false
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
    
    var body: some View {
        NavigationView {
            List {
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
            }
            .padding(.bottom, 60)
            .scrollContentBackground(.hidden)
            .background(
                SpectRoomBackground()
            )
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

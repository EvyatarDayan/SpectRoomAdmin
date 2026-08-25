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
    @State private var showingSignOutConfirmation = false

    private var signedInEmail: String {
        let profileEmail = appState.currentUser?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !profileEmail.isEmpty { return profileEmail }
        return FirebaseAuthService.shared.auth.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var signOutSubtitle: String {
        let email = signedInEmail
        guard !email.isEmpty else {
            return "settings.authentication.signout.subtitle".localized
        }
        return String(format: "settings.authentication.signout.subtitle.format".localized, email)
    }
    
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

                Section {
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
                                Text(signOutSubtitle)
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
            .overlay {
                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        onCancel: { showingSignOutConfirmation = false },
                        onConfirm: {
                            showingSignOutConfirmation = false
                            appState.signOut()
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

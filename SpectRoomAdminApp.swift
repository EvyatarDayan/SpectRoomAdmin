//
//  SpectRoomAdminApp.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import Combine
import UserNotifications


/// Presents Help & Support from a moderation popup with a stable, unique sheet identity.
private struct ModerationSupportPresentation: Identifiable {
    let id = UUID()
    let topic: HelpSupportView.Topic
}

@main
struct SpectRoomApp: App {
    @StateObject private var appState = AppStateManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var languageChanged = false
    @State private var moderationSupport: ModerationSupportPresentation? = nil
    
    init() {
        // Configure Firebase - try to load from bundle first, then fallback to file path
        var options: FirebaseOptions?
        var configurationSource: String?
        
        // First, try to load from app bundle (if file is added to Xcode project)
        if let bundlePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let bundleOptions = FirebaseOptions(contentsOfFile: bundlePath) {
            options = bundleOptions
            configurationSource = "main bundle"
        }
        // Fallback: try to load from project directory
        else if let projectPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist", inDirectory: nil),
                 let projectOptions = FirebaseOptions(contentsOfFile: projectPath) {
            options = projectOptions
            configurationSource = "project directory"
        }
        // Last resort: try absolute path
        else {
            let absolutePath = "/Users/evyatardayan/Desktop/My projects/swift/SpectRoom/SpectRoom/GoogleService-Info.plist"
            if FileManager.default.fileExists(atPath: absolutePath),
               let absoluteOptions = FirebaseOptions(contentsOfFile: absolutePath) {
                options = absoluteOptions
                configurationSource = "absolute path"
            }
        }
        
        if let options = options {
            FirebaseApp.configure(options: options)
            print("✅ Firebase configured with project: \(options.projectID) (source: \(configurationSource ?? "unknown"))")
        } else {
            // If all else fails, try default configuration (might work if file is in bundle)
            FirebaseApp.configure()
            if let app = FirebaseApp.app() {
                print("✅ Firebase configured with default options: \(app.options.projectID)")
            } else {
                assertionFailure("❌ Firebase configuration failed. Ensure GoogleService-Info.plist is included in the target.")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-KeyboardComposerVisualTest") {
                KeyboardStickyComposerVisualTest()
            } else {
                mainRootView
            }
            #else
            mainRootView
            #endif
        }
    }
    
    @ViewBuilder
    private var mainRootView: some View {
        Group {
            if !appState.hasResolvedAuthState && !appState.isAuthenticated {
                // Wait for Firebase to restore session before showing welcome/sign-in
                LaunchAuthPlaceholderView()
            } else if appState.isAuthenticated {
                if appState.hasCompletedInitialProfile {
                    ContentView()
                        .environmentObject(appState)
                } else if appState.isNewSignup {
                    // New user after signup - must complete profile
                    ProfileEditView(isMandatoryCompletion: true)
                        .environmentObject(appState)
                } else {
                    // Existing user with incomplete profile - allow access but encourage completion
                    ContentView()
                        .environmentObject(appState)
                }
            } else {
                AuthenticationView()
                    .environmentObject(appState)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .overlay {
            if let notice = appState.pendingModerationNotice {
                SystemWarningOverlay(
                    title: notice.title,
                    message: notice.message,
                    acceptLabel: notice.acceptLabel,
                    requiresCheckbox: notice.requiresCheckbox,
                    secondaryLinkTitle: notice.showsContactSupport ? notice.contactSupportLabel : nil,
                    onSecondaryLink: notice.showsContactSupport
                        ? {
                            let topic: HelpSupportView.Topic
                            switch notice.kind {
                            case .banAcknowledgement, .loginBanned:
                                topic = .accountBan
                            default:
                                topic = .accountFreeze
                            }
                            moderationSupport = ModerationSupportPresentation(topic: topic)
                        }
                        : nil
                ) {
                    appState.dismissModerationNotice()
                }
                .zIndex(999)
            }
        }
        .sheet(item: $moderationSupport) { presentation in
            HelpSupportView(
                initialTopic: presentation.topic,
                lockedTopic: presentation.topic,
                maxMessageLength: 200,
                onMessageSent: {
                    moderationSupport = nil
                    appState.dismissModerationNotice()
                }
            )
            .id(presentation.id)
            .environmentObject(appState)
        }
        .onAppear {
            // Set online status when app first appears and user is authenticated
            if appState.isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.updateAppStateInFirestore(isActive: true)
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onChange(of: appState.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onChange(of: appState.hasResolvedUserProfile) { _, resolved in
            if resolved, appState.isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Update online status and preload photos when app becomes active
            if appState.isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.updateAppStateInFirestore(isActive: true)
                    await FirebaseAuthService.shared.syncPhotosFromStorage()
                    appState.refreshUnreadMessageCount()
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if appState.isAuthenticated {
                appState.syncAppIconBadgeBeforeBackground()
                Task {
                    await appState.updateAppStateInFirestore(isActive: false)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if appState.isAuthenticated {
                appState.syncAppIconBadgeBeforeBackground()
                Task {
                    await appState.updateAppStateInFirestore(isActive: false)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            // Trigger view refresh when language changes
            languageChanged.toggle()
        }
        .id(languageChanged) // Force view refresh on language change
    }
}

/// Neutral launch screen while Firebase restores the persisted session.
private struct LaunchAuthPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            SpectRoomBackground()
        }
    }
}

// MARK: - AppDelegate for handling push notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Set Firebase Messaging delegate
        Messaging.messaging().delegate = self
        
        // Request notification permission
        if !ProcessInfo.processInfo.arguments.contains("-KeyboardComposerVisualTest") {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if granted {
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                    print("✅ Notification permission granted on app launch")
                } else {
                    print("❌ Notification permission denied on app launch")
                }
            }
        }
        
        return true
    }
    
    // Handle APNs token registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 APNs token received")
        // Pass token to Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // Handle APNs token registration failure
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(userInfo)
        syncBadgeCount(from: userInfo)
        completionHandler(.newData)
    }
    
    private func syncBadgeCount(from userInfo: [AnyHashable: Any]) {
        if let aps = userInfo["aps"] as? [String: Any] {
            if let badge = aps["badge"] as? Int {
                Task { @MainActor in
                    AppStateManager.shared.unreadMessageCount = badge
                    NotificationService.shared.setAppIconBadgeCount(badge)
                }
                return
            }
        }
        
        if let badgeString = userInfo["badge"] as? String, let badge = Int(badgeString) {
            Task { @MainActor in
                AppStateManager.shared.unreadMessageCount = badge
                NotificationService.shared.setAppIconBadgeCount(badge)
            }
            return
        }
        
        if let gcmOptions = userInfo["gcm.notification"] as? [String: Any],
           let badgeString = gcmOptions["badge"] as? String,
           let badge = Int(badgeString) {
            Task { @MainActor in
                AppStateManager.shared.unreadMessageCount = badge
                NotificationService.shared.setAppIconBadgeCount(badge)
            }
        }
    }
    
    // MARK: - MessagingDelegate
    
    // Handle FCM token refresh
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM token received: \(fcmToken ?? "nil")")
        
        guard let fcmToken = fcmToken else {
            print("⚠️ FCM token is nil")
            return
        }
        
        // Save FCM token to Firestore
        Task {
            await saveFCMTokenToFirestore(fcmToken)
        }
    }
    
    // Save FCM token to Firestore
    private func saveFCMTokenToFirestore(_ token: String) async {
        guard let userId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            print("⚠️ No user logged in, cannot save FCM token")
            return
        }
        
        do {
            try await FirebaseAuthService.shared.updateUserData(["fcmToken": token])
            print("✅ FCM token saved to Firestore for user: \(userId)")
        } catch {
            print("❌ Failed to save FCM token to Firestore: \(error.localizedDescription)")
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        syncBadgeCount(from: userInfo)
        refreshModerationNoticeIfNeeded(from: userInfo)
        
        if NotificationService.shouldSuppressForegroundMatchNotification(userInfo: userInfo) {
            completionHandler([])
            return
        }
        
        if NotificationService.shouldSuppressForegroundMessageNotification(userInfo: userInfo) {
            completionHandler([])
            return
        }
        
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        syncBadgeCount(from: userInfo)
        refreshModerationNoticeIfNeeded(from: userInfo)
        print("📱 Notification tapped, userInfo: \(userInfo)")
        
        let type = NotificationService.notificationString(userInfo, key: "type")
        switch type {
        case "match":
            if let matchId = NotificationService.notificationString(userInfo, key: "matchId") {
                print("📱 User tapped match notification: \(matchId)")
            }
        case "message":
            if let senderId = NotificationService.notificationString(userInfo, key: "senderId") {
                print("📱 User tapped message notification from: \(senderId)")
                DispatchQueue.main.async {
                    AppStateManager.shared.openConversationFromNotification(senderId: senderId)
                }
            } else {
                print("⚠️ Message notification tap missing senderId")
            }
        case "moderation_warning", "moderation_freeze", "moderation_freeze_extended", "moderation_unfreeze", "moderation_ban", "moderation_unban":
            print("📱 User opened moderation notification: \(type ?? "")")
            Task { @MainActor in
                AppStateManager.shared.startListeningForModerationStatus()
                await AppStateManager.shared.refreshPendingModerationNotice()
            }
        default:
            print("⚠️ Unknown or missing notification type on tap: \(type ?? "nil")")
        }
        
        completionHandler()
    }

    private func refreshModerationNoticeIfNeeded(from userInfo: [AnyHashable: Any]) {
        let type = NotificationService.notificationString(userInfo, key: "type")
        switch type {
        case "moderation_warning", "moderation_freeze", "moderation_freeze_extended", "moderation_ban", "moderation_unban":
            Task { @MainActor in
                AppStateManager.shared.startListeningForModerationStatus()
                await AppStateManager.shared.refreshPendingModerationNotice()
            }
        default:
            break
        }
    }
}

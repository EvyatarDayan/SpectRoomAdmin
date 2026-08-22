//
//  NotificationService.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation
import UserNotifications
import UIKit

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    
    static func shouldSuppressForegroundMessageNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard notificationString(userInfo, key: "type") == "message" else { return false }
        let senderId = notificationString(userInfo, key: "senderId") ?? ""
        return AppStateManager.shared.shouldSuppressMessageNotification(for: senderId)
    }
    
    /// Match pushes are only for closed/backgrounded app — in foreground the match popup is enough.
    static func shouldSuppressForegroundMatchNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard notificationString(userInfo, key: "type") == "match" else { return false }
        return UIApplication.shared.applicationState == .active
    }
    
    /// FCM data values usually arrive as strings in notification userInfo.
    static func notificationString(_ userInfo: [AnyHashable: Any], key: String) -> String? {
        if let value = userInfo[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = userInfo[key] as? NSNumber {
            return value.stringValue
        }
        return nil
    }
    
    private override init() {
        super.init()
        // Do not set UNUserNotificationCenter.delegate here — AppDelegate owns taps
        // so notification opens can navigate into the conversation.
    }
    
    /// Check if notification permission is granted
    func checkNotificationPermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    
    /// Check if notifications are enabled in app settings
    func areNotificationsEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }
    
    /// Update the app icon badge (home screen) with the total unread message count.
    @MainActor
    func setAppIconBadgeCount(_ count: Int) {
        let badgeCount = max(0, count)
        
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(badgeCount) { error in
                if let error = error {
                    print("❌ Failed to set app icon badge: \(error.localizedDescription)")
                } else {
                    print("📱 App icon badge set to \(badgeCount)")
                }
            }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
            print("📱 App icon badge set to \(badgeCount)")
        }
    }
    
    /// Send a local push notification for a new match (background / closed app only).
    func sendNewMatchNotification(matchName: String, matchId: String) {
        guard UIApplication.shared.applicationState != .active else {
            print("📱 App is active — skipping match push (in-app popup will show)")
            return
        }
        guard areNotificationsEnabled() else {
            print("📱 Notifications disabled in settings, skipping push notification")
            return
        }
        
        Task {
            let hasPermission = await checkNotificationPermission()
            guard hasPermission else {
                print("📱 Notification permission not granted, skipping push notification")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "It's a match! 💕"
            content.body = "You and \(matchName) like each other!"
            content.sound = .default
            content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
            content.userInfo = ["type": "match", "matchId": matchId]
            
            // Schedule notification immediately
            let request = UNNotificationRequest(
                identifier: "match_\(matchId)",
                content: content,
                trigger: nil // nil trigger means immediate
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                print("📱 Push notification sent for match: \(matchName)")
            } catch {
                print("❌ Failed to send match notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Send a local push notification for a new message
    func sendNewMessageNotification(senderName: String, messageContent: String, senderId: String, badgeCount: Int) {
        guard areNotificationsEnabled() else {
            print("📱 Notifications disabled in settings, skipping push notification")
            return
        }
        
        Task {
            let hasPermission = await checkNotificationPermission()
            guard hasPermission else {
                print("📱 Notification permission not granted, skipping push notification")
                return
            }
            
            let content = UNMutableNotificationContent()
            var firstName = senderName.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? senderName
            if firstName.isEmpty {
                firstName = senderName
            }
            let previewSource = Self.sanitizedMessagePreview(messageContent)
            let preview = previewSource.count > 50 ? String(previewSource.prefix(50)) + "..." : previewSource
            content.title = "message.notification.push.title".localized
            content.body = String(format: "message.notification.push.body".localized, firstName, preview)
            content.sound = .default
            content.badge = NSNumber(value: badgeCount)
            content.userInfo = ["type": "message", "senderId": senderId]
            
            // Schedule notification immediately
            let request = UNNotificationRequest(
                identifier: "message_\(senderId)_\(UUID().uuidString)",
                content: content,
                trigger: nil // nil trigger means immediate
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                await MainActor.run {
                    setAppIconBadgeCount(badgeCount)
                }
                print("📱 Push notification sent for message from: \(senderName)")
            } catch {
                print("❌ Failed to send message notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Avoid showing raw Firebase Storage URLs in notification banners.
    private static func sanitizedMessagePreview(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("firebasestorage.googleapis.com")
            || lower.hasPrefix("gs://")
            || (lower.hasPrefix("http") && (lower.contains("/o/") || lower.contains(".m4a") || lower.contains(".mp3") || lower.contains(".caf") || lower.contains(".wav"))) {
            if lower.contains(".m4a") || lower.contains(".mp3") || lower.contains(".caf") || lower.contains(".wav") || lower.contains("voice") {
                return "messages.preview.voice".localized
            }
            if lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".heic") || lower.contains("photo") || lower.contains("image") {
                return "messages.preview.photo".localized
            }
            return "messages.preview.voice".localized
        }
        return trimmed
    }
    
    /// Request notification permission
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                // Register for remote notifications if permission granted
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("✅ Notification permission granted")
            } else {
                print("❌ Notification permission denied")
            }
            return granted
        } catch {
            print("❌ Error requesting notification permission: \(error.localizedDescription)")
            return false
        }
    }
}



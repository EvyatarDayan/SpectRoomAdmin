//
//  Message.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let senderFirebaseId: String // Store the actual Firebase UID
    let content: String
    let type: MessageType
    let createdAt: Date
    var isRead: Bool
    var readAt: Date?
    var voiceDuration: TimeInterval?
    
    init(conversationId: UUID, senderId: UUID, senderFirebaseId: String, content: String, type: MessageType = .text, voiceDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderFirebaseId = senderFirebaseId
        self.content = content
        self.type = type
        self.createdAt = Date()
        self.isRead = false
        self.readAt = nil
        self.voiceDuration = voiceDuration
    }
    
    // Custom initializer for messages with specific timestamp (from Firebase)
    init(conversationId: UUID, senderId: UUID, senderFirebaseId: String, content: String, createdAt: Date, type: MessageType = .text, voiceDuration: TimeInterval? = nil) {
        self.id = UUID()
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderFirebaseId = senderFirebaseId
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.isRead = false
        self.readAt = nil
        self.voiceDuration = voiceDuration
    }
}

enum MessageType: String, CaseIterable, Codable {
    case text = "text"
    case image = "image"
    case voice = "voice"
    case video = "video"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .voice:
            return "Voice Message"
        case .video:
            return "Video"
        case .system:
            return "System Message"
        }
    }
    
    var icon: String {
        switch self {
        case .text:
            return "text.bubble"
        case .image:
            return "photo"
        case .voice:
            return "mic.fill"
        case .video:
            return "video.fill"
        case .system:
            return "info.circle"
        }
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    let participantIds: [UUID]
    let lastMessage: Message?
    let createdAt: Date
    var isActive: Bool
    var unreadCount: Int
    
    init(participantIds: [UUID]) {
        self.id = UUID()
        self.participantIds = participantIds
        self.lastMessage = nil
        self.createdAt = Date()
        self.isActive = true
        self.unreadCount = 0
    }
}

// Helper struct for displaying conversation in UI
struct ConversationDisplay: Identifiable {
    let id: UUID
    let otherUser: SpectRoomUser
    let lastMessage: String
    let timestamp: String
    let isOnline: Bool
    let unreadCount: Int
    
    init(conversation: Conversation, otherUser: SpectRoomUser, lastMessage: Message?) {
        self.id = conversation.id
        self.otherUser = otherUser
        self.lastMessage = lastMessage?.content ?? "No messages yet"
        self.timestamp = lastMessage?.createdAt.timeAgoDisplay() ?? ""
        self.isOnline = otherUser.isOnline
        self.unreadCount = conversation.unreadCount
    }
}

// Helper struct for displaying messages in UI with sender/recipient names
struct MessageDisplay: Identifiable {
    let id: String
    let content: String
    let messageType: MessageType
    let senderName: String
    let recipientName: String
    let senderId: String // Firebase user ID
    let recipientId: String // Firebase user ID
    let createdAt: Date
    let isRead: Bool
    let senderProfilePhotoURL: String? // Profile photo URL of the sender
    let recipientProfilePhotoURL: String? // Profile photo URL of the recipient
    let voiceDuration: TimeInterval?
    
    init(message: Message, senderName: String, recipientName: String, senderId: String, recipientId: String, senderProfilePhotoURL: String? = nil, recipientProfilePhotoURL: String? = nil) {
        self.id = message.id.uuidString
        self.content = message.content
        self.messageType = message.type
        self.senderName = senderName
        self.recipientName = recipientName
        self.senderId = senderId
        self.recipientId = recipientId
        self.createdAt = message.createdAt
        self.isRead = message.isRead
        self.senderProfilePhotoURL = senderProfilePhotoURL
        self.recipientProfilePhotoURL = recipientProfilePhotoURL
        self.voiceDuration = message.voiceDuration
    }
    
    init(
        id: String,
        content: String,
        messageType: MessageType,
        senderName: String,
        recipientName: String,
        senderId: String,
        recipientId: String,
        createdAt: Date,
        isRead: Bool,
        senderProfilePhotoURL: String?,
        recipientProfilePhotoURL: String?,
        voiceDuration: TimeInterval?
    ) {
        self.id = id
        self.content = content
        self.messageType = messageType
        self.senderName = senderName
        self.recipientName = recipientName
        self.senderId = senderId
        self.recipientId = recipientId
        self.createdAt = createdAt
        self.isRead = isRead
        self.senderProfilePhotoURL = senderProfilePhotoURL
        self.recipientProfilePhotoURL = recipientProfilePhotoURL
        self.voiceDuration = voiceDuration
    }
    
    /// Stable identity for deduplicating optimistic vs server-fetched copies of the same message.
    var deduplicationKey: String {
        "\(senderId)_\(recipientId)_\(messageType.rawValue)_\(content)"
    }
    
    func replacingPartnerIdentity(name: String, photoURL: String?, currentUserId: String) -> MessageDisplay {
        let isOutgoing = senderId == currentUserId || senderName == "You"
        return MessageDisplay(
            id: id,
            content: content,
            messageType: messageType,
            senderName: isOutgoing ? senderName : name,
            recipientName: isOutgoing ? name : recipientName,
            senderId: senderId,
            recipientId: recipientId,
            createdAt: createdAt,
            isRead: isRead,
            senderProfilePhotoURL: isOutgoing ? senderProfilePhotoURL : (photoURL ?? senderProfilePhotoURL),
            recipientProfilePhotoURL: isOutgoing ? (photoURL ?? recipientProfilePhotoURL) : recipientProfilePhotoURL,
            voiceDuration: voiceDuration
        )
    }
}

extension Array where Element == MessageDisplay {
    func deduplicatedConversationMessages() -> [MessageDisplay] {
        var seen = Set<String>()
        return sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            // Same-second messages: keep a stable order.
            return lhs.deduplicationKey < rhs.deduplicationKey
        }.filter { message in
            seen.insert(message.deduplicationKey).inserted
        }
    }
}

struct ConversationMessagesPage {
    let messages: [MessageDisplay]
    let hasMoreOlder: Bool
}

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           !selectedLanguage.isEmpty {
            formatter.locale = Locale(identifier: selectedLanguage)
        }
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy HH:mm"
        return formatter.string(from: self)
    }
    
    func formattedBubbleTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
    
    /// Conversation list timestamp: "14:20" / "Yesterday" / "13/07/2026".
    func formattedConversationListTime() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formattedBubbleTime()
        }
        if calendar.isDateInYesterday(self) {
            return "messages.date.yesterday".localized
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: self)
    }
    
    /// WhatsApp-style chat day label: Today / Yesterday / "Thu, 21 May".
    func formattedChatDayTitle() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "messages.date.today".localized
        }
        if calendar.isDateInYesterday(self) {
            return "messages.date.yesterday".localized
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        if let selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           !selectedLanguage.isEmpty {
            formatter.locale = Locale(identifier: selectedLanguage)
        }
        return formatter.string(from: self)
    }
}

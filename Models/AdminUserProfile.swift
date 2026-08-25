import Foundation

struct AdminUserProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let age: Int?
    let email: String
    let bio: String
    let photoURL: String?
    let photos: [String]
    let gender: String
    let interests: [String]
    let interestedIn: [String]
    let lookingFor: [String]
    let locationDisplay: String
    let isOnline: Bool
    let lastSeen: Date?
    let isBanned: Bool
    let isFrozen: Bool
    let frozenUntil: Date?
    let isDeleted: Bool
    let isIncomplete: Bool
    let createdAt: Date?

    var titleText: String {
        if let age {
            return "\(name), \(age)"
        }
        return name
    }

    var statusLabelKey: String {
        if isDeleted { return "admin.all.profiles.status.deleted" }
        if isBanned { return "admin.all.profiles.status.banned" }
        if isFrozen { return "admin.all.profiles.status.frozen" }
        if isIncomplete { return "admin.all.profiles.status.incomplete" }
        if isOnline { return "admin.all.profiles.status.online" }
        return "admin.all.profiles.status.offline"
    }

    /// Status shown in list / detail rows. Incomplete includes creation date when available.
    var statusDisplayText: String {
        if isDeleted || isBanned || isFrozen || !isIncomplete {
            return statusLabelKey.localized
        }
        guard let createdAt else {
            return "admin.all.profiles.status.incomplete".localized
        }
        let dateText = Self.formattedSinceDate(createdAt)
        let format = "admin.all.profiles.status.incomplete.since".localized
        if format == "admin.all.profiles.status.incomplete.since" || !format.contains("%@") {
            return "Incomplete - Since \(dateText)"
        }
        return String(format: format, dateText)
    }

    private static func formattedSinceDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "dd/MM/yy"
        return formatter.string(from: date)
    }

    func applyingFreeze(until: Date) -> AdminUserProfile {
        AdminUserProfile(
            id: id,
            name: name,
            age: age,
            email: email,
            bio: bio,
            photoURL: photoURL,
            photos: photos,
            gender: gender,
            interests: interests,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            locationDisplay: locationDisplay,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isBanned: isBanned,
            isFrozen: true,
            frozenUntil: until,
            isDeleted: isDeleted,
            isIncomplete: isIncomplete,
            createdAt: createdAt
        )
    }

    func applyingBan() -> AdminUserProfile {
        AdminUserProfile(
            id: id,
            name: name,
            age: age,
            email: email,
            bio: bio,
            photoURL: photoURL,
            photos: photos,
            gender: gender,
            interests: interests,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            locationDisplay: locationDisplay,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isBanned: true,
            isFrozen: isFrozen,
            frozenUntil: frozenUntil,
            isDeleted: isDeleted,
            isIncomplete: isIncomplete,
            createdAt: createdAt
        )
    }

    func withName(_ name: String) -> AdminUserProfile {
        AdminUserProfile(
            id: id,
            name: name,
            age: age,
            email: email,
            bio: bio,
            photoURL: photoURL,
            photos: photos,
            gender: gender,
            interests: interests,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            locationDisplay: locationDisplay,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isBanned: isBanned,
            isFrozen: isFrozen,
            frozenUntil: frozenUntil,
            isDeleted: isDeleted,
            isIncomplete: isIncomplete,
            createdAt: createdAt
        )
    }

    func withAge(_ age: Int?) -> AdminUserProfile {
        AdminUserProfile(
            id: id,
            name: name,
            age: age,
            email: email,
            bio: bio,
            photoURL: photoURL,
            photos: photos,
            gender: gender,
            interests: interests,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            locationDisplay: locationDisplay,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isBanned: isBanned,
            isFrozen: isFrozen,
            frozenUntil: frozenUntil,
            isDeleted: isDeleted,
            isIncomplete: isIncomplete,
            createdAt: createdAt
        )
    }

    func withEmail(_ email: String) -> AdminUserProfile {
        AdminUserProfile(
            id: id,
            name: name,
            age: age,
            email: email,
            bio: bio,
            photoURL: photoURL,
            photos: photos,
            gender: gender,
            interests: interests,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            locationDisplay: locationDisplay,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isBanned: isBanned,
            isFrozen: isFrozen,
            frozenUntil: frozenUntil,
            isDeleted: isDeleted,
            isIncomplete: isIncomplete,
            createdAt: createdAt
        )
    }

    func withCreatedAt(_ createdAt: Date) -> AdminUserProfile {
        AdminUserProfile(
            id: id,
            name: name,
            age: age,
            email: email,
            bio: bio,
            photoURL: photoURL,
            photos: photos,
            gender: gender,
            interests: interests,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            locationDisplay: locationDisplay,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isBanned: isBanned,
            isFrozen: isFrozen,
            frozenUntil: frozenUntil,
            isDeleted: isDeleted,
            isIncomplete: isIncomplete,
            createdAt: createdAt
        )
    }
}

struct AdminRecentConversation: Identifiable, Equatable {
    let id: String
    let partnerId: String
    let partnerName: String
    let partnerPhotoURL: String?
    let preview: String
    let isOutgoing: Bool
    let createdAt: Date
}

struct AdminConversationMessage: Identifiable, Equatable {
    let id: String
    let content: String
    let type: MessageType
    /// `true` when the subject profile (the user being inspected) sent this message.
    let isFromSubject: Bool
    let createdAt: Date
    let voiceDuration: TimeInterval?
}

enum AdminProfileHistoryKind: String, Equatable {
    case reported
    case warning
    case freeze
    case freezeEnded
    case ban
    case banLifted
}

struct AdminProfileHistoryEvent: Identifiable, Equatable {
    let id: String
    let kind: AdminProfileHistoryKind
    let title: String
    let detail: String?
    let status: String?
    let date: Date

    var systemImage: String {
        switch kind {
        case .reported: return "exclamationmark.bubble.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .freeze: return "snowflake"
        case .freezeEnded: return "sun.max.fill"
        case .ban: return "person.crop.circle.badge.xmark"
        case .banLifted: return "person.crop.circle.badge.checkmark"
        }
    }
}

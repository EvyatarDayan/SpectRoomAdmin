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
        if isOnline { return "admin.all.profiles.status.online" }
        return "admin.all.profiles.status.offline"
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

import Foundation

/// Stored on `users/{uid}.profileStatus` for admin filtering of unfinished signups.
enum UserProfileStatus: String {
    case incomplete
    case complete

    static let firestoreKey = "profileStatus"

    /// Same completion rules as `AppStateManager.isProfileComplete()`.
    static func evaluate(from userData: [String: Any]) -> UserProfileStatus {
        let name = (userData["name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nameComponents = name.components(separatedBy: " ")
        let hasFullName = nameComponents.count >= 2 && nameComponents.allSatisfy { !$0.isEmpty }

        let age = userData["age"] as? Int
            ?? (userData["age"] as? NSNumber)?.intValue
            ?? 0
        let hasValidAge = age >= 18

        let location = FirebaseAuthService.parseLocation(from: userData)
        let trimmedLocation = location.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLocation: Bool
        if trimmedLocation.isEmpty {
            hasLocation = false
        } else if let latitude = location.latitude, let longitude = location.longitude {
            hasLocation = SwedenLocation.contains(latitude: latitude, longitude: longitude)
        } else {
            hasLocation = true
        }

        let bio = (userData["bio"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBio = bio.count >= 30

        let profilePhotoURL = (userData["profilePhotoURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasProfilePhoto = !profilePhotoURL.isEmpty && URL(string: profilePhotoURL) != nil

        let photos = (userData["photos"] as? [String] ?? []).filter { photoURL in
            let trimmed = photoURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && URL(string: trimmed) != nil
        }
        let hasPhotos = photos.count >= 2 && photos.count <= 5

        let interests = userData["interests"] as? [String] ?? []
        let hasInterests = interests.count >= 3
        let hasGender = !(userData["gender"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let interestedIn = userData["interestedIn"] as? [String] ?? []
        let lookingFor = userData["lookingFor"] as? [String] ?? []
        let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []

        let isComplete = hasFullName
            && hasValidAge
            && hasLocation
            && hasBio
            && hasProfilePhoto
            && hasPhotos
            && hasInterests
            && hasGender
            && !interestedIn.isEmpty
            && !lookingFor.isEmpty
            && !idealFirstDate.isEmpty

        return isComplete ? .complete : .incomplete
    }

    /// Live status from profile fields. Do not trust a stored `profileStatus` alone —
    /// it can stay `"incomplete"` after the user finishes their profile.
    static func resolve(from userData: [String: Any]) -> UserProfileStatus {
        evaluate(from: userData)
    }
}

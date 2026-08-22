import Foundation

struct UserReport: Identifiable, Equatable {
    let id: String
    let reporterUserId: String
    let reportedUserId: String
    let reportedName: String
    let category: String
    let details: String?
    let status: String
    let createdAt: Date?
    let bio: String
    let profilePhotoURLs: [String]

    var primaryPhotoURL: String? {
        profilePhotoURLs.first
    }
}

import Foundation

struct UserReport: Identifiable, Equatable {
    let id: String
    let reporterUserId: String
    let reportedUserId: String
    let reportedName: String
    let reporterName: String?
    let reporterEmail: String?
    let reportedEmail: String?
    let reporterPhotoURL: String?
    let category: String
    let details: String?
    let status: String
    let createdAt: Date?
    let bio: String
    let profilePhotoURLs: [String]

    var primaryPhotoURL: String? {
        profilePhotoURLs.first
    }

    var displayReporterName: String {
        let trimmed = reporterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    func withIdentities(
        reporterEmail: String?,
        reportedEmail: String?,
        reporterName: String? = nil,
        reporterPhotoURL: String? = nil
    ) -> UserReport {
        UserReport(
            id: id,
            reporterUserId: reporterUserId,
            reportedUserId: reportedUserId,
            reportedName: reportedName,
            reporterName: reporterName ?? self.reporterName,
            reporterEmail: reporterEmail ?? self.reporterEmail,
            reportedEmail: reportedEmail ?? self.reportedEmail,
            reporterPhotoURL: reporterPhotoURL ?? self.reporterPhotoURL,
            category: category,
            details: details,
            status: status,
            createdAt: createdAt,
            bio: bio,
            profilePhotoURLs: profilePhotoURLs
        )
    }

    /// Backward-compatible alias.
    func withEmails(
        reporterEmail: String?,
        reportedEmail: String?,
        reporterName: String? = nil
    ) -> UserReport {
        withIdentities(
            reporterEmail: reporterEmail,
            reportedEmail: reportedEmail,
            reporterName: reporterName
        )
    }
}

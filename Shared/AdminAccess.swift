import Foundation

enum AdminAccess {
    /// Emails that can open the Admin section and moderate reports.
    static let adminEmails: Set<String> = [
        "admin1@yopmail.com"
    ]

    static func isAdmin(email: String?) -> Bool {
        guard let email else { return false }
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return adminEmails.contains(normalized)
    }
}

enum ModerationFreezeDuration: Int, CaseIterable, Identifiable {
    case hours24 = 24
    case hours48 = 48
    case hours72 = 72

    var id: Int { rawValue }

    var labelKey: String {
        switch self {
        case .hours24: return "admin.reports.freeze.24h"
        case .hours48: return "admin.reports.freeze.48h"
        case .hours72: return "admin.reports.freeze.72h"
        }
    }
}

enum ReportModerationAction: String {
    case dismiss
    case warning
    case freeze
    case ban
}

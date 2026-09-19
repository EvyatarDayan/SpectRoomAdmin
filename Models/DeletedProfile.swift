import Foundation

enum DeleteRecordStatus: String, Equatable {
    case active
    case fullyDeleted
    case restored

    var localizationKey: String {
        switch self {
        case .active: return "admin.deleted.status.active"
        case .fullyDeleted: return "admin.deleted.status.fully.deleted"
        case .restored: return "admin.deleted.status.restored"
        }
    }
}

enum DeletedByActor: String, Equatable {
    case user
    case admin
    case unknown

    var localizationKey: String {
        switch self {
        case .user: return "admin.deleted.by.user"
        case .admin: return "admin.deleted.by.admin"
        case .unknown: return "admin.deleted.by.unknown"
        }
    }

    static func parse(from raw: String?) -> DeletedByActor {
        switch (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "user", "self":
            return .user
        case "admin":
            return .admin
        default:
            return .unknown
        }
    }
}

struct DeletedProfile: Identifiable, Equatable {
    /// List identity (history record id when present, otherwise user id).
    let id: String
    let userId: String
    let name: String
    let age: Int?
    let email: String?
    let photoURL: String?
    let status: DeleteRecordStatus
    let deletedBy: DeletedByActor
    let deletedAt: Date?
    /// Scheduled or completed hard-purge timestamp.
    let fullyDeletedAt: Date?
    let restoredAt: Date?

    /// Soft-deleted or fully wiped records shown on the Deleted tab.
    var isCurrentlyDeleted: Bool {
        status == .active || status == .fullyDeleted
    }

    var isFullyDeleted: Bool {
        status == .fullyDeleted
    }

    var canUndelete: Bool {
        status == .active
    }

    var isHistoryItem: Bool {
        status == .restored
    }

    var displayEmail: String {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "admin.reports.detail.email.unavailable".localized : trimmed
    }

    var displayFullyDeletedAt: String {
        if let fullyDeletedAt {
            return ModerationNotice.formattedUnlockDate(fullyDeletedAt)
        }
        return "admin.deleted.detail.fully.deleted.not.scheduled".localized
    }
}

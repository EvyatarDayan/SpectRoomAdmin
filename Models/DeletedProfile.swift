import Foundation

enum DeleteRecordStatus: String, Equatable {
    case active
    case restored

    var localizationKey: String {
        switch self {
        case .active: return "admin.deleted.status.active"
        case .restored: return "admin.deleted.status.restored"
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
    let deletedAt: Date?
    let restoredAt: Date?

    var isCurrentlyDeleted: Bool {
        status == .active
    }

    var isHistoryItem: Bool {
        !isCurrentlyDeleted
    }
}

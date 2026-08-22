import Foundation

enum FreezeRecordStatus: String, Equatable {
    case active
    case lifted
    case expired
    case banned

    var localizationKey: String {
        switch self {
        case .active: return "admin.frozen.status.active"
        case .lifted: return "admin.frozen.status.lifted"
        case .expired: return "admin.frozen.status.expired"
        case .banned: return "admin.frozen.status.banned"
        }
    }
}

struct FrozenProfile: Identifiable, Equatable {
    /// List identity (history record id when present, otherwise user id).
    let id: String
    let userId: String
    let historyRecordId: String?
    let name: String
    let age: Int?
    let email: String?
    let photoURL: String?
    let frozenUntil: Date
    let freezeHours: Int
    let reportId: String?
    let status: FreezeRecordStatus
    let createdAt: Date?
    let endedAt: Date?

    var unlockLabel: String {
        ModerationNotice.formattedUnlockDate(frozenUntil)
    }

    var isCurrentlyFrozen: Bool {
        status == .active && frozenUntil > Date()
    }

    var isHistoryItem: Bool {
        !isCurrentlyFrozen
    }
}

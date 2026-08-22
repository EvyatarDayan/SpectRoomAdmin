import Foundation

enum BanRecordStatus: String, Equatable {
    case active
    case lifted

    var localizationKey: String {
        switch self {
        case .active: return "admin.banned.status.active"
        case .lifted: return "admin.banned.status.lifted"
        }
    }
}

struct BannedProfile: Identifiable, Equatable {
    /// List identity (history record id when present, otherwise user id).
    let id: String
    let userId: String
    let historyRecordId: String?
    let name: String
    let age: Int?
    let email: String?
    let photoURL: String?
    let reportId: String?
    let status: BanRecordStatus
    let bannedAt: Date?
    let endedAt: Date?

    var isCurrentlyBanned: Bool {
        status == .active
    }

    var isHistoryItem: Bool {
        !isCurrentlyBanned
    }
}

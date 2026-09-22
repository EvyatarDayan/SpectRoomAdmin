import Foundation

struct AdminDashboardStats: Equatable {
    var totalUsers: Int = 0
    var activeUsers: Int = 0
    var onlineUsers: Int = 0
    var pendingReports: Int = 0
    var pendingSupportTickets: Int = 0
    var resolvedSupportTickets: Int = 0
    var newRegistrationsToday: Int = 0
    var activeBans: Int = 0
    var activeFreezes: Int = 0
    var reportsResolvedToday: Int = 0

    static let empty = AdminDashboardStats()
}

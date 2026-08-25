import Foundation

struct SupportTicket: Identifiable, Equatable {
    let id: String
    /// Human-readable ticket number (e.g. `24082026-82134`), from Firestore `ticketId`.
    let ticketNumber: String
    let userId: String
    let userName: String
    let userEmail: String
    let topic: String
    let message: String
    let status: String
    let createdAt: Date?
    let resolvedAt: Date?

    var isOpen: Bool {
        let normalized = status.lowercased()
        return normalized != "resolved" && normalized != "closed"
    }

    var statusLabelKey: String {
        isOpen ? "admin.support.status.new" : "admin.support.status.resolved"
    }

    /// Prefer the DB ticket number; fall back to the Firestore document id.
    var displayTicketNumber: String {
        let trimmed = ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }
}

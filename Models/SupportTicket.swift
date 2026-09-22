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
    /// Optional image attachment download URL (`imageURL` in Firestore).
    let imageURL: String?
    let status: String
    let createdAt: Date?
    let resolvedAt: Date?
    let updatedAt: Date?
    /// Admin reply body emailed when the ticket was marked resolved.
    let adminReply: String?

    var isOpen: Bool {
        let normalized = status.lowercased()
        return normalized != "resolved" && normalized != "closed"
    }

    var statusLabelKey: String {
        isOpen ? "admin.support.status.new" : "admin.support.status.resolved"
    }

    var hasImageAttachment: Bool {
        guard let imageURL else { return false }
        return !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Prefer email in the support list whenever it is available.
    var displaySenderLabel: String {
        let email = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.contains("@") {
            return email
        }
        return userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detail “From” — real name when known, otherwise email.
    var displayFromLabel: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !Self.isPlaceholderName(name) {
            return name
        }
        return displaySenderLabel
    }

    /// Prefer the stable human ticket number (e.g. `21092026-96479`).
    /// Never treat the Firestore document id as the ticket number when a real one exists.
    var displayTicketNumber: String {
        let trimmed = ticketNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != id {
            return trimmed
        }
        return id
    }

    /// True when `ticketNumber` looks like `ddMMyyyy-#####`.
    var hasHumanTicketNumber: Bool {
        Self.isHumanTicketNumber(ticketNumber)
    }

    static func isHumanTicketNumber(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d{8}-\d{5}$"#, options: .regularExpression) != nil
    }

    static func makeSupportTicketId(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "ddMMyyyy"
        let datePart = formatter.string(from: date)
        let randomPart = String(format: "%05d", Int.random(in: 0...99_999))
        return "\(datePart)-\(randomPart)"
    }

    /// Newest activity first — resolved tickets use resolve time.
    var listSortDate: Date {
        if !isOpen {
            return resolvedAt ?? updatedAt ?? createdAt ?? .distantPast
        }
        return createdAt ?? updatedAt ?? .distantPast
    }

    var needsProfileEnrichment: Bool {
        Self.isPlaceholderName(userName) || userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func withAdminReply(_ reply: String) -> SupportTicket {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return SupportTicket(
            id: id,
            ticketNumber: ticketNumber,
            userId: userId,
            userName: userName,
            userEmail: userEmail,
            topic: topic,
            message: message,
            imageURL: imageURL,
            status: status,
            createdAt: createdAt,
            resolvedAt: resolvedAt ?? Date(),
            updatedAt: updatedAt ?? Date(),
            adminReply: trimmed.isEmpty ? adminReply : trimmed
        )
    }

    static func isPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.caseInsensitiveCompare("Unknown") == .orderedSame
            || trimmed.caseInsensitiveCompare("Unknown User") == .orderedSame
            || trimmed.caseInsensitiveCompare("SpectRoom User") == .orderedSame
    }
}

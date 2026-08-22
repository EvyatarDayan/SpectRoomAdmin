import Foundation

struct BlockedUser: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var blockedAt: Date?
    
    init(id: String, name: String, blockedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.blockedAt = blockedAt
    }
}


//
//  Match.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation

struct Match: Identifiable, Codable {
    let id: UUID
    let user1Id: UUID
    let user2Id: UUID
    let matchedAt: Date
    var isActive: Bool
    var lastMessageAt: Date?
    var conversationId: UUID?
    
    init(user1Id: UUID, user2Id: UUID) {
        self.id = UUID()
        self.user1Id = user1Id
        self.user2Id = user2Id
        self.matchedAt = Date()
        self.isActive = true
        self.lastMessageAt = nil
        self.conversationId = UUID()
    }
}

struct Like: Identifiable, Codable {
    let id: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let createdAt: Date
    var isSuperLike: Bool
    
    init(fromUserId: UUID, toUserId: UUID, isSuperLike: Bool = false) {
        self.id = UUID()
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.createdAt = Date()
        self.isSuperLike = isSuperLike
    }
}

struct SwipeAction: Identifiable, Codable {
    let id: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let action: SwipeType
    let createdAt: Date
    
    init(fromUserId: UUID, toUserId: UUID, action: SwipeType) {
        self.id = UUID()
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.action = action
        self.createdAt = Date()
    }
}

enum SwipeType: String, CaseIterable, Codable {
    case like = "like"
    case pass = "pass"
    case superLike = "super_like"
    
    var displayName: String {
        switch self {
        case .like:
            return "Like"
        case .pass:
            return "Pass"
        case .superLike:
            return "Super Like"
        }
    }
    
    var icon: String {
        switch self {
        case .like:
            return "heart.fill"
        case .pass:
            return "xmark"
        case .superLike:
            return "star.fill"
        }
    }
    
    var color: String {
        switch self {
        case .like:
            return "red"
        case .pass:
            return "gray"
        case .superLike:
            return "blue"
        }
    }
}

struct MatchDisplay: Identifiable {
    let id: String
    let otherUser: ProfileCard
    let matchedAt: Date
    let lastMessageAt: Date?
    
    init(id: String, otherUser: ProfileCard, matchedAt: Date, lastMessageAt: Date? = nil) {
        self.id = id
        self.otherUser = otherUser
        self.matchedAt = matchedAt
        self.lastMessageAt = lastMessageAt
    }
}

struct ProfileCard: Codable {
    let userId: String // Firebase UID
    let name: String
    let age: Int
    let bio: String
    let interests: [String]
    let distance: String
    let imageURL: String?
    let gender: String
    let interestedIn: [String]
    let lookingFor: [String]
    let photos: [String]
    let lifestyle: String
    let shareLifestyle: Bool
    let bodyType: String
    let shareBodyType: Bool
    let preferredAgeMin: Int
    let preferredAgeMax: Int
    let isOnline: Bool
    let lastSeen: Date
    let idealFirstDate: [String]
    let shareIdealFirstDate: Bool
    let sensoryPreferences: [String]
    let shareSensoryPreferences: Bool
    var energyLevel: Int
    let matchPercentage: Int
    
    init(
        userId: String,
        name: String,
        age: Int,
        bio: String,
        interests: [String],
        distance: String,
        imageURL: String?,
        gender: String,
        interestedIn: [String],
        lookingFor: [String],
        photos: [String],
        lifestyle: String,
        shareLifestyle: Bool,
        bodyType: String,
        shareBodyType: Bool,
        preferredAgeMin: Int,
        preferredAgeMax: Int,
        isOnline: Bool,
        lastSeen: Date,
        idealFirstDate: [String],
        shareIdealFirstDate: Bool,
        sensoryPreferences: [String] = [],
        shareSensoryPreferences: Bool = false,
        energyLevel: Int,
        matchPercentage: Int = 0
    ) {
        self.userId = userId
        self.name = name
        self.age = age
        self.bio = bio
        self.interests = interests
        self.distance = distance
        self.imageURL = imageURL
        self.gender = gender
        self.interestedIn = interestedIn
        self.lookingFor = lookingFor
        self.photos = photos
        self.lifestyle = lifestyle
        self.shareLifestyle = shareLifestyle
        self.bodyType = bodyType
        self.shareBodyType = shareBodyType
        self.preferredAgeMin = preferredAgeMin
        self.preferredAgeMax = preferredAgeMax
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.idealFirstDate = idealFirstDate
        self.shareIdealFirstDate = shareIdealFirstDate
        self.sensoryPreferences = sensoryPreferences
        self.shareSensoryPreferences = shareSensoryPreferences
        self.energyLevel = energyLevel
        self.matchPercentage = matchPercentage
    }
    
    struct MatchBreakdown {
        let percentage: Int
        let commonInterests: [String]
        let commonLookingFor: [String]
        let commonSensoryPreferences: [String]
        /// Shared lifestyle raw value when both share the same one; otherwise nil.
        let sharedLifestyle: String?
        let commonIdealFirstDates: [String]
        /// Positive = you are older; negative = you are younger; 0 = same age.
        let ageDeltaFromYou: Int
    }
    
    static func calculateMatchBreakdown(
        interests: [String],
        age: Int,
        gender: String,
        lookingFor: [String] = [],
        sensoryPreferences: [String] = [],
        shareSensoryPreferences: Bool = false,
        lifestyle: String = "",
        shareLifestyle: Bool = false,
        idealFirstDate: [String] = [],
        shareIdealFirstDate: Bool = false,
        currentUser: SpectRoomUser
    ) -> MatchBreakdown {
        // Gender is part of discover filtering, not the visible match score.
        _ = gender
        
        var matchScore = 0
        let totalFactors = 100
        
        let currentUserInterests = Set(currentUser.interests)
        let profileInterests = Set(interests)
        let commonInterests = Array(currentUserInterests.intersection(profileInterests)).sorted()
        let interestsMatch = commonInterests.count > 0
            ? Double(commonInterests.count) / Double(max(currentUserInterests.count, profileInterests.count))
            : 0.0
        matchScore += Int(interestsMatch * 25)
        
        let ageDeltaFromYou = currentUser.age - age
        let ageDifference = abs(ageDeltaFromYou)
        let ageMatch = max(0, 1.0 - Double(ageDifference) / 20.0)
        matchScore += Int(ageMatch * 20)
        
        let currentLookingFor = normalizedLookingForValues(currentUser.lookingFor)
        let otherLookingFor = normalizedLookingForValues(lookingFor)
        var commonLookingFor: [String] = []
        if !currentLookingFor.isEmpty && !otherLookingFor.isEmpty {
            commonLookingFor = Array(currentLookingFor.intersection(otherLookingFor)).sorted()
            let lookingForMatch = commonLookingFor.count > 0
                ? Double(commonLookingFor.count) / Double(max(currentLookingFor.count, otherLookingFor.count))
                : 0.0
            matchScore += Int(lookingForMatch * 15)
        }
        
        let currentUserSharesSensory = currentUser.shareSensoryPreferences && !currentUser.sensoryPreferences.isEmpty
        let otherSharesSensory = shareSensoryPreferences && !sensoryPreferences.isEmpty
        var commonSensoryPreferences: [String] = []
        if currentUserSharesSensory && otherSharesSensory {
            let currentSensory = Set(currentUser.sensoryPreferences)
            let otherSensory = Set(sensoryPreferences)
            commonSensoryPreferences = Array(currentSensory.intersection(otherSensory)).sorted()
            let sensoryMatch = commonSensoryPreferences.count > 0
                ? Double(commonSensoryPreferences.count) / Double(max(currentSensory.count, otherSensory.count))
                : 0.0
            matchScore += Int(sensoryMatch * 15)
        }
        
        let sharedLifestyle = sharedLifestyleValue(
            currentLifestyle: currentUser.lifestyle,
            currentShares: currentUser.shareLifestyle,
            otherLifestyle: lifestyle,
            otherShares: shareLifestyle
        )
        if sharedLifestyle != nil {
            matchScore += 15
        }
        
        let currentUserSharesFirstDate = currentUser.shareIdealFirstDate && !currentUser.idealFirstDate.isEmpty
        let otherSharesFirstDate = shareIdealFirstDate && !idealFirstDate.isEmpty
        var commonIdealFirstDates: [String] = []
        if currentUserSharesFirstDate && otherSharesFirstDate {
            let currentDates = Set(currentUser.idealFirstDate)
            let otherDates = Set(idealFirstDate)
            commonIdealFirstDates = Array(currentDates.intersection(otherDates)).sorted()
            let firstDateMatch = commonIdealFirstDates.count > 0
                ? Double(commonIdealFirstDates.count) / Double(max(currentDates.count, otherDates.count))
                : 0.0
            matchScore += Int(firstDateMatch * 10)
        }
        
        let percentage = Int((Double(matchScore) / Double(totalFactors)) * 100)
        return MatchBreakdown(
            percentage: min(max(percentage, 0), 95),
            commonInterests: commonInterests,
            commonLookingFor: commonLookingFor,
            commonSensoryPreferences: commonSensoryPreferences,
            sharedLifestyle: sharedLifestyle,
            commonIdealFirstDates: commonIdealFirstDates,
            ageDeltaFromYou: ageDeltaFromYou
        )
    }
    
    /// Canonical looking-for values for scoring; excludes "Not sure yet".
    private static func normalizedLookingForValues(_ values: [String]) -> Set<String> {
        Set(values.compactMap { value -> String? in
            switch value {
            case "Romantic relationship", "Relationship":
                return "Relationship"
            case "In-Person Friendship", "Friendship":
                return "Friendship"
            case "Online Friendship":
                return "Online Friendship"
            case "Hobby Buddy":
                return "Hobby Buddy"
            case "Not Sure Yet", "Not sure yet":
                return nil
            default:
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        })
    }
    
    private static func sharedLifestyleValue(
        currentLifestyle: String,
        currentShares: Bool,
        otherLifestyle: String,
        otherShares: Bool
    ) -> String? {
        guard currentShares, otherShares else { return nil }
        let current = currentLifestyle.trimmingCharacters(in: .whitespacesAndNewlines)
        let other = otherLifestyle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, !other.isEmpty else { return nil }
        guard current != "preferNot", other != "preferNot" else { return nil }
        return current == other ? current : nil
    }
    
    static func calculateMatchPercentage(
        interests: [String],
        age: Int,
        gender: String,
        lookingFor: [String] = [],
        sensoryPreferences: [String] = [],
        shareSensoryPreferences: Bool = false,
        lifestyle: String = "",
        shareLifestyle: Bool = false,
        idealFirstDate: [String] = [],
        shareIdealFirstDate: Bool = false,
        currentUser: SpectRoomUser
    ) -> Int {
        calculateMatchBreakdown(
            interests: interests,
            age: age,
            gender: gender,
            lookingFor: lookingFor,
            sensoryPreferences: sensoryPreferences,
            shareSensoryPreferences: shareSensoryPreferences,
            lifestyle: lifestyle,
            shareLifestyle: shareLifestyle,
            idealFirstDate: idealFirstDate,
            shareIdealFirstDate: shareIdealFirstDate,
            currentUser: currentUser
        ).percentage
    }
}


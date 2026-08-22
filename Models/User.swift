//
//  User.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation

struct SpectRoomUser: Identifiable, Codable, Equatable {
    let id: UUID
    var firebaseDocumentId: String? // Firebase document ID
    var name: String
    var age: Int
    var dateOfBirth: Date? // Actual date of birth from user selection
    var email: String
    var bio: String
    var interests: [String]
    var profilePhotoURL: String? // URL to profile photo
    var photos: [String] // URLs to gallery photos
    var blockedUsers: [BlockedUser] = []
    var blockedByUsers: [BlockedUser] = []
    var location: Location
    var preferences: UserPreferences
    var isOnline: Bool
    var lastSeen: Date
    var createdAt: Date
    var gender: String // "Man", "Woman", or custom text
    var interestedIn: [String] // Array of genders user is interested in
    var lookingFor: [String] // Array of what user is looking for
    var preferredAgeMin: Int // Minimum preferred age
    var preferredAgeMax: Int // Maximum preferred age
    var lifestyle: String = "" // Lifestyle selection
    var shareLifestyle: Bool = false // Whether to share lifestyle
    var bodyType: String = "" // Body type selection
    var shareBodyType: Bool = false // Whether to share body type
    var idealFirstDate: [String] = [] // Ideal first date selections (multiple)
    var shareIdealFirstDate: Bool = false // Whether to share ideal first date
    var sensoryPreferences: [String] = [] // Sensory preference selections (multiple)
    var shareSensoryPreferences: Bool = false // Whether to share sensory preferences
    var energyLevel: Int = 4 // 0 Low Battery, 2 Moderate Social, 4 Fully Social Mode
    
    init(name: String, age: Int, email: String, bio: String = "", interests: [String] = [], location: Location = Location(), preferences: UserPreferences = UserPreferences(), gender: String = "", interestedIn: [String] = [], lookingFor: [String] = [], preferredAgeMin: Int? = nil, preferredAgeMax: Int? = nil, lifestyle: String = "", shareLifestyle: Bool = false, bodyType: String = "", shareBodyType: Bool = false, idealFirstDate: [String] = [], shareIdealFirstDate: Bool = false, sensoryPreferences: [String] = [], shareSensoryPreferences: Bool = false, energyLevel: Int = 4) {
        self.id = UUID()
        self.name = name
        self.age = age
        self.dateOfBirth = nil // Will be set when user selects date
        self.email = email
        self.bio = bio
        self.interests = interests
        self.profilePhotoURL = nil
        self.photos = []
        self.blockedUsers = []
        self.blockedByUsers = []
        self.location = location
        self.preferences = preferences
        self.isOnline = false
        self.lastSeen = Date()
        self.createdAt = Date()
        self.gender = gender
        self.interestedIn = interestedIn
        self.lookingFor = lookingFor
        // Set default preferred age range based on user's age
        self.preferredAgeMin = preferredAgeMin ?? age
        self.preferredAgeMax = preferredAgeMax ?? min(age + 5, 80) // Cap at 80
        self.lifestyle = lifestyle
        self.shareLifestyle = shareLifestyle
        self.bodyType = bodyType
        self.shareBodyType = shareBodyType
        self.idealFirstDate = idealFirstDate
        self.shareIdealFirstDate = shareIdealFirstDate
        self.sensoryPreferences = sensoryPreferences
        self.shareSensoryPreferences = shareSensoryPreferences
        self.energyLevel = energyLevel
    }
}

struct Location: Codable, Equatable {
    var displayString: String
    var city: String
    var state: String
    var country: String
    var latitude: Double?
    var longitude: Double?
    
    init(displayString: String = "", city: String = "", state: String = "", country: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.displayString = displayString
        self.city = city
        self.state = state
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct UserPreferences: Codable, Equatable {
    var ageRange: ClosedRange<Int>
    var maxDistance: Int // in kilometers
    var showOnlineOnly: Bool
    var interests: [String]
    var communicationStyle: CommunicationStyle
    var notificationSettings: NotificationSettings
    
    init(ageRange: ClosedRange<Int> = 18...35, maxDistance: Int = 50, showOnlineOnly: Bool = false, interests: [String] = [], communicationStyle: CommunicationStyle = .text, notificationSettings: NotificationSettings = NotificationSettings()) {
        self.ageRange = ageRange
        self.maxDistance = maxDistance
        self.showOnlineOnly = showOnlineOnly
        self.interests = interests
        self.communicationStyle = communicationStyle
        self.notificationSettings = notificationSettings
    }
}

enum CommunicationStyle: String, CaseIterable, Codable, Equatable {
    case text = "Text Only"
    case voice = "Voice Messages"
    case video = "Video Calls"
    case mixed = "Mixed Communication"
    
    var description: String {
        switch self {
        case .text:
            return "I prefer text-based communication"
        case .voice:
            return "I'm comfortable with voice messages"
        case .video:
            return "I enjoy video calls"
        case .mixed:
            return "I'm flexible with communication methods"
        }
    }
}

struct NotificationSettings: Codable, Equatable {
    var newMatches: Bool
    var newMessages: Bool
    var profileViews: Bool
    var likes: Bool
    var soundEnabled: Bool
    var vibrationEnabled: Bool
    
    init(newMatches: Bool = true, newMessages: Bool = true, profileViews: Bool = false, likes: Bool = true, soundEnabled: Bool = true, vibrationEnabled: Bool = true) {
        self.newMatches = newMatches
        self.newMessages = newMessages
        self.profileViews = profileViews
        self.likes = likes
        self.soundEnabled = soundEnabled
        self.vibrationEnabled = vibrationEnabled
    }
}

//
//  DiscoverRadiusCounter.swift
//  SpectRoom
//
//  Counts discover-eligible profiles within a search radius (for Profile radius preview).
//

import Foundation

enum DiscoverRadiusCounter {
    private static let pageSize = 40
    private static let maxPages = 50
    
    static func countEligibleProfiles(
        currentUser: SpectRoomUser,
        option: DiscoverDistanceOption,
        blockedUserIds: Set<String>
    ) async -> Int {
        do {
            let swipeFilter = try await FirebaseAuthService.shared.fetchSwipeFilterState(preferServer: false)
            var cursor: String?
            var hasMore = true
            var pages = 0
            var count = 0
            var seen = Set<String>()
            
            while hasMore && pages < maxPages {
                if Task.isCancelled { return count }
                
                let page = try await FirebaseAuthService.shared.fetchUsersPage(
                    limit: pageSize,
                    startAfterDocumentId: cursor
                )
                pages += 1
                cursor = page.lastDocumentId
                hasMore = page.hasMore
                
                for user in page.users {
                    let userId = user.firebaseDocumentId ?? user.id.uuidString
                    guard seen.insert(userId).inserted else { continue }
                    if isEligible(
                        user: user,
                        currentUser: currentUser,
                        likedUserIds: swipeFilter.likedUserIds,
                        passedUserIds: swipeFilter.passedUserIds,
                        blockedUserIds: blockedUserIds,
                        option: option
                    ) {
                        count += 1
                    }
                }
            }
            
            return count
        } catch {
            print("⚠️ DiscoverRadiusCounter failed: \(error.localizedDescription)")
            return 0
        }
    }
    
    private static func isEligible(
        user: SpectRoomUser,
        currentUser: SpectRoomUser,
        likedUserIds: Set<String>,
        passedUserIds: Set<String>,
        blockedUserIds: Set<String>,
        option: DiscoverDistanceOption
    ) -> Bool {
        let userId = user.firebaseDocumentId ?? user.id.uuidString
        if blockedUserIds.contains(userId) { return false }
        if likedUserIds.contains(userId) { return false }
        if passedUserIds.contains(userId) { return false }
        if !matchesDistance(currentUser: currentUser, otherUser: user, option: option) {
            return false
        }
        
        let currentLookingFor = Set(currentUser.lookingFor.filter { $0 != "Not sure yet" && $0 != "Not Sure Yet" })
        if !currentLookingFor.isEmpty {
            let otherLookingFor = Set(user.lookingFor.filter { $0 != "Not sure yet" && $0 != "Not Sure Yet" })
            if !otherLookingFor.isEmpty && currentLookingFor.intersection(otherLookingFor).isEmpty {
                return false
            }
        }
        
        if !matchesGender(currentUser: currentUser, otherUser: user) { return false }
        if !matchesAge(currentUser: currentUser, otherUser: user) { return false }
        return true
    }
    
    private static func matchesDistance(
        currentUser: SpectRoomUser,
        otherUser: SpectRoomUser,
        option: DiscoverDistanceOption
    ) -> Bool {
        guard let maxKm = option.maxKilometers else { return true }
        guard let distanceKm = haversineKm(from: currentUser.location, to: otherUser.location) else {
            return false
        }
        return distanceKm <= maxKm
    }
    
    private static func haversineKm(from source: Location, to target: Location) -> Double? {
        guard let sourceLat = source.latitude,
              let sourceLon = source.longitude,
              let targetLat = target.latitude,
              let targetLon = target.longitude else {
            return nil
        }
        
        let earthRadius = 6371.0
        let dLat = (targetLat - sourceLat) * .pi / 180.0
        let dLon = (targetLon - sourceLon) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(sourceLat * .pi / 180.0) * cos(targetLat * .pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
    
    private static func matchesGender(currentUser: SpectRoomUser, otherUser: SpectRoomUser) -> Bool {
        let currentGender = currentUser.gender
        let otherGender = otherUser.gender
        let currentInterestedIn = Set(currentUser.interestedIn)
        let otherInterestedIn = Set(otherUser.interestedIn)
        
        if currentGender.isEmpty || otherGender.isEmpty || currentInterestedIn.isEmpty || otherInterestedIn.isEmpty {
            return true
        }
        
        let currentMatchesOther = otherInterestedIn.contains("Anyone") || otherInterestedIn.contains(currentGender)
        let otherMatchesCurrent = currentInterestedIn.contains("Anyone") || currentInterestedIn.contains(otherGender)
        return currentMatchesOther && otherMatchesCurrent
    }
    
    private static func matchesAge(currentUser: SpectRoomUser, otherUser: SpectRoomUser) -> Bool {
        let preferredMin = currentUser.preferredAgeMin
        let preferredMax = currentUser.preferredAgeMax
        if (preferredMin == 0 && preferredMax == 0) || preferredMax < preferredMin {
            return true
        }
        return otherUser.age >= preferredMin && otherUser.age <= preferredMax
    }
}

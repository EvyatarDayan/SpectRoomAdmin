//
//  AppStateManager.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation
import SwiftUI
import FirebaseAuth
import Combine
import UIKit

struct DiscoverDeckFilterSignature: Codable, Equatable {
    let preferredAgeMin: Int
    let preferredAgeMax: Int
    let gender: String
    let interestedIn: [String]
    let lookingFor: [String]
    let locationLatitude: Double?
    let locationLongitude: Double?
    let distanceLimitRawValue: Int
}

class AppStateManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasResolvedAuthState = false
    @Published var hasResolvedUserProfile = false
    @Published var hasCompletedInitialProfile = false
    @Published var isNewSignup = false
    @Published var signUpName: String = ""
    @Published var currentUser: SpectRoomUser?
    @Published var matches: [Match] = []
    @Published var conversations: [Conversation] = []
    @Published var cachedMatches: [MatchDisplay] = [] // Cache for matches list
    @Published var cachedMessageConversations: [MessageDisplay] = [] // Cache for message conversations list
    @Published var cachedDiscoverProfiles: [ProfileCard] = []
    @Published var cachedDiscoverCardIndex: Int = 0
    @Published private(set) var discoverDeckRefreshID = UUID()
    /// Profiles removed from Home only because of a block — restored to the pile on unblock.
    @Published private(set) var discoverProfilesHeldByBlock: [String: ProfileCard] = [:]
    @Published private(set) var pendingDiscoverUnblockRestoreUserId: String?
    private var isDiscoverProfilesCacheValid = false
    private var cachedDiscoverFilterSignature: DiscoverDeckFilterSignature?
    @Published var blockedUsers: [BlockedUser] = []
    @Published var blockedByUsers: [BlockedUser] = []
    @Published private(set) var suppressedBlockedAlertUserIds: Set<String> = []
    @Published var authErrorMessage: String?
    @Published var pendingModerationNotice: ModerationNotice?
    /// Switch footer tab from nested sheets (e.g. report email → All Profiles).
    @Published var requestedAdminTab: Int?
    /// Prefill All Profiles search after navigating from another admin screen.
    @Published var pendingProfilesSearchQuery: String?
    /// Pending reports the admin has not opened yet (Restrict / reports badge).
    @Published var unseenAdminReportCount: Int = 0
    @Published private(set) var unseenAdminReportIds: Set<String> = []
    private var pendingAdminReportIds: Set<String> = []
    private var seenAdminReportIds: Set<String> = []
    private let seenAdminReportsStorageKeyPrefix = "admin.seenReportIds."
    private var lastMatchesUpdate: Date?
    private var lastMessageConversationsUpdate: Date?
    
    // Cache for individual conversation messages (keyed by otherUserId)
    private var cachedConversationStates: [String: CachedConversationState] = [:]
    @Published var isLoading = false
    
    // Match notification properties
    @Published var showingMatchNotification = false
    @Published var newMatchProfile: ProfileCard?
    @Published var shouldOpenMessageModal = false
    @Published var viewedMatchProfileId: String? = nil // Track when a match profile is viewed
    private var lastMatchId: String?
    private var isShowingSwipeMatchPopup = false
    
    // New message notification properties
    @Published var showingNewMessageNotification = false
    @Published var newMessageSenderName: String = ""
    @Published var newMessageSenderPhotoURL: String?
    @Published var newMessageSenderId: String = ""
    @Published var shouldOpenConversation = false
    @Published var conversationToOpenSenderId: String? = nil
    @Published var conversationToOpenProfile: ProfileCard? = nil
    @Published var currentlyOpenConversationSenderId: String? = nil // Track which conversation is currently open
    @Published private(set) var isMessagesTabActive = false
    @Published var unreadMessageCount: Int = 0
    @Published var conversationUnreadCounts: [String: Int] = [:]
    private var lastMessageId: String?
    private var lastPlayedMessageSoundId: String?
    /// Skip the in-app chime briefly after opening a chat from a notification
    /// (the message is already known; playing again feels like a duplicate).
    private var suppressIncomingMessageSoundUntil: Date?
    
    private let firebaseAuth = FirebaseAuthService.shared
    private var cancellables = Set<AnyCancellable>()
    private let newMessageReceivedSubject = PassthroughSubject<MessageDisplay, Never>()
    var newMessageReceivedPublisher: AnyPublisher<MessageDisplay, Never> {
        newMessageReceivedSubject.eraseToAnyPublisher()
    }
    private let newMatchReceivedSubject = PassthroughSubject<MatchDisplay, Never>()
    var newMatchReceivedPublisher: AnyPublisher<MatchDisplay, Never> {
        newMatchReceivedSubject.eraseToAnyPublisher()
    }
    
    static let shared = AppStateManager()
    
    private init() {
        // Listen to Firebase authentication state changes
        // Ensure all updates happen on the main thread to avoid publishing from background threads
        // Mirror Firebase auth immediately so launch routing does not wait on the Combine subscription.
        isAuthenticated = firebaseAuth.isAuthenticated
        hasResolvedAuthState = firebaseAuth.hasResolvedAuthState
        hasResolvedUserProfile = firebaseAuth.hasResolvedUserProfile
        
        firebaseAuth.$hasResolvedAuthState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] resolved in
                self?.hasResolvedAuthState = resolved
            }
            .store(in: &cancellables)
        
        firebaseAuth.$hasResolvedUserProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] resolved in
                self?.hasResolvedUserProfile = resolved
            }
            .store(in: &cancellables)
        
        firebaseAuth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                let wasAuthenticated = self?.isAuthenticated ?? false
                self?.isAuthenticated = isAuth
                if isAuth {
                    if !wasAuthenticated, self?.firebaseAuth.currentUser == nil {
                        // New login: keep home on the spinner until this account's profile loads.
                        self?.hasResolvedUserProfile = false
                    }
                    self?.restoreSignupNameFromAuthIfNeeded()
                    // User is authenticated - set online status and preload photos
                    Task {
                        await self?.updateOnlineStatus(isOnline: true)
                        await self?.preloadUserPhotos()
                    }
                    self?.loadPersistedDiscoverProfilesCacheIfNeeded()
                    // Start listening for new matches when authenticated
                    // This will notify users when they receive a match (even if they didn't swipe)
                    self?.startListeningForMatches()
                    // Start listening for new messages when authenticated
                    // This will notify users when they receive a new message
                    self?.startListeningForNewMessages()
                    self?.startListeningForBlockedByUsers()
                    self?.startListeningForModerationStatus()
                    self?.startListeningForPendingAdminReportsIfNeeded()
                    self?.refreshUnreadMessageCount()
                } else {
                    // Set offline status before clearing data
                    Task {
                        await self?.updateOnlineStatus(isOnline: false)
                    }
                    self?.firebaseAuth.stopListeningForBlockedByUsers()
                    self?.firebaseAuth.stopListeningForModerationStatus()
                    self?.firebaseAuth.stopListeningForPendingAdminReports()
                    self?.pendingAdminReportIds = []
                    self?.seenAdminReportIds = []
                    self?.unseenAdminReportIds = []
                    self?.unseenAdminReportCount = 0
                    // Keep login-blocked freeze notice so the user can still dismiss it after sign-out.
                    if case .loginBlocked = self?.pendingModerationNotice?.kind {
                        // leave notice
                    } else {
                        self?.pendingModerationNotice = nil
                    }
                    // Clear user data when not authenticated to prevent stale data
                    self?.currentUser = nil
                    self?.unreadMessageCount = 0
                    self?.clearMessageConversationsCache() // Clear message conversations cache
                    // Keep persisted discover deck on disk so a daily-limit freeze survives relaunch.
                    // Explicit sign-out / reset clears the persisted cache separately.
                    self?.cachedDiscoverProfiles = []
                    self?.cachedDiscoverCardIndex = 0
                    self?.isDiscoverProfilesCacheValid = false
                    Task { @MainActor in
                        NotificationService.shared.setAppIconBadgeCount(0)
                    }
                    print("🔐 User logged out - cleared all user data")
                }
            }
            .store(in: &cancellables)
        
        // Listen to Firebase user changes
        // Ensure all updates happen on the main thread to avoid publishing from background threads
        firebaseAuth.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newUser in
                self?.currentUser = newUser
                if let user = newUser {
                    print("🔄 AppStateManager: Updated currentUser with \(user.photos.count) photos")
                    self?.blockedUsers = user.blockedUsers
                    self?.blockedByUsers = user.blockedByUsers
                    self?.loadSuppressedBlockedAlerts()
                    self?.syncInitialProfileCompletionIfNeeded()
                    self?.startListeningForPendingAdminReportsIfNeeded()
                } else {
                    self?.blockedUsers = []
                    self?.blockedByUsers = []
                    self?.discoverProfilesHeldByBlock = [:]
                    self?.pendingDiscoverUnblockRestoreUserId = nil
                    self?.suppressedBlockedAlertUserIds = []
                    self?.firebaseAuth.stopListeningForPendingAdminReports()
                    self?.pendingAdminReportIds = []
                    self?.seenAdminReportIds = []
                    self?.unseenAdminReportIds = []
                    self?.unseenAdminReportCount = 0
                }
            }
            .store(in: &cancellables)
        
        // Note: Sound is now played when push notification is received (handled by iOS)
        
        // Load saved state if available (but not authentication state)
        loadAppState()
        
        // Clear any stale authentication data on app start
        clearStaleAuthData()
    }
    
    // MARK: - Authentication
    func signIn(email: String, password: String) {
        isLoading = true
        
        // Check for empty fields - treat as invalid credentials
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedEmail.isEmpty || trimmedPassword.isEmpty {
            // Treat empty fields as invalid credentials
            Task { @MainActor in
                self.isLoading = false
                let currentAttempts = UserDefaults.standard.integer(forKey: "failedSignInAttempts")
                let newAttempts = currentAttempts + 1
                UserDefaults.standard.set(newAttempts, forKey: "failedSignInAttempts")
                
                // Show extended message every 5th time (5th, 10th, 15th, etc.)
                if newAttempts % 5 == 0 {
                    self.authErrorMessage = "auth.error.credentials.with.forgot".localized
                } else {
                    self.authErrorMessage = "auth.error.credentials".localized
                }
            }
            return
        }
        
        Task {
            do {
                try await firebaseAuth.signIn(email: trimmedEmail, password: trimmedPassword)
                await MainActor.run {
                    self.isLoading = false
                    // Reset failed sign-in attempts counter on successful sign-in
                    UserDefaults.standard.set(0, forKey: "failedSignInAttempts")
                }
            } catch let error as SpectRoomAuthError {
                await MainActor.run {
                    self.isLoading = false
                    // Soft-deleted accounts look like invalid credentials (don't reveal account status).
                    if case .accountPendingDeletion = error {
                        let currentAttempts = UserDefaults.standard.integer(forKey: "failedSignInAttempts")
                        let newAttempts = currentAttempts + 1
                        UserDefaults.standard.set(newAttempts, forKey: "failedSignInAttempts")
                        if newAttempts % 5 == 0 {
                            self.authErrorMessage = "auth.error.credentials.with.forgot".localized
                        } else {
                            self.authErrorMessage = "auth.error.credentials".localized
                        }
                    } else if case .accountBanned = error {
                        self.authErrorMessage = nil
                        self.pendingModerationNotice = ModerationNotice(kind: .loginBanned)
                    } else if case .accountFrozen(let until) = error {
                        self.authErrorMessage = nil
                        self.pendingModerationNotice = ModerationNotice(kind: .loginBlocked(until: until))
                    } else {
                        self.authErrorMessage = error.errorDescription
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Sign in error: \(error.localizedDescription)")
                    
                    // Increment failed sign-in attempts counter
                    let currentAttempts = UserDefaults.standard.integer(forKey: "failedSignInAttempts")
                    let newAttempts = currentAttempts + 1
                    UserDefaults.standard.set(newAttempts, forKey: "failedSignInAttempts")
                    
                    // Show extended message every 5th time (5th, 10th, 15th, etc.)
                    if newAttempts % 5 == 0 {
                        self.authErrorMessage = "auth.error.credentials.with.forgot".localized
                    } else {
                        self.authErrorMessage = "auth.error.credentials".localized
                    }
                }
            }
        }
    }
    
    func deleteAccount(password: String) async throws {
        try await firebaseAuth.reauthenticate(withPassword: password)
        try await firebaseAuth.requestAccountDeletion()
    }
    
    func signUp(name: String, age: Int, email: String, password: String) {
        isLoading = true
        
        Task {
            do {
                try await firebaseAuth.signUp(email: email, password: password, name: name, age: age)
                await MainActor.run {
                    self.isLoading = false
                    // Admin app: skip consumer profile completion and open the main UI.
                    self.isNewSignup = false
                    self.signUpName = name
                    self.hasCompletedInitialProfile = true
                    self.saveAppState()
                    print("🆕 New admin user signed up — opening main app")
                }
            } catch let error as SpectRoomAuthError {
                await MainActor.run {
                    self.isLoading = false
                    self.authErrorMessage = error.errorDescription
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Sign up error: \(error.localizedDescription)")
                    self.authErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func signOut() {
        Task {
            do {
                try await firebaseAuth.signOut()
                await MainActor.run {
                    currentUser = nil
                    isNewSignup = false
                    signUpName = ""
                    hasCompletedInitialProfile = false
                    matches = []
                    cachedMatches = []
                    lastMatchesUpdate = nil
                    conversations = []
                    blockedUsers = []
                    blockedByUsers = []
                    discoverProfilesHeldByBlock = [:]
                    pendingDiscoverUnblockRestoreUserId = nil
                    clearMessageConversationsCache()
                    clearDiscoverProfilesCache()
                    
                    saveAppState()
                    print("🔐 User signed out successfully")
                }
            } catch {
                await MainActor.run {
                    print("Sign out error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    
    func resetPassword(email: String) {
        Task {
            do {
                try await firebaseAuth.resetPassword(email: email)
            } catch {
                print("Reset password error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - User Data
    // User data is now automatically synced with FirebaseAuthService via @Published properties
    
    func cleanupUserPhotos() {
        if var user = currentUser {
            let originalCount = user.photos.count
            user.photos = user.photos.filter { photoURL in
                let trimmedURL = photoURL.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmedURL.isEmpty && URL(string: trimmedURL) != nil
            }
            currentUser = user
            print("🧹 AppStateManager: Cleaned up photos from \(originalCount) to \(user.photos.count)")
            saveAppState()
        }
    }
    
    func isProfileComplete() -> Bool {
        guard let user = currentUser else { return false }
        
        let nameComponents = user.name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        let hasFullName = nameComponents.count >= 2 && nameComponents.allSatisfy { !$0.isEmpty }
        
        let hasValidAge = user.age >= 18
        
        let trimmedLocation = user.location.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLocation: Bool
        if trimmedLocation.isEmpty {
            hasLocation = false
        } else if let latitude = user.location.latitude, let longitude = user.location.longitude {
            hasLocation = SwedenLocation.contains(latitude: latitude, longitude: longitude)
        } else {
            hasLocation = true
        }
        
        let hasBio = user.bio.trimmingCharacters(in: .whitespacesAndNewlines).count >= 30
        
        let hasProfilePhoto: Bool = {
            if let profilePhotoURL = user.profilePhotoURL?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !profilePhotoURL.isEmpty,
               URL(string: profilePhotoURL) != nil {
                return true
            }
            return false
        }()
        
        let validPhotos = user.photos.filter { photoURL in
            let trimmedURL = photoURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedURL.isEmpty && URL(string: trimmedURL) != nil
        }
        let hasPhotos = validPhotos.count >= 2 && validPhotos.count <= 5
        
        let hasInterests = user.interests.count >= 3
        let hasGender = !user.gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasInterestedIn = !user.interestedIn.isEmpty
        let hasLookingFor = !user.lookingFor.isEmpty
        let hasIdealFirstDate = !user.idealFirstDate.isEmpty
        
        return hasFullName
            && hasValidAge
            && hasLocation
            && hasBio
            && hasProfilePhoto
            && hasPhotos
            && hasInterests
            && hasGender
            && hasInterestedIn
            && hasLookingFor
            && hasIdealFirstDate
    }
    
    func syncInitialProfileCompletionIfNeeded() {
        guard !hasCompletedInitialProfile else { return }
        guard isProfileComplete() else { return }
        hasCompletedInitialProfile = true
        isNewSignup = false
        saveAppState()
        print("✅ Synced initial profile completion from saved user data")
    }
    
    
    func restoreSignupNameFromAuthIfNeeded() {
        let existing = signUpName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing.isEmpty else { return }
        let authName = (firebaseAuth.auth.currentUser?.displayName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authName.isEmpty else { return }
        signUpName = authName
        saveAppState()
        print("📝 Restored signup name from Auth account: \(authName)")
    }
    
    func completeInitialProfile() {
        hasCompletedInitialProfile = true
        isNewSignup = false
        signUpName = "" // Clear the sign up name
        saveAppState()
        print("✅ Initial profile completed - user can now access main app")
    }
    
    /// Lets a new user browse the app before finishing mandatory profile setup.
    func deferInitialProfileCompletion() {
        guard isNewSignup else { return }
        isNewSignup = false
        saveAppState()
        print("📝 Deferred mandatory profile completion — user can finish profile later")
    }
    
    // MARK: - Matches
    func addMatch(_ match: Match) {
        matches.append(match)
        saveAppState()
    }
    
    func removeMatch(_ match: Match) {
        matches.removeAll { $0.id == match.id }
        saveAppState()
    }

    // MARK: - Matches Cache
    func getCachedOrFreshMatches() async throws -> [MatchDisplay] {
        if let lastUpdate = lastMatchesUpdate,
           Date().timeIntervalSince(lastUpdate) < 60,
           !cachedMatches.isEmpty {
            print("💕 Returning cached matches (\(cachedMatches.count) items, updated \(Date().timeIntervalSince(lastUpdate)) seconds ago)")
            return cachedMatches
        }
        return try await refreshMatchesCache()
    }
    
    @discardableResult
    func refreshMatchesCache() async throws -> [MatchDisplay] {
        print("💕 Refreshing matches cache...")
        let fetched = try await firebaseAuth.fetchMatches()
        await MainActor.run {
            cachedMatches = fetched
            lastMatchesUpdate = Date()
        }
        return fetched
    }
    
    func refreshCachedMatchEnergyLevels() async {
        let matches = await MainActor.run { cachedMatches }
        let userIds = matches.map(\.otherUser.userId)
        guard !userIds.isEmpty else { return }
        
        let levels = await firebaseAuth.fetchEnergyLevels(for: userIds)
        guard !levels.isEmpty else { return }
        
        await MainActor.run {
            var didChange = false
            cachedMatches = cachedMatches.map { match in
                guard let level = levels[match.otherUser.userId],
                      match.otherUser.energyLevel != level else {
                    return match
                }
                didChange = true
                var updatedUser = match.otherUser
                updatedUser.energyLevel = level
                return MatchDisplay(
                    id: match.id,
                    otherUser: updatedUser,
                    matchedAt: match.matchedAt,
                    lastMessageAt: match.lastMessageAt
                )
            }
            if didChange {
                print("💕 Updated energy levels for matches")
            }
        }
    }
    
    func updateMatchesCache(with match: MatchDisplay) {
        Task {
            await MainActor.run {
                if let index = cachedMatches.firstIndex(where: { $0.otherUser.userId == match.otherUser.userId }) {
                    cachedMatches[index] = match
                } else {
                    cachedMatches.insert(match, at: 0)
                }
                cachedMatches.sort { $0.matchedAt > $1.matchedAt }
                lastMatchesUpdate = Date()
                newMatchReceivedSubject.send(match)
            }
        }
    }

    // MARK: - Discover Profiles Cache
    func currentDiscoverFilterSignature() -> DiscoverDeckFilterSignature? {
        guard let user = currentUser else { return nil }
        return DiscoverDeckFilterSignature(
            preferredAgeMin: user.preferredAgeMin,
            preferredAgeMax: user.preferredAgeMax,
            gender: user.gender,
            interestedIn: user.interestedIn.sorted(),
            lookingFor: user.lookingFor.sorted(),
            locationLatitude: user.location.latitude,
            locationLongitude: user.location.longitude,
            distanceLimitRawValue: DiscoverDistanceLimit.currentOption.rawValue
        )
    }
    
    var hasValidDiscoverProfilesCache: Bool {
        guard isDiscoverProfilesCacheValid, !cachedDiscoverProfiles.isEmpty else { return false }
        guard let cached = cachedDiscoverFilterSignature,
              let current = currentDiscoverFilterSignature() else { return false }
        return cached == current
    }

    func updateDiscoverProfilesCache(profiles: [ProfileCard], cardIndex: Int) {
        guard !profiles.isEmpty else {
            clearDiscoverProfilesCache()
            return
        }
        cachedDiscoverProfiles = profiles
        // Allow index == count for the empty end-of-deck state.
        cachedDiscoverCardIndex = max(0, min(cardIndex, profiles.count))
        cachedDiscoverFilterSignature = currentDiscoverFilterSignature()
        isDiscoverProfilesCacheValid = true
        persistDiscoverProfilesCache()
    }

    func clearDiscoverProfilesCache() {
        cachedDiscoverProfiles = []
        cachedDiscoverCardIndex = 0
        cachedDiscoverFilterSignature = nil
        isDiscoverProfilesCacheValid = false
        clearPersistedDiscoverProfilesCache()
    }
    
    func invalidateDiscoverDeckAfterProfileUpdate() {
        if DiscoverDailyLimit.currentCount() >= DiscoverDailyLimit.maxSwipesPerDay {
            DiscoverDistanceLimit.hasPendingDeckRefresh = true
            print("🔍 Deferred discover deck refresh until daily swipe limit resets")
            return
        }
        
        DiscoverDistanceLimit.hasPendingDeckRefresh = false
        clearDiscoverProfilesCache()
        discoverDeckRefreshID = UUID()
        print("🔍 Invalidated discover deck after profile update")
    }
    
    private var discoverCacheAccountKey: String? {
        if let uid = firebaseAuth.auth.currentUser?.uid, !uid.isEmpty {
            return uid
        }
        if let email = firebaseAuth.auth.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !email.isEmpty {
            return email
        }
        return nil
    }
    
    private func discoverProfilesStorageKey(for accountKey: String) -> String {
        "discoverProfilesCache_\(accountKey)"
    }
    
    private func discoverCardIndexStorageKey(for accountKey: String) -> String {
        "discoverCardIndexCache_\(accountKey)"
    }
    
    private func discoverFilterSignatureStorageKey(for accountKey: String) -> String {
        "discoverFilterSignatureCache_\(accountKey)"
    }
    
    private func persistDiscoverProfilesCache() {
        guard let accountKey = discoverCacheAccountKey else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(cachedDiscoverProfiles) {
            UserDefaults.standard.set(data, forKey: discoverProfilesStorageKey(for: accountKey))
            UserDefaults.standard.set(cachedDiscoverCardIndex, forKey: discoverCardIndexStorageKey(for: accountKey))
        }
        if let signature = cachedDiscoverFilterSignature,
           let signatureData = try? encoder.encode(signature) {
            UserDefaults.standard.set(signatureData, forKey: discoverFilterSignatureStorageKey(for: accountKey))
        }
    }
    
    private func clearPersistedDiscoverProfilesCache() {
        guard let accountKey = discoverCacheAccountKey else { return }
        UserDefaults.standard.removeObject(forKey: discoverProfilesStorageKey(for: accountKey))
        UserDefaults.standard.removeObject(forKey: discoverCardIndexStorageKey(for: accountKey))
        UserDefaults.standard.removeObject(forKey: discoverFilterSignatureStorageKey(for: accountKey))
    }
    
    func loadPersistedDiscoverProfilesCacheIfNeeded() {
        guard !isDiscoverProfilesCacheValid || cachedDiscoverProfiles.isEmpty else { return }
        loadPersistedDiscoverProfilesCache()
    }
    
    private func loadPersistedDiscoverProfilesCache() {
        guard let accountKey = discoverCacheAccountKey else { return }
        let decoder = JSONDecoder()
        guard let signatureData = UserDefaults.standard.data(forKey: discoverFilterSignatureStorageKey(for: accountKey)),
              let signature = try? decoder.decode(DiscoverDeckFilterSignature.self, from: signatureData),
              signature == currentDiscoverFilterSignature() else {
            return
        }
        guard let data = UserDefaults.standard.data(forKey: discoverProfilesStorageKey(for: accountKey)),
              let profiles = try? decoder.decode([ProfileCard].self, from: data),
              !profiles.isEmpty else {
            return
        }
        let storedIndex = UserDefaults.standard.integer(forKey: discoverCardIndexStorageKey(for: accountKey))
        cachedDiscoverProfiles = profiles
        cachedDiscoverCardIndex = max(0, min(storedIndex, profiles.count))
        cachedDiscoverFilterSignature = signature
        isDiscoverProfilesCacheValid = true
        print("📱 Restored \(profiles.count) discover profiles from disk at index \(cachedDiscoverCardIndex)")
    }
    
    // MARK: - Conversations
    func addConversation(_ conversation: Conversation) {
        conversations.append(conversation)
        saveAppState()
    }
    
    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
            saveAppState()
        }
    }
    
    // MARK: - Persistence
    func saveAppState() {
        let encoder = JSONEncoder()
        
        if let userData = try? encoder.encode(currentUser) {
            UserDefaults.standard.set(userData, forKey: "currentUser")
        }
        
        // Don't save authentication state - Firebase handles this
        UserDefaults.standard.set(hasCompletedInitialProfile, forKey: "hasCompletedInitialProfile")
        UserDefaults.standard.set(isNewSignup, forKey: "isNewSignup")
        UserDefaults.standard.set(signUpName, forKey: "signUpName")
        
        if let matchesData = try? encoder.encode(matches) {
            UserDefaults.standard.set(matchesData, forKey: "matches")
        }
        
        if let conversationsData = try? encoder.encode(conversations) {
            UserDefaults.standard.set(conversationsData, forKey: "conversations")
        }
    }
    
    private func loadAppState() {
        let decoder = JSONDecoder()
        
        if let userData = UserDefaults.standard.data(forKey: "currentUser"),
           let user = try? decoder.decode(SpectRoomUser.self, from: userData) {
            currentUser = user
            blockedUsers = user.blockedUsers
            blockedByUsers = user.blockedByUsers
            print("📱 Loaded user from UserDefaults with \(user.photos.count) photos")
        }
        
        // Don't load authentication state from UserDefaults - rely on Firebase
        // isAuthenticated will be set by FirebaseAuthService
        hasCompletedInitialProfile = UserDefaults.standard.bool(forKey: "hasCompletedInitialProfile")
        isNewSignup = UserDefaults.standard.bool(forKey: "isNewSignup")
        signUpName = UserDefaults.standard.string(forKey: "signUpName") ?? ""
        restoreSignupNameFromAuthIfNeeded()
        
        if let matchesData = UserDefaults.standard.data(forKey: "matches"),
           let matches = try? decoder.decode([Match].self, from: matchesData) {
            self.matches = matches
        }
        
        if let conversationsData = UserDefaults.standard.data(forKey: "conversations"),
           let conversations = try? decoder.decode([Conversation].self, from: conversationsData) {
            self.conversations = conversations
        }
        
        syncInitialProfileCompletionIfNeeded()
    }
    
    private func clearStaleAuthData() {
        // Clear any cached authentication data to prevent stale state
        UserDefaults.standard.removeObject(forKey: "isAuthenticated")
        print("🧹 Cleared stale authentication data from UserDefaults")
    }
    
    func resetAllAppState() {
        // Reset all app state for testing/development
        Task {
            do {
                // Delete all swipes, matches, and messages from Firebase
                try await FirebaseAuthService.shared.deleteAllUserInteractions()
                
                await MainActor.run {
                    // Reset local state
                    hasCompletedInitialProfile = false
                    isNewSignup = false
                    currentUser = nil
                    matches = []
                    conversations = []
                    blockedUsers = []
                    blockedByUsers = []
                    clearMessageConversationsCache() // Clear message conversations cache
                    clearDiscoverProfilesCache()
                    DiscoverDailyLimit.reset()
                    DiscoverDistanceLimit.resetToDefault()
                    saveAppState()
                    print("🔄 All app state reset - app will start fresh")
                }
            } catch {
                await MainActor.run {
                    print("❌ Error deleting user interactions: \(error.localizedDescription)")
                    // Still reset local state even if Firebase deletion fails
                    hasCompletedInitialProfile = false
                    isNewSignup = false
                    currentUser = nil
                    matches = []
                    conversations = []
                    clearMessageConversationsCache()
                    clearDiscoverProfilesCache()
                    DiscoverDailyLimit.reset()
                    DiscoverDistanceLimit.resetToDefault()
                    saveAppState()
                }
            }
        }
    }
    
    func isUserBlocked(_ userId: String) -> Bool {
        blockedUsers.contains(where: { $0.id == userId })
    }
    
    func isBlockedByUser(_ userId: String) -> Bool {
        blockedByUsers.contains(where: { $0.id == userId })
    }
    
    /// True when either side has blocked the other — use for mutual hide in UI.
    func isMessagingBlocked(with userId: String) -> Bool {
        isUserBlocked(userId) || isBlockedByUser(userId)
    }
    
    /// User IDs that must be hidden from discover / matches / messages.
    var hiddenByBlockUserIds: Set<String> {
        Set(blockedUsers.map(\.id)).union(blockedByUsers.map(\.id))
    }
    
    func isHiddenByBlock(_ userId: String) -> Bool {
        isMessagingBlocked(with: userId)
    }
    
    func shouldShowBlockedAlert(for userId: String) -> Bool {
        !suppressedBlockedAlertUserIds.contains(userId)
    }
    
    func suppressBlockedAlert(for userId: String) {
        suppressedBlockedAlertUserIds.insert(userId)
        persistSuppressedBlockedAlerts()
    }
    
    func unsuppressBlockedAlert(for userId: String) {
        suppressedBlockedAlertUserIds.remove(userId)
        persistSuppressedBlockedAlerts()
    }
    
    private var suppressedBlockedAlertsStorageKey: String? {
        guard let uid = firebaseAuth.auth.currentUser?.uid else { return nil }
        return "suppressedBlockedAlertUserIds_\(uid)"
    }
    
    func loadSuppressedBlockedAlerts() {
        guard let key = suppressedBlockedAlertsStorageKey else {
            suppressedBlockedAlertUserIds = []
            return
        }
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        suppressedBlockedAlertUserIds = Set(ids)
    }
    
    private func persistSuppressedBlockedAlerts() {
        guard let key = suppressedBlockedAlertsStorageKey else { return }
        UserDefaults.standard.set(Array(suppressedBlockedAlertUserIds), forKey: key)
    }
    
    func refreshBlockedByUsers() {
        Task {
            do {
                let users = try await firebaseAuth.fetchBlockedByUsers()
                await MainActor.run {
                    self.applyBlockedByUsers(users)
                }
            } catch {
                print("⚠️ Unable to refresh blockedBy users: \(error.localizedDescription)")
            }
        }
    }
    
    func startListeningForBlockedByUsers() {
        guard isAuthenticated else { return }
        firebaseAuth.listenForBlockedByUsers { [weak self] users in
            Task { @MainActor in
                self?.applyBlockedByUsers(users)
            }
        }
    }

    func startListeningForModerationStatus() {
        guard isAuthenticated else { return }
        firebaseAuth.listenForModerationStatus(
            onBanned: { [weak self] in
                Task { @MainActor in
                    if case .loginBanned = self?.pendingModerationNotice?.kind {
                        // keep login ban notice
                    } else if case .loginBlocked = self?.pendingModerationNotice?.kind {
                        // keep login freeze notice
                    } else if case .banAcknowledgement = self?.pendingModerationNotice?.kind {
                        // Ban popup is showing — do not clear or force another sign-out yet.
                    } else {
                        self?.pendingModerationNotice = nil
                        self?.signOut()
                    }
                }
            },
            onNotice: { [weak self] notice in
                Task { @MainActor in
                    guard self?.isDismissingModerationNotice != true else { return }
                    self?.pendingModerationNotice = notice
                }
            },
            onNoticeCleared: { [weak self] in
                Task { @MainActor in
                    guard self?.isDismissingModerationNotice != true else { return }
                    // Never auto-clear warnings from a "cleared" snapshot — a stale cache
                    // event can wipe a warning that was just loaded from the server.
                    // Warnings are cleared only when the user taps OK.
                    switch self?.pendingModerationNotice?.kind {
                    case .freezeAcknowledgement:
                        self?.pendingModerationNotice = nil
                    default:
                        // Keep warnings / ban acknowledgement until the user dismisses.
                        break
                    }
                }
            }
        )
        Task { await refreshPendingModerationNotice() }
    }

    @MainActor
    func refreshPendingModerationNotice() async {
        guard isAuthenticated else { return }
        do {
            if let notice = try await firebaseAuth.fetchPendingModerationNotice(preferServer: true) {
                pendingModerationNotice = notice
            }
        } catch {
            print("⚠️ Failed to refresh moderation notice: \(error.localizedDescription)")
        }
    }

    /// Backward-compatible alias used by older call sites.
    @MainActor
    func refreshPendingSystemWarning() async {
        await refreshPendingModerationNotice()
    }

    /// Open All Profiles with search prefilled (e.g. from a report email link).
    @MainActor
    func openAllProfilesSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingProfilesSearchQuery = trimmed
        requestedAdminTab = AdminTab.profiles.rawValue
    }

    private var isDismissingModerationNotice = false

    @MainActor
    func dismissModerationNotice() {
        guard let notice = pendingModerationNotice, !isDismissingModerationNotice else { return }
        isDismissingModerationNotice = true

        switch notice.kind {
        case .loginBlocked, .loginBanned:
            pendingModerationNotice = nil
            isDismissingModerationNotice = false

        case .warning:
            Task {
                do {
                    try await firebaseAuth.clearPendingSystemWarning()
                    await MainActor.run {
                        self.pendingModerationNotice = nil
                        self.isDismissingModerationNotice = false
                    }
                } catch {
                    print("⚠️ Failed to clear system warning: \(error.localizedDescription)")
                    await MainActor.run {
                        self.isDismissingModerationNotice = false
                    }
                }
            }

        case .freezeAcknowledgement:
            Task {
                do {
                    try await firebaseAuth.clearPendingAccountFreezeNotice()
                } catch {
                    print("⚠️ Failed to clear account freeze notice: \(error.localizedDescription)")
                }
                await MainActor.run {
                    self.pendingModerationNotice = nil
                    self.isDismissingModerationNotice = false
                    self.signOut()
                }
            }

        case .banAcknowledgement:
            Task {
                do {
                    try await firebaseAuth.clearPendingAccountBanNotice()
                } catch {
                    print("⚠️ Failed to clear account ban notice: \(error.localizedDescription)")
                }
                await MainActor.run {
                    self.pendingModerationNotice = nil
                    self.isDismissingModerationNotice = false
                    self.signOut()
                }
            }

        case .banLifted:
            Task {
                do {
                    try await firebaseAuth.clearPendingAccountUnbanNotice()
                } catch {
                    print("⚠️ Failed to clear account unban notice: \(error.localizedDescription)")
                }
                await MainActor.run {
                    self.pendingModerationNotice = nil
                    self.isDismissingModerationNotice = false
                }
            }
        }
    }

    /// Backward-compatible alias.
    @MainActor
    func dismissSystemWarning() {
        dismissModerationNotice()
    }

    var isAdminUser: Bool {
        AdminAccess.isAdmin(email: currentUser?.email ?? firebaseAuth.auth.currentUser?.email)
    }

    func startListeningForPendingAdminReportsIfNeeded() {
        guard isAuthenticated, isAdminUser else {
            firebaseAuth.stopListeningForPendingAdminReports()
            pendingAdminReportIds = []
            unseenAdminReportIds = []
            unseenAdminReportCount = 0
            return
        }

        loadSeenAdminReportIds()
        firebaseAuth.startListeningForPendingAdminReports { [weak self] pendingIds in
            guard let self else { return }
            self.pendingAdminReportIds = Set(pendingIds)
            self.pruneSeenAdminReportIds()
            self.refreshUnseenAdminReportCount()
        }
    }

    /// Mark a report as opened so the Restrict/reports badge decrements.
    func markAdminReportAsSeen(_ reportId: String) {
        let trimmed = reportId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !seenAdminReportIds.contains(trimmed) else { return }
        seenAdminReportIds.insert(trimmed)
        persistSeenAdminReportIds()
        refreshUnseenAdminReportCount()
    }

    func isAdminReportUnseen(_ reportId: String) -> Bool {
        unseenAdminReportIds.contains(reportId)
    }

    private func refreshUnseenAdminReportCount() {
        unseenAdminReportIds = pendingAdminReportIds.subtracting(seenAdminReportIds)
        unseenAdminReportCount = unseenAdminReportIds.count
    }

    private func seenAdminReportsStorageKey() -> String? {
        guard let uid = firebaseAuth.auth.currentUser?.uid, !uid.isEmpty else { return nil }
        return seenAdminReportsStorageKeyPrefix + uid
    }

    private func loadSeenAdminReportIds() {
        guard let key = seenAdminReportsStorageKey() else {
            seenAdminReportIds = []
            return
        }
        seenAdminReportIds = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private func persistSeenAdminReportIds() {
        guard let key = seenAdminReportsStorageKey() else { return }
        UserDefaults.standard.set(Array(seenAdminReportIds), forKey: key)
    }

    private func pruneSeenAdminReportIds() {
        let pruned = seenAdminReportIds.intersection(pendingAdminReportIds)
        guard pruned.count != seenAdminReportIds.count else { return }
        seenAdminReportIds = pruned
        persistSeenAdminReportIds()
    }
    
    @MainActor
    private func applyBlockedByUsers(_ users: [BlockedUser]) {
        let previousIds = Set(blockedByUsers.map(\.id))
        let newIds = Set(users.map(\.id))
        blockedByUsers = users
        if var current = currentUser {
            current.blockedByUsers = users
            currentUser = current
        }
        
        let newlyBlockedIds = newIds.subtracting(previousIds)
        if !newlyBlockedIds.isEmpty {
            stripDiscoverProfiles(matching: newlyBlockedIds, reloadDeck: false)
            if let openId = currentlyOpenConversationSenderId, newlyBlockedIds.contains(openId) {
                currentlyOpenConversationSenderId = nil
            }
            if showingMatchNotification, let profile = newMatchProfile, newlyBlockedIds.contains(profile.userId) {
                showingMatchNotification = false
                newMatchProfile = nil
            }
            if showingNewMessageNotification, newlyBlockedIds.contains(newMessageSenderId) {
                dismissNewMessageNotification()
            }
        }
        
        // Someone unblocked us — refresh discover so they can appear in cards again.
        let newlyUnblockedIds = previousIds.subtracting(newIds)
        if !newlyUnblockedIds.isEmpty {
            invalidateDiscoverDeckAfterProfileUpdate()
        }
    }
    
    @MainActor
    private func stripDiscoverProfiles(matching userIds: Set<String>, reloadDeck: Bool) {
        guard !userIds.isEmpty else { return }
        
        for profile in cachedDiscoverProfiles where userIds.contains(profile.userId) {
            discoverProfilesHeldByBlock[profile.userId] = profile
        }
        
        cachedDiscoverProfiles.removeAll { userIds.contains($0.userId) }
        if cachedDiscoverProfiles.isEmpty {
            clearDiscoverProfilesCache()
        } else {
            if cachedDiscoverCardIndex > cachedDiscoverProfiles.count {
                cachedDiscoverCardIndex = cachedDiscoverProfiles.count
            }
            persistDiscoverProfilesCache()
        }
        
        if reloadDeck {
            discoverDeckRefreshID = UUID()
        }
    }
    
    func rememberDiscoverProfileHiddenByBlock(_ profile: ProfileCard) {
        discoverProfilesHeldByBlock[profile.userId] = profile
    }
    
    func consumePendingDiscoverUnblockRestore() -> ProfileCard? {
        guard let userId = pendingDiscoverUnblockRestoreUserId else { return nil }
        pendingDiscoverUnblockRestoreUserId = nil
        return discoverProfilesHeldByBlock.removeValue(forKey: userId)
    }

    @MainActor
    func removeMatchFromCache(userId: String) {
        cachedMatches.removeAll { $0.otherUser.userId == userId }
        lastMatchesUpdate = Date()
    }
    
    /// Unlike a profile: record a pass swipe and remove any existing match.
    func unlikeUser(userId: String) {
        Task {
            await MainActor.run {
                self.removeMatchFromCache(userId: userId)
                self.cachedDiscoverProfiles.removeAll { $0.userId == userId }
                if self.cachedDiscoverProfiles.isEmpty {
                    self.clearDiscoverProfilesCache()
                } else {
                    if self.cachedDiscoverCardIndex > self.cachedDiscoverProfiles.count {
                        self.cachedDiscoverCardIndex = self.cachedDiscoverProfiles.count
                    }
                    self.persistDiscoverProfilesCache()
                }
            }
            
            do {
                try await firebaseAuth.recordSwipe(to: userId, action: .pass)
                try await firebaseAuth.deleteMatch(with: userId)
                _ = try? await refreshMatchesCache()
            } catch {
                print("⚠️ Unable to unlike user \(userId): \(error.localizedDescription)")
            }
        }
    }
    
    /// Re-like a previously unliked profile (toggle off).
    func relikeUser(userId: String) {
        Task {
            do {
                try await firebaseAuth.recordSwipe(to: userId, action: .like)
                _ = try await firebaseAuth.checkForMatch(with: userId)
                _ = try? await refreshMatchesCache()
            } catch {
                print("⚠️ Unable to re-like user \(userId): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func blockUser(userId: String, name: String) {
        guard !isUserBlocked(userId) else { return }
        let blockedUser = BlockedUser(id: userId, name: name, blockedAt: Date())

        // Apply locally first so Home can remove the card before the profile sheet closes.
        blockedUsers.append(blockedUser)
        if let cached = cachedDiscoverProfiles.first(where: { $0.userId == userId }) {
            discoverProfilesHeldByBlock[userId] = cached
        }
        // Keep the live deck in place; SearchView removes the card like a pass.
        stripDiscoverProfiles(matching: [userId], reloadDeck: false)
        if var current = currentUser {
            current.blockedUsers = blockedUsers
            currentUser = current
        }
        if currentlyOpenConversationSenderId == userId {
            currentlyOpenConversationSenderId = nil
        }
        if showingMatchNotification, newMatchProfile?.userId == userId {
            showingMatchNotification = false
            newMatchProfile = nil
        }
        if showingNewMessageNotification, newMessageSenderId == userId {
            dismissNewMessageNotification()
        }
        saveAppState()

        Task {
            do {
                try await firebaseAuth.blockUser(userId: userId, name: name)
            } catch {
                print("⚠️ Unable to persist block to Firestore: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func unblockUser(userId: String) {
        guard isUserBlocked(userId) else { return }
        unsuppressBlockedAlert(for: userId)

        blockedUsers.removeAll { $0.id == userId }
        if var current = currentUser {
            current.blockedUsers = blockedUsers
            currentUser = current
        }
        saveAppState()

        if discoverProfilesHeldByBlock[userId] != nil {
            // Put the card back on Home without rebuilding the whole deck.
            if let held = discoverProfilesHeldByBlock[userId],
               !cachedDiscoverProfiles.contains(where: { $0.userId == userId }) {
                let insertAt = min(cachedDiscoverCardIndex, cachedDiscoverProfiles.count)
                cachedDiscoverProfiles.insert(held, at: insertAt)
                isDiscoverProfilesCacheValid = true
                persistDiscoverProfilesCache()
            }
            pendingDiscoverUnblockRestoreUserId = userId
        } else {
            invalidateDiscoverDeckAfterProfileUpdate()
        }

        Task {
            do {
                try await firebaseAuth.unblockUser(userId: userId)
            } catch {
                print("⚠️ Unable to persist unblock to Firestore: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Photo Preloading
    private func preloadUserPhotos() async {
        // Preload photos from Firebase Storage to improve user experience
        print("🔄 Preloading user photos for better UX...")
        
        // Only sync photos once when user first logs in, not continuously
        guard currentUser?.photos.isEmpty == true else {
            print("📸 Photos already loaded, skipping preload")
            return
        }
        
        await firebaseAuth.syncPhotosFromStorage()
        print("✅ User photos preloaded successfully")
    }
    
    func startListeningForMatches() {
        guard isAuthenticated else {
            print("❌ Cannot start listening for matches - user not authenticated")
            return
        }
        
        print("💕 Starting to listen for new matches...")
        
        firebaseAuth.listenForNewMatches { [weak self] matchDisplay in
            self?.handleIncomingMatchNotification(matchDisplay)
        }
    }
    
    func presentMatchNotification(otherUser: ProfileCard, matchId: String) {
        let matchDisplay = MatchDisplay(
            id: matchId,
            otherUser: otherUser,
            matchedAt: Date()
        )
        handleIncomingMatchNotification(matchDisplay)
    }
    
    private func handleIncomingMatchNotification(_ matchDisplay: MatchDisplay) {
        DispatchQueue.main.async { [weak self] in
            print("💕 New match received: \(matchDisplay.otherUser.name)")
            print("💕 Match ID: \(matchDisplay.id)")
            
            guard self?.isHiddenByBlock(matchDisplay.otherUser.userId) != true else {
                print("💕 Ignoring match notification — blocked with \(matchDisplay.otherUser.userId)")
                return
            }
            
            guard self?.lastMatchId != matchDisplay.id else {
                print("💕 Duplicate match notification, ignoring")
                return
            }
            
            guard self?.showingMatchNotification != true else {
                print("💕 Match notification already showing, ignoring new match")
                return
            }
            
            self?.lastMatchId = matchDisplay.id
            self?.newMatchProfile = matchDisplay.otherUser
            self?.showingMatchNotification = true
            self?.updateMatchesCache(with: matchDisplay)
            self?.playMatchSoundIfEnabled()
            print("💕 Match notification set to show for: \(matchDisplay.otherUser.name)")
        }
    }
    
    private func playMatchSoundIfEnabled() {
        if let settings = currentUser?.preferences.notificationSettings {
            guard settings.newMatches, settings.soundEnabled else { return }
        }
        SoundService.shared.playMatchSound()
    }
    
    func dismissMatchNotification() {
        print("💕 Dismissing match notification")
        print("💕 Current showingMatchNotification: \(showingMatchNotification)")
        print("💕 Current newMatchProfile: \(newMatchProfile?.name ?? "nil")")
        
        showingMatchNotification = false
        newMatchProfile = nil
        shouldOpenMessageModal = false
        isShowingSwipeMatchPopup = false
        
        print("💕 Match notification dismissed")
    }
    
    func setShowingSwipeMatchPopup(_ showing: Bool) {
        print("💕 Setting isShowingSwipeMatchPopup to: \(showing)")
        isShowingSwipeMatchPopup = showing
    }
    
    // MARK: - New Message Notification
    
    func refreshUnreadMessageCount() {
        guard isAuthenticated else {
            unreadMessageCount = 0
            conversationUnreadCounts = [:]
            syncAppIconBadge()
            return
        }
        
        Task {
            do {
                async let totalUnreadTask = firebaseAuth.countUnreadIncomingMessages()
                async let perConversationTask = firebaseAuth.fetchUnreadCountsBySender()
                let (totalUnread, perConversation) = try await (totalUnreadTask, perConversationTask)
                await MainActor.run {
                    self.unreadMessageCount = totalUnread
                    self.conversationUnreadCounts = perConversation
                    self.syncAppIconBadge()
                }
            } catch {
                print("❌ Error loading unread message count: \(error)")
                await MainActor.run {
                    self.unreadMessageCount = 0
                    self.syncAppIconBadge()
                }
            }
        }
    }
    
    private func syncAppIconBadge() {
        let count = unreadMessageCount
        Task { @MainActor in
            NotificationService.shared.setAppIconBadgeCount(count)
        }
    }
    
    /// Sync badge immediately when leaving the app so it persists on the home screen icon.
    func syncAppIconBadgeBeforeBackground() {
        guard isAuthenticated else { return }
        
        let cachedTotal = conversationUnreadCounts.values.reduce(0, +)
        if cachedTotal > unreadMessageCount {
            unreadMessageCount = cachedTotal
        }
        syncAppIconBadge()
        
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SyncAppIconBadge") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
        
        guard backgroundTaskID != .invalid else { return }
        
        Task {
            do {
                let totalUnread = try await firebaseAuth.countUnreadIncomingMessages()
                await MainActor.run {
                    self.unreadMessageCount = totalUnread
                    NotificationService.shared.setAppIconBadgeCount(totalUnread)
                }
            } catch {
                print("❌ Failed to sync app icon badge before background: \(error)")
            }
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
    }
    
    func refreshConversationUnreadCounts() {
        guard isAuthenticated else {
            conversationUnreadCounts = [:]
            return
        }
        
        Task {
            do {
                let counts = try await firebaseAuth.fetchUnreadCountsBySender()
                await MainActor.run {
                    self.conversationUnreadCounts = counts
                }
            } catch {
                print("❌ Error loading conversation unread counts: \(error)")
            }
        }
    }
    
    func markMessagesAsRead(from otherUserId: String) async {
        do {
            try await firebaseAuth.markMessagesAsRead(from: otherUserId)
            await MainActor.run {
                let clearedCount = self.conversationUnreadCounts[otherUserId] ?? 0
                var counts = self.conversationUnreadCounts
                counts[otherUserId] = 0
                self.conversationUnreadCounts = counts
                self.unreadMessageCount = max(0, self.unreadMessageCount - clearedCount)
                self.syncAppIconBadge()
                self.refreshUnreadMessageCount()
            }
        } catch {
            print("❌ Failed to mark messages as read: \(error)")
        }
    }
    
    func shouldSuppressMessageNotification(for senderId: String) -> Bool {
        if isMessagesTabActive {
            return true
        }
        if let openSenderId = currentlyOpenConversationSenderId, openSenderId == senderId {
            return true
        }
        return false
    }
    
    func setMessagesTabActive(_ isActive: Bool) {
        guard isMessagesTabActive != isActive else { return }
        isMessagesTabActive = isActive
        Task {
            await syncMessagesTabStateToFirestore(isActive: isActive)
        }
    }
    
    private func syncMessagesTabStateToFirestore(isActive: Bool) async {
        guard firebaseAuth.auth.currentUser != nil else { return }
        
        do {
            try await firebaseAuth.updateUserData([
                "messagesTabActive": isActive,
                "appStateUpdatedAt": Date().timeIntervalSince1970
            ])
            print("📱 Updated messages tab state in Firestore: \(isActive ? "active" : "inactive")")
        } catch {
            print("❌ Failed to update messages tab state: \(error)")
        }
    }
    
    func startListeningForNewMessages() {
        guard isAuthenticated else {
            print("❌ Cannot start listening for messages - user not authenticated")
            return
        }
        
        print("💬 Starting to listen for new messages...")
        
        firebaseAuth.listenForNewMessages { [weak self] senderId, senderName, senderPhotoURL, messageDocId, content, type, voiceDuration, createdAt, hasProfile in
            DispatchQueue.main.async {
                // Mutual block: keep quiet (no sound/badge/push). Cache still updates via preview
                // so unblock can restore the thread as it was.
                if self?.isHiddenByBlock(senderId) == true {
                    if !hasProfile {
                        self?.applyIncomingMessagePreview(
                            senderId: senderId,
                            senderName: senderName.isEmpty ? nil : senderName,
                            senderPhotoURL: senderPhotoURL,
                            content: content,
                            type: type,
                            voiceDuration: voiceDuration,
                            createdAt: createdAt
                        )
                    }
                    self?.lastMessageId = messageDocId
                    return
                }
                
                if !hasProfile {
                    print("💬 New message preview from: \(senderId), content: \(content.prefix(20))...")
                    self?.applyIncomingMessagePreview(
                        senderId: senderId,
                        senderName: senderName.isEmpty ? nil : senderName,
                        senderPhotoURL: senderPhotoURL,
                        content: content,
                        type: type,
                        voiceDuration: voiceDuration,
                        createdAt: createdAt
                    )
                    self?.incrementUnreadCount(for: senderId)
                    
                    // When this chat is open, the conversation UI appends the message and
                    // plays the sound together. Otherwise play here for list/other screens.
                    let chatIsOpen = self?.currentlyOpenConversationSenderId == senderId
                    if UIApplication.shared.applicationState == .active, chatIsOpen != true {
                        self?.playIncomingMessageSoundIfNeeded(for: messageDocId)
                    }
                    
                    if let openSenderId = self?.currentlyOpenConversationSenderId, openSenderId == senderId {
                        print("💬 Conversation with \(senderId) is already open, marking messages as read")
                        self?.lastMessageId = messageDocId
                        Task {
                            await self?.markMessagesAsRead(from: senderId)
                        }
                    }
                    return
                }
                
                // Profile resolved - replace any temporary "Unknown User" in the list/chat.
                self?.updateConversationPartnerDetails(
                    userId: senderId,
                    name: senderName,
                    photoURL: senderPhotoURL
                )
                
                print("💬 New message received from: \(senderName)")
                print("💬 Sender ID: \(senderId), Message Doc ID: \(messageDocId)")
                print("💬 Current showingNewMessageNotification state: \(self?.showingNewMessageNotification ?? false)")
                print("💬 Last message ID: \(self?.lastMessageId ?? "nil")")
                
                // Prevent duplicate notifications for the same message (using document ID)
                guard self?.lastMessageId != messageDocId else {
                    print("💬 Duplicate message notification (same document ID), ignoring")
                    return
                }
                
                // Only show notification if not already showing one
                guard self?.showingNewMessageNotification != true else {
                    print("💬 Message notification already showing, ignoring new message")
                    return
                }
                
                // If user is on Messages tab or already viewing this chat, skip notifications
                if self?.shouldSuppressMessageNotification(for: senderId) == true {
                    print("💬 Suppressing message notification for \(senderName) (messages tab or open conversation)")
                    self?.lastMessageId = messageDocId
                    return
                }
                
                self?.refreshUnreadMessageCount()
                
                // Check if app is in background/closed
                let isAppInBackground = UIApplication.shared.applicationState != .active
                
                // Only send push notification if app is closed/backgrounded
                if isAppInBackground {
                    // Fetch message content for notification
                    Task {
                        // Get message content for notification
                        let messageContent = try? await FirebaseAuthService.shared.fetchLatestMessageContent(from: senderId)
                        
                        let hasPermission = await NotificationService.shared.checkNotificationPermission()
                        if hasPermission && NotificationService.shared.areNotificationsEnabled() {
                            let (badgeCount, displayName) = await MainActor.run {
                                (
                                    self?.unreadMessageCount ?? 0,
                                    self?.resolvedPartnerName(for: senderId, preferred: senderName) ?? senderName
                                )
                            }
                            let notificationPreview: String
                            if type == .voice {
                                notificationPreview = "messages.preview.voice".localized
                            } else if type == .image {
                                notificationPreview = "messages.preview.photo".localized
                            } else {
                                notificationPreview = messageContent ?? content
                            }
                            NotificationService.shared.sendNewMessageNotification(
                                senderName: displayName,
                                messageContent: notificationPreview,
                                senderId: senderId,
                                badgeCount: badgeCount
                            )
                            print("📱 Push notification sent for message from: \(displayName)")
                        }
                    }
                }
                
                // Just update the message ID to prevent duplicates
                self?.lastMessageId = messageDocId
            }
        }
    }
    
    func playIncomingMessageSoundIfNeeded(for messageDocId: String) {
        guard lastPlayedMessageSoundId != messageDocId else { return }
        
        if let until = suppressIncomingMessageSoundUntil, Date() < until {
            // Consume the id so this same message does not chime after the window ends.
            lastPlayedMessageSoundId = messageDocId
            return
        }
        
        lastPlayedMessageSoundId = messageDocId
        
        if let settings = currentUser?.preferences.notificationSettings {
            guard settings.newMessages, settings.soundEnabled else { return }
        }
        
        SoundService.shared.playNewMessageSound()
    }
    
    func dismissNewMessageNotification() {
        print("💬 Dismissing new message notification")
        print("💬 Current showingNewMessageNotification: \(showingNewMessageNotification)")
        
        showingNewMessageNotification = false
        newMessageSenderName = ""
        newMessageSenderPhotoURL = nil
        newMessageSenderId = ""
        shouldOpenConversation = false
        conversationToOpenSenderId = nil
        conversationToOpenProfile = nil
        
        print("💬 New message notification dismissed")
    }
    
    /// Open Messages and the sender's conversation after a push notification tap.
    @MainActor
    func openConversationFromNotification(senderId: String) {
        let trimmed = senderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Avoid replaying the message sound when the chat surfaces that message.
        suppressIncomingMessageSoundUntil = Date().addingTimeInterval(3.0)
        
        conversationToOpenSenderId = trimmed
        shouldOpenConversation = true
        newMessageSenderId = trimmed
        print("📱 Queued conversation open from notification for sender: \(trimmed)")
    }
    
    
    // MARK: - Message Conversations Cache
    
    /// Get cached conversations if available and recent (within 30 seconds), otherwise fetch fresh
    func getCachedOrFreshConversations() async throws -> [MessageDisplay] {
        // If cache is empty or older than 30 seconds, fetch fresh
        if let lastUpdate = lastMessageConversationsUpdate,
           Date().timeIntervalSince(lastUpdate) < 30.0,
           !cachedMessageConversations.isEmpty {
            print("💬 Returning cached conversations (\(cachedMessageConversations.count) items, updated \(Date().timeIntervalSince(lastUpdate)) seconds ago)")
            refreshConversationUnreadCounts()
            return cachedMessageConversations
        }
        
        // Cache is stale or empty, fetch fresh
        print("💬 Cache is stale or empty, fetching fresh conversations...")
        return try await refreshMessageConversationsCache()
    }
    
    /// Refresh the message conversations cache from Firebase
    func refreshMessageConversationsCache() async throws -> [MessageDisplay] {
        print("💬 Refreshing message conversations cache...")
        async let latestMessagesTask = firebaseAuth.fetchLatestMessagesFromEachUser()
        async let unreadCountsTask = firebaseAuth.fetchUnreadCountsBySender()
        
        let latestMessages = try await latestMessagesTask
        let unreadCounts = try await unreadCountsTask
        let sortedMessages = latestMessages.sorted { $0.createdAt > $1.createdAt }
        
        await MainActor.run {
            cachedMessageConversations = sortedMessages
            conversationUnreadCounts = unreadCounts
            print("💬 Cache updated with \(sortedMessages.count) conversations")
            lastMessageConversationsUpdate = Date()
        }
        
        return sortedMessages
    }
    
    /// Update a single conversation in the cache (when a new message arrives or is sent)
    @MainActor
    func updateConversationInCache(_ conversation: MessageDisplay) {
        let newOtherUserId = otherUserId(for: conversation)
        var updated = cachedMessageConversations
        
        if let index = updated.firstIndex(where: { otherUserId(for: $0) == newOtherUserId }) {
            let existing = updated[index]
            guard conversation.createdAt >= existing.createdAt else {
                return
            }
            updated[index] = conversationPreservingKnownIdentity(new: conversation, existing: existing)
            print("💬 Updated conversation in cache: \(updated[index].senderName == "You" ? updated[index].recipientName : updated[index].senderName)")
        } else {
            updated.append(conversation)
            print("💬 Added new conversation to cache: \(conversation.senderName == "You" ? conversation.recipientName : conversation.senderName)")
        }
        
        cachedMessageConversations = updated.sorted { $0.createdAt > $1.createdAt }
        lastMessageConversationsUpdate = Date()
        newMessageReceivedSubject.send(updated.first(where: { otherUserId(for: $0) == newOtherUserId }) ?? conversation)
    }
    
    @MainActor
    func applyIncomingMessagePreview(
        senderId: String,
        senderName: String?,
        senderPhotoURL: String?,
        content: String,
        type: MessageType,
        voiceDuration: TimeInterval?,
        createdAt: Date
    ) {
        guard let currentUserId = firebaseAuth.auth.currentUser?.uid else { return }
        
        let resolvedName = resolvedPartnerName(for: senderId, preferred: senderName)
        let resolvedPhotoURL = resolvedPartnerPhotoURL(for: senderId, preferred: senderPhotoURL)
        
        let message = Message(
            conversationId: UUID(),
            senderId: UUID(),
            senderFirebaseId: senderId,
            content: content,
            createdAt: createdAt,
            type: type,
            voiceDuration: voiceDuration
        )
        let messageDisplay = MessageDisplay(
            message: message,
            senderName: resolvedName,
            recipientName: "You",
            senderId: senderId,
            recipientId: currentUserId,
            senderProfilePhotoURL: resolvedPhotoURL,
            recipientProfilePhotoURL: currentUser?.profilePhotoURL
        )
        updateConversationInCache(messageDisplay)
        // Keep the open-chat message pool in sync so the conversation UI can show
        // the bubble at the same time as the in-app sound.
        updateConversationMessagesCache([messageDisplay], for: senderId)
    }
    
    /// Patch conversation list + open-chat cache once the sender profile is known.
    @MainActor
    func updateConversationPartnerDetails(userId: String, name: String, photoURL: String?) {
        let resolvedName = resolvedPartnerName(for: userId, preferred: name)
        guard !isUnknownPartnerName(resolvedName) else { return }
        guard let currentUserId = firebaseAuth.auth.currentUser?.uid else { return }
        
        var didUpdateList = false
        cachedMessageConversations = cachedMessageConversations.map { conversation in
            guard otherUserId(for: conversation) == userId else { return conversation }
            let currentName = conversation.senderName == "You" ? conversation.recipientName : conversation.senderName
            let currentPhoto = conversation.senderName == "You" ? conversation.recipientProfilePhotoURL : conversation.senderProfilePhotoURL
            if currentName == resolvedName, (photoURL == nil || currentPhoto == photoURL) {
                return conversation
            }
            didUpdateList = true
            return conversation.replacingPartnerIdentity(
                name: resolvedName,
                photoURL: photoURL ?? currentPhoto,
                currentUserId: currentUserId
            )
        }
        
        if didUpdateList {
            lastMessageConversationsUpdate = Date()
            if let updated = cachedMessageConversations.first(where: { otherUserId(for: $0) == userId }) {
                newMessageReceivedSubject.send(updated)
            }
        }
        
        if var state = cachedConversationStates[userId] {
            state.messagePool = state.messagePool.map {
                $0.replacingPartnerIdentity(name: resolvedName, photoURL: photoURL, currentUserId: currentUserId)
            }
            state.visibleMessages = state.visibleMessages.map {
                $0.replacingPartnerIdentity(name: resolvedName, photoURL: photoURL, currentUserId: currentUserId)
            }
            state.updatedAt = Date()
            cachedConversationStates[userId] = state
        }
    }
    
    private func resolvedPartnerName(for userId: String, preferred: String?) -> String {
        if let preferred, !isUnknownPartnerName(preferred) {
            return preferred
        }
        
        if let fromConversation = cachedMessageConversations.first(where: { otherUserId(for: $0) == userId }) {
            let name = fromConversation.senderName == "You"
                ? fromConversation.recipientName
                : fromConversation.senderName
            if !isUnknownPartnerName(name) {
                return name
            }
        }
        
        if let fromMatch = cachedMatches.first(where: { $0.otherUser.userId == userId }),
           !isUnknownPartnerName(fromMatch.otherUser.name) {
            return fromMatch.otherUser.name
        }
        
        return preferred?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferred!
            : "Unknown User"
    }
    
    private func resolvedPartnerPhotoURL(for userId: String, preferred: String?) -> String? {
        if let preferred, !preferred.isEmpty {
            return preferred
        }
        
        if let fromConversation = cachedMessageConversations.first(where: { otherUserId(for: $0) == userId }) {
            return fromConversation.senderName == "You"
                ? fromConversation.recipientProfilePhotoURL
                : fromConversation.senderProfilePhotoURL
        }
        
        return cachedMatches.first(where: { $0.otherUser.userId == userId })?.otherUser.imageURL
    }
    
    private func isUnknownPartnerName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.caseInsensitiveCompare("Unknown User") == .orderedSame
            || trimmed.caseInsensitiveCompare("Unknown") == .orderedSame
            || trimmed.caseInsensitiveCompare("Other User") == .orderedSame
    }
    
    private func conversationPreservingKnownIdentity(new: MessageDisplay, existing: MessageDisplay) -> MessageDisplay {
        guard let currentUserId = firebaseAuth.auth.currentUser?.uid else { return new }
        
        let existingName = existing.senderName == "You" ? existing.recipientName : existing.senderName
        let newName = new.senderName == "You" ? new.recipientName : new.senderName
        let existingPhoto = existing.senderName == "You" ? existing.recipientProfilePhotoURL : existing.senderProfilePhotoURL
        let newPhoto = new.senderName == "You" ? new.recipientProfilePhotoURL : new.senderProfilePhotoURL
        
        let shouldKeepExistingName = isUnknownPartnerName(newName) && !isUnknownPartnerName(existingName)
        let resolvedName = shouldKeepExistingName ? existingName : newName
        let resolvedPhoto = (newPhoto?.isEmpty == false) ? newPhoto : existingPhoto
        
        if resolvedName == newName, resolvedPhoto == newPhoto {
            return new
        }
        
        return new.replacingPartnerIdentity(
            name: resolvedName,
            photoURL: resolvedPhoto,
            currentUserId: currentUserId
        )
    }
    
    @MainActor
    private func incrementUnreadCount(for senderId: String) {
        guard currentlyOpenConversationSenderId != senderId else { return }
        var counts = conversationUnreadCounts
        counts[senderId, default: 0] += 1
        conversationUnreadCounts = counts
        unreadMessageCount += 1
        syncAppIconBadge()
        refreshUnreadMessageCount()
    }
    
    private func otherUserId(for conversation: MessageDisplay) -> String {
        conversation.senderName == "You" ? conversation.recipientId : conversation.senderId
    }
    
    /// Optimistically update the messages list after sending a message, then refresh from the server.
    @MainActor
    func recordOutgoingMessage(
        to recipientId: String,
        recipientName: String,
        recipientPhotoURL: String?,
        content: String,
        type: MessageType = .text
    ) {
        guard let currentUserId = firebaseAuth.auth.currentUser?.uid else { return }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        
        let message = Message(
            conversationId: UUID(),
            senderId: UUID(),
            senderFirebaseId: currentUserId,
            content: trimmedContent,
            type: type
        )
        let messageDisplay = MessageDisplay(
            message: message,
            senderName: "You",
            recipientName: recipientName,
            senderId: currentUserId,
            recipientId: recipientId,
            senderProfilePhotoURL: currentUser?.profilePhotoURL,
            recipientProfilePhotoURL: recipientPhotoURL
        )
        updateConversationInCache(messageDisplay)
        
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            _ = try? await refreshMessageConversationsCache()
        }
    }
    
    /// Clear the message conversations cache (e.g., on logout)
    func clearMessageConversationsCache() {
        cachedMessageConversations = []
        conversationUnreadCounts = [:]
        lastMessageConversationsUpdate = nil
        cachedConversationStates = [:]
        print("💬 Message conversations cache cleared")
    }
    
    func exportAllMessagesToFile() async throws -> URL? {
        let export = try await firebaseAuth.fetchAllConversationsForExport()
        guard !export.conversations.isEmpty else { return nil }
        return try await MessagesExport.writePDFFile(
            currentUserName: export.currentUserName,
            currentUserId: export.currentUserId,
            conversations: export.conversations
        )
    }

    /// Admin: export one user's last 6 months of conversations into a PDF (same format as Settings).
    func exportAdminUserMessagesToFile(userId: String, userName: String) async throws -> URL? {
        let export = try await firebaseAuth.fetchAllConversationsForExport(
            forUserId: userId,
            userName: userName
        )
        guard !export.conversations.isEmpty else { return nil }
        return try await MessagesExport.writePDFFile(
            currentUserName: export.currentUserName,
            currentUserId: export.currentUserId,
            conversations: export.conversations
        )
    }
    
    // MARK: - Individual Conversation Messages Cache
    
    struct ConversationCacheSnapshot {
        let messagePool: [MessageDisplay]
        let visibleMessages: [MessageDisplay]
        let hasMoreOlderMessages: Bool
    }
    
    private struct CachedConversationState {
        var messagePool: [MessageDisplay]
        var visibleMessages: [MessageDisplay]
        var hasMoreOlderMessages: Bool
        var updatedAt: Date
    }
    
    /// Returns the in-memory conversation cache for the current app session.
    func getCachedConversationState(for otherUserId: String) -> ConversationCacheSnapshot? {
        guard let state = cachedConversationStates[otherUserId] else {
            print("💬 No cached conversation state for \(otherUserId)")
            return nil
        }
        
        print("💬 Returning cached conversation state for \(otherUserId) (\(state.visibleMessages.count) visible / \(state.messagePool.count) total messages)")
        return ConversationCacheSnapshot(
            messagePool: state.messagePool.deduplicatedConversationMessages(),
            visibleMessages: state.visibleMessages.deduplicatedConversationMessages(),
            hasMoreOlderMessages: state.hasMoreOlderMessages
        )
    }
    
    /// Backward-compatible accessor for callers that only need the message pool.
    func getCachedConversationMessages(for otherUserId: String) -> [MessageDisplay]? {
        getCachedConversationState(for: otherUserId)?.messagePool
    }
    
    /// Persist the full scroll state so reopening/scrolling does not reload already fetched messages.
    func cacheConversationState(
        for otherUserId: String,
        messagePool: [MessageDisplay],
        visibleMessages: [MessageDisplay],
        hasMoreOlderMessages: Bool
    ) {
        let pool = messagePool.deduplicatedConversationMessages()
        let visible = visibleMessages.deduplicatedConversationMessages()
        cachedConversationStates[otherUserId] = CachedConversationState(
            messagePool: pool,
            visibleMessages: visible,
            hasMoreOlderMessages: hasMoreOlderMessages,
            updatedAt: Date()
        )
        print("💬 Cached conversation state for \(otherUserId) (\(visible.count) visible / \(pool.count) total messages)")
    }
    
    /// Cache only the message pool, preserving any existing visible scroll state.
    func cacheConversationMessages(_ messages: [MessageDisplay], for otherUserId: String) {
        let pool = messages.deduplicatedConversationMessages()
        if var existingState = cachedConversationStates[otherUserId] {
            existingState.messagePool = pool
            existingState.updatedAt = Date()
            cachedConversationStates[otherUserId] = existingState
            print("💬 Updated message pool cache for \(otherUserId) (\(pool.count) messages)")
            return
        }
        
        cacheConversationState(
            for: otherUserId,
            messagePool: pool,
            visibleMessages: pool,
            hasMoreOlderMessages: false
        )
    }
    
    /// Update conversation messages cache when new messages arrive.
    /// Only appends to an existing cache - never seeds a one-message cache from a preview,
    /// or reopening the chat would hide the real history.
    func updateConversationMessagesCache(_ newMessages: [MessageDisplay], for otherUserId: String) {
        guard var existingState = cachedConversationStates[otherUserId] else {
            print("💬 Skipping conversation cache update for \(otherUserId) - no existing history cache")
            return
        }
        
        let existingKeys = Set(existingState.messagePool.map(\.deduplicationKey))
        var appendedToVisible = false
        
        for newMessage in newMessages where !existingKeys.contains(newMessage.deduplicationKey) {
            existingState.messagePool.append(newMessage)
            existingState.visibleMessages.append(newMessage)
            appendedToVisible = true
        }
        
        existingState.messagePool = existingState.messagePool.deduplicatedConversationMessages()
        if appendedToVisible {
            existingState.visibleMessages = existingState.visibleMessages.deduplicatedConversationMessages()
        }
        existingState.updatedAt = Date()
        cachedConversationStates[otherUserId] = existingState
        print("💬 Updated conversation cache for \(otherUserId) (total: \(existingState.messagePool.count))")
    }
    
    /// Clear cache for a specific conversation
    func clearConversationMessagesCache(for otherUserId: String) {
        cachedConversationStates.removeValue(forKey: otherUserId)
        print("💬 Cleared conversation cache for \(otherUserId)")
    }
    
    /// Partner IDs whose currently cached conversation pools contain `query`.
    func partnerIdsMatchingCachedMessageHistory(_ query: String) -> Set<String> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var matches = Set<String>()
        for (partnerId, state) in cachedConversationStates {
            if state.messagePool.contains(where: { $0.content.localizedCaseInsensitiveContains(trimmed) }) {
                matches.insert(partnerId)
            }
        }
        return matches
    }
    
    // MARK: - App State Management for Push Notifications
    
    private var presenceHeartbeatTask: Task<Void, Never>?
    
    /// Keep Firestore presence fresh while foregrounded so Cloud Functions can
    /// distinguish a live session from a force-quit with stale flags.
    func startPresenceHeartbeat() {
        stopPresenceHeartbeat()
        presenceHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.touchPresenceHeartbeat()
            }
        }
    }
    
    func stopPresenceHeartbeat() {
        presenceHeartbeatTask?.cancel()
        presenceHeartbeatTask = nil
    }
    
    private func touchPresenceHeartbeat() async {
        guard firebaseAuth.auth.currentUser != nil else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        
        do {
            try await firebaseAuth.updateUserData([
                "appIsActive": true,
                "appStateUpdatedAt": Date().timeIntervalSince1970
            ])
        } catch {
            print("❌ Failed to refresh presence heartbeat: \(error)")
        }
    }
    
    /// Update app state in Firestore so Cloud Functions can check if app is active
    func updateAppStateInFirestore(isActive: Bool) async {
        guard firebaseAuth.auth.currentUser != nil else {
            return
        }
        
        do {
            let now = Date()
            var state: [String: Any] = [
                "appIsActive": isActive,
                "appStateUpdatedAt": now.timeIntervalSince1970,
                "isOnline": isActive,
                "lastSeen": now.timeIntervalSince1970
            ]
            
            // Clear stale in-app state when app is backgrounded or closed
            if !isActive {
                state["openConversationUserId"] = NSNull()
                state["messagesTabActive"] = false
                await MainActor.run {
                    self.isMessagesTabActive = false
                }
                stopPresenceHeartbeat()
            } else {
                await MainActor.run {
                    self.startPresenceHeartbeat()
                }
            }
            
            try await firebaseAuth.updateUserData(state)
            
            // Also update local user object
            if var user = currentUser {
                user.isOnline = isActive
                user.lastSeen = now
                await MainActor.run {
                    self.currentUser = user
                }
            }
            
            print("📱 Updated app state in Firestore: \(isActive ? "active" : "inactive"), isOnline: \(isActive)")
        } catch {
            print("❌ Failed to update app state in Firestore: \(error)")
        }
    }
    
    func updateEnergyLevel(_ level: Int) {
        let clamped = min(max(level, 0), 4)
        if var user = currentUser {
            user.energyLevel = clamped
            currentUser = user
            firebaseAuth.currentUser = user
            saveAppState()
        }
        
        Task {
            do {
                try await firebaseAuth.updateUserData(["energyLevel": clamped])
                print("✅ Updated energy level: \(clamped)")
            } catch {
                print("❌ Failed to update energy level: \(error)")
            }
        }
    }
    
    // MARK: - Update Online Status
    func updateOnlineStatus(isOnline: Bool) async {
        guard firebaseAuth.auth.currentUser != nil else {
            return
        }
        
        do {
            let now = Date()
            let statusData: [String: Any] = [
                "isOnline": isOnline,
                "lastSeen": now.timeIntervalSince1970
            ]
            try await firebaseAuth.updateUserData(statusData)
            
            // Also update local user object
            if var user = currentUser {
                user.isOnline = isOnline
                user.lastSeen = now
                await MainActor.run {
                    self.currentUser = user
                }
            }
            
            print("🟢 Updated online status: \(isOnline ? "online" : "offline")")
        } catch {
            print("❌ Failed to update online status: \(error)")
        }
    }
}

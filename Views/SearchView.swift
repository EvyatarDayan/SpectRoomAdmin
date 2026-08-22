//
//  SearchView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

/// Tracks how many discover like/pass actions each account has used today (local day).
enum DiscoverDailyLimit {
    static let maxSwipesPerDay = 10
    private static let legacyDateKey = "discoverDailySwipeDate"
    private static let legacyCountKey = "discoverDailySwipeCount"
    
    private static var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    /// Prefer Firebase uid; fall back to email so the quota is per account, not per device.
    private static var accountKey: String? {
        if let uid = FirebaseAuthService.shared.auth.currentUser?.uid, !uid.isEmpty {
            return uid
        }
        if let email = FirebaseAuthService.shared.auth.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !email.isEmpty {
            return email
        }
        return nil
    }
    
    private static func dateStorageKey(for accountKey: String) -> String {
        "discoverDailySwipeDate_\(accountKey)"
    }
    
    private static func countStorageKey(for accountKey: String) -> String {
        "discoverDailySwipeCount_\(accountKey)"
    }
    
    private static func clearLegacyDeviceKeys() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyDateKey)
        defaults.removeObject(forKey: legacyCountKey)
    }
    
    private static func secondThoughtsStorageKey(for accountKey: String) -> String {
        "discoverSecondThoughtsUsed_\(accountKey)"
    }
    
    private static func secondThoughtsDateStorageKey(for accountKey: String) -> String {
        "discoverSecondThoughtsDate_\(accountKey)"
    }
    
    static func currentCount() -> Int {
        clearLegacyDeviceKeys()
        guard let accountKey else { return 0 }
        
        let defaults = UserDefaults.standard
        let dateKey = dateStorageKey(for: accountKey)
        let countKey = countStorageKey(for: accountKey)
        
        if defaults.string(forKey: dateKey) != todayKey {
            defaults.set(todayKey, forKey: dateKey)
            defaults.set(0, forKey: countKey)
            defaults.set(todayKey, forKey: secondThoughtsDateStorageKey(for: accountKey))
            defaults.set(false, forKey: secondThoughtsStorageKey(for: accountKey))
            return 0
        }
        return defaults.integer(forKey: countKey)
    }
    
    @discardableResult
    static func recordSwipe() -> Int {
        clearLegacyDeviceKeys()
        guard let accountKey else { return 0 }
        
        let count = currentCount() + 1
        let defaults = UserDefaults.standard
        defaults.set(todayKey, forKey: dateStorageKey(for: accountKey))
        defaults.set(count, forKey: countStorageKey(for: accountKey))
        return count
    }
    
    /// Rolls back one recorded discover swipe for today (used by single-step undo).
    @discardableResult
    static func undoLastSwipe() -> Int {
        clearLegacyDeviceKeys()
        guard let accountKey else { return 0 }
        
        let count = max(0, currentCount() - 1)
        let defaults = UserDefaults.standard
        defaults.set(todayKey, forKey: dateStorageKey(for: accountKey))
        defaults.set(count, forKey: countStorageKey(for: accountKey))
        return count
    }
    
    static var hasReachedLimit: Bool {
        currentCount() >= maxSwipesPerDay
    }
    
    static func hasUsedSecondThoughtsToday() -> Bool {
        clearLegacyDeviceKeys()
        guard let accountKey else { return true }
        let defaults = UserDefaults.standard
        let dateKey = secondThoughtsDateStorageKey(for: accountKey)
        if defaults.string(forKey: dateKey) != todayKey {
            defaults.set(todayKey, forKey: dateKey)
            defaults.set(false, forKey: secondThoughtsStorageKey(for: accountKey))
            return false
        }
        return defaults.bool(forKey: secondThoughtsStorageKey(for: accountKey))
    }
    
    static func markSecondThoughtsUsed() {
        clearLegacyDeviceKeys()
        guard let accountKey else { return }
        let defaults = UserDefaults.standard
        defaults.set(todayKey, forKey: secondThoughtsDateStorageKey(for: accountKey))
        defaults.set(true, forKey: secondThoughtsStorageKey(for: accountKey))
    }
    
    /// Clears today's discover swipe quota for the signed-in account (e.g. Reset user data).
    static func reset() {
        clearLegacyDeviceKeys()
        guard let accountKey else { return }
        
        let defaults = UserDefaults.standard
        defaults.set(todayKey, forKey: dateStorageKey(for: accountKey))
        defaults.set(0, forKey: countStorageKey(for: accountKey))
        defaults.set(todayKey, forKey: secondThoughtsDateStorageKey(for: accountKey))
        defaults.set(false, forKey: secondThoughtsStorageKey(for: accountKey))
    }
}

/// One undoable Home discover action (only the latest swipe can be reversed).
private struct UndoableDiscoverSwipe {
    let profile: ProfileCard
    let action: SwipeType
    let cardIndexBeforeSwipe: Int
    let countedTowardDailyLimit: Bool
}

/// Drives the card fly-back animation when undoing a swipe.
struct UndoCardEntrance: Equatable {
    let profileId: String
    /// `true` = enter from left (undo pass); `false` = enter from right (undo like).
    let fromLeadingEdge: Bool
    let token: UUID
}

struct SearchView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedFilters: Set<String> = []
    @State private var currentCardIndex = 0
    @State private var profiles: [ProfileCard] = []
    @State private var dragOffset = CGSize.zero
    @State private var showingMatchModal = false
    @State private var matchedProfile: ProfileCard?
    @State private var isLoading = true
    @State private var showingProfileModal = false
    @State private var selectedProfile: ProfileCard?
    @State private var showingNewMessageModal = false
    @State private var matchCheckTimer: Timer?
    @State private var hasCompletedDiscoverLoad = false
    @State private var programmaticSwipeDirection: String? = nil // "left" or "right" for button-triggered swipes
    @State private var lastFetchedUserDocumentId: String?
    @State private var hasMoreUsersToLoad = true
    @State private var hasMoreRemoteUsers = true
    @State private var isLoadingMoreProfiles = false
    @State private var cachedSwipeFilter: FirebaseAuthService.SwipeFilterState?
    @State private var pendingDiscoverProfiles: [ProfileCard] = []
    @State private var dailySwipeCount = DiscoverDailyLimit.currentCount()
    @State private var hasUsedSecondThoughtsToday = DiscoverDailyLimit.hasUsedSecondThoughtsToday()
    @State private var isReviewingTodaysPasses = false
    @State private var isLoadingSecondThoughts = false
    @State private var savedProfilesBeforeSecondThoughts: [ProfileCard] = []
    @State private var savedCardIndexBeforeSecondThoughts = 0
    @State private var secondThoughtsErrorMessage: String?
    @State private var showingEnergyLevelPicker = false
    @State private var showingDistancePicker = false
    @State private var selectedDistanceOption = DiscoverDistanceLimit.currentOption
    /// Single-step undo for the most recent like/pass on Home.
    @State private var lastUndoableSwipe: UndoableDiscoverSwipe?
    @State private var isUndoingSwipe = false
    /// Kept false until the swipe animation has finished so quick taps can't fight the fly-off.
    @State private var canUseUndoButton = false
    /// Invalidates in-flight swipe writes if the user undoes before they finish.
    @State private var activeSwipeTokens: [String: UUID] = [:]
    /// Bumped to cancel in-flight card fly-off animations / delayed swipe handlers.
    @State private var swipeActionEpoch = 0
    @State private var undoEnableWorkItem: DispatchWorkItem?
    /// Triggers a fly-back entrance on the restored top card after undo.
    @State private var pendingUndoEntrance: UndoCardEntrance?
    /// Bumped on each deck reload so stale in-flight fetches cannot overwrite a newer load.
    @State private var discoverLoadEpoch = 0
    /// Top-card block: play the pass fly-off instead of splicing the array (which desyncs the UI).
    @State private var blockPassInProgressUserId: String?
    
    private var hasReachedDailyLimit: Bool {
        dailySwipeCount >= DiscoverDailyLimit.maxSwipesPerDay
    }
    
    /// Locked overlay on the top card (not while reviewing today's passes).
    private var showsDailyLimitOverlay: Bool {
        hasReachedDailyLimit && !isReviewingTodaysPasses
    }
    
    private var needsProfileCompletion: Bool {
        !appState.isProfileComplete()
    }
    
    private var hasResolvedDiscoverProfileState: Bool {
        appState.hasResolvedAuthState && appState.hasResolvedUserProfile
    }
    
    private var shouldShowProfileIncompleteCard: Bool {
        hasResolvedDiscoverProfileState && needsProfileCompletion
    }
    
    private var shouldShowDiscoverLoadingSpinner: Bool {
        guard appState.isAuthenticated else { return false }
        
        if !hasResolvedDiscoverProfileState {
            return true
        }
        
        if shouldShowProfileIncompleteCard {
            return false
        }
        
        return isLoading && profiles.isEmpty
    }
    
    private enum DiscoverConstants {
        /// How many discover cards to surface per load.
        static let profilesPerBatch = 10
        /// Firestore page size used while collecting eligible users for a batch.
        static let firestorePageSize = 20
        /// Prefetch when the user reaches the 7th card of the current 10
        /// (4 cards remaining including the current one: indices 6…9).
        static let prefetchRemainingThreshold = 4
    }
    
    let filterOptions = ["Nearby", "Similar Interests", "Same Age Group", "Online Now"]
    
    /// Stable key so one `onChange` can watch both lat & long without blowing up type-check time.
    private var discoverLocationSignature: String {
        let lat = appState.currentUser?.location.latitude.map { String($0) } ?? "nil"
        let lon = appState.currentUser?.location.longitude.map { String($0) } ?? "nil"
        return "\(lat),\(lon)"
    }
    
    var body: some View {
        applyDiscoverLifecycle(to: discoverChrome)
    }
    
    @ViewBuilder
    private var discoverChrome: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Card stack area
                    ZStack(alignment: .top) {
                        if shouldShowDiscoverLoadingSpinner {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                
                                Text("search.loading".localized)
                                    .font(.headline)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                            }
                        } else if shouldShowProfileIncompleteCard {
                            EmptyStateCard(
                                isProfileIncomplete: true,
                                onProfileTap: { selectedTab = 3 }
                            )
                        } else if currentCardIndex < profiles.count {
                            // Show only 3 cards in the pile (top card + 2 behind it)
                            ForEach(Array(profiles.enumerated().reversed()), id: \.offset) { index, profile in
                                if index >= currentCardIndex && index < currentCardIndex + 3 {
                                    SwipeableProfileCard(
                                        profile: profile,
                                        isTopCard: index == currentCardIndex,
                                        isDailyLimitReached: showsDailyLimitOverlay,
                                        canUseSecondThoughts: !hasUsedSecondThoughtsToday,
                                        isLoadingSecondThoughts: isLoadingSecondThoughts,
                                        swipeActionEpoch: swipeActionEpoch,
                                        undoEntrance: index == currentCardIndex ? pendingUndoEntrance : nil,
                                        programmaticSwipeDirection: index == currentCardIndex ? Binding(
                                            get: { programmaticSwipeDirection },
                                            set: { programmaticSwipeDirection = $0 }
                                        ) : Binding(get: { nil }, set: { _ in }),
                                        onSwipeRight: {
                                            handleSwipeRight(profile: profile)
                                        },
                                        onSwipeLeft: {
                                            handleSwipeLeft(profile: profile)
                                        },
                                        onSwipeCommitted: { direction in
                                            guard index == currentCardIndex else { return }
                                            prepareUndoableSwipe(
                                                profile: profile,
                                                action: direction == "right" ? .like : .pass
                                            )
                                        },
                                        onUndoEntranceConsumed: {
                                            if pendingUndoEntrance?.profileId == profile.userId {
                                                pendingUndoEntrance = nil
                                            }
                                        },
                                        onTap: {
                                            guard !showsDailyLimitOverlay else { return }
                                            selectedProfile = profile
                                            showingProfileModal = true
                                        },
                                        onSecondThoughtsTap: {
                                            startSecondThoughtsReview()
                                        }
                                    )
                                    .zIndex(Double(3 - (index - currentCardIndex))) // Higher zIndex for cards closer to front
                                    .modifier(StackAppearance(depth: index - currentCardIndex))
                                }
                            }
                        } else if isLoadingMoreProfiles {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                
                                Text("search.loading".localized)
                                    .font(.subheadline)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                            }
                        } else {
                            // Pool exhausted (e.g. distance filter) - not the daily swipe limit.
                            EmptyStateCard()
                                .onAppear {
                                    if hasMoreUsersToLoad {
                                        prefetchMoreProfilesIfNeeded()
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, -120) // Lowered cards (less negative = lower position)
                    .padding(.bottom, 10) // Space for floating buttons
                    .background(
                        SpectRoomBackground()
                    )
                }
                
                // Floating action buttons positioned below cards (on top of everything)
                if currentCardIndex < profiles.count, !shouldShowProfileIncompleteCard {
                    VStack {
                        Spacer()
                        
                        ZStack {
                            HStack(spacing: 14) {
                                // Pass button (left side)
                                Button(action: {
                                    guard !showsDailyLimitOverlay else { return }
                                    guard currentCardIndex < profiles.count else { return }
                                    prepareUndoableSwipe(profile: profiles[currentCardIndex], action: .pass)
                                    // Haptic feedback for pass
                                    let feedback = UINotificationFeedbackGenerator()
                                    feedback.notificationOccurred(.error)
                                    // Trigger programmatic swipe left
                                    programmaticSwipeDirection = "left"
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.red)
                                        .floatingCircleButtonStyle(colorScheme: colorScheme, size: 76)
                                }
                                .disabled(showsDailyLimitOverlay)
                                
                                // Undo last swipe (center, smaller)
                                Button(action: {
                                    undoLastSwipeIfPossible()
                                }) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(SpectRoomTheme.text)
                                        .floatingCircleButtonStyle(colorScheme: colorScheme, size: 52)
                                }
                                .disabled(!canUseUndoButton || lastUndoableSwipe == nil || isUndoingSwipe || showsDailyLimitOverlay)
                                .opacity(!canUseUndoButton || lastUndoableSwipe == nil || isUndoingSwipe ? 0.4 : 1)
                                .accessibilityLabel("search.undo".localized)
                                
                                // Like button (right side)
                                Button(action: {
                                    guard !showsDailyLimitOverlay else { return }
                                    guard currentCardIndex < profiles.count else { return }
                                    prepareUndoableSwipe(profile: profiles[currentCardIndex], action: .like)
                                    // Haptic feedback for like
                                    let feedback = UINotificationFeedbackGenerator()
                                    feedback.notificationOccurred(.success)
                                    // Trigger programmatic swipe right
                                    programmaticSwipeDirection = "right"
                                }) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(.green)
                                        .floatingCircleButtonStyle(colorScheme: colorScheme, size: 76)
                                }
                                .disabled(showsDailyLimitOverlay)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 100)
                        .blur(radius: showsDailyLimitOverlay ? 8 : 0)
                        .opacity(showsDailyLimitOverlay ? 0.85 : 1)
                    }
                    .allowsHitTesting(!showsDailyLimitOverlay)
                }
                
                ZStack {
                    if showingEnergyLevelPicker {
                        Color.clear
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showingEnergyLevelPicker = false
                                }
                            }
                        
                        ZStack(alignment: .top) {
                            EnergyLevelPickerOverlay(
                                selectedLevel: appState.currentUser?.energyLevel ?? 4,
                                onSelect: { level in
                                    appState.updateEnergyLevel(level)
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                        showingEnergyLevelPicker = false
                                    }
                                }
                            )
                            .padding(.horizontal, DiscoverHomeDialogMetrics.horizontalInset)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, -120)
                        .padding(.bottom, 10)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.82, anchor: .top)
                            )
                        )
                    }
                }
                .zIndex(200)
                
                ZStack {
                    if showingDistancePicker {
                        Color.clear
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showingDistancePicker = false
                                }
                            }
                        
                        ZStack(alignment: .top) {
                            SearchRadiusPickerOverlay(
                                selectedOption: selectedDistanceOption,
                                onSelect: { option in
                                    applySearchRadiusChange(option)
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                        showingDistancePicker = false
                                    }
                                }
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, -120)
                        .padding(.bottom, 10)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.82, anchor: .top)
                            )
                        )
                    }
                }
                .zIndex(201)
            }
            .spectRoomScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
        }
        .overlay(alignment: .topLeading) {
            searchRadiusCornerButton
                .padding(.top, 8)
                .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            energyLevelCornerButton
                .padding(.top, 8)
                .padding(.trailing, 16)
        }
    }
    
    private func applyDiscoverLifecycle<Content: View>(to content: Content) -> some View {
        content
            .onAppear {
                dailySwipeCount = DiscoverDailyLimit.currentCount()
                hasUsedSecondThoughtsToday = DiscoverDailyLimit.hasUsedSecondThoughtsToday()
                selectedDistanceOption = DiscoverDistanceLimit.currentOption
                appState.refreshBlockedByUsers()
                restoreDiscoverSessionIfAvailable()
                restoreUnblockedProfileToDeckIfNeeded()
            }
            .onChange(of: appState.hasResolvedUserProfile) { _, resolved in
                guard resolved else { return }
                restoreDiscoverSessionIfAvailable()
            }
            .onChange(of: needsProfileCompletion) { _, needsCompletion in
                guard hasResolvedDiscoverProfileState else { return }
                if needsCompletion {
                    restoreDiscoverSessionIfAvailable()
                } else {
                    reloadDiscoverDeck()
                }
            }
            .onChange(of: appState.hasCompletedInitialProfile) { _, isComplete in
                guard isComplete else { return }
                reloadDiscoverDeck()
            }
            .onChange(of: appState.discoverDeckRefreshID) { _, _ in
                reloadDiscoverDeck()
            }
            .onChange(of: appState.blockedUsers.map(\.id)) { _, _ in
                removeHiddenBlockedProfilesFromDeck()
            }
            .onChange(of: appState.blockedByUsers.map(\.id)) { _, _ in
                removeHiddenBlockedProfilesFromDeck()
            }
            .onChange(of: appState.pendingDiscoverUnblockRestoreUserId) { _, userId in
                guard userId != nil else { return }
                restoreUnblockedProfileToDeckIfNeeded()
            }
            .onChange(of: selectedTab) { _, tab in
                handleSelectedTabChange(tab)
            }
            .onChange(of: appState.currentUser?.id) { _, _ in
                handleCurrentUserChange()
            }
            .onChange(of: discoverLocationSignature) { _, _ in
                retryDiscoverLoadAfterLocationReady()
            }
            .onChange(of: showingProfileModal) { _, isShowing in
                handleProfileModalDismissed(isShowing: isShowing)
            }
            .onDisappear {
                syncDiscoverCache()
                matchCheckTimer?.invalidate()
                matchCheckTimer = nil
            }
            .alert(
                "search.daily.limit.second.thoughts".localized,
                isPresented: Binding(
                    get: { secondThoughtsErrorMessage != nil },
                    set: { if !$0 { secondThoughtsErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    secondThoughtsErrorMessage = nil
                }
            } message: {
                Text(secondThoughtsErrorMessage ?? "")
            }
            .sheet(isPresented: $showingProfileModal) {
                if let profile = selectedProfile {
                    UserProfileModal(profile: profile)
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showingNewMessageModal) {
                if let profile = matchedProfile {
                    NewMessageModal(profile: profile, isExistingConversation: false)
                }
            }
    }
    
    private func handleSelectedTabChange(_ tab: Int) {
        guard tab == 2 else { return }
        dailySwipeCount = DiscoverDailyLimit.currentCount()
        hasUsedSecondThoughtsToday = DiscoverDailyLimit.hasUsedSecondThoughtsToday()
        selectedDistanceOption = DiscoverDistanceLimit.currentOption
        restoreUnblockedProfileToDeckIfNeeded()
        if !appState.hasValidDiscoverProfilesCache
            && !isLoading
            && DiscoverDailyLimit.currentCount() < DiscoverDailyLimit.maxSwipesPerDay {
            reloadDiscoverDeck()
        }
    }
    
    private func handleCurrentUserChange() {
        dailySwipeCount = DiscoverDailyLimit.currentCount()
        hasUsedSecondThoughtsToday = DiscoverDailyLimit.hasUsedSecondThoughtsToday()
        guard appState.currentUser != nil else { return }
        appState.loadPersistedDiscoverProfilesCacheIfNeeded()
        if profiles.isEmpty {
            restoreDiscoverSessionIfAvailable()
            return
        }
        guard !appState.hasValidDiscoverProfilesCache else { return }
        guard !hasCompletedDiscoverLoad else { return }
        loadDiscoverProfilesWhenReady()
    }
    
    private func handleProfileModalDismissed(isShowing: Bool) {
        guard !isShowing else { return }
        if let selected = selectedProfile, appState.isHiddenByBlock(selected.userId) {
            selectedProfile = nil
        }
        // Let the sheet finish dismissing so the Home pile is visible for the pass animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            removeHiddenBlockedProfilesFromDeck()
        }
    }
    
    /// When a profile is blocked, fly the top card away like Pass; never splice the top card out of the array.
    private func removeHiddenBlockedProfilesFromDeck() {
        pendingDiscoverProfiles.removeAll {
            guard appState.isHiddenByBlock($0.userId) else { return false }
            appState.rememberDiscoverProfileHiddenByBlock($0)
            return true
        }
        
        guard currentCardIndex < profiles.count else {
            syncDiscoverCache()
            return
        }
        
        let top = profiles[currentCardIndex]
        if appState.isHiddenByBlock(top.userId) {
            guard !showingProfileModal else { return }
            triggerBlockPassAnimation(for: top)
            return
        }
        
        // Drop blocked profiles that are still ahead in the pile (not the visible top card).
        let kept = profiles.enumerated().compactMap { index, profile -> ProfileCard? in
            if index > currentCardIndex && appState.isHiddenByBlock(profile.userId) {
                appState.rememberDiscoverProfileHiddenByBlock(profile)
                return nil
            }
            return profile
        }
        if kept.count != profiles.count {
            profiles = kept
            syncDiscoverCache()
            prefetchMoreProfilesIfNeeded()
        }
    }
    
    private func triggerBlockPassAnimation(for profile: ProfileCard) {
        guard blockPassInProgressUserId == nil else { return }
        guard currentCardIndex < profiles.count,
              profiles[currentCardIndex].userId == profile.userId else { return }
        
        appState.rememberDiscoverProfileHiddenByBlock(profile)
        blockPassInProgressUserId = profile.userId
        
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.error)
        
        // Same path as the Pass button — card flies left, then handleSwipeLeft advances the pile.
        programmaticSwipeDirection = "left"
    }
    
    private func restoreUnblockedProfileToDeckIfNeeded() {
        guard let profile = appState.consumePendingDiscoverUnblockRestore() else { return }
        guard !profiles.contains(where: { $0.userId == profile.userId }) else {
            // Already in the pile (e.g. left behind after the block pass) — jump back to it.
            if let index = profiles.firstIndex(where: { $0.userId == profile.userId }) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    currentCardIndex = index
                }
                syncDiscoverCache()
            }
            return
        }
        
        let insertAt = min(currentCardIndex, profiles.count)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            profiles.insert(profile, at: insertAt)
            currentCardIndex = insertAt
        }
        pendingDiscoverProfiles.removeAll { $0.userId == profile.userId }
        syncDiscoverCache()
    }
    
    // MARK: - Helper function to calculate distance between two coordinates using Haversine formula
    private func calculateDistance(from sourceLocation: Location, to targetLocation: Location) -> Double? {
        guard let sourceLat = sourceLocation.latitude,
              let sourceLon = sourceLocation.longitude,
              let targetLat = targetLocation.latitude,
              let targetLon = targetLocation.longitude else {
            return nil
        }
        
        let earthRadius: Double = 6371 // Earth's radius in kilometers
        
        let dLat = (targetLat - sourceLat) * .pi / 180.0
        let dLon = (targetLon - sourceLon) * .pi / 180.0
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(sourceLat * .pi / 180.0) * cos(targetLat * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        let distance = earthRadius * c
        return distance
    }
    
    // MARK: - Helper function to format distance string
    private func formatDistance(_ distanceKm: Double) -> String {
        if distanceKm < 1.0 {
            return String(format: "search.distance.km".localized, "1")
        }
        let roundedDistance = round(distanceKm * 10) / 10
        if roundedDistance == floor(roundedDistance) {
            return String(format: "search.distance.km".localized, "\(Int(roundedDistance))")
        }
        return String(format: "search.distance.km".localized, String(format: "%.1f", roundedDistance))
    }
    
    // MARK: - Helper function to check if two users match based on age preferences
    private func matchesAgePreferences(currentUser: SpectRoomUser, otherUser: SpectRoomUser) -> Bool {
        let currentUserPreferredMin = currentUser.preferredAgeMin
        let currentUserPreferredMax = currentUser.preferredAgeMax
        let otherUserAge = otherUser.age
        
        // Filter based on current user's age preferences only (one-way filtering)
        // If current user has no age preferences set (both are 0 or invalid range), show all ages
        if (currentUserPreferredMin == 0 && currentUserPreferredMax == 0) || 
           currentUserPreferredMax < currentUserPreferredMin {
            // Current user has no valid age preferences set, allow match
            return true
        }
        
        // Check if other user's age is within current user's preferred range (inclusive)
        // Example: If preferred range is 32-52, show ages 32, 33, 34, ..., 51, 52
        // But NOT 31 or 53
        let isMatch = otherUserAge >= currentUserPreferredMin && otherUserAge <= currentUserPreferredMax
        
        if !isMatch {
            print("🔍 Age preference mismatch: Current user prefers \(currentUserPreferredMin)-\(currentUserPreferredMax), but other user is age \(otherUserAge)")
        }
        
        return isMatch
    }
    
    // MARK: - Helper function to check if two users match based on gender and interested in preferences
    private func matchesGenderPreferences(currentUser: SpectRoomUser, otherUser: SpectRoomUser) -> Bool {
        let currentUserGender = currentUser.gender
        let currentUserInterestedIn = Set(currentUser.interestedIn)
        let otherUserGender = otherUser.gender
        let otherUserInterestedIn = Set(otherUser.interestedIn)
        
        // Edge case: if either user has no gender or no interested in preferences, allow the match
        // This handles users who haven't completed their profile yet
        if currentUserGender.isEmpty || currentUserInterestedIn.isEmpty || otherUserGender.isEmpty || otherUserInterestedIn.isEmpty {
            print("🔍 Gender preference check: One or more users have incomplete gender/interested in data - allowing match")
            return true
        }
        
        // Check if current user's gender is in other user's interested in (or other user has "Anyone")
        let currentUserMatchesOther: Bool
        if otherUserInterestedIn.contains("Anyone") {
            currentUserMatchesOther = true // "Anyone" covers all genders
        } else {
            currentUserMatchesOther = otherUserInterestedIn.contains(currentUserGender)
        }
        
        // Check if other user's gender is in current user's interested in (or current user has "Anyone")
        let otherUserMatchesCurrent: Bool
        if currentUserInterestedIn.contains("Anyone") {
            otherUserMatchesCurrent = true // "Anyone" covers all genders
        } else {
            otherUserMatchesCurrent = currentUserInterestedIn.contains(otherUserGender)
        }
        
        // Both conditions must be true for a match
        let isMatch = currentUserMatchesOther && otherUserMatchesCurrent
        
        if !isMatch {
            print("🔍 Gender preference mismatch: Current user (\(currentUserGender)) interested in \(currentUserInterestedIn) vs Other user (\(otherUserGender)) interested in \(otherUserInterestedIn)")
        }
        
        return isMatch
    }

    private func isUserEligibleForDeck(
        user: SpectRoomUser,
        currentUser: SpectRoomUser,
        likedUserIds: Set<String>,
        passedUserIds: Set<String>,
        blockedUserIds: Set<String>,
        ignorePassedFilter: Bool
    ) -> Bool {
        let userId = user.firebaseDocumentId ?? user.id.uuidString

        if blockedUserIds.contains(userId) {
            return false
        }

        if likedUserIds.contains(userId) {
            return false
        }

        if !ignorePassedFilter && passedUserIds.contains(userId) {
            return false
        }

        if !matchesDistancePreference(currentUser: currentUser, otherUser: user) {
            return false
        }

        let currentUserLookingFor = Set(currentUser.lookingFor.filter { $0 != "Not sure yet" && $0 != "Not Sure Yet" })

        if currentUserLookingFor.isEmpty {
            if !matchesGenderPreferences(currentUser: currentUser, otherUser: user) {
                return false
            }
            if !matchesAgePreferences(currentUser: currentUser, otherUser: user) {
                return false
            }
            return true
        }

        let userLookingFor = Set(user.lookingFor.filter { $0 != "Not sure yet" && $0 != "Not Sure Yet" })
        if !userLookingFor.isEmpty && currentUserLookingFor.intersection(userLookingFor).isEmpty {
            return false
        }

        if !matchesGenderPreferences(currentUser: currentUser, otherUser: user) {
            return false
        }

        if !matchesAgePreferences(currentUser: currentUser, otherUser: user) {
            return false
        }

        return true
    }
    
    private func matchesDistancePreference(currentUser: SpectRoomUser, otherUser: SpectRoomUser) -> Bool {
        guard let maxKm = DiscoverDistanceLimit.currentOption.maxKilometers else {
            return true
        }
        guard let distanceKm = calculateDistance(from: currentUser.location, to: otherUser.location) else {
            // Without coordinates we cannot verify the radius - exclude when a limit is set.
            return false
        }
        return distanceKm <= maxKm
    }

    private func restoreDiscoverSessionIfAvailable() {
        guard appState.hasResolvedAuthState else {
            isLoading = true
            return
        }
        
        guard appState.hasResolvedUserProfile else {
            isLoading = true
            return
        }
        
        if needsProfileCompletion {
            profiles = []
            currentCardIndex = 0
            hasCompletedDiscoverLoad = true
            isLoading = false
            return
        }
        
        applyPendingDistanceRefreshIfAllowed()
        
        if !appState.hasValidDiscoverProfilesCache {
            appState.loadPersistedDiscoverProfilesCacheIfNeeded()
        }
        
        if appState.hasValidDiscoverProfilesCache, !appState.cachedDiscoverProfiles.isEmpty {
            profiles = appState.cachedDiscoverProfiles
            currentCardIndex = appState.cachedDiscoverCardIndex
            hasCompletedDiscoverLoad = true
            isLoading = false
            print("🔍 SearchView: Restored \(profiles.count) cached profiles at index \(currentCardIndex)")
            if currentCardIndex >= profiles.count {
                if hasMoreUsersToLoad
                    && DiscoverDailyLimit.currentCount() < DiscoverDailyLimit.maxSwipesPerDay {
                    prefetchMoreProfilesIfNeeded()
                }
            }
            return
        }

        // Daily limit with no frozen deck yet: still load so the blurry overlay has cards.
        if DiscoverDailyLimit.currentCount() >= DiscoverDailyLimit.maxSwipesPerDay {
            print("🔍 SearchView: Daily limit active without cache — loading deck for limit overlay")
            loadDiscoverProfilesWhenReady(allowWhileDailyLimitReached: true)
            return
        }

        if appState.hasValidDiscoverProfilesCache {
            appState.clearDiscoverProfilesCache()
        }
        loadDiscoverProfilesWhenReady()
    }
    
    private func reloadDiscoverDeck() {
        guard !needsProfileCompletion else { return }
        hasCompletedDiscoverLoad = false
        isLoading = true
        profiles = []
        currentCardIndex = 0
        lastFetchedUserDocumentId = nil
        hasMoreUsersToLoad = true
        hasMoreRemoteUsers = true
        cachedSwipeFilter = nil
        pendingDiscoverProfiles = []
        lastUndoableSwipe = nil
        canUseUndoButton = false
        undoEnableWorkItem?.cancel()
        pendingUndoEntrance = nil
        discoverLoadEpoch += 1
        restoreDiscoverSessionIfAvailable()
    }
    
    /// Distance may have changed while the daily limit froze the deck - refresh once unlocked.
    private func applyPendingDistanceRefreshIfAllowed() {
        guard DiscoverDistanceLimit.hasPendingDeckRefresh else { return }
        guard DiscoverDailyLimit.currentCount() < DiscoverDailyLimit.maxSwipesPerDay else { return }
        DiscoverDistanceLimit.hasPendingDeckRefresh = false
        appState.clearDiscoverProfilesCache()
        print("🔍 SearchView: Applying deferred discover deck refresh")
    }

    private func loadDiscoverProfilesWhenReady(allowWhileDailyLimitReached: Bool = false) {
        guard appState.isAuthenticated else {
            isLoading = false
            return
        }
        
        if needsProfileCompletion {
            hasCompletedDiscoverLoad = true
            isLoading = false
            profiles = []
            return
        }

        // Keep the frozen blurry deck while the daily swipe limit is active.
        if DiscoverDailyLimit.currentCount() >= DiscoverDailyLimit.maxSwipesPerDay,
           !allowWhileDailyLimitReached {
            hasCompletedDiscoverLoad = true
            isLoading = false
            return
        }

        guard appState.currentUser != nil else {
            print("🔍 SearchView: Waiting for current user before loading discover profiles")
            hasCompletedDiscoverLoad = false
            isLoading = true
            return
        }

        hasCompletedDiscoverLoad = false
        isLoading = true
        lastFetchedUserDocumentId = nil
        hasMoreUsersToLoad = true
        hasMoreRemoteUsers = true
        cachedSwipeFilter = nil
        pendingDiscoverProfiles = []
        // If a radius is set but we don't have coordinates yet, wait — otherwise every
        // candidate is filtered out and Home shows the empty "everyone nearby" card.
        if DiscoverDistanceLimit.currentOption.maxKilometers != nil,
           appState.currentUser?.location.latitude == nil
            || appState.currentUser?.location.longitude == nil {
            print("🔍 SearchView: Waiting for location coordinates before discover load")
            return
        }
        loadDiscoverProfiles()
    }
    
    /// After signup, location coords can arrive a moment after Home appears.
    private func retryDiscoverLoadAfterLocationReady() {
        guard !needsProfileCompletion else { return }
        guard profiles.isEmpty else { return }
        guard appState.currentUser?.location.latitude != nil,
              appState.currentUser?.location.longitude != nil else { return }
        print("🔍 SearchView: Location ready — reloading discover deck")
        reloadDiscoverDeck()
    }

    private func syncDiscoverCache() {
        guard appState.isAuthenticated, hasCompletedDiscoverLoad, !isLoading, !profiles.isEmpty else { return }
        appState.updateDiscoverProfilesCache(profiles: profiles, cardIndex: currentCardIndex)
    }

    private func markDiscoverLoadCompleted() {
        hasCompletedDiscoverLoad = true
        isLoading = false
        syncDiscoverCache()
    }
    
    private func makeProfileCard(from user: SpectRoomUser, currentUser: SpectRoomUser) -> ProfileCard {
        let distanceString: String
        if let distanceKm = calculateDistance(from: currentUser.location, to: user.location) {
            distanceString = formatDistance(distanceKm)
        } else {
            distanceString = String(format: "search.distance.km".localized, "2")
        }
        
        let matchPercentage = ProfileCard.calculateMatchPercentage(
            interests: user.interests,
            age: user.age,
            gender: user.gender,
            lookingFor: user.lookingFor,
            sensoryPreferences: user.sensoryPreferences,
            shareSensoryPreferences: user.shareSensoryPreferences,
            lifestyle: user.lifestyle,
            shareLifestyle: user.shareLifestyle,
            idealFirstDate: user.idealFirstDate,
            shareIdealFirstDate: user.shareIdealFirstDate,
            currentUser: currentUser
        )
        
        return ProfileCard(
            userId: user.firebaseDocumentId ?? user.id.uuidString,
            name: user.name,
            age: user.age,
            bio: user.bio,
            interests: user.interests,
            distance: distanceString,
            imageURL: user.profilePhotoURL,
            gender: user.gender,
            interestedIn: user.interestedIn,
            lookingFor: user.lookingFor,
            photos: user.photos,
            lifestyle: user.lifestyle,
            shareLifestyle: user.shareLifestyle,
            bodyType: user.bodyType,
            shareBodyType: user.shareBodyType,
            preferredAgeMin: user.preferredAgeMin,
            preferredAgeMax: user.preferredAgeMax,
            isOnline: user.isOnline,
            lastSeen: user.lastSeen,
            idealFirstDate: user.idealFirstDate,
            shareIdealFirstDate: user.shareIdealFirstDate,
            sensoryPreferences: user.sensoryPreferences,
            shareSensoryPreferences: user.shareSensoryPreferences,
            energyLevel: user.energyLevel,
            matchPercentage: matchPercentage
        )
    }
    
    private func sortProfilesByMatchPercentage(_ items: [ProfileCard]) -> [ProfileCard] {
        items.sorted {
            if $0.matchPercentage != $1.matchPercentage {
                return $0.matchPercentage > $1.matchPercentage
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    private func appendProfilesFromPendingQueue() {
        guard !pendingDiscoverProfiles.isEmpty else {
            hasMoreUsersToLoad = hasMoreRemoteUsers
            isLoadingMoreProfiles = false
            return
        }
        
        let nextBatch = Array(pendingDiscoverProfiles.prefix(DiscoverConstants.profilesPerBatch))
        pendingDiscoverProfiles.removeFirst(nextBatch.count)
        profiles.append(contentsOf: nextBatch)
        hasMoreUsersToLoad = hasMoreRemoteUsers || !pendingDiscoverProfiles.isEmpty
        isLoadingMoreProfiles = false
        print("✅ SearchView: Appended \(nextBatch.count) profiles from sorted queue (total: \(profiles.count))")
    }
    
    private func loadDiscoverProfiles(
        ignorePassedFilter: Bool = false,
        preferServerSwipeData: Bool = false,
        append: Bool = false
    ) {
        let loadEpoch = discoverLoadEpoch
        
        if append {
            guard !isLoadingMoreProfiles, hasMoreUsersToLoad else { return }
            isLoadingMoreProfiles = true
            
            if !pendingDiscoverProfiles.isEmpty {
                appendProfilesFromPendingQueue()
                syncDiscoverCache()
                return
            }
            
            guard hasMoreRemoteUsers else {
                hasMoreUsersToLoad = false
                isLoadingMoreProfiles = false
                return
            }
        } else {
            print("🔍 SearchView: Starting paginated profile load (batch size \(DiscoverConstants.profilesPerBatch))...")
            guard appState.currentUser != nil else {
                print("⚠️ SearchView: currentUser not ready yet, deferring profile load")
                hasCompletedDiscoverLoad = false
                isLoading = true
                return
            }
            isLoading = true
            lastFetchedUserDocumentId = nil
            hasMoreUsersToLoad = true
            hasMoreRemoteUsers = true
            pendingDiscoverProfiles = []
            profiles = []
            currentCardIndex = 0
        }
        
        Task {
            do {
                let swipeFilter: FirebaseAuthService.SwipeFilterState
                if append, let cachedSwipeFilter {
                    swipeFilter = cachedSwipeFilter
                } else {
                    swipeFilter = try await FirebaseAuthService.shared.fetchSwipeFilterState(preferServer: preferServerSwipeData)
                    await MainActor.run {
                        guard loadEpoch == discoverLoadEpoch else { return }
                        cachedSwipeFilter = swipeFilter
                    }
                }
                
                guard let currentUser = await MainActor.run(body: { appState.currentUser }) else {
                    await MainActor.run {
                        guard loadEpoch == discoverLoadEpoch else { return }
                        hasCompletedDiscoverLoad = false
                        isLoading = false
                        isLoadingMoreProfiles = false
                    }
                    return
                }
                
                let blockedUserIds = await MainActor.run { appState.hiddenByBlockUserIds }
                var collectedProfiles: [ProfileCard] = []
                var cursor = await MainActor.run { append ? lastFetchedUserDocumentId : nil }
                var hasMore = true
                var seenUserIds = await MainActor.run { Set(profiles.map(\.userId)) }
                let minimumProfiles = DiscoverConstants.profilesPerBatch
                
                while hasMore && collectedProfiles.count < minimumProfiles {
                    let stillCurrent = await MainActor.run { loadEpoch == discoverLoadEpoch }
                    guard stillCurrent else { return }
                    
                    let page = try await FirebaseAuthService.shared.fetchUsersPage(
                        limit: DiscoverConstants.firestorePageSize,
                        startAfterDocumentId: cursor
                    )
                    
                    cursor = page.lastDocumentId
                    hasMore = page.hasMore
                    
                    let eligibleUsers = page.users.filter { user in
                        let userId = user.firebaseDocumentId ?? user.id.uuidString
                        guard !seenUserIds.contains(userId) else { return false }
                        
                        let isEligible = isUserEligibleForDeck(
                            user: user,
                            currentUser: currentUser,
                            likedUserIds: swipeFilter.likedUserIds,
                            passedUserIds: swipeFilter.passedUserIds,
                            blockedUserIds: blockedUserIds,
                            ignorePassedFilter: ignorePassedFilter
                        )
                        
                        if isEligible {
                            seenUserIds.insert(userId)
                        }
                        
                        return isEligible
                    }
                    
                    collectedProfiles.append(contentsOf: eligibleUsers.map { makeProfileCard(from: $0, currentUser: currentUser) })
                }
                
                let sortedProfiles = sortProfilesByMatchPercentage(collectedProfiles)
                
                await MainActor.run {
                    guard loadEpoch == discoverLoadEpoch else {
                        print("🔍 SearchView: Ignoring stale discover load result (epoch \(loadEpoch))")
                        return
                    }
                    
                    lastFetchedUserDocumentId = cursor
                    hasMoreRemoteUsers = hasMore
                    
                    if append {
                        profiles.append(contentsOf: sortedProfiles)
                        hasMoreUsersToLoad = hasMoreRemoteUsers || !pendingDiscoverProfiles.isEmpty
                        isLoadingMoreProfiles = false
                        print("✅ SearchView: Loaded \(sortedProfiles.count) more profiles (total: \(profiles.count))")
                    } else {
                        profiles = Array(sortedProfiles.prefix(DiscoverConstants.profilesPerBatch))
                        pendingDiscoverProfiles = Array(sortedProfiles.dropFirst(DiscoverConstants.profilesPerBatch))
                        hasMoreUsersToLoad = hasMoreRemoteUsers || !pendingDiscoverProfiles.isEmpty
                        print("✅ SearchView: Loaded initial \(profiles.count) profiles, \(pendingDiscoverProfiles.count) queued by match %")
                        markDiscoverLoadCompleted()
                    }
                    
                    syncDiscoverCache()
                }
            } catch {
                print("❌ SearchView: Error loading users: \(error.localizedDescription)")
                await MainActor.run {
                    guard loadEpoch == discoverLoadEpoch else { return }
                    if !append {
                        profiles = []
                        pendingDiscoverProfiles = []
                        hasCompletedDiscoverLoad = false
                    }
                    isLoading = false
                    isLoadingMoreProfiles = false
                }
            }
        }
    }
    
    private func prefetchMoreProfilesIfNeeded() {
        // Don't rebuild/extend the deck while the daily limit freezes the UI.
        guard DiscoverDailyLimit.currentCount() < DiscoverDailyLimit.maxSwipesPerDay
                || isReviewingTodaysPasses else { return }
        
        let remainingCards = profiles.count - currentCardIndex
        // When the user reaches the 7th card of a 10-card batch, remaining == 4.
        guard remainingCards <= DiscoverConstants.prefetchRemainingThreshold,
              hasMoreUsersToLoad,
              !isLoadingMoreProfiles,
              !isLoading else { return }
        
        print("🔍 SearchView: Prefetching next \(DiscoverConstants.profilesPerBatch) profiles (at card \(currentCardIndex + 1), \(remainingCards) remaining)")
        loadDiscoverProfiles(append: true)
    }
    
    private func loadSampleProfiles() {
        profiles = [
            ProfileCard(userId: "sample_alex_id", name: "Alex", age: 25, bio: "Love photography and hiking. Looking for someone to explore the city with!", interests: ["Photography", "Hiking", "Coffee"], distance: "2 km away", imageURL: nil, gender: "Man", interestedIn: ["Woman"], lookingFor: ["Relationship"], photos: [], lifestyle: "independent", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 25, preferredAgeMax: 30, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_sam_id", name: "Sam", age: 28, bio: "Artist and musician. Always up for a good conversation!", interests: ["Art", "Music", "Reading"], distance: "5 km away", imageURL: nil, gender: "Woman", interestedIn: ["Man"], lookingFor: ["Friendship"], photos: [], lifestyle: "familySupport", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 28, preferredAgeMax: 33, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_jordan_id", name: "Jordan", age: 23, bio: "Tech enthusiast and gamer. Let's grab coffee and chat!", interests: ["Technology", "Gaming", "Coffee"], distance: "1 km away", imageURL: nil, gender: "Man", interestedIn: ["Woman"], lookingFor: ["Relationship"], photos: [], lifestyle: "assistedSetting", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 23, preferredAgeMax: 28, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_taylor_id", name: "Taylor", age: 26, bio: "Fitness lover and foodie. Looking for someone to share adventures with!", interests: ["Fitness", "Cooking", "Travel"], distance: "3 km away", imageURL: nil, gender: "Woman", interestedIn: ["Man"], lookingFor: ["Relationship"], photos: [], lifestyle: "independent", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 26, preferredAgeMax: 31, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_casey_id", name: "Casey", age: 24, bio: "Bookworm and nature enthusiast. Let's go for a walk!", interests: ["Reading", "Nature", "Writing"], distance: "4 km away", imageURL: nil, gender: "Other", interestedIn: ["Man", "Woman"], lookingFor: ["Friendship"], photos: [], lifestyle: "preferNot", shareLifestyle: false, bodyType: "", shareBodyType: false, preferredAgeMin: 24, preferredAgeMax: 29, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4)
        ]
    }
    
    private func prepareUndoableSwipe(profile: ProfileCard, action: SwipeType) {
        undoEnableWorkItem?.cancel()
        canUseUndoButton = false
        lastUndoableSwipe = UndoableDiscoverSwipe(
            profile: profile,
            action: action,
            cardIndexBeforeSwipe: currentCardIndex,
            countedTowardDailyLimit: !isReviewingTodaysPasses
        )
    }
    
    private func scheduleUndoButtonEnable() {
        undoEnableWorkItem?.cancel()
        canUseUndoButton = false
        let work = DispatchWorkItem {
            // Only arm undo once the fly-off has finished and the next card is showing.
            if lastUndoableSwipe != nil {
                canUseUndoButton = true
            }
        }
        undoEnableWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    
    private func handleSwipeRight(profile: ProfileCard) {
        guard !showsDailyLimitOverlay else { return }
        guard lastUndoableSwipe?.profile.userId == profile.userId,
              lastUndoableSwipe?.action == .like else {
            // Undo cancelled this swipe before it committed.
            return
        }
        
        // Advance the deck immediately - never wait on network for the next-card animation.
        print("✅ Liked: \(profile.name)")
        let countedTowardDailyLimit = lastUndoableSwipe?.countedTowardDailyLimit == true
        if countedTowardDailyLimit {
            dailySwipeCount = DiscoverDailyLimit.recordSwipe()
        }
        let swipeToken = UUID()
        activeSwipeTokens[profile.userId] = swipeToken
        moveToNextCard()
        scheduleUndoButtonEnable()
        
        Task {
            do {
                try await FirebaseAuthService.shared.recordSwipe(to: profile.userId, action: .like)
                
                let stillActive = await MainActor.run {
                    activeSwipeTokens[profile.userId] == swipeToken
                }
                if !stillActive {
                    try? await FirebaseAuthService.shared.undoLastSwipe(to: profile.userId)
                    return
                }
                
                guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else { return }
                
                let matchId = FirebaseAuthService.shared.matchDocumentId(
                    for: currentUserId,
                    and: profile.userId
                )
                
                var isMatch = try await FirebaseAuthService.shared.checkForMatch(with: profile.userId)
                
                if !isMatch {
                    // Cloud Function may create the match shortly after the swipe is saved.
                    // Poll briefly in the background - UI already advanced.
                    for _ in 0..<4 {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        let stillActive = await MainActor.run {
                            activeSwipeTokens[profile.userId] == swipeToken
                        }
                        if !stillActive {
                            try? await FirebaseAuthService.shared.undoLastSwipe(to: profile.userId)
                            return
                        }
                        isMatch = try await FirebaseAuthService.shared.matchExists(with: profile.userId)
                        if isMatch { break }
                    }
                }
                
                if isMatch {
                    await MainActor.run {
                        guard activeSwipeTokens[profile.userId] == swipeToken else { return }
                        print("💕 Match with \(profile.name)! Showing popup")
                        appState.presentMatchNotification(otherUser: profile, matchId: matchId)
                    }
                } else {
                    print("💕 Liked \(profile.name), but no match yet")
                }
            } catch {
                print("❌ Error handling swipe right: \(error)")
            }
        }
    }
    
    private func handleSwipeLeft(profile: ProfileCard) {
        guard !showsDailyLimitOverlay else { return }
        
        // Block from profile: same fly-off as Pass, but do not record a swipe (so unblock can restore).
        if blockPassInProgressUserId == profile.userId {
            blockPassInProgressUserId = nil
            print("🚫 Block-pass cleared from pile: \(profile.name)")
            lastUndoableSwipe = nil
            canUseUndoButton = false
            undoEnableWorkItem?.cancel()
            moveToNextCard()
            // Remove blocked profiles still waiting ahead in the pile.
            let kept = profiles.enumerated().compactMap { index, card -> ProfileCard? in
                if index > currentCardIndex && appState.isHiddenByBlock(card.userId) {
                    appState.rememberDiscoverProfileHiddenByBlock(card)
                    return nil
                }
                return card
            }
            if kept.count != profiles.count {
                profiles = kept
            }
            syncDiscoverCache()
            prefetchMoreProfilesIfNeeded()
            return
        }
        
        guard lastUndoableSwipe?.profile.userId == profile.userId,
              lastUndoableSwipe?.action == .pass else {
            // Undo cancelled this swipe before it committed.
            return
        }
        
        // Advance the deck immediately - never wait on network for the next-card animation.
        print("❌ Passed: \(profile.name)")
        let countedTowardDailyLimit = lastUndoableSwipe?.countedTowardDailyLimit == true
        if countedTowardDailyLimit {
            dailySwipeCount = DiscoverDailyLimit.recordSwipe()
        }
        let swipeToken = UUID()
        activeSwipeTokens[profile.userId] = swipeToken
        moveToNextCard()
        scheduleUndoButtonEnable()
        
        Task {
            do {
                try await FirebaseAuthService.shared.recordSwipe(to: profile.userId, action: .pass)
                let stillActive = await MainActor.run {
                    activeSwipeTokens[profile.userId] == swipeToken
                }
                if !stillActive {
                    try? await FirebaseAuthService.shared.undoLastSwipe(to: profile.userId)
                }
            } catch {
                print("❌ Error handling swipe left: \(error)")
            }
        }
    }
    
    private func undoLastSwipeIfPossible() {
        guard canUseUndoButton else { return }
        guard let undo = lastUndoableSwipe, !isUndoingSwipe, !showsDailyLimitOverlay else { return }
        
        isUndoingSwipe = true
        canUseUndoButton = false
        undoEnableWorkItem?.cancel()
        lastUndoableSwipe = nil
        activeSwipeTokens[undo.profile.userId] = UUID()
        // Cancel any in-flight fly-off animation / delayed swipe handler.
        swipeActionEpoch += 1
        programmaticSwipeDirection = nil
        
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.warning)
        
        if undo.countedTowardDailyLimit {
            dailySwipeCount = DiscoverDailyLimit.undoLastSwipe()
        }
        
        // Restore this profile as the top of the pile (still in the array after a swipe).
        let topIndex: Int
        if let existingIndex = profiles.firstIndex(where: { $0.userId == undo.profile.userId }) {
            topIndex = existingIndex
        } else {
            let insertAt = min(currentCardIndex, profiles.count)
            profiles.insert(undo.profile, at: insertAt)
            topIndex = insertAt
        }
        
        // Unique token so a delayed undo still triggers entrance (card remounts at center otherwise).
        pendingUndoEntrance = UndoCardEntrance(
            profileId: undo.profile.userId,
            fromLeadingEdge: undo.action == .pass,
            token: UUID()
        )
        // No spring on the index change — the card owns the fly-back animation.
        currentCardIndex = topIndex
        
        syncDiscoverCache()
        cachedSwipeFilter = nil
        
        if appState.newMatchProfile?.userId == undo.profile.userId {
            appState.dismissMatchNotification()
        }
        appState.removeMatchFromCache(userId: undo.profile.userId)
        
        Task {
            defer {
                Task { @MainActor in
                    isUndoingSwipe = false
                }
            }
            do {
                try await FirebaseAuthService.shared.undoLastSwipe(to: undo.profile.userId)
            } catch {
                print("❌ Error undoing swipe: \(error)")
            }
        }
    }
    
    private func moveToNextCard() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentCardIndex += 1
        }
        
        if isReviewingTodaysPasses {
            if currentCardIndex >= profiles.count {
                finishSecondThoughtsReview()
            }
            return
        }
        
        syncDiscoverCache()
        prefetchMoreProfilesIfNeeded()
    }
    
    private func startSecondThoughtsReview() {
        guard showsDailyLimitOverlay,
              !hasUsedSecondThoughtsToday,
              !isLoadingSecondThoughts,
              !isReviewingTodaysPasses else { return }
        
        isLoadingSecondThoughts = true
        
        Task {
            do {
                let passedIds = try await FirebaseAuthService.shared.fetchTodaysPassedUserIds()
                guard let currentUser = FirebaseAuthService.shared.currentUser else {
                    await MainActor.run {
                        isLoadingSecondThoughts = false
                        secondThoughtsErrorMessage = "search.daily.limit.second.thoughts.empty".localized
                    }
                    return
                }
                
                guard !passedIds.isEmpty else {
                    await MainActor.run {
                        DiscoverDailyLimit.markSecondThoughtsUsed()
                        hasUsedSecondThoughtsToday = true
                        isLoadingSecondThoughts = false
                        secondThoughtsErrorMessage = "search.daily.limit.second.thoughts.empty".localized
                    }
                    return
                }
                
                let users = try await FirebaseAuthService.shared.fetchUsers(byIds: passedIds)
                let cards = sortProfilesByMatchPercentage(
                    users.map { makeProfileCard(from: $0, currentUser: currentUser) }
                )
                
                await MainActor.run {
                    guard !cards.isEmpty else {
                        DiscoverDailyLimit.markSecondThoughtsUsed()
                        hasUsedSecondThoughtsToday = true
                        isLoadingSecondThoughts = false
                        secondThoughtsErrorMessage = "search.daily.limit.second.thoughts.empty".localized
                        return
                    }
                    
                    savedProfilesBeforeSecondThoughts = profiles
                    savedCardIndexBeforeSecondThoughts = currentCardIndex
                    profiles = cards
                    currentCardIndex = 0
                    isReviewingTodaysPasses = true
                    DiscoverDailyLimit.markSecondThoughtsUsed()
                    hasUsedSecondThoughtsToday = true
                    isLoadingSecondThoughts = false
                }
            } catch {
                print("❌ Error loading today's passed profiles: \(error)")
                await MainActor.run {
                    isLoadingSecondThoughts = false
                    secondThoughtsErrorMessage = "search.daily.limit.second.thoughts.empty".localized
                }
            }
        }
    }
    
    private func finishSecondThoughtsReview() {
        isReviewingTodaysPasses = false
        profiles = savedProfilesBeforeSecondThoughts
        currentCardIndex = min(savedCardIndexBeforeSecondThoughts, max(profiles.count - 1, 0))
        savedProfilesBeforeSecondThoughts = []
        savedCardIndexBeforeSecondThoughts = 0
        dailySwipeCount = DiscoverDailyLimit.currentCount()
        hasUsedSecondThoughtsToday = true
    }
    
    private func startCheckingForMatches() {
        print("💕 Starting periodic match checking")
        
        // Invalidate existing timer if any
        matchCheckTimer?.invalidate()
        
        // Check for matches every 3 seconds
        matchCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                await checkForNewMatches()
            }
        }
    }
    
    private func checkForNewMatches() async {
        // Only check if not already showing a match popup
        guard !showingMatchModal else {
            print("💕 Already showing match popup, skipping check")
            return
        }
        
        // Safety check for Firebase authentication
        guard FirebaseAuthService.shared.isAuthenticated else {
            print("💕 User not authenticated, skipping match check")
            return
        }
        
        do {
            // Fetch recent matches from Firebase
            let matches = try await FirebaseAuthService.shared.fetchMatches()
            
            // Check if there are any new matches
            for match in matches {
                let matchTime = match.matchedAt
                let timeDifference = Date().timeIntervalSince(matchTime)
                
                // Only show popup for matches created in the last 10 seconds
                if timeDifference <= 10.0 {
                    print("💕 Found new match: \(match.otherUser.name)")
                    
                    await MainActor.run {
                        // Set the profile FIRST, then show modal after a tiny delay
                        matchedProfile = match.otherUser
                        print("💕 matchedProfile set to: \(match.otherUser.name)")
                        
                        // Use asyncAfter to ensure state propagates before showing sheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            showingMatchModal = true
                            print("💕 showingMatchModal set to: \(showingMatchModal)")
                            print("💕 Showing match popup for: \(match.otherUser.name)")
                        }
                    }
                    break // Only show one popup at a time
                }
            }
        } catch {
            print("❌ Error checking for matches: \(error)")
        }
    }
    
    private var searchRadiusCornerButton: some View {
        Button {
            withAnimation(.spring(response: showingDistancePicker ? 0.34 : 0.42, dampingFraction: showingDistancePicker ? 0.86 : 0.78)) {
                showingDistancePicker.toggle()
                if showingDistancePicker {
                    showingEnergyLevelPicker = false
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image("map")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(selectedDistanceOption.shortButtonTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(SpectRoomTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(SpectRoomTheme.card, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(SpectRoomTheme.floatingPillBorder(for: colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("settings.distance.limit".localized)
        .accessibilityValue(selectedDistanceOption.title)
    }
    
    private func applySearchRadiusChange(_ option: DiscoverDistanceOption) {
        selectedDistanceOption = option
        DiscoverDistanceLimit.currentOption = option
        if DiscoverDailyLimit.currentCount() >= DiscoverDailyLimit.maxSwipesPerDay {
            DiscoverDistanceLimit.hasPendingDeckRefresh = true
        } else {
            DiscoverDistanceLimit.hasPendingDeckRefresh = false
            appState.invalidateDiscoverDeckAfterProfileUpdate()
        }
    }
    
    private var energyLevelCornerButton: some View {
        let option = EnergyLevelOption.resolved(from: appState.currentUser?.energyLevel ?? 4)
        return Button {
            withAnimation(.spring(response: showingEnergyLevelPicker ? 0.34 : 0.42, dampingFraction: showingEnergyLevelPicker ? 0.86 : 0.78)) {
                showingEnergyLevelPicker.toggle()
                if showingEnergyLevelPicker {
                    showingDistancePicker = false
                }
            }
        } label: {
            Text(option.emoji)
                .font(.system(size: 20))
                .floatingCircleButtonStyle(colorScheme: colorScheme, size: 44, brighterFrame: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("profile.my.energy.level".localized)
    }
}

struct EmptyStateCard: View {
    var isProfileIncomplete: Bool = false
    var onProfileTap: (() -> Void)? = nil
    
    private let cardWidth = UIScreen.main.bounds.width - 60
    private let cardHeight: CGFloat = 500
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(SpectRoomTheme.card)
                .frame(width: cardWidth, height: cardHeight)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            
            VStack(spacing: 24) {
                if isProfileIncomplete {
                    Text("search.empty.complete.profile.title".localized)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    
                    Text("search.empty.complete.profile.message".localized)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    
                    Button(action: { onProfileTap?() }) {
                        Text("search.empty.complete.profile.button".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(minWidth: 140)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("search.empty.no.more.profiles".localized)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

struct SwipeableProfileCard: View {
    let profile: ProfileCard
    let isTopCard: Bool
    var isDailyLimitReached: Bool = false
    var canUseSecondThoughts: Bool = false
    var isLoadingSecondThoughts: Bool = false
    var swipeActionEpoch: Int = 0
    var undoEntrance: UndoCardEntrance? = nil
    @Binding var programmaticSwipeDirection: String?
    let onSwipeRight: () -> Void
    let onSwipeLeft: () -> Void
    var onSwipeCommitted: ((String) -> Void)? = nil
    var onUndoEntranceConsumed: (() -> Void)? = nil
    let onTap: () -> Void
    var onSecondThoughtsTap: (() -> Void)? = nil
    
    private let cardWidth = UIScreen.main.bounds.width - 60
    private let cardHeight: CGFloat = 500
    private let photoAreaHeight: CGFloat = 340
    
    // MARK: - Helper function to extract first name
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    @State private var dragOffset = CGSize.zero
    @State private var rotationAngle: Double = 0
    @State private var isDragging = false
    @State private var programmaticDragOffset = CGSize.zero
    @State private var isProcessingProgrammaticSwipe = false
    @State private var showingDailyLimitWhy = false
    @State private var lastPlayedUndoEntranceToken: UUID?
    
    /// Snap off-screen then spring home. Works for immediate and delayed undo.
    private func playUndoEntranceIfNeeded() -> Bool {
        guard isTopCard,
              let entrance = undoEntrance,
              entrance.profileId == profile.userId,
              entrance.token != lastPlayedUndoEntranceToken else {
            return false
        }
        
        lastPlayedUndoEntranceToken = entrance.token
        isProcessingProgrammaticSwipe = false
        isDragging = false
        
        let screenWidth = UIScreen.main.bounds.width
        let startX = entrance.fromLeadingEdge ? -screenWidth * 1.15 : screenWidth * 1.15
        let startRotation = entrance.fromLeadingEdge ? -28.0 : 28.0
        
        var placeOffscreen = Transaction()
        placeOffscreen.disablesAnimations = true
        withTransaction(placeOffscreen) {
            programmaticDragOffset = CGSize(width: startX, height: 0)
            dragOffset = .zero
            rotationAngle = startRotation
        }
        
        // Next run loop so a remounted card paints off-screen before springing in.
        // Keep entrance token until the spring finishes so nothing else resets offsets mid-flight.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                programmaticDragOffset = .zero
                rotationAngle = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            onUndoEntranceConsumed?()
        }
        
        return true
    }
    
    var body: some View {
        ZStack {
            cardContent
                .blur(radius: isDailyLimitReached ? 8 : 0)
            
            if isDailyLimitReached {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: cardWidth, height: cardHeight)
                
                // Limit message only on the front card; pile tips stay blurred/dimmed.
                if isTopCard {
                    VStack(spacing: 18) {
                        Text("search.daily.limit.reached".localized)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        
                        if canUseSecondThoughts {
                            Button(action: {
                                onSecondThoughtsTap?()
                            }) {
                                Group {
                                    if isLoadingSecondThoughts {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("search.daily.limit.second.thoughts".localized)
                                            .font(.system(size: 15, weight: .semibold))
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                            }
                            .disabled(isLoadingSecondThoughts || onSecondThoughtsTap == nil)
                            .buttonStyle(.plain)
                        }
                        
                        Button(action: {
                            showingDailyLimitWhy = true
                        }) {
                            Text("search.daily.limit.why".localized)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .padding(.top, canUseSecondThoughts ? 2 : 0)
                    }
                }
            }
            
            // Swipe indicators overlay (centered on card)
            if isTopCard && !isDailyLimitReached {
                let combinedOffset = CGSize(
                    width: dragOffset.width + programmaticDragOffset.width,
                    height: dragOffset.height + programmaticDragOffset.height
                )
                
                // Pass indicator for left swipe
                if combinedOffset.width < 0 {
                    Text("search.pass".localized)
                        .font(.system(size: 72, weight: .heavy))
                        .foregroundColor(.red)
                        .opacity(min(abs(combinedOffset.width) / 170.0, 1.0))
                }
                
                // Like indicator for right swipe
                if combinedOffset.width > 0 {
                    Text("search.like".localized)
                        .font(.system(size: 72, weight: .heavy))
                        .foregroundColor(.green)
                        .opacity(min(combinedOffset.width / 170.0, 1.0))
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .offset(CGSize(
            width: isDailyLimitReached ? 0 : dragOffset.width + programmaticDragOffset.width,
            height: isDailyLimitReached ? 0 : dragOffset.height + programmaticDragOffset.height
        ))
        .rotationEffect(.degrees(isDailyLimitReached ? 0 : rotationAngle + Double(programmaticDragOffset.width / 20)))
        .onTapGesture {
            guard !isDailyLimitReached else { return }
            onTap()
        }
        .alert(
            "search.daily.limit.why.title".localized,
            isPresented: $showingDailyLimitWhy
        ) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("search.daily.limit.why.message".localized)
        }
        .onAppear {
            if isTopCard {
                if playUndoEntranceIfNeeded() {
                    return
                }
                // Don't snap-reset while an entrance is pending for this profile.
                if undoEntrance?.profileId == profile.userId {
                    return
                }
                programmaticDragOffset = .zero
                dragOffset = .zero
                rotationAngle = 0
                isProcessingProgrammaticSwipe = false
            }
        }
        .onChange(of: isTopCard) { newValue in
            if newValue {
                if playUndoEntranceIfNeeded() {
                    return
                }
                if undoEntrance?.profileId == profile.userId {
                    return
                }
                programmaticDragOffset = .zero
                dragOffset = .zero
                rotationAngle = 0
                isProcessingProgrammaticSwipe = false
            }
        }
        .onChange(of: undoEntrance?.token) { _ in
            _ = playUndoEntranceIfNeeded()
        }
        .task(id: undoEntrance?.token) {
            // Backup trigger for delayed undos where onAppear raced the entrance value.
            _ = playUndoEntranceIfNeeded()
        }
        .onChange(of: swipeActionEpoch) { _ in
            guard isTopCard else { return }
            // Don't clobber an in-progress undo entrance.
            if let entrance = undoEntrance, entrance.profileId == profile.userId {
                return
            }
            // Undo / cancel snapped the card back before the fly-off finished.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                programmaticDragOffset = .zero
                dragOffset = .zero
                rotationAngle = 0
            }
            isProcessingProgrammaticSwipe = false
        }
        .onChange(of: programmaticSwipeDirection) { newDirection in
            guard let direction = newDirection, isTopCard, !isProcessingProgrammaticSwipe else { return }
            
            // Set flag to prevent re-triggering
            isProcessingProgrammaticSwipe = true
            
            // Store the direction locally before clearing
            let swipeDirection = direction
            let epochAtStart = swipeActionEpoch
            
            // Reset programmatic drag state
            programmaticDragOffset = .zero
            
            // Clear the binding immediately to prevent onChange from triggering again
            programmaticSwipeDirection = nil
            
            // Step 1: Animate indicator appearing fully (reach 170pt for full opacity)
            withAnimation(.easeOut(duration: 0.6)) {
                if swipeDirection == "right" {
                    programmaticDragOffset = CGSize(width: 170, height: 0)
                } else if swipeDirection == "left" {
                    programmaticDragOffset = CGSize(width: -170, height: 0)
                }
            }
            
            // Step 2: After indicator is fully visible (full opacity), animate card off-screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard swipeActionEpoch == epochAtStart else {
                    isProcessingProgrammaticSwipe = false
                    return
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if swipeDirection == "right" {
                        programmaticDragOffset = CGSize(width: 1000, height: 0)
                        rotationAngle = 30
                    } else if swipeDirection == "left" {
                        programmaticDragOffset = CGSize(width: -1000, height: 0)
                        rotationAngle = -30
                    }
                }
                
                // Call handler after animation starts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard swipeActionEpoch == epochAtStart else {
                        isProcessingProgrammaticSwipe = false
                        return
                    }
                    if swipeDirection == "right" {
                        onSwipeRight()
                    } else if swipeDirection == "left" {
                        onSwipeLeft()
                    }
                    
                    // Reset flag after handler is called
                    // Don't reset visual state - keep card off-screen
                    // The state will be reset when a new card becomes the top card
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isProcessingProgrammaticSwipe = false
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !isDailyLimitReached else { return }
                    if isTopCard {
                        // Set dragging flag to prevent premature completion
                        if !isDragging {
                            isDragging = true
                        }
                        // Update visual feedback during drag
                        dragOffset = value.translation
                        rotationAngle = Double(value.translation.width / 20)
                    }
                }
                .onEnded { value in
                    guard !isDailyLimitReached else { return }
                    if isTopCard {
                        // Mark dragging as ended - user lifted their hand
                        isDragging = false
                        
                        let threshold: CGFloat = 100
                        let epochAtStart = swipeActionEpoch
                        
                        // Only complete swipe action if user lifted their hand (drag ended)
                        if value.translation.width > threshold {
                            // Swipe right - Like
                            onSwipeCommitted?("right")
                            withAnimation(.spring()) {
                                dragOffset = CGSize(width: 1000, height: 0)
                                rotationAngle = 30
                            }
                            // Action only executes after user lifts hand (onEnded)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                guard swipeActionEpoch == epochAtStart else { return }
                                // Double-check: only execute if user has lifted hand
                                if !isDragging {
                                    onSwipeRight()
                                }
                            }
                        } else if value.translation.width < -threshold {
                            // Swipe left - Pass
                            onSwipeCommitted?("left")
                            withAnimation(.spring()) {
                                dragOffset = CGSize(width: -1000, height: 0)
                                rotationAngle = -30
                            }
                            // Action only executes after user lifts hand (onEnded)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                guard swipeActionEpoch == epochAtStart else { return }
                                // Double-check: only execute if user has lifted hand
                                if !isDragging {
                                    onSwipeLeft()
                                }
                            }
                        } else {
                            // Return to center
                            withAnimation(.spring()) {
                                dragOffset = .zero
                                rotationAngle = 0
                            }
                        }
                    }
                }
        )
        .allowsHitTesting(true)
    }
    
    private var cardContent: some View {
        ZStack {
            // Card background with fixed width
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(SpectRoomTheme.card)
                .frame(width: cardWidth, height: cardHeight)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            
            VStack(spacing: 0) {
                // Immersive photo with identity overlays
                ZStack(alignment: .bottomLeading) {
                    ZStack {
                        if let imageURL = profile.imageURL, let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 80))
                                            .foregroundColor(.gray)
                                    )
                            }
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                    .frame(width: cardWidth, height: photoAreaHeight)
                    .clipped()
                    
                    // Soft top gradient so distance stays readable on bright photos
                    LinearGradient(
                        colors: [
                            .black.opacity(0.5),
                            .black.opacity(0.18),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Soft bottom gradient for readable name / age
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.15),
                            .black.opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    
                    // Distance - top trailing
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(profile.distance)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .padding(.top, 14)
                            .padding(.trailing, 14)
                        }
                        Spacer()
                    }
                    
                    // Name, age, online - bottom of photo
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(firstName(from: profile.name)), \(profile.age)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(profile.isOnline ? Color.green : Color.white.opacity(0.55))
                                    .frame(width: 8, height: 8)
                                Text(profile.isOnline ? "search.online.now".localized : "search.offline".localized)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(width: cardWidth, height: photoAreaHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24,
                        style: .continuous
                    )
                )
                
                // Bio + match - clean footer, no nested boxes
                VStack(alignment: .leading, spacing: 30) {
                    Text(profile.bio)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(SpectRoomTheme.text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        let matchPercentage = profile.matchPercentage
                        let profileFirstName = firstName(from: profile.name)
                        let matchColor: Color = matchPercentage > 49 ? .green : .secondary
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(matchColor)
                                    .frame(
                                        width: geo.size.width * CGFloat(max(0, min(matchPercentage, 100))) / 100.0,
                                        height: 6
                                    )
                            }
                        }
                        .frame(height: 6)
                        
                        (Text("search.match.prefix".localized)
                         + Text(String(format: "search.match.percent.part".localized, matchPercentage))
                            .foregroundColor(matchColor)
                         + Text("search.match.label".localized)
                         + Text(String(format: "search.match.suffix".localized, profileFirstName)))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(SpectRoomTheme.text)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

// Appearance for stacked cards under the top card
private struct StackAppearance: ViewModifier {
    let depth: Int
    func body(content: Content) -> some View {
        let clampedDepth = max(0, depth)
        
        // Pile effect: cards behind peek out from top center
        // Scale down slightly for cards behind
        let scale = max(0.95, 1.0 - CGFloat(clampedDepth) * 0.02)
        
        // Offset cards behind: move up only (centered horizontally, creating vertical pile effect)
        // Increased spacing for clearer pile effect
        let yOffset = CGFloat(clampedDepth) * -24  // Move up (negative = up), increased from -12 to -24 for more separation
        
        return content
            .scaleEffect(scale)
            .offset(y: yOffset)
            .opacity(clampedDepth == 0 ? 1.0 : 0.95)
    }
}

private struct BlueFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
            )
    }
}

private extension View {
    func blueFieldStyle() -> some View {
        modifier(BlueFieldStyle())
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

/// Shared Home picker chrome so energy + radius dialogs match in size and position.
private enum DiscoverHomeDialogMetrics {
    static let horizontalInset: CGFloat = 30
    static let contentPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 12
    static let energyRowHeight: CGFloat = 112
    static let energyRowCount = 3
    static let distanceRowCount = 5
    static let headerBlockHeight: CGFloat = 78
    static let accent = Color(hex: "#64B5F6")
    
    /// Same width energy gets via `.padding(.horizontal, horizontalInset)`.
    static var panelWidth: CGFloat {
        UIScreen.main.bounds.width - (horizontalInset * 2)
    }
    
    static var optionsStackHeight: CGFloat {
        CGFloat(energyRowCount) * energyRowHeight
            + CGFloat(energyRowCount - 1) * sectionSpacing
    }
    
    static var distanceRowHeight: CGFloat {
        let gaps = CGFloat(distanceRowCount - 1) * sectionSpacing
        return (optionsStackHeight - gaps) / CGFloat(distanceRowCount)
    }
    
    static var panelHeight: CGFloat {
        contentPadding * 2
            + headerBlockHeight
            + sectionSpacing
            + optionsStackHeight
    }
}

private struct EnergyLevelPickerOverlay: View {
    let selectedLevel: Int
    let onSelect: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private let accent = DiscoverHomeDialogMetrics.accent
    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? Color.white : Color.black }
    private var primaryText: Color { isLight ? Color.black : Color.white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.8) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DiscoverHomeDialogMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("profile.my.energy.level".localized)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(primaryText)
                
                Text("profile.energy.level.subtitle".localized)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: DiscoverHomeDialogMetrics.headerBlockHeight, maxHeight: DiscoverHomeDialogMetrics.headerBlockHeight, alignment: .topLeading)
            
            VStack(spacing: DiscoverHomeDialogMetrics.sectionSpacing) {
                ForEach(EnergyLevelOption.allCases, id: \.rawValue) { option in
                    energyOptionRow(option)
                }
            }
            .frame(maxWidth: .infinity, minHeight: DiscoverHomeDialogMetrics.optionsStackHeight, maxHeight: DiscoverHomeDialogMetrics.optionsStackHeight, alignment: .top)
        }
        .padding(DiscoverHomeDialogMetrics.contentPadding)
        .frame(maxWidth: .infinity)
        .frame(height: DiscoverHomeDialogMetrics.panelHeight)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isLight ? Color.black.opacity(0.06) : Color.clear, lineWidth: 1)
        )
    }
    
    private func energyOptionRow(_ option: EnergyLevelOption) -> some View {
        let isSelected = EnergyLevelOption.resolved(from: selectedLevel) == option
        let fill = isSelected
            ? accent.opacity(isLight ? 0.18 : 0.28)
            : (isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
        let stroke = isSelected
            ? accent.opacity(0.95)
            : (isLight ? Color.black.opacity(0.14) : Color.white.opacity(0.18))
        let titleColor = isSelected
            ? primaryText
            : primaryText.opacity(0.75)
        let detailColor = isSelected
            ? secondaryText
            : secondaryText.opacity(0.85)
        
        return Button {
            onSelect(option.rawValue)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(option.emoji)
                    .font(.system(size: 28))
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(titleColor)
                        .multilineTextAlignment(.leading)
                    Text(option.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(detailColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accent)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .frame(
                maxWidth: .infinity,
                minHeight: DiscoverHomeDialogMetrics.energyRowHeight,
                maxHeight: DiscoverHomeDialogMetrics.energyRowHeight,
                alignment: .center
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SearchRadiusPickerOverlay: View {
    let selectedOption: DiscoverDistanceOption
    let onSelect: (DiscoverDistanceOption) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private let accent = DiscoverHomeDialogMetrics.accent
    
    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? Color.white : Color.black }
    private var primaryText: Color { isLight ? Color.black : Color.white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.8) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DiscoverHomeDialogMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings.distance.limit".localized)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(primaryText)
                
                Text("search.radius.subtitle".localized)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: DiscoverHomeDialogMetrics.headerBlockHeight, maxHeight: DiscoverHomeDialogMetrics.headerBlockHeight, alignment: .topLeading)
            
            VStack(spacing: DiscoverHomeDialogMetrics.sectionSpacing) {
                ForEach(DiscoverDistanceOption.allCases) { option in
                    distanceOptionRow(option)
                }
            }
            .frame(maxWidth: .infinity, minHeight: DiscoverHomeDialogMetrics.optionsStackHeight, maxHeight: DiscoverHomeDialogMetrics.optionsStackHeight, alignment: .top)
        }
        .padding(DiscoverHomeDialogMetrics.contentPadding)
        .frame(width: DiscoverHomeDialogMetrics.panelWidth, height: DiscoverHomeDialogMetrics.panelHeight)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isLight ? Color.black.opacity(0.06) : Color.clear, lineWidth: 1)
        )
    }
    
    private func distanceOptionRow(_ option: DiscoverDistanceOption) -> some View {
        let isSelected = option == selectedOption
        let iconColor = isSelected ? accent : (isLight ? Color.black.opacity(0.45) : Color.white.opacity(0.45))
        let fill = isSelected
            ? accent.opacity(isLight ? 0.18 : 0.28)
            : (isLight ? Color.black.opacity(0.05) : Color.white.opacity(0.08))
        let stroke = isSelected
            ? accent.opacity(0.95)
            : (isLight ? Color.black.opacity(0.14) : Color.white.opacity(0.18))
        
        return Button {
            onSelect(option)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if option == .unlimited {
                        Image("World")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    } else {
                        Image("Radius")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    }
                }
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                
                if option == .unlimited {
                    Text(option.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? primaryText : primaryText.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(option.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? primaryText : primaryText.opacity(0.75))
                        .frame(width: 64, alignment: .leading)
                    
                    // Overlay keeps bar length from contributing to the row's minimum width.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .leading) {
                            illustrationBar(for: option, color: iconColor)
                        }
                }
                
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accent)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .frame(
                maxWidth: .infinity,
                minHeight: DiscoverHomeDialogMetrics.distanceRowHeight,
                maxHeight: DiscoverHomeDialogMetrics.distanceRowHeight,
                alignment: .center
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func illustrationBar(for option: DiscoverDistanceOption, color: Color) -> some View {
        if let barWidth = illustrationBarWidth(for: option) {
            let tickHeight: CGFloat = 9
            let tickWidth: CGFloat = 2
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: barWidth, height: 3)
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: tickWidth, height: tickHeight)
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: tickWidth, height: tickHeight)
                    .offset(x: barWidth - tickWidth)
            }
            .frame(width: barWidth, height: tickHeight, alignment: .center)
        }
    }
    
    /// Tiny length cue next to each radius option (none for unlimited).
    private func illustrationBarWidth(for option: DiscoverDistanceOption) -> CGFloat? {
        switch option {
        case .fiveKm: return 47
        case .tenKm: return 64
        case .twentyKm: return 80
        case .fiftyKm: return 97
        case .unlimited: return nil
        }
    }
}

struct UserProfileModal: View {
    let profile: ProfileCard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppStateManager
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    @State private var refreshedProfile: ProfileCard?
    @State private var showingBlockConfirmation = false
    @State private var showingReportReason = false
    @State private var showingReportThankYou = false
    @State private var pendingReportReason: ProfileReportReason?
    @State private var pendingReportDetails: String?
    @State private var showingMatchDetails = false
    @State private var showingLookingForDetails = false
    
    init(profile: ProfileCard) {
        self.profile = profile
        print("🔍 UserProfileModal INIT called with profile: \(profile.name), userId: \(profile.userId)")
    }
    
    private var profileTitle: String {
        let name = displayProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "profile.title".localized : name
    }

    private var displayProfile: ProfileCard {
        refreshedProfile ?? profile
    }
    
    /// Always compute against the logged-in user so Matches (which used to omit %)
    /// shows the same value as Home cards.
    private var resolvedMatchPercentage: Int {
        if let currentUser = appState.currentUser {
            return ProfileCard.calculateMatchPercentage(
                interests: displayProfile.interests,
                age: displayProfile.age,
                gender: displayProfile.gender,
                lookingFor: displayProfile.lookingFor,
                sensoryPreferences: displayProfile.sensoryPreferences,
                shareSensoryPreferences: displayProfile.shareSensoryPreferences,
                lifestyle: displayProfile.lifestyle,
                shareLifestyle: displayProfile.shareLifestyle,
                idealFirstDate: displayProfile.idealFirstDate,
                shareIdealFirstDate: displayProfile.shareIdealFirstDate,
                currentUser: currentUser
            )
        }
        return displayProfile.matchPercentage
    }
    
    private var resolvedMatchBreakdown: ProfileCard.MatchBreakdown? {
        guard let currentUser = appState.currentUser else { return nil }
        return ProfileCard.calculateMatchBreakdown(
            interests: displayProfile.interests,
            age: displayProfile.age,
            gender: displayProfile.gender,
            lookingFor: displayProfile.lookingFor,
            sensoryPreferences: displayProfile.sensoryPreferences,
            shareSensoryPreferences: displayProfile.shareSensoryPreferences,
            lifestyle: displayProfile.lifestyle,
            shareLifestyle: displayProfile.shareLifestyle,
            idealFirstDate: displayProfile.idealFirstDate,
            shareIdealFirstDate: displayProfile.shareIdealFirstDate,
            currentUser: currentUser
        )
    }
    
    var body: some View {
        let _ = print("🔍 UserProfileModal body being computed, profile name: \(profile.name)")
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Header Section
                    profileHeaderSection
                    
                    // My Photos Section (moved right after profile photo)
                    myPhotosSection
                    
                    // Match percentage (same as home card)
                    matchSection
                    
                    // Age Section
                    ageSection
                    
                    // Location Section
                    locationSection
                    
                    // Energy Level Section
                    energyLevelSection
                    
                    // Gender & Preferences Section
                    genderPreferencesSection
                    
                    // About Me Section
                    aboutMeSection
                    
                    // My Interests Section
                    myInterestsSection
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 100) // Increased bottom padding
            }
            .background(
                SpectRoomBackground()
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isProfileBlocked {
                        Button("settings.blocked.users.unblock.action".localized) {
                            appState.unblockUser(userId: displayProfile.userId)
                        }
                    } else {
                        Button {
                            showingBlockConfirmation = true
                        } label: {
                            Image("block")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                        .accessibilityLabel("profile.block.confirm.action".localized)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(profileTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            print("🔍 UserProfileModal appeared for: \(profile.name)")
            print("🔍 Profile userId: \(profile.userId), name: \(profile.name)")
            // Reset refreshed profile to ensure we use the original profile initially
            refreshedProfile = nil
            // Ensure profile data is available
            guard !profile.userId.isEmpty else {
                print("❌ Profile userId is empty!")
                return
            }
            // Refresh profile data in background after view renders
            // Use a longer delay to ensure view is fully rendered first
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await refreshProfileAsync()
            }
        }
        .refreshable {
            // Allow pull-to-refresh
            await refreshProfileAsync()
        }
        .sheet(isPresented: $showingPhotoViewer) {
            let allPhotos: [String] = {
                var photos = displayProfile.photos
                if let profilePhotoURL = displayProfile.imageURL, !profilePhotoURL.isEmpty {
                    photos.insert(profilePhotoURL, at: 0)
                }
                return photos
            }()
            
            if !allPhotos.isEmpty {
                PhotoViewerModal(
                    photos: allPhotos,
                    selectedIndex: $selectedPhotoIndex
                )
                .presentationBackground(.clear)
            }
        }
        .overlay {
            if showingBlockConfirmation {
                BlockConfirmationOverlay(
                    firstName: firstName(from: displayProfile.name),
                    onCancel: { showingBlockConfirmation = false },
                    onBlock: {
                        appState.blockUser(userId: displayProfile.userId, name: displayProfile.name)
                    },
                    onBlockComplete: {
                        showingBlockConfirmation = false
                        dismiss()
                    },
                    onBlockAndReport: {
                        showingBlockConfirmation = false
                        appState.blockUser(userId: displayProfile.userId, name: displayProfile.name)
                        pendingReportReason = nil
                        pendingReportDetails = nil
                        showingReportReason = true
                    }
                )
            } else if showingReportReason {
                ReportReasonOverlay(
                    firstName: firstName(from: displayProfile.name),
                    onCancel: {
                        showingReportReason = false
                        dismiss()
                    },
                    onSubmit: { reason, details in
                        pendingReportReason = reason
                        pendingReportDetails = details
                        showingReportReason = false
                        showingReportThankYou = true
                        let reportedProfile = displayProfile
                        Task {
                            do {
                                try await FirebaseAuthService.shared.submitUserReport(
                                    reportedUserId: reportedProfile.userId,
                                    category: reason.storageCategory,
                                    details: details,
                                    reportedProfile: reportedProfile
                                )
                            } catch {
                                print("⚠️ Failed to submit report: \(error.localizedDescription)")
                            }
                        }
                    }
                )
            } else if showingReportThankYou {
                ReportThankYouOverlay {
                    showingReportThankYou = false
                    dismiss()
                }
            } else if showingMatchDetails {
                MatchDetailsOverlay(
                    firstName: firstName(from: displayProfile.name),
                    breakdown: resolvedMatchBreakdown,
                    localizedInterests: (resolvedMatchBreakdown?.commonInterests ?? []).map { localizedInterest($0) },
                    localizedLookingFor: {
                        let common = resolvedMatchBreakdown?.commonLookingFor ?? []
                        guard !common.isEmpty else { return "" }
                        return formatLookingFor(common)
                    }(),
                    localizedSensory: SensoryPreferenceOption.formattedTitles(resolvedMatchBreakdown?.commonSensoryPreferences ?? []),
                    localizedLifestyle: {
                        guard let lifestyle = resolvedMatchBreakdown?.sharedLifestyle else { return "" }
                        return formattedLifestyle(lifestyle)
                    }(),
                    localizedIdealFirstDate: formattedIdealFirstDate(resolvedMatchBreakdown?.commonIdealFirstDates ?? []),
                    onDismiss: { showingMatchDetails = false }
                )
            } else if showingLookingForDetails {
                LookingForDetailsOverlay(
                    items: lookingForPopupItems(displayProfile.lookingFor).map { formatPreference($0) },
                    onDismiss: { showingLookingForDetails = false }
                )
            }
        }
    }
    
    private var isProfileBlocked: Bool {
        appState.isUserBlocked(displayProfile.userId)
    }
    
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    // MARK: - Refresh Profile
    private func refreshProfile() {
        Task {
            await refreshProfileAsync()
        }
    }
    
    private func refreshProfileAsync() async {
        do {
            // Fetch latest profile data from Firebase
            let refreshed = try await FirebaseAuthService.shared.fetchUserProfile(for: profile.userId)
            
            // Keep the original distance from the profile card (already calculated).
            // Recalculate match % from the latest current user + refreshed profile data.
            let matchPercentage: Int
            if let currentUser = appState.currentUser {
                matchPercentage = ProfileCard.calculateMatchPercentage(
                    interests: refreshed.interests,
                    age: refreshed.age,
                    gender: refreshed.gender,
                    lookingFor: refreshed.lookingFor,
                    sensoryPreferences: refreshed.sensoryPreferences,
                    shareSensoryPreferences: refreshed.shareSensoryPreferences,
                    lifestyle: refreshed.lifestyle,
                    shareLifestyle: refreshed.shareLifestyle,
                    idealFirstDate: refreshed.idealFirstDate,
                    shareIdealFirstDate: refreshed.shareIdealFirstDate,
                    currentUser: currentUser
                )
            } else {
                matchPercentage = refreshed.matchPercentage
            }
            
            let updatedProfile = ProfileCard(
                userId: refreshed.userId,
                name: refreshed.name,
                age: refreshed.age,
                bio: refreshed.bio,
                interests: refreshed.interests,
                distance: profile.distance, // Keep original distance from card
                imageURL: refreshed.imageURL,
                gender: refreshed.gender,
                interestedIn: refreshed.interestedIn,
                lookingFor: refreshed.lookingFor,
                photos: refreshed.photos,
                lifestyle: refreshed.lifestyle,
                shareLifestyle: refreshed.shareLifestyle,
                bodyType: refreshed.bodyType,
                shareBodyType: refreshed.shareBodyType,
                preferredAgeMin: refreshed.preferredAgeMin,
                preferredAgeMax: refreshed.preferredAgeMax,
                isOnline: refreshed.isOnline,
                lastSeen: refreshed.lastSeen,
                idealFirstDate: refreshed.idealFirstDate,
                shareIdealFirstDate: refreshed.shareIdealFirstDate,
                sensoryPreferences: refreshed.sensoryPreferences,
                shareSensoryPreferences: refreshed.shareSensoryPreferences,
                energyLevel: refreshed.energyLevel,
                matchPercentage: matchPercentage
            )
            
            await MainActor.run {
                refreshedProfile = updatedProfile
                print("✅ Profile refreshed for: \(updatedProfile.name)")
            }
        } catch {
            print("❌ Error refreshing profile: \(error)")
            // Keep using original profile if refresh fails
        }
    }
    
    // MARK: - Profile Header Section
    private var profileHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.profile.photo".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            ProfileMainPhotoCard(
                imageURL: displayProfile.imageURL,
                onTap: {
                    let hasProfilePhoto = displayProfile.imageURL != nil && !(displayProfile.imageURL?.isEmpty ?? true)
                    let hasGalleryPhotos = !displayProfile.photos.isEmpty
                    if hasProfilePhoto || hasGalleryPhotos {
                        selectedPhotoIndex = 0
                        showingPhotoViewer = true
                    }
                }
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ProfilePhotoStyle.cardCorner, style: .continuous)
                .fill(SpectRoomTheme.card)
        )
    }
    
    // MARK: - Age Section
    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.age".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("\(displayProfile.age) " + "profile.years.old".localized)
                .font(.subheadline)
                .blueFieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.location".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(displayProfile.distance)
                .font(.subheadline)
                .blueFieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Energy Level Section
    private var energyLevelSection: some View {
        let energyOption = EnergyLevelOption.resolved(from: displayProfile.energyLevel)
        let levelColor = energyOption.color
        
        return VStack(alignment: .leading, spacing: 14) {
            Text("profile.energy.level".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(alignment: .top, spacing: 12) {
                Text(energyOption.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 4) {
                    Text(energyOption.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(levelColor)
                    Text(energyOption.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(SpectRoomTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(levelColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(levelColor.opacity(0.45), lineWidth: 1.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - About Me Section
    private var aboutMeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("profile.about.me".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(displayProfile.bio.isEmpty ? "profile.no.bio".localized : displayProfile.bio)
                .font(.body)
                .foregroundColor(displayProfile.bio.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .blueFieldStyle()
            
            if displayProfile.shareLifestyle {
                Text("profile.lifestyle.title".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(formattedLifestyle(displayProfile.lifestyle))
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .blueFieldStyle()
            }
            
            if displayProfile.shareBodyType, !displayProfile.bodyType.isEmpty {
                Text("profile.body.type".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(formattedBodyType(displayProfile.bodyType))
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .blueFieldStyle()
            }
            
            if !displayProfile.idealFirstDate.isEmpty {
                Text("profile.ideal.first.date".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(formattedIdealFirstDate(displayProfile.idealFirstDate))
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .blueFieldStyle()
            }
            
            if !displayProfile.sensoryPreferences.isEmpty {
                Text("profile.sensory.preferences".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(SensoryPreferenceOption.formattedTitles(displayProfile.sensoryPreferences))
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .blueFieldStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - My Interests Section
    private var myInterestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.interests".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            if displayProfile.interests.isEmpty {
                Text("profile.no.interests".localized)
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .blueFieldStyle()
            } else {
                Text(displayProfile.interests.map { localizedInterest($0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .blueFieldStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Gender & Preferences Section
    private var genderPreferencesSection: some View {
        let hasGenderOrInterestedIn = !displayProfile.gender.isEmpty || !displayProfile.interestedIn.isEmpty
        let hasLookingFor = !displayProfile.lookingFor.isEmpty
        let defaultMin = displayProfile.age
        let defaultMax = min(displayProfile.age + 5, 70)
        let hasCustomPreferredAge = displayProfile.preferredAgeMin != defaultMin || displayProfile.preferredAgeMax != defaultMax
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("profile.preferences".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            if hasGenderOrInterestedIn || hasLookingFor || hasCustomPreferredAge {
                VStack(alignment: .leading, spacing: 8) {
                    if hasGenderOrInterestedIn {
                        Group {
                            if !displayProfile.gender.isEmpty && !displayProfile.interestedIn.isEmpty {
                                Text("profile.im.a".localized + " \(formatGender(displayProfile.gender)), " + "profile.interested.in".localized + " \(formatInterestedIn(displayProfile.interestedIn))")
                            } else if !displayProfile.gender.isEmpty {
                                Text("profile.im.a".localized + " \(formatGender(displayProfile.gender))")
                            } else {
                                Text("profile.interested.in".localized.capitalized + " \(formatInterestedIn(displayProfile.interestedIn))")
                            }
                        }
                        .font(.body)
                        .foregroundColor(SpectRoomTheme.text)
                        .italic()
                        .blueFieldStyle()
                    }
                    
                    if hasLookingFor {
                        let lookingForText = "profile.looking.for".localized + ": \(formatLookingFor(displayProfile.lookingFor))"
                        let hasMultipleLookingFor = displayProfile.lookingFor.count > 1
                        
                        HStack(alignment: .center, spacing: 8) {
                            Text(lookingForText)
                                .font(.body)
                                .foregroundColor(SpectRoomTheme.text)
                                .italic()
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if hasMultipleLookingFor {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .blueFieldStyle()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if hasMultipleLookingFor {
                                showingLookingForDetails = true
                            }
                        }
                    }
                    
                    if hasCustomPreferredAge {
                        Text(String(format: "profile.preferred.age".localized, "\(displayProfile.preferredAgeMin)", "\(displayProfile.preferredAgeMax)"))
                            .font(.body)
                            .foregroundColor(SpectRoomTheme.text)
                            .italic()
                            .blueFieldStyle()
                    }
                }
            } else {
                Text("profile.no.preferences".localized)
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .italic()
                    .blueFieldStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func formatInterestedIn(_ preferences: [String]) -> String {
        if preferences.contains("Anyone") {
            return "profile.interested.anyone".localized
        } else if preferences.isEmpty {
            return "profile.no.one".localized
        } else {
            let formatted = preferences.map { formatPreference($0) }
            return formatted.joined(separator: " / ")
        }
    }
    
    private func formatGender(_ gender: String) -> String {
        gender.lowercased()
    }
    
    private func formatLookingFor(_ lookingFor: [String]) -> String {
        if lookingFor.isEmpty {
            return "profile.nothing.specific".localized
        } else {
            let formatted = lookingFor.map { formatPreference($0) }
            return formatted.joined(separator: " / ")
        }
    }

    private func formattedLifestyle(_ lifestyle: String) -> String {
        switch lifestyle {
        case "independent":
            return "profile.edit.lifestyle.independent".localized
        case "familySupport":
            return "profile.edit.lifestyle.family".localized
        case "assistedSetting":
            return "profile.edit.lifestyle.assisted".localized
        case "preferNot":
            // Migration: handle old "preferNot" value gracefully
            return ""
        default:
            return lifestyle.isEmpty ? "" : "profile.lifestyle.placeholder".localized
        }
    }
    
    private func formattedBodyType(_ bodyType: String) -> String {
        switch bodyType {
        case "slim":
            return "profile.edit.body.type.slim".localized
        case "average":
            return "profile.edit.body.type.average".localized
        case "athletic":
            return "profile.edit.body.type.athletic".localized
        case "fullBodied":
            return "profile.edit.body.type.full.bodied".localized
        case "preferNot":
            // Migration: handle old "preferNot" value gracefully
            return ""
        default:
            return bodyType
        }
    }
    
    // MARK: - Helper function to localize interest names
    private func localizedInterest(_ interest: String) -> String {
        let key = "profile.edit.interest.\(interest.lowercased())"
        let localized = key.localized
        // If localization key doesn't exist, return original
        return localized == key ? interest : localized
    }
    
    private func formattedIdealFirstDate(_ idealFirstDate: [String]) -> String {
        let formatted = idealFirstDate.map { option in
            switch option {
            case "relaxingParkWalk":
                return "profile.edit.ideal.date.relaxing.park.walk".localized
            case "cozyCafeMeet":
                return "profile.edit.ideal.date.cozy.cafe.meet".localized
            case "museumGalleryStroll":
                return "profile.edit.ideal.date.museum.gallery.stroll".localized
            case "cinemaMovieNight":
                return "profile.edit.ideal.date.cinema.movie.night".localized
            case "friendlyVideoChat":
                return "profile.edit.ideal.date.friendly.video.chat".localized
            default:
                return option
            }
        }
        return formatted.joined(separator: ", ")
    }
    
    private func lookingForPopupItems(_ lookingFor: [String]) -> [String] {
        let definiteOptions = lookingFor.filter { $0 != "Not sure yet" && $0 != "Not Sure Yet" }
        return definiteOptions.isEmpty ? lookingFor : definiteOptions
    }
    
    private func formatPreference(_ preference: String) -> String {
        switch preference {
        case "Romantic relationship", "Relationship":
            return "profile.edit.looking.romantic.relationship".localized
        case "In-Person Friendship", "Friendship":
            return "profile.edit.looking.in.person.friendship".localized
        case "Online Friendship":
            return "profile.edit.looking.online.friendship".localized
        case "Hobby Buddy":
            return "profile.edit.looking.hobby.buddy".localized
        case "Not Sure Yet", "Not sure yet":
            return "profile.edit.looking.not.sure".localized
        default:
            return preference
        }
    }

    // MARK: - My Photos Section
    private var myPhotosSection: some View {
        ProfileGalleryPhotosCard(
            photoURLs: displayProfile.photos,
            title: "profile.photos".localized,
            allowsPaging: false,
            onSelectRemote: { index in
                selectedPhotoIndex = index + 1
                showingPhotoViewer = true
            },
            usesWhiteBackground: true
        )
    }
    
    private var matchSection: some View {
        let matchPercentage = resolvedMatchPercentage
        let profileFirstName = firstName(from: displayProfile.name)
        let matchColor: Color = matchPercentage > 49 ? .green : .secondary
        
        return Button {
            showingMatchDetails = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(matchColor)
                            .frame(
                                width: geo.size.width * CGFloat(max(0, min(matchPercentage, 100))) / 100.0,
                                height: 6
                            )
                    }
                }
                .frame(height: 6)
                
                HStack(alignment: .top, spacing: 8) {
                    (Text("search.match.prefix".localized)
                     + Text(String(format: "search.match.percent.part".localized, matchPercentage))
                        .foregroundColor(matchColor)
                     + Text("search.match.label".localized)
                     + Text(String(format: "search.match.suffix".localized, profileFirstName)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.top, 1)
                }
            }
            .blueFieldStyle()
            .padding()
            .background(SpectRoomTheme.card)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private enum ProfileReportReason: String, CaseIterable, Identifiable {
    case inappropriateContent
    case fakeProfileOrSpam
    case harassmentOrBullying
    case somethingElse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inappropriateContent: return "profile.report.reason.inappropriate.content".localized
        case .fakeProfileOrSpam: return "profile.report.reason.fake.profile.spam".localized
        case .harassmentOrBullying: return "profile.report.reason.harassment.bullying".localized
        case .somethingElse: return "profile.report.reason.something.else".localized
        }
    }

    /// Stable English value stored in Firestore (not localized).
    var storageCategory: String {
        switch self {
        case .inappropriateContent: return "Inappropriate Content"
        case .fakeProfileOrSpam: return "Fake profile or Spam"
        case .harassmentOrBullying: return "Harassment or Bullying"
        case .somethingElse: return "Something else"
        }
    }
}

private struct BlockConfirmationOverlay: View {
    let firstName: String
    let onCancel: () -> Void
    let onBlock: () -> Void
    let onBlockComplete: () -> Void
    let onBlockAndReport: () -> Void

    @State private var showingBlockedSuccess = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture {
                    if showingBlockedSuccess {
                        onBlockComplete()
                    } else {
                        onCancel()
                    }
                }

            if showingBlockedSuccess {
                blockedSuccessContent
            } else {
                confirmationContent
            }
        }
    }

    private var confirmationContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(String(format: "profile.block.confirm.title".localized, firstName))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.bottom, 4)

                Text("profile.block.confirm.message".localized)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            HStack(spacing: 12) {
                destructiveOutlineButton(
                    title: "profile.block.confirm.block.and.report".localized,
                    lineLimit: 2,
                    action: onBlockAndReport
                )

                destructiveOutlineButton(
                    title: "profile.block.confirm.action".localized,
                    lineLimit: 1,
                    action: {
                        onBlock()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingBlockedSuccess = true
                        }
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(SpectRoomTheme.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .padding(.horizontal, 36)
    }

    private var blockedSuccessContent: some View {
        VStack(spacing: 20) {
            Text(String(format: "profile.report.blocked.notice".localized, firstName))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.red)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Button(action: onBlockComplete) {
                Text("common.got.it".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 36)
    }

    @ViewBuilder
    private func destructiveOutlineButton(title: String, lineLimit: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ReportReasonOverlay: View {
    let firstName: String
    let onCancel: () -> Void
    let onSubmit: (ProfileReportReason, String?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    @State private var selectedReason: ProfileReportReason? = .inappropriateContent
    @State private var somethingElseText = ""
    @State private var didAttemptSubmit = false
    @State private var showBlockedNotReportedConfirmation = false

    private let somethingElseMinChars = 20
    private let somethingElseMaxChars = 200

    private var trimmedSomethingElseText: String {
        somethingElseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showSomethingElseMinWarning: Bool {
        selectedReason == .somethingElse
            && didAttemptSubmit
            && trimmedSomethingElseText.count < somethingElseMinChars
    }

    private var isSomethingElseActive: Bool {
        selectedReason == .somethingElse
    }

    private var allReasons: [ProfileReportReason] {
        ProfileReportReason.allCases
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture {
                    if showBlockedNotReportedConfirmation {
                        onCancel()
                    }
                }

            if showBlockedNotReportedConfirmation {
                blockedNotReportedContent
            } else {
                reportFormContent
            }
        }
    }

    private var blockedNotReportedContent: some View {
        VStack(spacing: 0) {
            Text(String(format: "profile.report.blocked.not.reported".localized, firstName))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(SpectRoomTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()

            Button(action: onCancel) {
                Text("common.got.it".localized)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var reportFormContent: some View {
        VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: "profile.report.blocked.notice".localized, firstName))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 4)

                    Divider()

                    Text(String(format: "profile.report.title".localized, firstName))
                        .font(.headline)
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.leading)

                    Text(String(format: "profile.report.confidential".localized, firstName))
                        .font(.subheadline)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    ForEach(allReasons) { reason in
                        reportOptionButton(reason: reason, isSelected: selectedReason == reason) {
                            selectReason(reason)
                        }
                    }

                    textFieldSection
                }

                HStack(spacing: 12) {
                    Button {
                        showBlockedNotReportedConfirmation = true
                    } label: {
                        Text("common.cancel".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SpectRoomTheme.text)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SpectRoomTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        submitReport()
                    } label: {
                        Text("profile.report.submit".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
    }

    private var textFieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if somethingElseText.isEmpty {
                    Text("profile.report.something.else.placeholder".localized)
                        .font(.body)
                        .foregroundColor(Color.gray.opacity(isSomethingElseActive ? 0.6 : 0.35))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $somethingElseText)
                    .frame(height: 100)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .focused($isTextFieldFocused)
                    .disabled(!isSomethingElseActive)
                    .opacity(isSomethingElseActive ? 1 : 0.45)
                    .onChange(of: somethingElseText) { _, newValue in
                        if newValue.count > somethingElseMaxChars {
                            somethingElseText = String(newValue.prefix(somethingElseMaxChars))
                        }
                    }
            }
            .background(isSomethingElseActive ? SpectRoomTheme.background : SpectRoomTheme.background.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        showSomethingElseMinWarning ? Color.red : Color.gray.opacity(isSomethingElseActive ? 0.25 : 0.15),
                        lineWidth: showSomethingElseMinWarning ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectSomethingElseField()
            }

            HStack {
                Text(showSomethingElseMinWarning ? "support.message.min.chars".localized : " ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                    .opacity(showSomethingElseMinWarning ? 1 : 0)
                Spacer()
                Text("\(somethingElseText.count) / \(somethingElseMaxChars)")
                    .font(.system(size: 12))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .opacity(isSomethingElseActive ? 1 : 0.45)
            }
            .padding(.top, 2)
        }
        .opacity(isSomethingElseActive ? 1 : 0.85)
    }

    private func submitReport() {
        didAttemptSubmit = true
        guard let selectedReason else { return }
        if selectedReason == .somethingElse {
            guard trimmedSomethingElseText.count >= somethingElseMinChars else { return }
            onSubmit(selectedReason, trimmedSomethingElseText)
            return
        }
        onSubmit(selectedReason, nil)
    }

    private func selectReason(_ reason: ProfileReportReason) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedReason = reason
            didAttemptSubmit = false
            if reason == .somethingElse {
                isTextFieldFocused = true
            } else {
                isTextFieldFocused = false
            }
        }
    }

    private func selectSomethingElseField() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedReason = .somethingElse
            isTextFieldFocused = true
        }
    }

    @ViewBuilder
    private func reportOptionButton(
        reason: ProfileReportReason,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                reportIcon(for: reason)
                    .frame(width: 24, height: 24)

                Text(reason.label)
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.blue.opacity(0.08) : SpectRoomTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.blue : SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func reportIcon(for reason: ProfileReportReason) -> some View {
        switch reason {
        case .inappropriateContent:
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.orange)
        case .fakeProfileOrSpam:
            Text("🤖")
                .font(.system(size: 20))
        case .harassmentOrBullying:
            Text("🚫")
                .font(.system(size: 20))
        case .somethingElse:
            Text("💬")
                .font(.system(size: 20))
        }
    }
}

private struct ReportThankYouOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 20) {
                Text("profile.report.thank.you".localized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                Button(action: onDismiss) {
                    Text("common.ok".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
    }
}

private struct MatchDetailsOverlay: View {
    let firstName: String
    let breakdown: ProfileCard.MatchBreakdown?
    let localizedInterests: [String]
    let localizedLookingFor: String
    let localizedSensory: String
    let localizedLifestyle: String
    let localizedIdealFirstDate: String
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var isLight: Bool { colorScheme == .light }
    private var panelBackground: Color { isLight ? Color.white : Color.black }
    private var primaryText: Color { isLight ? Color.black : Color.white }
    private var secondaryText: Color { isLight ? Color.black.opacity(0.55) : Color.white.opacity(0.7) }
    
    var body: some View {
        let matchPercentage = breakdown?.percentage ?? 0
        let matchColor: Color = matchPercentage > 49 ? .green : primaryText.opacity(0.75)
        
        ZStack {
            Color.black.opacity(isLight ? 0.35 : 0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: "search.match.details.title".localized, firstName))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(String(format: "search.match.details.percent".localized, matchPercentage))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(matchColor)
                
                VStack(alignment: .leading, spacing: 12) {
                    matchDetailRow(
                        title: "search.match.details.age".localized,
                        value: ageDetailText
                    )
                    if !localizedLookingFor.isEmpty {
                        matchDetailRow(
                            title: "search.match.details.looking.for".localized,
                            value: localizedLookingFor
                        )
                    }
                    if !localizedInterests.isEmpty {
                        matchDetailRow(
                            title: "search.match.details.interests".localized,
                            value: localizedInterests.joined(separator: ", ")
                        )
                    }
                    if !localizedSensory.isEmpty {
                        matchDetailRow(
                            title: "search.match.details.sensory".localized,
                            value: localizedSensory
                        )
                    }
                    if !localizedLifestyle.isEmpty {
                        matchDetailRow(
                            title: "search.match.details.lifestyle".localized,
                            value: localizedLifestyle
                        )
                    }
                    if !localizedIdealFirstDate.isEmpty {
                        matchDetailRow(
                            title: "search.match.details.ideal.first.date".localized,
                            value: localizedIdealFirstDate
                        )
                    }
                }
                
                Button(action: onDismiss) {
                    Text("common.got.it".localized)
                        .font(.body.weight(.medium))
                        .foregroundColor(primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isLight ? Color.black.opacity(0.06) : Color.clear, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isLight ? 0.12 : 0), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
    }
    
    private var ageDetailText: String {
        let delta = breakdown?.ageDeltaFromYou ?? 0
        if delta == 0 {
            return String(format: "search.match.details.age.same".localized, firstName)
        }
        if delta < 0 {
            return String(format: "search.match.details.age.younger".localized, abs(delta), firstName)
        }
        return String(format: "search.match.details.age.older".localized, delta, firstName)
    }
    
    private func matchDetailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(secondaryText)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LookingForDetailsOverlay: View {
    let items: [String]
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("profile.looking.for.details.title".localized)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text(item)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: onDismiss) {
                    Text("common.got.it".localized)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding(.horizontal, 28)
        }
    }
}

struct PhotoViewerModal: View {
    let photos: [String]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        ZStack {
            // Semi-transparent background overlay (same as recording popup)
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            if !photos.isEmpty {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photoURL in
                        CachedAsyncImage(url: URL(string: photoURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                )
                        }
                        .padding(.horizontal, 40)
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                .onAppear {
                    preloadAllPhotos()
                }
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    Text("profile.no.photos".localized)
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            
            // Done button
            VStack {
                HStack {
                    Spacer()
                    Button("common.done".localized) {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.trailing, 35)
                    .padding(.top, 24)
                }
                Spacer()
            }
        }
    }
    
    private func preloadAllPhotos() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for photoURL in photos {
                    group.addTask {
                        guard let url = URL(string: photoURL) else { return }
                        // Check if already cached
                        if ImageCacheService.shared.image(for: photoURL) != nil {
                            return
                        }
                        // Preload image
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            if let uiImage = UIImage(data: data) {
                                ImageCacheService.shared.insert(uiImage, for: photoURL)
                            }
                        } catch {
                            // Silently fail - image will load when viewed
                        }
                    }
                }
            }
        }
    }
}

struct NewMessageModal: View {
    let profile: ProfileCard
    let isExistingConversation: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var appState: AppStateManager
    @State private var messageText: String = ""
    @State private var showingPreMessageOptions = false
    @State private var isBlockedByRecipient = false
    @State private var showingBlockedAlert = false
    
    init(profile: ProfileCard, isExistingConversation: Bool) {
        self.profile = profile
        self.isExistingConversation = isExistingConversation
        print("💬 NewMessageModal INIT called with profile: \(profile.name), userId: \(profile.userId), isExistingConversation: \(isExistingConversation)")
    }
    
    var body: some View {
        let _ = print("💬 NewMessageModal body being computed, profile name: \(profile.name), isExistingConversation: \(isExistingConversation)")
        NavigationView {
            VStack(spacing: 20) {
                // Header with profile info
                VStack(spacing: 12) {
                    // Profile image
                    CachedAsyncImage(url: URL(string: profile.imageURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.gray)
                            )
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                }
                .padding(.top, 20)
                
                // Message input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("matches.message.label".localized)
                            .font(.headline)
                            .foregroundColor(SpectRoomTheme.text)
                        
                        Spacer()
                        
                        Button(action: {
                            showingPreMessageOptions = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 14))
                                Text("matches.pre.message.button".localized)
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .disabled(isBlockedByRecipient)
                        .opacity(isBlockedByRecipient ? 0.5 : 1)
                    }
                    
                    TextEditor(text: $messageText)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(SpectRoomTheme.card)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .disabled(isBlockedByRecipient)
                        .opacity(isBlockedByRecipient ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Send button
                Button(action: {
                    Task {
                        await sendMessage()
                    }
                }) {
                    Text("messages.send.message".localized)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBlockedByRecipient)
                .opacity(isBlockedByRecipient ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(
                SpectRoomBackground()
            )
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("matches.new.message".localized)
                            .font(.headline)
                        Text(String(format: "matches.new.message.to".localized, profile.name))
                            .font(.caption)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPreMessageOptions) {
            PreMessageOptionsModal(
                profileName: profile.name,
                onSelect: { selectedMessage in
                    messageText = selectedMessage
                    showingPreMessageOptions = false
                }
            )
        }
        .overlay {
            if showingBlockedAlert {
                BlockedUserAlertOverlay(
                    firstName: firstName(from: profile.name),
                    onDismiss: { dontShowAgain in
                        if dontShowAgain {
                            appState.suppressBlockedAlert(for: profile.userId)
                        }
                        showingBlockedAlert = false
                    }
                )
            }
        }
        .onAppear {
            print("💬 NewMessageModal appeared for: \(profile.name)")
            print("💬 Profile userId: \(profile.userId), isExistingConversation: \(isExistingConversation)")
            print("💬 Modal appeared - messageText will be set: \(!isExistingConversation)")
            Task {
                await checkBlockStatus()
            }
        }
        .onChange(of: appState.blockedUsers.map(\.id)) { _, _ in
            if appState.isMessagingBlocked(with: profile.userId) {
                isBlockedByRecipient = true
                messageText = ""
                dismiss()
            }
        }
        .onChange(of: appState.blockedByUsers.map(\.id)) { _, _ in
            if appState.isMessagingBlocked(with: profile.userId) {
                isBlockedByRecipient = true
                messageText = ""
                dismiss()
            }
        }
    }
    
    private func checkBlockStatus() async {
        let locallyHidden = await MainActor.run { appState.isMessagingBlocked(with: profile.userId) }
        do {
            let theyBlockedMe = try await FirebaseAuthService.shared.isBlockedBy(userId: profile.userId)
            print("🚫 Block status for \(profile.userId): theyBlockedMe=\(theyBlockedMe) locallyHidden=\(locallyHidden)")
            await MainActor.run {
                let blocked = theyBlockedMe || appState.isMessagingBlocked(with: profile.userId)
                isBlockedByRecipient = blocked
                if blocked {
                    messageText = ""
                    if theyBlockedMe, appState.shouldShowBlockedAlert(for: profile.userId) {
                        showingBlockedAlert = true
                    } else if appState.isMessagingBlocked(with: profile.userId) {
                        dismiss()
                    }
                } else if !isExistingConversation {
                    messageText = "matches.default.message".localized
                    print("💬 Default message text set: \(messageText)")
                }
            }
        } catch {
            print("⚠️ Unable to check block status for \(profile.userId): \(error.localizedDescription)")
            await MainActor.run {
                isBlockedByRecipient = locallyHidden || appState.isMessagingBlocked(with: profile.userId)
                if isBlockedByRecipient {
                    dismiss()
                } else if !isExistingConversation {
                    messageText = "matches.default.message".localized
                }
            }
        }
    }
    
    // Helper function to extract first name
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    private func sendMessage() async {
        guard !isBlockedByRecipient else { return }
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        await MainActor.run {
            appState.recordOutgoingMessage(
                to: profile.userId,
                recipientName: profile.name,
                recipientPhotoURL: profile.imageURL,
                content: trimmedMessage
            )
        }
        
        do {
            let messageId = try await FirebaseAuthService.shared.sendMessage(
                to: profile.userId,
                content: trimmedMessage
            )
            
            print("✅ Message sent successfully with ID: \(messageId)")
            
            await MainActor.run {
                dismiss()
            }
            
        } catch {
            print("❌ Error sending message: \(error)")
            // TODO: Show error alert to user
        }
    }
}

// MARK: - Pre-Message Options Modal
struct PreMessageOptionsModal: View {
    let profileName: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedCategory: QuickMessageCategory = .lowPressure
    @State private var isDragging = false
    
    enum QuickMessageCategory: String, CaseIterable {
        case lowPressure
        case casual
        case questions
        
        var title: String {
            switch self {
            case .lowPressure: return "quick.msg.category.low.pressure".localized
            case .casual: return "quick.msg.category.casual".localized
            case .questions: return "quick.msg.category.questions".localized
            }
        }
        
        var messages: [String] {
            switch self {
            case .lowPressure: return (1...8).map { "quick.msg.low.\($0)".localized }
            case .casual: return (1...8).map { "quick.msg.casual.\($0)".localized }
            case .questions: return (1...8).map { "quick.msg.question.\($0)".localized }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                SpectRoomBackground()
                
                VStack(spacing: 0) {
                    categoryFilterBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(selectedCategory.messages.enumerated()), id: \.offset) { _, message in
                                Button {
                                    guard !isDragging else { return }
                                    onSelect(message)
                                } label: {
                                    HStack(alignment: .center, spacing: 12) {
                                        Text(message)
                                            .font(.body)
                                            .foregroundColor(SpectRoomTheme.text)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        Text("+")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(SpectRoomTheme.secondaryText)
                                    }
                                    .padding()
                                    .background(SpectRoomTheme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 100)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { _ in isDragging = true }
                            .onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isDragging = false }
                            }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("matches.pre.message.title".localized)
                            .font(.headline)
                        Text("matches.pre.message.subtitle".localized)
                            .font(.caption)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.close".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var categoryFilterBar: some View {
        HStack(spacing: 10) {
            ForEach(QuickMessageCategory.allCases, id: \.rawValue) { category in
                let isSelected = category == selectedCategory
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = category
                    }
                } label: {
                    Text(category.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundColor(isSelected ? Color.white : SpectRoomTheme.text)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.blue : SpectRoomTheme.card)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected ? Color.clear : SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    SearchView(selectedTab: .constant(1))
        .environmentObject(AppStateManager.shared)
}

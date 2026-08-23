//
//  MessagesView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import PhotosUI
import UIKit
import Photos
import Foundation
import AVFoundation

struct MessagesView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: Int
    @State private var conversations: [MessageDisplay] = []
    @State private var isLoading = true
    @State private var showingMessageModal = false
    @State private var selectedMessage: MessageDisplay?
    @State private var conversationMessages: [MessageDisplay] = []
    @State private var searchText = ""
    @State private var historyMatchPartnerIds: Set<String> = []
    @State private var historySearchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool
    /// Same as search bar `.padding(.bottom, 10)`.
    private let searchContentSpacing: CGFloat = 10
    /// Height of the custom tab menu body (above the home indicator).
    private let tabMenuBodyHeight: CGFloat = 70
    
    private func conversationOtherUserId(for conversation: MessageDisplay) -> String {
        conversation.senderName == "You" ? conversation.recipientId : conversation.senderId
    }
    
    private var visibleConversations: [MessageDisplay] {
        conversations.filter { !appState.isHiddenByBlock(conversationOtherUserId(for: $0)) }
    }
    
    private var filteredConversations: [MessageDisplay] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleConversations }
        return visibleConversations.filter { conversationMatchesSearch($0, query: query) }
    }
    
    /// Matches that still count for this tab (excludes people either side has blocked).
    private var visibleMatches: [MatchDisplay] {
        appState.cachedMatches.filter { !appState.isHiddenByBlock($0.otherUser.userId) }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !isLoading && !visibleConversations.isEmpty {
                    messagesSearchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, searchContentSpacing)
                }
                
                Group {
                    if isLoading {
                        VStack(spacing: 20) {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("messages.loading".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if visibleConversations.isEmpty {
                        emptyConversationsView
                    } else {
                        ZStack {
                            List(filteredConversations) { conversation in
                                let _ = print("💬 List: Rendering conversation with ID: \(conversation.id), recipient: \(conversation.recipientName)")
                                ConversationRow(conversation: conversation) {
                                    handleConversationTap(conversation)
                                }
                                .environmentObject(appState)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            .listStyle(PlainListStyle())
                            .scrollContentBackground(.hidden)
                            
                            if filteredConversations.isEmpty {
                                noSearchResultsView
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Mirror top spacing: 10pt gap, then reserve space for the overlay menu.
                Color.clear
                    .frame(height: tabMenuBodyHeight)
                    .padding(.top, searchContentSpacing)
            }
            .background(
                SpectRoomBackground()
            )
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("messages.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: searchText) { _, newValue in
            scheduleHistorySearch(for: newValue)
        }
        .onReceive(appState.$cachedMessageConversations) { updatedConversations in
            let sorted = sortedConversations(updatedConversations)
            conversations = sorted
            if isLoading {
                isLoading = false
            }
        }
        .onReceive(appState.newMessageReceivedPublisher) { newMessage in
            conversations = mergeConversation(newMessage, into: conversations)
        }
        .onAppear {
            loadConversationsFromCache()
            appState.refreshBlockedByUsers()
            appState.refreshConversationUnreadCounts()
            // If we have a conversation to open and we're just appearing, try to open it
            if let senderId = appState.conversationToOpenSenderId, !senderId.isEmpty {
                print("💬 MessagesView appeared with conversationToOpenSenderId: \(senderId)")
                // Wait for conversations to load, then open
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.appState.conversationToOpenSenderId == senderId {
                    self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .onChange(of: appState.conversationToOpenSenderId) { senderId in
            print("💬 conversationToOpenSenderId changed to: \(senderId ?? "nil")")
            if let senderId = senderId, !senderId.isEmpty {
                print("💬 Opening conversation for sender: \(senderId)")
                // First ensure conversations are loaded
                if conversations.isEmpty {
                    print("💬 Conversations list is empty, loading first...")
                loadConversations()
                }
                // Wait a bit longer to ensure conversations are loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.appState.conversationToOpenSenderId == senderId {
                        print("💬 Attempting to open conversation for: \(senderId)")
                        self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .onChange(of: conversations.count) { count in
            // If we have a conversation to open and conversations just loaded, try to open it
            if let senderId = appState.conversationToOpenSenderId, !senderId.isEmpty,
               count > 0 || appState.conversationToOpenProfile?.userId == senderId {
                print("💬 Conversations loaded (\(count) items), checking if we can open conversation for: \(senderId)")
                // Small delay to ensure conversations array is fully populated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if self.appState.conversationToOpenSenderId == senderId {
                        print("💬 Opening conversation after conversations loaded")
                        self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .onChange(of: isLoading) { loading in
            // When loading finishes, check if we need to open a conversation
            if !loading, let senderId = appState.conversationToOpenSenderId, !senderId.isEmpty {
                print("💬 Loading finished with \(conversations.count) conversations, checking if we can open conversation for: \(senderId)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if self.appState.conversationToOpenSenderId == senderId {
                        print("💬 Attempting to open conversation after loading finished")
                        self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { 
                let isPresented = showingMessageModal
                print("💬 MessagesView Sheet binding GET - isPresented: \(isPresented), selectedMessage: \(selectedMessage?.recipientName ?? "nil")")
                return isPresented
            },
            set: { newValue in
                print("💬 MessagesView Sheet binding SET - newValue: \(newValue), current showingMessageModal: \(showingMessageModal)")
                print("💬 selectedMessage at set time: \(selectedMessage?.recipientName ?? "nil"), content: \(selectedMessage?.content.prefix(20) ?? "nil")...")
                showingMessageModal = newValue
                
                // Track which conversation is currently open
                if newValue, let message = selectedMessage {
                    // Determine the other user's ID (the one we're conversing with)
                    let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
                    appState.currentlyOpenConversationSenderId = otherUserId
                    print("💬 Conversation opened with user: \(otherUserId)")
                    
                    // Mark all incoming messages from this user as read when conversation opens
                    Task {
                        await appState.markMessagesAsRead(from: otherUserId)
                    }
                    
                    // Store in Firestore so Cloud Function can check if conversation is open
                    Task {
                        await updateConversationOpenState(userId: otherUserId, isOpen: true)
                    }
                } else {
                    // Conversation closed
                    let previousUserId = appState.currentlyOpenConversationSenderId
                    appState.currentlyOpenConversationSenderId = nil
                    print("💬 Conversation closed")
                    
                    // Clear from Firestore
                    if let userId = previousUserId {
                        Task {
                            await updateConversationOpenState(userId: userId, isOpen: false)
                        }
                    }
                    DispatchQueue.main.async {
                        self.loadConversations()
                    }
                }
                
                print("💬 showingMessageModal after set: \(showingMessageModal)")
            }
        )) {
            let _ = print("💬 MessagesView Sheet closure EXECUTING - selectedMessage: \(selectedMessage?.recipientName ?? "nil")")
            if let message = selectedMessage {
                let _ = print("💬 MessagesView Creating MessageConversationModal with message: \(message.recipientName), content: \(message.content.prefix(20))...")
                MessageConversationModal(
                    message: message,
                    conversationMessages: $conversationMessages
                )
                // Clear cover so swipe-right reveals the messages list underneath.
                .presentationBackground(.clear)
            } else {
                let _ = print("❌ MessagesView selectedMessage is nil in sheet closure!")
                VStack {
                    Text("messages.error.no.message".localized)
                        .foregroundColor(.red)
                    Button("common.close".localized) {
                        showingMessageModal = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SpectRoomTheme.background.ignoresSafeArea())
                .presentationBackground(.clear)
            }
        }
    }
    
    // Update conversation open state in Firestore
    private func updateConversationOpenState(userId: String, isOpen: Bool) async {
        await updateConversationOpenStateInFirestore(userId: userId, isOpen: isOpen)
    }
    
    // Helper function to update conversation open state in Firestore
    private func updateConversationOpenStateInFirestore(userId: String, isOpen: Bool) async {
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            return
        }
        
        do {
            let state: [String: Any] = [
                "openConversationUserId": isOpen ? userId : NSNull(),
                "appIsActive": true,
                "appStateUpdatedAt": Date().timeIntervalSince1970
            ]
            try await FirebaseAuthService.shared.updateUserData(state)
            print("💬 Updated conversation open state in Firestore: \(isOpen ? "open with \(userId)" : "closed")")
        } catch {
            print("❌ Failed to update conversation open state: \(error)")
        }
    }
    
    private func loadConversationsFromCache() {
        print("💬 MessagesView: Loading conversations from cache...")
        print("💬 MessagesView: Current conversations count: \(conversations.count)")
        
        // Check if user is authenticated
        guard FirebaseAuthService.shared.isAuthenticated else {
            print("❌ MessagesView: User not authenticated, skipping conversations load")
            return
        }
        
        if conversations.isEmpty {
            print("💬 MessagesView: Conversations list empty, showing loading spinner")
            isLoading = true
        }
        
        // First, load from cache instantly if available
        Task {
            do {
                // Try to get cached conversations first (fast)
                let cachedOrFresh = try await appState.getCachedOrFreshConversations()
                
                await MainActor.run {
                    print("💬 MessagesView: Setting conversations from cache to \(cachedOrFresh.count) items")
                    conversations = sortedConversations(cachedOrFresh)
                    isLoading = false
                    print("💬 MessagesView: Conversations loaded from cache")
                }
                
                // Then refresh in background (slow, but updates cache)
                Task {
                    do {
                        let refreshed = try await appState.refreshMessageConversationsCache()
                        await MainActor.run {
                            // Only update if count changed or if we got more recent data
                            if refreshed.count != conversations.count {
                                print("💬 MessagesView: Refreshing conversations from \(conversations.count) to \(refreshed.count) items")
                                conversations = sortedConversations(refreshed)
                            } else {
                                // Check if any conversation was updated (newer timestamp)
                                var updated = false
                                for refreshedConv in refreshed {
                                    if let existingIndex = conversations.firstIndex(where: { conv in
                                        let otherUserId = conv.senderName == "You" ? conv.recipientId : conv.senderId
                                        let newOtherUserId = refreshedConv.senderName == "You" ? refreshedConv.recipientId : refreshedConv.senderId
                                        return otherUserId == newOtherUserId
                                    }) {
                                        if refreshedConv.createdAt > conversations[existingIndex].createdAt {
                                            conversations[existingIndex] = refreshedConv
                                            updated = true
                                        }
                                    }
                                }
                                if updated {
                                    print("💬 MessagesView: Updated conversations with newer messages")
                                    conversations = sortedConversations(conversations)
                                }
                            }
                        }
                    } catch {
                        print("❌ MessagesView: Error refreshing conversations: \(error)")
                    }
                }
            } catch {
                print("❌ MessagesView: Error loading conversations: \(error)")
                await MainActor.run {
                    conversations = []
                    isLoading = false
                }
            }
        }
    }
    
    private func loadConversations() {
        // Legacy function - now just calls the cache version
        loadConversationsFromCache()
    }
    
    private func sortedConversations(_ list: [MessageDisplay]) -> [MessageDisplay] {
        list.sorted { $0.createdAt > $1.createdAt }
    }
    
    private var messagesSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SpectRoomTheme.secondaryText)
            
            TextField("messages.search.placeholder".localized, text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(SpectRoomTheme.text)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($isSearchFieldFocused)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("messages.search.clear".localized)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpectRoomTheme.card)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
        )
    }
    
    private var emptyConversationsView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("💬")
                    .font(.system(size: 48))
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.14))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.blue.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.blue.opacity(0.16), radius: 12, y: 4)
                
                Text("messages.empty.has.matches.title".localized)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
                
                Text("messages.empty.no.matches.description".localized)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noSearchResultsView: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(Color.blue.opacity(0.75))
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(SpectRoomTheme.card)
                    )
                    .offset(x: 6, y: 6)
            }
            .padding(.bottom, 4)
            
            Text("messages.search.no.results".localized)
                .font(.headline)
                .foregroundColor(.primary.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Text("messages.search.no.results.hint".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func conversationMatchesSearch(_ conversation: MessageDisplay, query: String) -> Bool {
        let otherName = conversation.senderName == "You"
            ? conversation.recipientName
            : conversation.senderName
        let partnerId = conversation.senderName == "You"
            ? conversation.recipientId
            : conversation.senderId
        
        if otherName.localizedCaseInsensitiveContains(query) {
            return true
        }
        
        // Match last-message preview text (including photo/voice labels via content when present).
        if conversation.content.localizedCaseInsensitiveContains(query) {
            return true
        }
        
        switch conversation.messageType {
        case .image:
            if "messages.preview.photo".localized.localizedCaseInsensitiveContains(query) {
                return true
            }
        case .voice:
            if "messages.preview.voice".localized.localizedCaseInsensitiveContains(query) {
                return true
            }
        default:
            break
        }
        
        // Match any message already loaded into this conversation's cache.
        if let cached = appState.getCachedConversationMessages(for: partnerId),
           cached.contains(where: { $0.content.localizedCaseInsensitiveContains(query) }) {
            return true
        }
        
        // Match results from full Firebase history scan.
        if historyMatchPartnerIds.contains(partnerId) {
            return true
        }
        
        return false
    }
    
    private func scheduleHistorySearch(for rawQuery: String) {
        historySearchTask?.cancel()
        
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            historyMatchPartnerIds = []
            return
        }
        
        // Instant matches from already-cached conversation history.
        historyMatchPartnerIds = appState.partnerIdsMatchingCachedMessageHistory(query)
        
        historySearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            do {
                let matchedIds = try await FirebaseAuthService.shared.findConversationPartnerIds(matching: query)
                await MainActor.run {
                    let currentQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard currentQuery == query else { return }
                    historyMatchPartnerIds = matchedIds.union(
                        appState.partnerIdsMatchingCachedMessageHistory(query)
                    )
                }
            } catch {
                print("❌ Messages history search failed: \(error)")
            }
        }
    }
    
    private func mergeConversation(_ newMessage: MessageDisplay, into list: [MessageDisplay]) -> [MessageDisplay] {
        let newOtherUserId = newMessage.senderName == "You" ? newMessage.recipientId : newMessage.senderId
        var updated = list
        if let index = updated.firstIndex(where: {
            let otherUserId = $0.senderName == "You" ? $0.recipientId : $0.senderId
            return otherUserId == newOtherUserId
        }) {
            if newMessage.createdAt >= updated[index].createdAt {
                updated[index] = newMessage
            }
        } else {
            updated.append(newMessage)
        }
        return sortedConversations(updated)
    }
    
    private func handleConversationTap(_ conversation: MessageDisplay) {
        print("💬 Conversation tapped for: \(conversation.recipientName)")
        print("💬 Message content: \(conversation.content)")
        print("💬 Message senderId: \(conversation.senderId), recipientId: \(conversation.recipientId)")
        
        let otherUserId = conversation.senderName == "You" ? conversation.recipientId : conversation.senderId
        guard !appState.isHiddenByBlock(otherUserId) else {
            print("🚫 Ignoring tap on blocked conversation with \(otherUserId)")
            return
        }
        
        print("💬 Setting selectedMessage to conversation")
        selectedMessage = conversation
        
        appState.currentlyOpenConversationSenderId = otherUserId
        print("💬 Set currentlyOpenConversationSenderId to: \(otherUserId)")
        
        prepareConversationMessages(for: otherUserId)
        
        print("💬 selectedMessage after set: \(selectedMessage?.recipientName ?? "nil"), content: \(selectedMessage?.content.prefix(20) ?? "nil")...")
        print("💬 showingMessageModal before: \(showingMessageModal)")
        showingMessageModal = true
        print("💬 showingMessageModal after: \(showingMessageModal)")
    }
    
    /// Seed the shared conversation binding before presenting so the modal
    /// never briefly shows the previous chat (or an empty loading flash).
    private func prepareConversationMessages(for otherUserId: String) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let cached = appState.getCachedConversationState(for: otherUserId) {
                conversationMessages = Array(cached.messagePool.suffix(10))
            } else {
                conversationMessages = []
            }
        }
    }
    
    private func openConversationForSender(senderId: String, retryCount: Int = 0) {
        print("💬 Opening conversation for sender: \(senderId) (retry: \(retryCount))")
        
        guard !appState.isHiddenByBlock(senderId) else {
            print("🚫 Ignoring open for blocked conversation with \(senderId)")
            appState.conversationToOpenSenderId = nil
            appState.shouldOpenConversation = false
            appState.conversationToOpenProfile = nil
            return
        }
        
        print("💬 Current conversations count: \(conversations.count)")
        print("💬 isLoading: \(isLoading)")
        print("💬 Conversation list: \(conversations.map { "\($0.recipientName) (sender: \($0.senderId), recipient: \($0.recipientId))" })")
        
        let pendingNewConversation = appState.conversationToOpenProfile?.userId == senderId
        
        // If conversations are still loading, wait briefly unless we're opening a brand-new conversation
        if isLoading && retryCount < 3 && !pendingNewConversation {
            print("💬 Conversations still loading, will retry in 0.5 seconds (retry: \(retryCount + 1))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.appState.conversationToOpenSenderId == senderId {
                    self.openConversationForSender(senderId: senderId, retryCount: retryCount + 1)
                }
            }
            return
        }
        
        // Find the conversation with this sender
        // For incoming messages, senderId matches the sender
        // For sent messages, recipientId matches the sender
        if let conversation = conversations.first(where: { conv in
            // If message was sent by current user, check recipientId
            // If message was received from sender, check senderId
            let otherUserId = conv.senderName == "You" ? conv.recipientId : conv.senderId
            print("💬 Checking conversation: sender=\(conv.senderName), senderId=\(conv.senderId), recipientId=\(conv.recipientId), otherUserId=\(otherUserId), target=\(senderId)")
            return otherUserId == senderId
        }) {
            print("💬 ✅ Found conversation with sender: \(conversation.recipientName)")
            print("💬 Setting selectedMessage and showingMessageModal to true")
            // Set selectedMessage first
            selectedMessage = conversation
            print("💬 selectedMessage set: \(selectedMessage?.recipientName ?? "nil")")
            
                    // Set the currently open conversation ID to prevent notifications for this conversation
            appState.currentlyOpenConversationSenderId = senderId
                    print("💬 Set currentlyOpenConversationSenderId to: \(senderId)")
            
            prepareConversationMessages(for: senderId)
                    
            // Store in Firestore so Cloud Function can check if conversation is open
            Task {
                await updateConversationOpenState(userId: senderId, isOpen: true)
            }
            
            // Use a small delay to ensure SwiftUI has processed selectedMessage before opening modal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                print("💬 Opening message modal now - showingMessageModal: \(self.showingMessageModal)")
                print("💬 selectedMessage check: \(self.selectedMessage != nil ? "exists" : "nil")")
                if self.selectedMessage != nil {
                    // Force open the modal
                    self.showingMessageModal = true
                    print("💬 ✅ showingMessageModal set to: \(self.showingMessageModal)")
                    print("💬 ✅ Modal should now be visible")
                    // Clear the conversationToOpenSenderId after opening
                    self.appState.conversationToOpenSenderId = nil
                    self.appState.shouldOpenConversation = false
                    self.appState.conversationToOpenProfile = nil
                    // Clear the sender info from AppStateManager
                    self.appState.newMessageSenderName = ""
                    self.appState.newMessageSenderPhotoURL = nil
                    self.appState.newMessageSenderId = ""
                } else {
                    print("❌ selectedMessage is nil when trying to open modal - retrying...")
                    // Retry if selectedMessage is still nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if self.selectedMessage != nil {
                            self.showingMessageModal = true
                            print("💬 ✅ Retry successful - showingMessageModal set to: \(self.showingMessageModal)")
                        } else {
                            print("❌ selectedMessage still nil after retry")
                        }
                    }
                }
            }
        } else if pendingNewConversation || retryCount == 0 {
            print("💬 No conversation found in list, resolving conversation for sender: \(senderId)")
            Task {
                await fetchAndCreateConversationForSender(senderId: senderId)
            }
        } else if retryCount < 3 {
            print("💬 No conversation found with sender: \(senderId) - will retry (\(retryCount + 1)/3)")
            // Refresh conversations and retry
            loadConversations()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if self.appState.conversationToOpenSenderId == senderId {
                self.openConversationForSender(senderId: senderId, retryCount: retryCount + 1)
                }
            }
        } else {
            print("💬 Conversation not found after retries, checking for new conversation profile")
            if let profile = appState.conversationToOpenProfile, profile.userId == senderId {
                openNewConversationModal(for: profile)
            } else {
                print("💬 No profile available for new conversation, clearing state")
                // Clear the conversationToOpenSenderId even if not found
                appState.conversationToOpenSenderId = nil
                appState.conversationToOpenProfile = nil
                // Clear the sender info from AppStateManager
                appState.newMessageSenderName = ""
                appState.newMessageSenderPhotoURL = nil
                appState.newMessageSenderId = ""
            }
        }
    }
    
    private func openNewConversationModal(for profile: ProfileCard) {
        print("💬 Opening new conversation modal for: \(profile.name)")
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            appState.conversationToOpenSenderId = nil
            appState.conversationToOpenProfile = nil
            return
        }
        
        let placeholderMessage = Message(
            conversationId: UUID(),
            senderId: UUID(),
            senderFirebaseId: currentUserId,
            content: "",
            createdAt: Date(),
            type: .text
        )
        
        let messageDisplay = MessageDisplay(
            message: placeholderMessage,
            senderName: "You",
            recipientName: profile.name,
            senderId: currentUserId,
            recipientId: profile.userId,
            senderProfilePhotoURL: nil,
            recipientProfilePhotoURL: profile.imageURL
        )
        
        selectedMessage = messageDisplay
        prepareConversationMessages(for: profile.userId)
        appState.currentlyOpenConversationSenderId = profile.userId
        
        Task {
            await updateConversationOpenState(userId: profile.userId, isOpen: true)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if self.selectedMessage != nil {
                self.showingMessageModal = true
                print("💬 ✅ New conversation modal opened for: \(profile.name)")
            }
            self.appState.conversationToOpenSenderId = nil
            self.appState.conversationToOpenProfile = nil
        }
    }
    
    private func fetchAndCreateConversationForSender(senderId: String) async {
        print("💬 Fetching latest message from sender: \(senderId)")
        do {
            // Fetch the latest message from this sender using FirebaseAuthService helper
            if let messageDisplay = try await FirebaseAuthService.shared.fetchLatestMessageFromSender(senderId: senderId) {
                await MainActor.run {
                    print("💬 Found and created MessageDisplay for sender: \(messageDisplay.senderName)")
                    print("💬 Setting selectedMessage and showingMessageModal to true")
                    // Set selectedMessage first
                    selectedMessage = messageDisplay
                    print("💬 selectedMessage set: \(selectedMessage?.recipientName ?? "nil")")
                    // Use a small delay to ensure SwiftUI has processed selectedMessage before opening modal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        print("💬 Opening message modal now - showingMessageModal: \(self.showingMessageModal)")
                        if self.selectedMessage != nil {
                            // Set the currently open conversation ID to prevent notifications for this conversation
                            self.appState.currentlyOpenConversationSenderId = senderId
                            print("💬 Set currentlyOpenConversationSenderId to: \(senderId)")
                            
                            self.prepareConversationMessages(for: senderId)
                            
                            // Store in Firestore so Cloud Function can check if conversation is open
                            Task {
                                await self.updateConversationOpenState(userId: senderId, isOpen: true)
                            }
                            
                            self.showingMessageModal = true
                            print("💬 ✅ showingMessageModal set to: \(self.showingMessageModal)")
                            print("💬 ✅ Modal should now be visible")
                            // Clear the conversationToOpenSenderId
                            self.appState.conversationToOpenSenderId = nil
                            self.appState.conversationToOpenProfile = nil
                            // Clear the sender info from AppStateManager
                            self.appState.newMessageSenderName = ""
                            self.appState.newMessageSenderPhotoURL = nil
                            self.appState.newMessageSenderId = ""
                        } else {
                            print("❌ selectedMessage is nil when trying to open modal - retrying...")
                            // Retry if selectedMessage is still nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if self.selectedMessage != nil {
                                    self.showingMessageModal = true
                                    print("💬 ✅ Retry successful - showingMessageModal set to: \(self.showingMessageModal)")
                                } else {
                                    print("❌ selectedMessage still nil after retry")
                                }
                            }
                        }
                    }
                }
            } else {
                print("❌ No message found from sender: \(senderId)")
                await MainActor.run {
                    if let profile = appState.conversationToOpenProfile, profile.userId == senderId {
                        openNewConversationModal(for: profile)
                    } else {
                        appState.conversationToOpenSenderId = nil
                        appState.conversationToOpenProfile = nil
                        appState.newMessageSenderName = ""
                        appState.newMessageSenderPhotoURL = nil
                        appState.newMessageSenderId = ""
                    }
                }
            }
        } catch {
            print("❌ Error fetching message from sender: \(error)")
            await MainActor.run {
                if let profile = appState.conversationToOpenProfile, profile.userId == senderId {
                    openNewConversationModal(for: profile)
                } else {
                    appState.conversationToOpenSenderId = nil
                    appState.conversationToOpenProfile = nil
                    appState.newMessageSenderName = ""
                    appState.newMessageSenderPhotoURL = nil
                    appState.newMessageSenderId = ""
                }
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: MessageDisplay
    let onTap: () -> Void
    @EnvironmentObject private var appState: AppStateManager
    
    var body: some View {
        let _ = print("💬 ConversationRow: Rendering row for \(conversation.recipientName), content: \(conversation.content.prefix(20))...")
        ZStack {
            HStack(spacing: 12) {
                profilePhoto
                    .overlay(alignment: .topTrailing) {
                        UnreadCountBadge(count: unreadCount)
                            .offset(x: 6, y: -6)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(otherUserName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(SpectRoomTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(conversation.createdAt.formattedConversationListTime())
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(SpectRoomTheme.card)
            .cornerRadius(12)
            
            if isBlockedConversation {
                BlockedProfileLabel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private var otherUserName: String {
        if conversation.senderName == "You" {
            return conversation.recipientName
        } else {
            return conversation.senderName
        }
    }
    
    private var otherUserId: String {
        conversation.senderName == "You" ? conversation.recipientId : conversation.senderId
    }
    
    private var isBlockedConversation: Bool {
        appState.isMessagingBlocked(with: otherUserId)
    }
    
    private var unreadCount: Int {
        appState.conversationUnreadCounts[otherUserId] ?? 0
    }
    
    @ViewBuilder
    private var profilePhoto: some View {
        if let profilePhotoURL = otherUserProfilePhotoURL, !profilePhotoURL.isEmpty {
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    CachedAsyncImage(url: URL(string: profilePhotoURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .overlay(
                                Text(String(otherUserName.prefix(1)).uppercased())
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            )
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        } else {
            Circle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(otherUserName.prefix(1)).uppercased())
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }
    
    private var otherUserProfilePhotoURL: String? {
        if conversation.senderName == "You" {
            return conversation.recipientProfilePhotoURL
        } else {
            return conversation.senderProfilePhotoURL
        }
    }
    
    private var previewText: String {
        switch conversation.messageType {
        case .image:
            return "messages.preview.photo".localized
        case .voice:
            if let duration = conversation.voiceDuration {
                return String(format: "messages.preview.voice.duration".localized, formattedDuration(duration))
            } else {
                return "messages.preview.voice".localized
            }
        default:
            return conversation.content
        }
    }
}

struct MessageConversationModal: View {
    let message: MessageDisplay
    @Binding var conversationMessages: [MessageDisplay]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppStateManager
    
    // Helper function to update conversation open state in Firestore
    private func updateConversationOpenStateInFirestore(userId: String, isOpen: Bool) async {
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            return
        }
        
        do {
            let state: [String: Any] = [
                "openConversationUserId": isOpen ? userId : NSNull(),
                "appIsActive": true,
                "appStateUpdatedAt": Date().timeIntervalSince1970
            ]
            try await FirebaseAuthService.shared.updateUserData(state)
            print("💬 MessageConversationModal: Updated conversation open state in Firestore: \(isOpen ? "open with \(userId)" : "closed")")
        } catch {
            print("❌ MessageConversationModal: Failed to update conversation open state: \(error)")
        }
    }
    @State private var isTextFieldFocused: Bool = false
    @State private var replyText: String = ""
    @State private var isSendingReply = false
    @State private var isLoadingMessages = true
    @State private var refreshTimer: Timer?
    @State private var currentUserProfilePhotoURL: String?
    @State private var otherUserProfilePhotoURL: String?
    @State private var hasMarkedAsRead = false
    @State private var showingImagePicker = false
    @State private var showingPhotoShareWarning = false
    @State private var selectedImage: UIImage?
    @State private var showingImageReadyPreview = false
    @State private var isUploadingImage = false
    /// Local previews keyed by message content (`pending://…` or final image URL).
    @State private var localImagePreviews: [String: UIImage] = [:]
    @State private var showingConversationPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    @State private var previousMessageCount = 0
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioRecordingURL: URL?
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var isRecording = false
    @State private var showRecordingPreview = false
    @State private var isSendingVoice = false
    @State private var showingMicrophonePermissionAlert = false
    @State private var showingMicLongPressTip = false
    @State private var loadError = false
    @State private var showingPreMessageOptions = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackTimer: Timer?
    @State private var tempFileURL: URL?
    @State private var pendingAutoPlay = false
    @State private var showElapsedTime = false
    @State private var isBlockedByRecipient = false
    @State private var showingBlockedAlert = false
    @State private var hasMoreOlderMessages = false
    @State private var isLoadingOlderMessages = false
    @State private var cachedMessagesPool: [MessageDisplay] = []
    @State private var shouldScrollToBottom = false
    @State private var keyboardScrollToken = 0
    @State private var edgeSwipeOffset: CGFloat = 0
    @State private var isEdgeSwiping = false
    /// Long text messages stay collapsed until the user taps "Read more" in this open chat.
    @State private var expandedLongMessageIds: Set<String> = []
    @State private var showingOtherUserProfile = false
    @State private var otherUserProfile: ProfileCard?
    @State private var resolvedPartnerName: String?
    
    private let conversationPageSize = 10
    private let conversationBottomAnchorID = "conversation-bottom-anchor"
    private let edgeSwipeActivationWidth: CGFloat = 28
    private let edgeSwipeDismissThreshold: CGFloat = 110
    
    init(message: MessageDisplay, conversationMessages: Binding<[MessageDisplay]>) {
        self.message = message
        self._conversationMessages = conversationMessages
        // Skip the loading flash when the parent already seeded cached messages.
        self._isLoadingMessages = State(initialValue: conversationMessages.wrappedValue.isEmpty)
        let photoURL = message.senderName == "You" ? message.recipientProfilePhotoURL : message.senderProfilePhotoURL
        self._otherUserProfilePhotoURL = State(initialValue: photoURL)
        let name = message.senderName == "You" ? message.recipientName : message.senderName
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUnknown = trimmed.isEmpty
            || trimmed.caseInsensitiveCompare("Unknown User") == .orderedSame
            || trimmed.caseInsensitiveCompare("Unknown") == .orderedSame
            || trimmed.caseInsensitiveCompare("Other User") == .orderedSame
        self._resolvedPartnerName = State(initialValue: isUnknown ? nil : name)
        print("💬 MessageConversationModal INIT called with message: \(message.recipientName), content: \(message.content.prefix(20))...")
    }
    
    var conversationTitle: String {
        if let resolvedPartnerName, !isUnknownChatName(resolvedPartnerName) {
            return resolvedPartnerName
        }
        return message.senderName == "You" ? message.recipientName : message.senderName
    }
    
    private var otherUserId: String {
        message.senderName == "You" ? message.recipientId : message.senderId
    }
    
    private var otherUserName: String {
        conversationTitle
    }
    
    private func conversationPartnerId(for conversation: MessageDisplay) -> String {
        conversation.senderName == "You" ? conversation.recipientId : conversation.senderId
    }
    
    private func isUnknownChatName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.caseInsensitiveCompare("Unknown User") == .orderedSame
            || trimmed.caseInsensitiveCompare("Unknown") == .orderedSame
            || trimmed.caseInsensitiveCompare("Other User") == .orderedSame
    }
    
    private func bestKnownPartnerName() -> String? {
        if let resolvedPartnerName, !isUnknownChatName(resolvedPartnerName) {
            return resolvedPartnerName
        }
        if let profileName = otherUserProfile?.name, !isUnknownChatName(profileName) {
            return profileName
        }
        if let matchName = appState.cachedMatches.first(where: { $0.otherUser.userId == otherUserId })?.otherUser.name,
           !isUnknownChatName(matchName) {
            return matchName
        }
        if let conversation = appState.cachedMessageConversations.first(where: { conversationPartnerId(for: $0) == otherUserId }) {
            let name = conversation.senderName == "You" ? conversation.recipientName : conversation.senderName
            if !isUnknownChatName(name) {
                return name
            }
        }
        let fromMessage = message.senderName == "You" ? message.recipientName : message.senderName
        return isUnknownChatName(fromMessage) ? nil : fromMessage
    }
    
    @ViewBuilder
    private var chatHeaderAvatar: some View {
        let photoURL = otherUserProfilePhotoURL
            ?? (message.senderName == "You" ? message.recipientProfilePhotoURL : message.senderProfilePhotoURL)
        
        Group {
            if let photoURL, !photoURL.isEmpty {
                CachedAsyncImage(url: URL(string: photoURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    chatHeaderAvatarPlaceholder
                }
            } else {
                chatHeaderAvatarPlaceholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
    
    private var chatHeaderAvatarPlaceholder: some View {
        Circle()
            .fill(Color.blue.opacity(0.18))
            .overlay(
                Text(String(conversationTitle.prefix(1)).uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            )
    }
    
    var body: some View {
        let _ = print("💬 MessageConversationModal body being computed, message: \(message.recipientName), isLoadingMessages: \(isLoadingMessages)")
        NavigationStack {
            conversationContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack {
                        // Solid underlay prevents a blank flash while the image materializes.
                        SpectRoomTheme.background
                        Image(colorScheme == .dark ? "chatBackDark" : "chatBack")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                    .ignoresSafeArea()
                }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeChat()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("common.close".localized)
                }
                
                ToolbarItem(placement: .principal) {
                    Button {
                        openOtherUserProfile()
                    } label: {
                        HStack(spacing: 8) {
                            chatHeaderAvatar
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(conversationTitle)
                                    .font(.headline)
                                    .foregroundColor(SpectRoomTheme.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Text("messages.tap.to.see.profile".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        // Keep the tappable header compact so trailing actions still fit.
                        .frame(maxWidth: 220, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    // Avoid the default press fade that makes the subtitle look like it vanishes.
                    .buttonStyle(ChatHeaderButtonStyle())
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPreMessageOptions = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                            Text("matches.pre.message.button.short".localized)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                    .disabled(isBlockedByRecipient)
                    .opacity(isBlockedByRecipient ? 0.5 : 1)
                }
            }
        }
        // Opaque panel that moves with the swipe so the messages list can show through the gap.
        .background {
            ZStack {
                SpectRoomTheme.background
                Image(colorScheme == .dark ? "chatBackDark" : "chatBack")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .ignoresSafeArea()
        }
        .offset(x: max(0, edgeSwipeOffset))
        .overlay(alignment: .leading) {
            // Thin left-edge hit area for iOS-style swipe-to-close.
            Color.clear
                .frame(width: edgeSwipeActivationWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .onChanged { value in
                            guard !isRecording, !showRecordingPreview, !showingMicLongPressTip else { return }
                            if !isEdgeSwiping {
                                guard value.startLocation.x <= edgeSwipeActivationWidth + 8 else { return }
                                isEdgeSwiping = true
                            }
                            edgeSwipeOffset = max(0, value.translation.width)
                        }
                        .onEnded { value in
                            guard isEdgeSwiping else { return }
                            isEdgeSwiping = false
                            
                            let shouldDismiss =
                                value.translation.width > edgeSwipeDismissThreshold
                                || value.predictedEndTranslation.width > edgeSwipeDismissThreshold * 1.4
                            
                            if shouldDismiss {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    edgeSwipeOffset = UIScreen.main.bounds.width
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                    // Swipe already took the view off-screen; skip the
                                    // fullScreenCover's default slide-down dismiss.
                                    closeChat(animated: false)
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    edgeSwipeOffset = 0
                                }
                            }
                        }
                )
                .allowsHitTesting(!isRecording && !showRecordingPreview)
        }
        .overlay {
            if showingBlockedAlert {
                BlockedUserAlertOverlay(
                    firstName: firstName(from: otherUserName),
                    onDismiss: { dontShowAgain in
                        if dontShowAgain {
                            appState.suppressBlockedAlert(for: otherUserId)
                        }
                        showingBlockedAlert = false
                    }
                )
            } else if showingPhotoShareWarning {
                PhotoShareWarningOverlay(
                    onContinue: { dontShowAgain in
                        PhotoShareWarningOverlay.setDontShowAgain(dontShowAgain)
                        showingPhotoShareWarning = false
                        showingImagePicker = true
                    },
                    onCancel: {
                        showingPhotoShareWarning = false
                    }
                )
            }
        }
        .onAppear {
            print("💬 MessageConversationModal appeared for: \(conversationTitle)")
            print("💬 Message senderId: \(message.senderId), recipientId: \(message.recipientId)")
            print("💬 Modal appeared - conversationMessages count: \(conversationMessages.count)")
            
            let otherUserId = otherUserId
            
            appState.currentlyOpenConversationSenderId = otherUserId
            print("💬 Set currentlyOpenConversationSenderId to: \(otherUserId) (from modal onAppear)")
            
            expandedLongMessageIds.removeAll()
            
            Task {
                await updateConversationOpenStateInFirestore(userId: otherUserId, isOpen: true)
                await checkBlockStatus()
            }
            
            prefetchOtherUserProfile()
            resolveChatPartnerNameIfNeeded()
            loadConversationMessages()
            startAutoRefresh()
        }
        .onChange(of: appState.blockedUsers.map(\.id)) { _, _ in
            syncBlockStateFromAppState()
        }
        .onChange(of: appState.blockedByUsers.map(\.id)) { _, _ in
            syncBlockStateFromAppState()
        }
        .onReceive(appState.newMessageReceivedPublisher) { newMessage in
            appendIncomingMessageIfNeeded(newMessage)
            refreshPartnerNameFromIncomingMessageIfNeeded(newMessage)
        }
        .onDisappear {
            // Determine the other user's ID
            let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
            
            persistConversationCache()
            
            // Clear the currently open conversation ID
            appState.currentlyOpenConversationSenderId = nil
            print("💬 Cleared currentlyOpenConversationSenderId (from modal onDisappear)")
            
            // Clear from Firestore
            Task {
                await updateConversationOpenStateInFirestore(userId: otherUserId, isOpen: false)
            }
            
            stopAutoRefresh()
        }
        .sheet(isPresented: $showingImagePicker) {
            MessageImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { newImage in
            showingImageReadyPreview = newImage != nil
        }
        .sheet(isPresented: $showingImageReadyPreview) {
            if let image = selectedImage {
                ImagePreviewReadySheet(
                    image: image,
                    isSending: isUploadingImage,
                    onSend: {
                        showingImageReadyPreview = false
                        sendImageMessage(image: image)
                    },
                    onDiscard: {
                        selectedImage = nil
                        showingImageReadyPreview = false
                    }
                )
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isUploadingImage)
                .presentationBackground(.regularMaterial)
            }
        }
        .sheet(isPresented: $showingConversationPhotoViewer) {
            let imageMessages = conversationMessages.filter { $0.messageType == .image }
            let imageURLs = imageMessages.map { $0.content }
            ConversationPhotoViewerModal(
                photos: imageURLs,
                selectedIndex: $selectedPhotoIndex,
                conversationMessages: conversationMessages
            )
        }
        .sheet(isPresented: $showingOtherUserProfile, onDismiss: {
            // Keep chat marked open after returning from profile.
            // Keep `otherUserProfile` cached so reopening does not refetch/flicker the header.
            appState.currentlyOpenConversationSenderId = otherUserId
        }) {
            if let otherUserProfile {
                UserProfileModal(profile: otherUserProfile)
                    .environmentObject(appState)
            }
        }
        .alert("Microphone Access Needed", isPresented: $showingMicrophonePermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enable microphone access in Settings to record voice messages.")
        }
        .alert(
            "messages.voice.long.press.tip.title".localized,
            isPresented: $showingMicLongPressTip
        ) {
            Button("messages.voice.long.press.tip.got.it".localized, role: .cancel) {}
        } message: {
            Text("messages.voice.long.press.tip.message".localized)
        }
        .sheet(isPresented: $showingPreMessageOptions) {
            PreMessageOptionsModal(
                profileName: conversationTitle,
                onSelect: { selectedMessage in
                    replyText = selectedMessage
                    showingPreMessageOptions = false
                    // Open keyboard after a short delay to ensure the text field is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isTextFieldFocused = true
                    }
                }
            )
        }
        .sheet(isPresented: $isRecording) {
            RecordingIndicatorSheet(
                durationText: formattedDuration(recordingDuration),
                onStop: { stopRecording() },
                onCancel: { discardRecording() }
            )
            .presentationDetents([.height(230)])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(true)
            .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: Binding(
            get: { showRecordingPreview },
            set: { newValue in
                if !newValue, !isSendingVoice {
                    discardRecording()
                } else if newValue {
                    showRecordingPreview = true
                }
            }
        )) {
            if let audioRecordingURL {
                RecordingPreviewSheet(
                    audioURL: audioRecordingURL,
                    duration: recordingDuration,
                    isSending: isSendingVoice,
                    onSend: {
                        sendVoiceMessage(audioURL: audioRecordingURL, duration: recordingDuration)
                    },
                    onDiscard: {
                        discardRecording()
                    }
                )
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isSendingVoice)
                .presentationBackground(.regularMaterial)
            }
        }
    }
    
    private var conversationContent: some View {
        conversationMessagesArea
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Keep the composer mounted so opening does not jump when loading finishes.
                if !isBlockedByRecipient {
                    MessageComposerBar(
                        text: $replyText,
                        isFocused: $isTextFieldFocused,
                        placeholder: "",
                        isDisabled: isBlockedByRecipient || isLoadingMessages,
                        isSending: isSendingReply,
                        isRecording: isRecording,
                        onSend: { sendReply() },
                        onCamera: { requestPhotoShare() },
                        onRecordingPressChanged: { pressing in
                            if pressing, !isRecording {
                                startRecording()
                            }
                        },
                        onShortMicTap: {
                            showingMicLongPressTip = true
                        }
                    )
                    .opacity(isLoadingMessages ? 0.55 : 1)
                    .allowsHitTesting(!isLoadingMessages)
                    .background {
                        Color(.systemGray2)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    keyboardScrollToken += 1
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    keyboardScrollToken += 1
                }
            }
    }
    
    private var conversationMessagesArea: some View {
        Group {
            if isLoadingMessages && conversationMessages.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("messages.loading.conversation".localized)
                        .font(.subheadline)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                    Spacer()
                }
            } else if conversationMessages.isEmpty {
                emptyConversationPrompt
                    .padding(.horizontal, 32)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if isLoadingOlderMessages {
                                ProgressView()
                                    .padding(.vertical, 8)
                            }
                            
                            ForEach(Array(conversationMessages.enumerated()), id: \.element.id) { index, msg in
                                let showDateHeader: Bool = {
                                    guard index > 0 else { return true }
                                    let previous = conversationMessages[index - 1]
                                    return !Calendar.current.isDate(msg.createdAt, inSameDayAs: previous.createdAt)
                                }()
                                
                                if showDateHeader {
                                    ChatDateSeparator(title: msg.createdAt.formattedChatDayTitle())
                                        .id("date-\(msg.id)")
                                }
                                
                                MessageBubble(
                                    message: msg,
                                    conversationMessages: conversationMessages,
                                    isLongMessageExpanded: expandedLongMessageIds.contains(msg.id),
                                    onExpandLongMessage: {
                                        // Expand in place - do not scroll; user continues reading from here.
                                        shouldScrollToBottom = false
                                        var transaction = Transaction()
                                        transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            expandedLongMessageIds.insert(msg.id)
                                        }
                                    },
                                    showingConversationPhotoViewer: $showingConversationPhotoViewer,
                                    selectedPhotoIndex: $selectedPhotoIndex,
                                    localImagePreview: localImagePreviews[msg.content],
                                    isImageUploading: msg.content.hasPrefix("pending://")
                                )
                                .id(msg.id)
                                .onAppear {
                                    if msg.id == conversationMessages.first?.id {
                                        loadOlderMessagesIfNeeded()
                                    }
                                }
                            }
                            
                            // Spacer is the scroll target so the last bubble keeps
                            // breathing room above the composer (VStack bottom padding
                            // would sit below the anchor and get clipped).
                            Color.clear
                                .frame(height: 12)
                                .id(conversationBottomAnchorID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 0)
                    }
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    // Land on the latest messages on the first frame (avoids top→bottom jump).
                    .defaultScrollAnchor(.bottom)
                    .onAppear {
                        // One quiet pin after layout; no multi-delay animated chasing.
                        scrollToLatestMessage(proxy: proxy, force: true, animated: false)
                    }
                    .onChange(of: isLoadingMessages) { _, isLoading in
                        guard !isLoading else { return }
                        scrollToLatestMessage(proxy: proxy, force: true, animated: false)
                    }
                    .onChange(of: isUploadingImage) { _, uploading in
                        if uploading {
                            shouldScrollToBottom = true
                            scheduleScrollToBottom(proxy: proxy, force: true)
                        }
                    }
                    .onChange(of: conversationMessages.count) { _ in
                        if shouldScrollToBottom {
                            scheduleScrollToBottom(proxy: proxy, force: true, isInitial: false)
                            shouldScrollToBottom = false
                        }
                    }
                    .onChange(of: conversationMessages.last?.id) { _, _ in
                        if shouldScrollToBottom {
                            scheduleScrollToBottom(proxy: proxy, force: true, isInitial: false)
                            shouldScrollToBottom = false
                        }
                    }
                    .onChange(of: keyboardScrollToken) { _ in
                        scrollToLatestMessage(proxy: proxy, force: true)
                    }
                    .onChange(of: isTextFieldFocused) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToLatestMessage(proxy: proxy, force: true)
                        }
                    }
                }
            }
        }
    }
    
    private func closeChat(animated: Bool = true) {
        isTextFieldFocused = false
        isEdgeSwiping = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        if animated {
            edgeSwipeOffset = 0
            dismiss()
        } else {
            // Keep the off-screen swipe offset so the cover doesn't snap back
            // before the unanimated dismiss finishes.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dismiss()
            }
        }
    }
    
    private func prefetchOtherUserProfile() {
        guard otherUserProfile == nil else { return }
        let userId = otherUserId
        Task {
            do {
                let profile = try await FirebaseAuthService.shared.fetchUserProfile(for: userId)
                await MainActor.run {
                    // Only set if still needed - avoid clobbering a newer fetch from tap.
                    if otherUserProfile == nil {
                        otherUserProfile = profile
                    }
                    applyResolvedPartnerIdentity(
                        name: profile.name,
                        photoURL: profile.imageURL
                    )
                }
            } catch {
                print("❌ Failed to prefetch chat profile for \(userId): \(error)")
            }
        }
    }
    
    private func resolveChatPartnerNameIfNeeded() {
        if let known = bestKnownPartnerName() {
            resolvedPartnerName = known
            return
        }
        
        let userId = otherUserId
        Task {
            // Dedicated name lookup in case the full profile path is slow or incomplete.
            if let name = try? await FirebaseAuthService.shared.fetchSenderName(for: userId),
               !isUnknownChatName(name) {
                await MainActor.run {
                    applyResolvedPartnerIdentity(name: name, photoURL: otherUserProfilePhotoURL)
                }
                return
            }
            
            if let profile = try? await FirebaseAuthService.shared.fetchUserProfile(for: userId) {
                await MainActor.run {
                    if otherUserProfile == nil {
                        otherUserProfile = profile
                    }
                    applyResolvedPartnerIdentity(name: profile.name, photoURL: profile.imageURL)
                }
            }
        }
    }
    
    private func refreshPartnerNameFromIncomingMessageIfNeeded(_ newMessage: MessageDisplay) {
        guard isUnknownChatName(conversationTitle) else { return }
        guard conversationPartnerId(for: newMessage) == otherUserId
                || newMessage.senderId == otherUserId
                || newMessage.recipientId == otherUserId else { return }
        
        let candidate = newMessage.senderName == "You" ? newMessage.recipientName : newMessage.senderName
        if !isUnknownChatName(candidate) {
            applyResolvedPartnerIdentity(
                name: candidate,
                photoURL: newMessage.senderName == "You" ? newMessage.recipientProfilePhotoURL : newMessage.senderProfilePhotoURL
            )
        }
    }
    
    private func applyResolvedPartnerIdentity(name: String, photoURL: String?) {
        guard !isUnknownChatName(name) else { return }
        resolvedPartnerName = name
        if let photoURL, !photoURL.isEmpty, otherUserProfilePhotoURL == nil {
            otherUserProfilePhotoURL = photoURL
        }
        appState.updateConversationPartnerDetails(
            userId: otherUserId,
            name: name,
            photoURL: photoURL ?? otherUserProfilePhotoURL
        )
    }
    
    private func openOtherUserProfile() {
        // Prefer already-cached profile so the header never enters a loading state.
        if otherUserProfile != nil {
            showingOtherUserProfile = true
            return
        }
        
        let userId = otherUserId
        Task {
            do {
                let profile = try await FirebaseAuthService.shared.fetchUserProfile(for: userId)
                await MainActor.run {
                    otherUserProfile = profile
                    applyResolvedPartnerIdentity(name: profile.name, photoURL: profile.imageURL)
                    showingOtherUserProfile = true
                }
            } catch {
                print("❌ Failed to open chat profile for \(userId): \(error)")
            }
        }
    }
    
    private var emptyConversationPrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Text("💬")
                .font(.system(size: 48))
                .frame(width: 96, height: 96)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.blue.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.blue.opacity(0.16), radius: 12, y: 4)
            
            Text(String(format: "messages.no.messages.found".localized, firstName(from: otherUserName)))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SpectRoomTheme.text)
                .multilineTextAlignment(.center)
            
            emptyConversationBodyWithLink
                .multilineTextAlignment(.center)
            
            Spacer()
        }
    }
    
    private var emptyConversationBodyWithLink: some View {
        let prefix = "messages.no.messages.found.body".localized
        let linkTitle = "messages.no.messages.found.quick.messages".localized
        var bodyText = AttributedString(prefix)
        bodyText.foregroundColor = UIColor(SpectRoomTheme.text)
        
        var linkText = AttributedString(linkTitle)
        linkText.link = URL(string: "spectroom://quick-messages")
        linkText.foregroundColor = isBlockedByRecipient ? UIColor.secondaryLabel : UIColor.systemBlue
        linkText.underlineStyle = .single
        
        return Text(bodyText + linkText + AttributedString("."))
            .font(.subheadline)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "spectroom", url.host == "quick-messages" else {
                    return .systemAction
                }
                guard !isBlockedByRecipient else { return .handled }
                showingPreMessageOptions = true
                return .handled
            })
    }
    
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    private func checkBlockStatus() async {
        let locallyHidden = await MainActor.run { appState.isMessagingBlocked(with: otherUserId) }
        do {
            let theyBlockedMe = try await FirebaseAuthService.shared.isBlockedBy(userId: otherUserId)
            print("🚫 Block status for \(otherUserId): theyBlockedMe=\(theyBlockedMe) locallyHidden=\(locallyHidden)")
            await MainActor.run {
                let blocked = theyBlockedMe || appState.isMessagingBlocked(with: otherUserId)
                isBlockedByRecipient = blocked
                if blocked {
                    replyText = ""
                    // Only show the "they've blocked you" alert when they blocked you
                    // (not when you blocked them — they're simply hidden from your lists).
                    if theyBlockedMe, appState.shouldShowBlockedAlert(for: otherUserId) {
                        showingBlockedAlert = true
                    }
                    if theyBlockedMe {
                        appState.refreshBlockedByUsers()
                    }
                    if appState.isMessagingBlocked(with: otherUserId) {
                        dismiss()
                    }
                }
            }
        } catch {
            print("⚠️ Unable to check block status for \(otherUserId): \(error.localizedDescription)")
            await MainActor.run {
                isBlockedByRecipient = locallyHidden || appState.isMessagingBlocked(with: otherUserId)
                if appState.isMessagingBlocked(with: otherUserId) {
                    dismiss()
                }
            }
        }
    }
    
    private func syncBlockStateFromAppState() {
        let blocked = appState.isMessagingBlocked(with: otherUserId)
        isBlockedByRecipient = blocked
        if blocked {
            replyText = ""
            dismiss()
        }
    }
    
    private func formattedDuration(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = time >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: time) ?? "0:00"
    }
    
    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy) {
        guard shouldScrollToBottom else { return }
        scheduleScrollToBottom(proxy: proxy, force: true, isInitial: true)
        shouldScrollToBottom = false
    }
    
    private func scheduleScrollToBottom(
        proxy: ScrollViewProxy,
        force: Bool = false,
        isInitial: Bool = false
    ) {
        // Keep initial open calm: a couple of instant pins beat many delayed animated jumps.
        let delays: [TimeInterval] = isInitial ? [0, 0.08] : [0.05, 0.2]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                scrollToLatestMessage(
                    proxy: proxy,
                    force: force || shouldScrollToBottom,
                    animated: !isInitial
                )
            }
        }
    }
    
    private func scrollToLatestMessage(
        proxy: ScrollViewProxy,
        force: Bool,
        animated: Bool = true
    ) {
        guard force || shouldScrollToBottom else { return }
        guard !conversationMessages.isEmpty else { return }
        
        // Materialize the last bubble in LazyVStack first, then pin the bottom
        // spacer so designed padding sits above the text field.
        let scrollAction = {
            if let lastID = conversationMessages.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            proxy.scrollTo(conversationBottomAnchorID, anchor: .bottom)
        }
        
        if animated {
            withAnimation(.easeOut(duration: 0.25), scrollAction)
        } else {
            scrollAction()
        }
    }
    
    private func persistConversationCache() {
        guard !isLoadingMessages else { return }
        let pool = cachedMessagesPool.isEmpty ? conversationMessages : cachedMessagesPool
        guard !pool.isEmpty else { return }
        
        appState.cacheConversationState(
            for: otherUserId,
            messagePool: pool,
            visibleMessages: conversationMessages,
            hasMoreOlderMessages: hasMoreOlderMessages
        )
    }
    
    private func loadConversationMessages() {
        print("💬 MessageConversationModal: Loading conversation messages for: \(message.content)")
        
        // Restore cached scroll state synchronously so the first frame already has messages.
        if let cachedState = appState.getCachedConversationState(for: otherUserId) {
            print("💬 MessageConversationModal: Using cached conversation state (\(cachedState.visibleMessages.count) visible / \(cachedState.messagePool.count) total messages)")
            applyConversationSnapshot(
                pool: cachedState.messagePool,
                visible: Array(cachedState.messagePool.suffix(conversationPageSize)),
                hasMoreOlder: cachedState.messagePool.count > conversationPageSize
                    || cachedState.hasMoreOlderMessages,
                markLoaded: true,
                pinToBottom: false
            )
            
            Task {
                if !hasMarkedAsRead {
                    await appState.markMessagesAsRead(from: otherUserId)
                    await MainActor.run {
                        hasMarkedAsRead = true
                    }
                }
                
                if currentUserProfilePhotoURL == nil || otherUserProfilePhotoURL == nil {
                    await fetchProfilePhotosIfNeeded(otherUserId: otherUserId)
                }
                
                // Quiet background merge - only refresh UI when content actually changes.
                await loadRecentConversationPageAndMerge(otherUserId: otherUserId)
            }
            return
        }
        
        // Parent may have already seeded the binding with cached/empty state.
        if !conversationMessages.isEmpty {
            applyConversationSnapshot(
                pool: conversationMessages,
                visible: conversationMessages,
                hasMoreOlder: false,
                markLoaded: true,
                pinToBottom: false
            )
        }
        
        Task {
            do {
                if !hasMarkedAsRead {
                    await appState.markMessagesAsRead(from: otherUserId)
                    await MainActor.run {
                        hasMarkedAsRead = true
                    }
                }
                
                let page = try await FirebaseAuthService.shared.fetchConversationMessagesPage(
                    with: otherUserId,
                    limit: conversationPageSize
                )
                
                if currentUserProfilePhotoURL == nil || otherUserProfilePhotoURL == nil {
                    await fetchProfilePhotosIfNeeded(otherUserId: otherUserId)
                }
                
                await MainActor.run {
                    applyConversationSnapshot(
                        pool: page.messages,
                        visible: page.messages,
                        hasMoreOlder: page.hasMoreOlder,
                        markLoaded: true,
                        pinToBottom: false
                    )
                    persistConversationCache()
                }
            } catch {
                print("❌ MessageConversationModal: Error loading conversation messages: \(error)")
                await MainActor.run {
                    let fallback = [message].sorted { $0.createdAt < $1.createdAt }
                    applyConversationSnapshot(
                        pool: fallback,
                        visible: fallback,
                        hasMoreOlder: false,
                        markLoaded: true,
                        pinToBottom: false
                    )
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if isLoadingMessages {
                print("⚠️ MessageConversationModal: Loading timeout reached, showing fallback")
                let fallback = [message].sorted { $0.createdAt < $1.createdAt }
                applyConversationSnapshot(
                    pool: fallback,
                    visible: fallback,
                    hasMoreOlder: false,
                    markLoaded: true,
                    pinToBottom: false
                )
            }
        }
    }
    
    private func applyConversationSnapshot(
        pool: [MessageDisplay],
        visible: [MessageDisplay],
        hasMoreOlder: Bool,
        markLoaded: Bool,
        pinToBottom: Bool = true
    ) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cachedMessagesPool = pool
            conversationMessages = visible
            hasMoreOlderMessages = hasMoreOlder
            previousMessageCount = visible.count
            if markLoaded {
                isLoadingMessages = false
            }
            shouldScrollToBottom = pinToBottom
        }
    }
    
    /// Fetches the latest page and merges it into the local pool so opening a chat
    /// always restores history even if the cache only had a preview message.
    private func loadRecentConversationPageAndMerge(otherUserId: String) async {
        do {
            let page = try await FirebaseAuthService.shared.fetchConversationMessagesPage(
                with: otherUserId,
                limit: conversationPageSize
            )
            
            await MainActor.run {
                let mergedPool = (cachedMessagesPool + page.messages)
                    .deduplicatedConversationMessages()
                let newVisible = Array(mergedPool.suffix(conversationPageSize))
                let oldKeys = conversationMessages.map(\.deduplicationKey)
                let newKeys = newVisible.map(\.deduplicationKey)
                
                cachedMessagesPool = mergedPool
                hasMoreOlderMessages = page.hasMoreOlder
                    || mergedPool.count > conversationPageSize
                
                // Avoid rewriting the list (and re-scrolling) when nothing meaningful changed.
                guard oldKeys != newKeys else {
                    persistConversationCache()
                    return
                }
                
                applyConversationSnapshot(
                    pool: mergedPool,
                    visible: newVisible,
                    hasMoreOlder: hasMoreOlderMessages,
                    markLoaded: true,
                    // Only nudge scroll if the tip of the chat actually changed.
                    pinToBottom: newKeys.last != oldKeys.last
                )
                persistConversationCache()
            }
        } catch {
            print("❌ MessageConversationModal: Error merging recent conversation page: \(error)")
            // Fall back to newer-only refresh if the full page fetch fails.
            await refreshConversationMessagesInBackground(otherUserId: otherUserId)
        }
    }
    
    private func loadOlderMessagesIfNeeded() {
        guard hasMoreOlderMessages, !isLoadingOlderMessages, !isLoadingMessages else { return }
        isLoadingOlderMessages = true
        
        if let oldestVisible = conversationMessages.first,
           let oldestIndex = cachedMessagesPool.firstIndex(where: { $0.deduplicationKey == oldestVisible.deduplicationKey }),
           oldestIndex > 0 {
            let startIndex = max(0, oldestIndex - conversationPageSize)
            let olderMessages = Array(cachedMessagesPool[startIndex..<oldestIndex])
            
            conversationMessages = (olderMessages + conversationMessages)
                .deduplicatedConversationMessages()
            hasMoreOlderMessages = startIndex > 0
            isLoadingOlderMessages = false
            persistConversationCache()
            return
        }
        
        Task {
            do {
                let beforeDate = conversationMessages.first?.createdAt
                let page = try await FirebaseAuthService.shared.fetchConversationMessagesPage(
                    with: otherUserId,
                    limit: conversationPageSize,
                    before: beforeDate
                )
                
                await MainActor.run {
                    if page.messages.isEmpty {
                        hasMoreOlderMessages = false
                    } else {
                        let existingKeys = Set(conversationMessages.map(\.deduplicationKey))
                        let uniqueOlder = page.messages.filter { !existingKeys.contains($0.deduplicationKey) }
                        conversationMessages = (uniqueOlder + conversationMessages)
                            .deduplicatedConversationMessages()
                        
                        cachedMessagesPool = (uniqueOlder + cachedMessagesPool)
                            .deduplicatedConversationMessages()
                        hasMoreOlderMessages = page.hasMoreOlder
                        persistConversationCache()
                    }
                    isLoadingOlderMessages = false
                }
            } catch {
                print("❌ MessageConversationModal: Error loading older messages: \(error)")
                await MainActor.run {
                    isLoadingOlderMessages = false
                }
            }
        }
    }
    
    private func startAutoRefresh() {
        print("🔄 MessageConversationModal: Starting auto-refresh timer (10 seconds)")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            print("🔄 MessageConversationModal: Auto-refreshing conversation...")
            refreshMessagesOnly()
        }
    }
    
    private func refreshMessagesOnly() {
        print("💬 MessageConversationModal: Refreshing message content only (no profile photos)...")
        print("💬 MessageConversationModal: Current cached profile photos - Current: \(currentUserProfilePhotoURL != nil), Other: \(otherUserProfilePhotoURL != nil)")
        
        // Determine the other user's ID
        let otherUserId: String
        if message.senderName == "You" {
            otherUserId = message.recipientId
        } else {
            otherUserId = message.senderId
        }
        
        // Refresh in background
        Task {
            await refreshConversationMessagesInBackground(otherUserId: otherUserId)
        }
    }
    
    private func appendIncomingMessageIfNeeded(_ newMessage: MessageDisplay) {
        // Only handle messages from the other person in this open chat.
        guard newMessage.senderId == otherUserId else { return }
        
        let key = newMessage.deduplicationKey
        if conversationMessages.contains(where: { $0.deduplicationKey == key }) {
            return
        }
        
        // Always re-sort: while backgrounded, Firestore can deliver several
        // adds in non-chronological order.
        conversationMessages = (conversationMessages + [newMessage])
            .deduplicatedConversationMessages()
        cachedMessagesPool = (cachedMessagesPool + [newMessage]).deduplicatedConversationMessages()
        shouldScrollToBottom = true
        previousMessageCount = conversationMessages.count
        keyboardScrollToken += 1
        persistConversationCache()
        
        // Play sound at the same moment the bubble is added (not when the
        // Firestore listener first fires ahead of the UI refresh).
        appState.playIncomingMessageSoundIfNeeded(for: key)
        
        Task {
            await appState.markMessagesAsRead(from: otherUserId)
        }
    }
    
    private func refreshConversationMessagesInBackground(otherUserId: String) async {
        do {
            let newestTimestamp = await MainActor.run {
                conversationMessages.last?.createdAt ?? cachedMessagesPool.last?.createdAt
            }
            
            if let newestTimestamp {
                let newerMessages = try await FirebaseAuthService.shared.fetchConversationMessagesNewerThan(
                    with: otherUserId,
                    since: newestTimestamp
                )
                
                guard !newerMessages.isEmpty else { return }
                
                await MainActor.run {
                    let existingKeys = Set(conversationMessages.map(\.deduplicationKey))
                    let uniqueNew = newerMessages.filter { !existingKeys.contains($0.deduplicationKey) }
                    
                    guard !uniqueNew.isEmpty else { return }
                    
                    conversationMessages = (conversationMessages + uniqueNew)
                        .deduplicatedConversationMessages()
                    cachedMessagesPool = (cachedMessagesPool + uniqueNew).deduplicatedConversationMessages()
                    shouldScrollToBottom = true
                    persistConversationCache()
                    
                    let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                    let hasNewIncomingMessage = uniqueNew.contains { $0.senderId != currentUserId }
                    if hasNewIncomingMessage {
                        Task {
                            await appState.markMessagesAsRead(from: otherUserId)
                        }
                    }
                    
                    previousMessageCount = conversationMessages.count
                    // Tip: newer messages often arrive right after open - keep scrolling to the end.
                    keyboardScrollToken += 1
                }
                return
            }
            
            let page = try await FirebaseAuthService.shared.fetchConversationMessagesPage(
                with: otherUserId,
                limit: conversationPageSize
            )
            
            await MainActor.run {
                guard conversationMessages.isEmpty else { return }
                
                conversationMessages = page.messages
                cachedMessagesPool = page.messages
                hasMoreOlderMessages = page.hasMoreOlder
                persistConversationCache()
                previousMessageCount = conversationMessages.count
            }
        } catch {
            print("❌ MessageConversationModal: Error refreshing message content: \(error)")
        }
    }
    
    private func fetchProfilePhotosIfNeeded(otherUserId: String) async {
        // Get current user ID
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            return
        }
        
        // Fetch both profile photos in parallel
        do {
            async let currentUserPhoto = FirebaseAuthService.shared.fetchUserProfilePhotoURL(for: currentUserId)
            async let otherUserPhoto = FirebaseAuthService.shared.fetchUserProfilePhotoURL(for: otherUserId)
            
            let (currentPhoto, otherPhoto) = try await (currentUserPhoto, otherUserPhoto)
            
            await MainActor.run {
                currentUserProfilePhotoURL = currentPhoto
                otherUserProfilePhotoURL = otherPhoto
                print("💬 MessageConversationModal: Profile photos cached - Current: \(currentPhoto != nil), Other: \(otherPhoto != nil)")
            }
        } catch {
            print("❌ MessageConversationModal: Error fetching profile photos: \(error)")
        }
    }
    
    private func updateMessageContentOnly(with newMessages: [Message]) {
        // Determine the other user's ID
        let otherUserId: String
        if message.senderName == "You" {
            otherUserId = message.recipientId
        } else {
            otherUserId = message.senderId
        }
        // Create a map of existing messages by stable identity for quick lookup
        var existingMessagesMap: [String: MessageDisplay] = [:]
        for msg in conversationMessages {
            existingMessagesMap[msg.deduplicationKey] = msg
        }
        
        // Create new MessageDisplay objects only for new messages
        var updatedMessages: [MessageDisplay] = []
        
        for message in newMessages {
            let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
            let senderName = message.senderFirebaseId == currentUserId ? "You" : "Other User"
            let recipientName = senderName == "You" ? "Other User" : "You"
            let recipientId = message.senderFirebaseId == currentUserId ? otherUserId : currentUserId
            let dedupKey = "\(message.senderFirebaseId)_\(recipientId)_\(message.type.rawValue)_\(message.content)"
            
            if let existingMessage = existingMessagesMap[dedupKey] {
                updatedMessages.append(existingMessage)
            } else {
                let messageDisplay = MessageDisplay(
                    message: message,
                    senderName: senderName,
                    recipientName: recipientName,
                    senderId: message.senderFirebaseId,
                    recipientId: message.senderFirebaseId == currentUserId ? otherUserId : currentUserId,
                    senderProfilePhotoURL: senderName == "You" ? currentUserProfilePhotoURL : otherUserProfilePhotoURL,
                    recipientProfilePhotoURL: senderName == "You" ? otherUserProfilePhotoURL : currentUserProfilePhotoURL
                )
                
                updatedMessages.append(messageDisplay)
            }
        }
        
        conversationMessages = updatedMessages.deduplicatedConversationMessages()
        print("💬 MessageConversationModal: Updated \(updatedMessages.count) messages, preserved existing profile photos")
    }
    
    private func stopAutoRefresh() {
        print("🔄 MessageConversationModal: Stopping auto-refresh timer")
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func requestPhotoShare() {
        guard !isBlockedByRecipient else { return }
        isTextFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if PhotoShareWarningOverlay.shouldShowWarning {
            showingPhotoShareWarning = true
        } else {
            showingImagePicker = true
        }
    }
    
    private func sendReply() {
        guard !isBlockedByRecipient else { return }
        guard !isSendingReply else { return }
        let trimmedContent = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        
        // Clear text immediately and keep focus so the keyboard stays up.
        replyText = ""
        isTextFieldFocused = true
        isSendingReply = true
        updateConversationListAfterOutgoingMessage(content: trimmedContent, type: .text, voiceDuration: nil)
        shouldScrollToBottom = true
        // Composer shrinks when text clears; re-pin after that layout settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            keyboardScrollToken += 1
        }
        
        Task {
            do {
                // Determine recipient ID based on message type
                let recipientId: String
                if message.senderName == "You" {
                    recipientId = message.recipientId
                } else {
                    recipientId = message.senderId
                }
                
                let messageId = try await FirebaseAuthService.shared.sendMessage(
                    to: recipientId,
                    content: trimmedContent
                )
                
                print("✅ Reply sent successfully with ID: \(messageId)")
                
                await MainActor.run {
                    isSendingReply = false
                    isTextFieldFocused = true
                    refreshMessagesOnly()
                }
                
            } catch {
                print("❌ Error sending reply: \(error)")
                await MainActor.run {
                    // Restore text if send failed so the user can retry.
                    if replyText.isEmpty {
                        replyText = trimmedContent
                    }
                    isSendingReply = false
                    isTextFieldFocused = true
                }
            }
        }
    }
    
    private func sendImageMessage(image: UIImage) {
        guard !isBlockedByRecipient else { return }
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            print("❌ Cannot send image - user not authenticated")
            return
        }
        
        let pendingContent = "pending://\(UUID().uuidString)"
        isUploadingImage = true
        localImagePreviews[pendingContent] = image
        updateConversationListAfterOutgoingMessage(
            content: pendingContent,
            type: .image,
            voiceDuration: nil
        )
        shouldScrollToBottom = true
        
        Task {
            do {
                let recipientId: String
                if message.senderName == "You" {
                    recipientId = message.recipientId
                } else {
                    recipientId = message.senderId
                }
                
                let imageURL = try await PhotoStorageService.shared.uploadMessageImage(image, for: currentUserId)
                print("✅ Image uploaded successfully: \(imageURL)")
                
                let messageId = try await FirebaseAuthService.shared.sendImageMessage(
                    to: recipientId,
                    imageURL: imageURL
                )
                
                print("✅ Image message sent successfully with ID: \(messageId)")
                
                await MainActor.run {
                    selectedImage = nil
                    // Swap pending bubble → real URL, keep the same local image under the spinner until ready.
                    if let index = conversationMessages.firstIndex(where: { $0.content == pendingContent }) {
                        let pending = conversationMessages[index]
                        let finalized = Message(
                            conversationId: UUID(),
                            senderId: UUID(),
                            senderFirebaseId: currentUserId,
                            content: imageURL,
                            type: .image
                        )
                        let finalizedDisplay = MessageDisplay(
                            message: finalized,
                            senderName: pending.senderName,
                            recipientName: pending.recipientName,
                            senderId: pending.senderId,
                            recipientId: pending.recipientId,
                            senderProfilePhotoURL: pending.senderProfilePhotoURL,
                            recipientProfilePhotoURL: pending.recipientProfilePhotoURL
                        )
                        conversationMessages[index] = finalizedDisplay
                        localImagePreviews[imageURL] = image
                        localImagePreviews.removeValue(forKey: pendingContent)
                        cachedMessagesPool = (cachedMessagesPool.filter { $0.content != pendingContent } + [finalizedDisplay])
                            .deduplicatedConversationMessages()
                        persistConversationCache()
                        appState.updateConversationInCache(finalizedDisplay)
                    } else {
                        localImagePreviews[imageURL] = image
                        localImagePreviews.removeValue(forKey: pendingContent)
                        updateConversationListAfterOutgoingMessage(content: imageURL, type: .image, voiceDuration: nil)
                    }
                    isUploadingImage = false
                    refreshMessagesOnly()
                }
                
            } catch {
                print("❌ Error sending image message: \(error)")
                await MainActor.run {
                    selectedImage = nil
                    isUploadingImage = false
                    conversationMessages.removeAll { $0.content == pendingContent }
                    cachedMessagesPool.removeAll { $0.content == pendingContent }
                    localImagePreviews.removeValue(forKey: pendingContent)
                    persistConversationCache()
                }
            }
        }
    }
    
    private func startRecording() {
        guard !isBlockedByRecipient else { return }
        // Remove any existing preview and file before starting a new recording
        if showRecordingPreview {
            discardRecording()
        }
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    beginRecordingSession()
                } else {
                    showingMicrophonePermissionAlert = true
                }
            }
        }
    }
    
    private func beginRecordingSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            audioRecordingURL = fileURL
            recordingDuration = 0
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                recordingDuration = audioRecorder?.currentTime ?? recordingDuration
            }
            
            withAnimation {
                isRecording = true
            }
        } catch {
            print("❌ Failed to begin recording session: \(error)")
            showingMicrophonePermissionAlert = true
            discardRecording()
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        let capturedDuration = audioRecorder?.currentTime ?? recordingDuration
        audioRecorder = nil
        
        withAnimation {
            isRecording = false
        }
        
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        
        recordingDuration = max(capturedDuration, 0.1)
        // Let the recording sheet finish dismissing before presenting the ready sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showRecordingPreview = true
        }
    }
    
    private func discardRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        if let url = audioRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioRecordingURL = nil
        recordingDuration = 0
        isSendingVoice = false
        
        isRecording = false
        showRecordingPreview = false
    }
    
    private func sendVoiceMessage(audioURL: URL, duration: TimeInterval) {
        guard !isBlockedByRecipient else { return }
        guard !isSendingVoice else { return }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            discardRecording()
            return
        }
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            discardRecording()
            return
        }
        
        isSendingVoice = true
        
        Task {
            do {
                let recipientId = message.senderName == "You" ? message.recipientId : message.senderId
                let remoteURL = try await PhotoStorageService.shared.uploadVoiceMessage(audioURL, for: currentUserId)
                let messageId = try await FirebaseAuthService.shared.sendVoiceMessage(
                    to: recipientId,
                    audioURL: remoteURL,
                    duration: duration
                )
                
                print("✅ Voice message sent successfully with ID: \(messageId)")
                
                // Cleanup local file
                try? FileManager.default.removeItem(at: audioURL)
                
                await MainActor.run {
                    isSendingVoice = false
                    discardRecording()
                    updateConversationListAfterOutgoingMessage(
                        content: remoteURL,
                        type: .voice,
                        voiceDuration: duration
                    )
                    refreshMessagesOnly()
                }
            } catch {
                print("❌ Error sending voice message: \(error)")
                await MainActor.run {
                    isSendingVoice = false
                }
            }
        }
    }
    
    private func updateConversationListAfterOutgoingMessage(content: String, type: MessageType, voiceDuration: TimeInterval?) {
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else { return }
        let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
        let otherUserName = message.senderName == "You" ? message.recipientName : message.senderName
        let newMessage = Message(
            conversationId: UUID(),
            senderId: UUID(),
            senderFirebaseId: currentUserId,
            content: content,
            type: type,
            voiceDuration: voiceDuration
        )
        let messageDisplay = MessageDisplay(
            message: newMessage,
            senderName: "You",
            recipientName: otherUserName,
            senderId: currentUserId,
            recipientId: otherUserId,
            senderProfilePhotoURL: currentUserProfilePhotoURL,
            recipientProfilePhotoURL: otherUserProfilePhotoURL
        )
        conversationMessages = (conversationMessages + [messageDisplay])
            .deduplicatedConversationMessages()
        cachedMessagesPool = (cachedMessagesPool + [messageDisplay]).deduplicatedConversationMessages()
        persistConversationCache()
        appState.updateConversationInCache(messageDisplay)
    }
}

struct MessageImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MessageImagePicker
        
        init(_ parent: MessageImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                if let image = image as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                    }
                }
            }
        }
    }
}

struct RecordingIndicatorSheet: View {
    let durationText: String
    let onStop: () -> Void
    let onCancel: () -> Void
    @State private var animate = false
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("messages.voice.recording".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .scaleEffect(animate ? 1.2 : 0.9)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animate)
                        .onAppear { animate = true }
                    
                    Text(durationText)
                        .font(.title3)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundColor(SpectRoomTheme.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(height: 64)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Button(role: .destructive, action: onCancel) {
                    Text("common.delete".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: onStop) {
                    Text("common.done".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct SendingSpinner: View {
    @State private var rotating = false
    
    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.88)
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.75).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
    }
}

struct RecordingPreviewSheet: View {
    let audioURL: URL
    let duration: TimeInterval
    let isSending: Bool
    let onSend: () -> Void
    let onDiscard: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("messages.voice.ready".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                // Same allocated slot as the recording progress row.
                VoiceMessagePlayerView(
                    audioURL: audioURL,
                    displayDuration: duration,
                    accentColor: Color(red: 0.07, green: 0.55, blue: 0.47),
                    textColor: .primary,
                    baseColor: Color(.systemGray5),
                    waveColor: Color.gray.opacity(0.45)
                )
                .frame(height: 64)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Button(role: .destructive, action: onDiscard) {
                    Text("common.delete".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSending)
                
                Button(action: onSend) {
                    HStack(spacing: 8) {
                        if isSending {
                            SendingSpinner()
                            Text("messages.sending".localized)
                        } else {
                            Text("messages.send".localized)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct ImagePreviewReadySheet: View {
    let image: UIImage
    let isSending: Bool
    let onSend: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("messages.voice.ready".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 100)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: onDiscard) {
                    Text("settings.cancel".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSending)

                Button(action: onSend) {
                    HStack(spacing: 8) {
                        if isSending {
                            SendingSpinner()
                            Text("messages.sending".localized)
                        } else {
                            Text("messages.send".localized)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct VoiceMessagePlayerView: View {
    let audioURL: URL?
    let displayDuration: TimeInterval?
    let accentColor: Color
    let textColor: Color
    let baseColor: Color
    let waveColor: Color
    var timestampText: String? = nil
    var isOutgoing: Bool = true
    
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isLoading = false
    @State private var isPlaying = false
    @State private var loadError = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackTimer: Timer?
    @State private var tempFileURL: URL?
    @State private var pendingAutoPlay = false
    @State private var showElapsedTime = false
    
    private let playedWaveColor = Color.black.opacity(0.85)
    private let unplayedWaveColor = Color.gray.opacity(0.35)
    private let scrubberColor = Color(red: 0.45, green: 0.78, blue: 0.95)
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: togglePlayback) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    if isLoading {
                        ProgressView()
                            .tint(accentColor)
                    } else if loadError {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading || loadError || audioURL == nil)
            
            VStack(alignment: .leading, spacing: 4) {
                VoiceMessageWaveform(
                    progress: progress,
                    playedColor: playedWaveColor,
                    unplayedColor: unplayedWaveColor,
                    scrubberColor: scrubberColor,
                    onSeek: seekToProgress
                )
                .frame(height: 24)
                
                HStack(alignment: .bottom) {
                    Text(displayTime)
                        .font(.caption2)
                        .foregroundColor(textColor.opacity(0.65))
                        .monospacedDigit()
                    
                    Spacer(minLength: 8)
                    
                    if let timestampText {
                        Text(timestampText)
                            .font(.caption2)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .padding(.leading, isOutgoing ? 0 : 7)
        .padding(.trailing, isOutgoing ? 7 : 0)
        .frame(minWidth: 200, maxWidth: 260)
        .background(baseColor, in: ChatBubbleShape(isOutgoing: isOutgoing))
        .onAppear {
            if duration == 0, let displayDuration {
                duration = displayDuration
            }
            prepareAudioIfNeeded(autoPlay: false)
        }
        .onDisappear {
            stopPlayback(resetPosition: true)
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
            audioPlayer = nil
        }
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    
    private var displayTime: String {
        if showElapsedTime || isPlaying || currentTime > 0 {
            return formattedDuration(currentTime)
        }
        return formattedDuration(duration > 0 ? duration : (displayDuration ?? 0))
    }
    
    private func formattedDuration(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func seekToProgress(_ newProgress: Double) {
        let clamped = min(max(newProgress, 0), 1)
        guard duration > 0 else { return }
        let newTime = duration * clamped
        currentTime = newTime
        showElapsedTime = true
        audioPlayer?.currentTime = newTime
        if isPlaying {
            audioPlayer?.play()
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback(resetPosition: false)
        } else {
            if audioPlayer == nil {
                prepareAudioIfNeeded(autoPlay: true)
            } else {
                startPlayback()
            }
        }
    }
    
    private func prepareAudioIfNeeded(autoPlay: Bool) {
        guard audioPlayer == nil, !isLoading else {
            if autoPlay {
                startPlayback()
            }
            return
        }
        guard let audioURL else {
            loadError = true
            return
        }
        
        isLoading = true
        loadError = false
        pendingAutoPlay = autoPlay
        
        Task {
            do {
                let localURL: URL
                if audioURL.isFileURL {
                    localURL = audioURL
                } else {
                    let (data, _) = try await URLSession.shared.data(from: audioURL)
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice_preview_\(UUID().uuidString).m4a")
                    try data.write(to: tempURL, options: .atomic)
                    localURL = tempURL
                    await MainActor.run {
                        tempFileURL = tempURL
                    }
                }
                
                let player = try AVAudioPlayer(contentsOf: localURL)
                player.prepareToPlay()
                let actualDuration = player.duration
                
                await MainActor.run {
                    audioPlayer = player
                    if actualDuration > 0 {
                        duration = actualDuration
                    } else if let displayDuration, displayDuration > 0 {
                        duration = displayDuration
                    }
                    isLoading = false
                    
                    if pendingAutoPlay {
                        startPlayback()
                    }
                }
            } catch {
                print("❌ Failed to load audio: \(error)")
                await MainActor.run {
                    isLoading = false
                    loadError = true
                    showElapsedTime = false
                }
            }
        }
    }
    
    private func startPlayback() {
        guard let player = audioPlayer else { return }
        player.currentTime = currentTime
        if player.duration > 0 {
            duration = player.duration
        }
        player.play()
        isPlaying = true
        showElapsedTime = true
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            currentTime = min(player.currentTime, duration)
            if !player.isPlaying {
                stopPlayback(resetPosition: true)
            }
        }
    }
    
    private func stopPlayback(resetPosition: Bool) {
        if let player = audioPlayer, player.isPlaying {
            player.pause()
        }
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        if resetPosition {
            currentTime = 0
            showElapsedTime = false
            audioPlayer?.currentTime = 0
        }
    }
}

struct VoiceMessageWaveform: View {
    let progress: Double
    let playedColor: Color
    let unplayedColor: Color
    let scrubberColor: Color
    var onSeek: ((Double) -> Void)?
    
    private let barCount = 40
    private let scrubberSize: CGFloat = 11
    private let scrubberHitSize: CGFloat = 32
    
    @State private var dragStartProgress: Double?
    
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let step = width / CGFloat(max(barCount - 1, 1))
            let progressX = width * CGFloat(min(max(progress, 0), 1))
            let centerY = height / 2
            let scrubberX = max(scrubberSize / 2, min(progressX, width - scrubberSize / 2))
            
            ZStack {
                Canvas { context, size in
                    let midY = size.height / 2
                    for index in 0..<barCount {
                        let normalized = Double(index) / Double(max(barCount - 1, 1))
                        let isPlayed = normalized <= progress
                        let currentWidth = barWidth(for: index)
                        let currentHeight = min(barHeight(for: index), size.height - 4)
                        let xPosition = step * CGFloat(index)
                        let rect = CGRect(
                            x: xPosition - currentWidth / 2,
                            y: midY - currentHeight / 2,
                            width: currentWidth,
                            height: currentHeight
                        )
                        let path = Path(roundedRect: rect, cornerRadius: currentWidth / 2)
                        context.fill(path, with: .color(isPlayed ? playedColor : unplayedColor))
                    }
                }
                .allowsHitTesting(false)
                
                // Seek only via the blue time indicator (expanded hit target for usability).
                Circle()
                    .fill(scrubberColor)
                    .frame(width: scrubberSize, height: scrubberSize)
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 0.5)
                    .frame(width: scrubberHitSize, height: scrubberHitSize)
                    .contentShape(Rectangle())
                    .position(x: scrubberX, y: centerY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard width > 0, let onSeek else { return }
                                if dragStartProgress == nil {
                                    dragStartProgress = progress
                                }
                                let delta = Double(value.translation.width / width)
                                onSeek(min(max((dragStartProgress ?? progress) + delta, 0), 1))
                            }
                            .onEnded { _ in
                                dragStartProgress = nil
                            }
                    )
            }
            .frame(width: width, height: height)
            .animation(nil, value: progress)
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        // Compact WhatsApp-style bars, vertically centered in the wave area.
        let pattern: [CGFloat] = [
            6, 10, 14, 8, 16, 9, 12, 7, 15, 10,
            11, 8, 17, 10, 13, 7, 15, 9, 12, 7,
            14, 10, 11, 8, 16, 9, 12, 7, 15, 10,
            11, 7, 14, 9, 16, 8, 12, 7, 13, 9
        ]
        return pattern[index % pattern.count]
    }
    
    private func barWidth(for index: Int) -> CGFloat {
        index % 4 == 0 ? 2.5 : 2
    }
}

struct ChatImageBubbleContent: View {
    let remoteURL: URL?
    let localImage: UIImage?
    let isUploading: Bool
    
    var body: some View {
        ZStack {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 150, maxHeight: 150)
                    .cornerRadius(10)
            } else if let remoteURL {
                // Cache + retries (AsyncImage was failing intermittently in chat).
                ChatCachedImage(url: remoteURL)
            } else {
                ProgressView()
                    .frame(width: 150, height: 150)
            }
            
            if isUploading {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.35))
                    .frame(maxWidth: 150, maxHeight: 150)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.15)
                    .padding(14)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
        }
        .frame(maxWidth: 150, maxHeight: 150)
        .onAppear {
            // Warm the cache even when a local preview is shown (e.g. just-sent image).
            if let remoteURL, localImage != nil {
                ImageCacheService.shared.prefetch(remoteURL)
            }
        }
    }
}

/// Keeps chat header label fully opaque while pressed (default styles fade it).
private struct ChatHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Centered pill used to separate messages by calendar day.
private struct ChatDateSeparator: View {
    let title: String
    
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(SpectRoomTheme.card.opacity(0.82))
                )
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// WhatsApp-style chat bubble with a small nozzle on the bottom corner.
private struct ChatBubbleShape: Shape {
    var isOutgoing: Bool
    var cornerRadius: CGFloat = 14
    
    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let tail: CGFloat = 6
        var path = Path()
        
        if isOutgoing {
            // Top edge
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX - r - tail, y: 0))
            // Top-right corner
            path.addArc(
                center: CGPoint(x: rect.maxX - r - tail, y: r),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            // Right edge down to near the tail
            path.addLine(to: CGPoint(x: rect.maxX - tail, y: rect.maxY - r))
            // Bottom-right corner into the nozzle
            path.addArc(
                center: CGPoint(x: rect.maxX - r - tail, y: rect.maxY - r),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(35),
                clockwise: false
            )
            // Nozzle tip
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tail * 0.2, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - tail - 8, y: rect.maxY),
                control: CGPoint(x: rect.maxX - 1, y: rect.maxY)
            )
            // Bottom edge
            path.addLine(to: CGPoint(x: r, y: rect.maxY))
            // Bottom-left corner
            path.addArc(
                center: CGPoint(x: r, y: rect.maxY - r),
                radius: r,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            // Left edge
            path.addLine(to: CGPoint(x: 0, y: r))
            // Top-left corner
            path.addArc(
                center: CGPoint(x: r, y: r),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            // Top edge (incoming - nozzle on bottom-left)
            path.move(to: CGPoint(x: r + tail, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
            // Top-right
            path.addArc(
                center: CGPoint(x: rect.maxX - r, y: r),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            // Right edge
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            // Bottom-right
            path.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            // Bottom edge to nozzle
            path.addLine(to: CGPoint(x: tail + 8, y: rect.maxY))
            // Nozzle tip
            path.addQuadCurve(
                to: CGPoint(x: 0, y: rect.maxY),
                control: CGPoint(x: 1, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: tail, y: rect.maxY - r + 4),
                control: CGPoint(x: tail * 0.2, y: rect.maxY)
            )
            // Left edge up
            path.addLine(to: CGPoint(x: tail, y: r))
            // Top-left
            path.addArc(
                center: CGPoint(x: r + tail, y: r),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        
        path.closeSubpath()
        return path
    }
}

struct MessageBubble: View {
    let message: MessageDisplay
    let conversationMessages: [MessageDisplay]
    var isLongMessageExpanded: Bool = false
    var onExpandLongMessage: (() -> Void)? = nil
    @Binding var showingConversationPhotoViewer: Bool
    @Binding var selectedPhotoIndex: Int
    var localImagePreview: UIImage? = nil
    var isImageUploading: Bool = false
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false
    
    private let outgoingBubbleColor = Color(red: 0.851, green: 0.992, blue: 0.827) // WhatsApp-style green (#D9FDD3)
    private let incomingBubbleColor = Color.white
    private let bubbleTextColor = Color.black
    private let voiceAccentColor = Color(red: 0.07, green: 0.55, blue: 0.47)
    private let longMessageCollapseLimit = 300
    private let readMoreColor = Color(red: 0.07, green: 0.55, blue: 0.47)
    
    private var isOutgoing: Bool {
        message.senderName == "You"
    }
    
    private var bubbleColor: Color {
        isOutgoing ? outgoingBubbleColor : incomingBubbleColor
    }
    
    private var bubbleTimeText: String {
        message.createdAt.formattedBubbleTime()
    }
    
    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(isOutgoing: isOutgoing)
    }
    
    private var isLongMessage: Bool {
        message.content.count > longMessageCollapseLimit
    }
    
    private var displayedText: String {
        guard isLongMessage, !isLongMessageExpanded else {
            return message.content
        }
        return String(message.content.prefix(longMessageCollapseLimit))
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isOutgoing {
                Spacer(minLength: 48)
                bubbleContent
            } else {
                bubbleContent
                Spacer(minLength: 48)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var bubbleContent: some View {
        switch message.messageType {
        case .image:
            Button(action: {
                guard !isImageUploading, !message.content.hasPrefix("pending://") else { return }
                let imageMessages = conversationMessages.filter { $0.messageType == .image && !$0.content.hasPrefix("pending://") }
                if let index = imageMessages.firstIndex(where: { $0.id == message.id }) {
                    selectedPhotoIndex = index
                    showingConversationPhotoViewer = true
                }
            }) {
                ZStack(alignment: .bottomTrailing) {
                    ChatImageBubbleContent(
                        remoteURL: message.content.hasPrefix("pending://") ? nil : URL(string: message.content),
                        localImage: localImagePreview,
                        isUploading: isImageUploading
                    )
                    
                    Text(bubbleTimeText)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(3)
                .padding(.leading, isOutgoing ? 0 : 7)
                .padding(.trailing, isOutgoing ? 7 : 0)
                .background(bubbleColor, in: bubbleShape)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isOutgoing && (isImageUploading || message.content.hasPrefix("pending://")))
            
        case .voice:
            VoiceMessagePlayerView(
                audioURL: URL(string: message.content),
                displayDuration: message.voiceDuration,
                accentColor: voiceAccentColor,
                textColor: bubbleTextColor,
                baseColor: bubbleColor,
                waveColor: Color.gray.opacity(0.45),
                timestampText: bubbleTimeText,
                isOutgoing: isOutgoing
            )
            
        default:
            VStack(alignment: .trailing, spacing: 2) {
                Text(displayedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .foregroundColor(bubbleTextColor)
                    .multilineTextAlignment(.leading)
                
                HStack(alignment: .bottom, spacing: 8) {
                    if isLongMessage && !isLongMessageExpanded {
                        Button {
                            onExpandLongMessage?()
                        } label: {
                            Text("messages.read.more".localized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(readMoreColor)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer(minLength: 8)
                    }
                    
                    Text(bubbleTimeText)
                        .font(.caption2)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.leading, isOutgoing ? 0 : 7)
            .padding(.trailing, isOutgoing ? 7 : 0)
            .background(bubbleColor, in: bubbleShape)
        }
    }
}

struct ConversationPhotoViewerModal: View {
    let photos: [String]
    @Binding var selectedIndex: Int
    let conversationMessages: [MessageDisplay]
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset = CGSize.zero
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()
                
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.save".localized) {
                        guard selectedIndex >= 0, selectedIndex < photos.count else {
                            print("❌ Invalid photo index: \(selectedIndex), photos count: \(photos.count)")
                            return
                        }
                        saveImageToPhotoLibrary(imageURL: photos[selectedIndex])
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("messages.image.saved".localized, isPresented: $showingSaveAlert) {
                Button("common.ok".localized) { }
            } message: {
                Text(saveSuccess ? "messages.image.saved.success".localized : "messages.image.saved.failed".localized)
            }
        }
    }
    
    private func saveImageToPhotoLibrary(imageURL: String) {
        guard let url = URL(string: imageURL) else {
            Task { @MainActor in
                saveSuccess = false
                showingSaveAlert = true
            }
            return
        }
        
        Task {
            do {
                // Download image data
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    await MainActor.run {
                        saveSuccess = false
                        showingSaveAlert = true
                        print("❌ Failed to create UIImage from data")
                    }
                    return
                }
                
                // Check current authorization status
                let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                
                // Request authorization if needed
                let status: PHAuthorizationStatus
                if currentStatus == .notDetermined {
                    status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                } else {
                    status = currentStatus
                }
                
                // Check if we have permission
                guard status == .authorized || status == .limited else {
                    await MainActor.run {
                        saveSuccess = false
                        showingSaveAlert = true
                        print("❌ Photo library permission denied or restricted. Status: \(status.rawValue)")
                    }
                    return
                }
                
                // Save image to photo library
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            self.saveSuccess = true
                            self.showingSaveAlert = true
                            print("✅ Image saved successfully")
                        } else {
                            self.saveSuccess = false
                            self.showingSaveAlert = true
                            if let error = error {
                                print("❌ Error saving image: \(error.localizedDescription)")
                            } else {
                                print("❌ Unknown error saving image")
                            }
                        }
                    }
                })
            } catch {
                await MainActor.run {
                    saveSuccess = false
                    showingSaveAlert = true
                    print("❌ Error downloading image: \(error.localizedDescription)")
                }
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

fileprivate func formattedDuration(_ interval: TimeInterval) -> String {
    guard interval.isFinite && !interval.isNaN else { return "0:00" }
    let total = max(Int(interval.rounded()), 0)
    let minutes = total / 60
    let seconds = total % 60
    return String(format: "%d:%02d", minutes, seconds)
}

#Preview {
    MessagesView(selectedTab: .constant(0))
}

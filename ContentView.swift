//
//  ContentView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var selectedTab = 2
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNewMessageModal = false
    @State private var messageRecipient: ProfileCard?
    
    private var isMatchPopupVisible: Bool {
        appState.showingMatchNotification && appState.newMatchProfile != nil
    }
    
    private var matchPopupDimmingOpacity: Double {
        colorScheme == .dark ? 0.55 : 0.45
    }
    
    var body: some View {
        ZStack {
            // Content views based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    MessagesView(selectedTab: $selectedTab)
                case 1:
                    MatchesView(selectedTab: $selectedTab)
                case 2:
                    SearchView(selectedTab: $selectedTab)
                case 3:
                    ProfileEditView(embedsInTabBar: true, selectedTab: $selectedTab)
                case 4:
                    SettingsView()
                default:
                    SearchView(selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom footer menu
        VStack {
                Spacer()
                CustomFooterMenu(selectedTab: $selectedTab)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .ignoresSafeArea(edges: .bottom)
            
            if isMatchPopupVisible {
                Color.black.opacity(matchPopupDimmingOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            appState.setMessagesTabActive(selectedTab == 0)
            openMessagesTabIfNeededFromNotification()
        }
        .onChange(of: appState.shouldOpenConversation) { shouldOpen in
            if shouldOpen {
                openMessagesTabIfNeededFromNotification()
            }
        }
        .onChange(of: appState.conversationToOpenSenderId) { senderId in
            if let senderId, !senderId.isEmpty {
                openMessagesTabIfNeededFromNotification()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isMatchPopupVisible)
        .sheet(isPresented: Binding(
            get: { isMatchPopupVisible },
            set: { if !$0 { appState.dismissMatchNotification() } }
        )) {
            if let matchProfile = appState.newMatchProfile {
                MatchModalView(
                    otherUser: matchProfile,
                    onSendMessage: {
                        appState.dismissMatchNotification()
                        messageRecipient = matchProfile
                        selectedTab = 0 // Navigate to Messages tab
                        showingNewMessageModal = true
                    },
                    onMaybeLater: {
                        appState.dismissMatchNotification()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(24)
            }
        }
        .sheet(isPresented: $showingNewMessageModal) {
            if let recipient = messageRecipient {
                NewMessageModal(profile: recipient, isExistingConversation: false)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showingNewMessageNotification && !appState.newMessageSenderName.isEmpty },
            set: { if !$0 { appState.dismissNewMessageNotification() } }
        )) {
            NewMessageNotificationModal(
                senderName: appState.newMessageSenderName,
                senderProfilePhotoURL: appState.newMessageSenderPhotoURL,
                onOpen: {
                    let senderId = appState.newMessageSenderId
                    appState.dismissNewMessageNotification()
                    selectedTab = 0 // Navigate to Messages tab
                    // Wait for MessagesView to be ready before opening the conversation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        appState.openConversationFromNotification(senderId: senderId)
                        print("💬 Opened conversation from in-app notification for: \(senderId)")
                    }
                },
                onLater: {
                    appState.dismissNewMessageNotification()
                }
            )
            .presentationBackground(.clear)
        }
        .onChange(of: appState.shouldOpenMessageModal) { shouldOpen in
            print("💬 shouldOpenMessageModal changed to: \(shouldOpen)")
            print("💬 newMatchProfile: \(appState.newMatchProfile?.name ?? "nil")")
            
            if shouldOpen && appState.newMatchProfile != nil {
                print("💬 Opening message modal for: \(appState.newMatchProfile?.name ?? "unknown")")
                // Handle the "Send a message" action from the global match notification
                messageRecipient = appState.newMatchProfile
                selectedTab = 0 // Navigate to Messages tab
                showingNewMessageModal = true
                appState.dismissMatchNotification()
            }
        }
    }
    
    private func openMessagesTabIfNeededFromNotification() {
        let shouldOpen = appState.shouldOpenConversation
            || !(appState.conversationToOpenSenderId ?? "").isEmpty
        guard shouldOpen else { return }
        if selectedTab != 0 {
            selectedTab = 0
            print("💬 Switched to Messages tab from notification tap")
        }
    }
}

struct CustomFooterMenu: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayMatchCount: Int {
        appState.cachedMatches.filter { !appState.isHiddenByBlock($0.otherUser.userId) }.count
    }
    
    private var displayUnreadMessageCount: Int {
        max(0, appState.unreadMessageCount)
    }
    
    var body: some View {
        ZStack {
            // Background and other buttons
            HStack(spacing: 0) {
                // Messages button
                Button(action: {
                    selectedTab = 0
                }) {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 20))
                                .foregroundColor(selectedTab == 0 ? .blue : .gray)
                            
                            // Badge for unread messages - positioned on the icon
                            if displayUnreadMessageCount > 0 {
                                UnreadCountBadge(count: displayUnreadMessageCount)
                                    .offset(x: 6, y: -6)
                            }
                        }
                        
                        Text("nav.messages".localized)
                            .font(.system(size: 11))
                            .foregroundColor(selectedTab == 0 ? .blue : .gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
                
                // Matches button
                Button(action: {
                    selectedTab = 1
                }) {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 20))
                                .foregroundColor(selectedTab == 1 ? .blue : .gray)
                            
                            // Badge for total matches - positioned on the icon
                            if displayMatchCount > 0 {
                                UnreadCountBadge(count: displayMatchCount)
                                    .offset(x: 6, y: -6)
                            }
                        }
                        
                        Text("nav.matches".localized)
                            .font(.system(size: 11))
                            .foregroundColor(selectedTab == 1 ? .blue : .gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
                
                // Spacer for Discover button position
                Spacer()
                    .frame(width: 64) // Space for Discover button
                
                // Profile button - tap again while open returns to Home
                Button(action: {
                    selectedTab = selectedTab == 3 ? 2 : 3
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                        Text("nav.profile".localized)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(selectedTab == 3 ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
                
                // Settings button
                Button(action: {
                    selectedTab = 4
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                        Text("nav.settings".localized)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(selectedTab == 4 ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 18)
            .background(SpectRoomTheme.card)
            .cornerRadius(15, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
            
            // Discover button (elevated on top of everything)
            HStack {
                Spacer()
                
                Button(action: {
                    selectedTab = 2
                }) {
                    Image("profileCard")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .foregroundColor(selectedTab == 2 ? .blue : .gray)
                        .floatingCircleButtonStyle(colorScheme: colorScheme)
                }
                .offset(y: -34) // Elevated to extend partially outside menu borders
                
                Spacer()
            }
            .zIndex(1) // Ensure Discover button is on top
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.refreshUnreadMessageCount()
                refreshMatchCount()
            }
        }
        .onReceive(appState.newMessageReceivedPublisher) { _ in
            appState.refreshUnreadMessageCount()
        }
        .onReceive(appState.newMatchReceivedPublisher) { _ in
            refreshMatchCount()
        }
        .onChange(of: selectedTab) { newTab in
            appState.setMessagesTabActive(newTab == 0)
            if newTab == 0 && appState.isAuthenticated {
                appState.refreshUnreadMessageCount()
            }
            if newTab == 1 && appState.isAuthenticated {
                refreshMatchCount()
            }
        }
        .onChange(of: appState.currentlyOpenConversationSenderId) { _ in
            if appState.isAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appState.refreshUnreadMessageCount()
                }
            }
        }
        .onChange(of: appState.showingMatchNotification) { isShowing in
            // When a new match notification appears or is dismissed, refresh match count
            if appState.isAuthenticated {
                let delay: TimeInterval = isShowing ? 0.5 : 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    refreshMatchCount()
                }
            }
        }
    }
    
    private func refreshMatchCount() {
        guard appState.isAuthenticated else { return }
        
        Task {
            do {
                _ = try await appState.getCachedOrFreshMatches()
            } catch {
                print("❌ Error loading match count: \(error)")
            }
        }
    }
}

// Extension for rounded corners on specific sides
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    func floatingCircleButtonStyle(
        colorScheme: ColorScheme,
        size: CGFloat = 60,
        brighterFrame: Bool = false
    ) -> some View {
        let border = brighterFrame
            ? SpectRoomTheme.floatingPillBorder(for: colorScheme)
            : SpectRoomTheme.subtleBorder(for: colorScheme)
        return frame(width: size, height: size)
            .background(SpectRoomTheme.card, in: Circle())
            .overlay(
                Circle()
                    .stroke(border, lineWidth: 1)
            )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ContentView()
}

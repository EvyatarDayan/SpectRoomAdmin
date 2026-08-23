//
//  ContentView.swift
//  SpectRoomAdmin
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

/// Tab indices for the admin app footer.
enum AdminTab: Int {
    case messages = 0
    case admin = 1
    case settings = 2
}

struct ContentView: View {
    @State private var selectedTab = AdminTab.admin.rawValue
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNewMessageModal = false
    @State private var messageRecipient: ProfileCard?
    
    var body: some View {
        ZStack {
            Group {
                switch selectedTab {
                case AdminTab.messages.rawValue:
                    MessagesView(selectedTab: $selectedTab)
                case AdminTab.admin.rawValue:
                    AdminHubView()
                case AdminTab.settings.rawValue:
                    SettingsView()
                default:
                    AdminHubView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack {
                Spacer()
                CustomFooterMenu(selectedTab: $selectedTab)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            appState.setMessagesTabActive(selectedTab == AdminTab.messages.rawValue)
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
                    selectedTab = AdminTab.messages.rawValue
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
            if shouldOpen, let matchProfile = appState.newMatchProfile {
                messageRecipient = matchProfile
                selectedTab = AdminTab.messages.rawValue
                showingNewMessageModal = true
                appState.dismissMatchNotification()
            }
        }
    }
    
    private func openMessagesTabIfNeededFromNotification() {
        let shouldOpen = appState.shouldOpenConversation
            || !(appState.conversationToOpenSenderId ?? "").isEmpty
        guard shouldOpen else { return }
        if selectedTab != AdminTab.messages.rawValue {
            selectedTab = AdminTab.messages.rawValue
            print("💬 Switched to Messages tab from notification tap")
        }
    }
}

struct CustomFooterMenu: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager
    
    private var displayUnreadMessageCount: Int {
        max(0, appState.unreadMessageCount)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                selectedTab = AdminTab.messages.rawValue
            }) {
                VStack(spacing: 3) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                            .foregroundColor(selectedTab == AdminTab.messages.rawValue ? .blue : .gray)
                        
                        if displayUnreadMessageCount > 0 {
                            UnreadCountBadge(count: displayUnreadMessageCount)
                                .offset(x: 6, y: -6)
                        }
                    }
                    
                    Text("nav.messages".localized)
                        .font(.system(size: 11))
                        .foregroundColor(selectedTab == AdminTab.messages.rawValue ? .blue : .gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }

            Button(action: {
                selectedTab = AdminTab.admin.rawValue
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 20))
                    Text("nav.admin".localized)
                        .font(.system(size: 11))
                }
                .foregroundColor(selectedTab == AdminTab.admin.rawValue ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
            
            Button(action: {
                selectedTab = AdminTab.settings.rawValue
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                    Text("nav.settings".localized)
                        .font(.system(size: 11))
                }
                .foregroundColor(selectedTab == AdminTab.settings.rawValue ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 18)
        .background(SpectRoomTheme.card)
        .cornerRadius(15, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.refreshUnreadMessageCount()
            }
        }
        .onReceive(appState.newMessageReceivedPublisher) { _ in
            appState.refreshUnreadMessageCount()
        }
        .onChange(of: selectedTab) { newTab in
            appState.setMessagesTabActive(newTab == AdminTab.messages.rawValue)
            if newTab == AdminTab.messages.rawValue && appState.isAuthenticated {
                appState.refreshUnreadMessageCount()
            }
        }
        .onChange(of: appState.currentlyOpenConversationSenderId) { _ in
            if appState.isAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appState.refreshUnreadMessageCount()
                }
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
        .environmentObject(AppStateManager.shared)
}

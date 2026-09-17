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
    case support = 0
    case profiles = 1
    case dashboard = 2
    case admin = 3
    case settings = 4
}

struct ContentView: View {
    @State private var selectedTab = AdminTab.dashboard.rawValue
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Group {
                switch selectedTab {
                case AdminTab.dashboard.rawValue:
                    AdminDashboardView()
                case AdminTab.profiles.rawValue:
                    AdminAllProfilesView(showsDismissButton: false)
                case AdminTab.support.rawValue:
                    AdminSupportView(showsDismissButton: false)
                case AdminTab.admin.rawValue:
                    AdminHubView()
                case AdminTab.settings.rawValue:
                    SettingsView()
                default:
                    AdminDashboardView()
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
            appState.setMessagesTabActive(false)
            applyRequestedAdminTabIfNeeded()
        }
        .onChange(of: selectedTab) { _ in
            appState.setMessagesTabActive(false)
        }
        .onChange(of: appState.requestedAdminTab) { _ in
            applyRequestedAdminTabIfNeeded()
        }
        .sheet(isPresented: Binding(
            get: { appState.showingNewMessageNotification && !appState.newMessageSenderName.isEmpty },
            set: { if !$0 { appState.dismissNewMessageNotification() } }
        )) {
            NewMessageNotificationModal(
                senderName: appState.newMessageSenderName,
                senderProfilePhotoURL: appState.newMessageSenderPhotoURL,
                onOpen: {
                    appState.dismissNewMessageNotification()
                },
                onLater: {
                    appState.dismissNewMessageNotification()
                }
            )
            .presentationBackground(.clear)
        }
    }

    private func applyRequestedAdminTabIfNeeded() {
        guard let tab = appState.requestedAdminTab else { return }
        selectedTab = tab
        appState.requestedAdminTab = nil
    }
}

struct CustomFooterMenu: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                selectedTab = AdminTab.support.rawValue
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 20))
                    Text("nav.support".localized)
                        .font(.system(size: 11))
                }
                .foregroundColor(selectedTab == AdminTab.support.rawValue ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }

            Button(action: {
                selectedTab = AdminTab.profiles.rawValue
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20))
                    Text("nav.profiles".localized)
                        .font(.system(size: 11))
                }
                .foregroundColor(selectedTab == AdminTab.profiles.rawValue ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }

            Button(action: {
                selectedTab = AdminTab.dashboard.rawValue
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20))
                    Text("nav.dashboard".localized)
                        .font(.system(size: 11))
                }
                .foregroundColor(selectedTab == AdminTab.dashboard.rawValue ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            }

            Button(action: {
                selectedTab = AdminTab.admin.rawValue
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 20))
                        .overlay(alignment: .topTrailing) {
                            UnreadCountBadge(count: appState.unseenAdminReportCount)
                                .offset(x: 10, y: -8)
                        }
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

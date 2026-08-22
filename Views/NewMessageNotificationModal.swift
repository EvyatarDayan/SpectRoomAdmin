//
//  NewMessageNotificationModal.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI

struct NewMessageNotificationModal: View {
    let senderName: String
    let senderProfilePhotoURL: String?
    let onOpen: () -> Void
    let onLater: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let modalBackgroundColor = SpectRoomTheme.card
        
        return ZStack {
            // Background overlay (existing, for tap gesture)
            Color.blue.opacity(0.1)
                .ignoresSafeArea()
                .onTapGesture { onLater() }

            // Modal content (compact)
            VStack(spacing: 20) {
                // Profile photo
                CachedAsyncImage(url: URL(string: senderProfilePhotoURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                )
                
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("New Message")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? Color.gray : Color.black)
                    
                    Text("from \(senderName)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    // Open message button (blue)
                    Button(action: {
                        onOpen()
                    }) {
                        Text("Open Message")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                    }
                    .padding(.horizontal, 20)
                    
                    // Later button (gray, same size)
                    Button(action: {
                        onLater()
                    }) {
                        Text("Later")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray)
                            )
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: 280)
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(modalBackgroundColor)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 16)
        }
        .ignoresSafeArea(.all, edges: .all)
    }
}

#Preview {
    NewMessageNotificationModal(
        senderName: "Sarah",
        senderProfilePhotoURL: nil,
        onOpen: {},
        onLater: {}
    )
}


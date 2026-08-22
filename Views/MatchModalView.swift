//
//  MatchModalView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI

struct MatchModalView: View {
    let otherUser: ProfileCard
    let onSendMessage: () -> Void
    let onMaybeLater: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showConfetti = false
    
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    var body: some View {
        let modalBackgroundColor = SpectRoomTheme.card
        
        VStack(spacing: 20) {
            // User photos section
            HStack(spacing: -20) {
                CachedAsyncImage(url: URL(string: FirebaseAuthService.shared.currentUser?.profilePhotoURL ?? "")) { image in
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
                .rotationEffect(.degrees(-8))
                .overlay(
                    VStack {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundColor(.pink)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                )
                
                CachedAsyncImage(url: URL(string: otherUser.imageURL ?? "")) { image in
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
                .rotationEffect(.degrees(8))
                .overlay(
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(8)
                )
            }
            .padding(.horizontal, 40)
            .confettiBurstAnchor()
            
            VStack(spacing: 12) {
                let baseColor = colorScheme == .dark ? Color.gray : Color.black
                let titlePrefix = "match.modal.title.prefix".localized
                let titleHighlight = "match.modal.title.highlight".localized
                (
                    Text(titlePrefix + " ")
                        .foregroundColor(baseColor)
                    + Text(titleHighlight)
                        .foregroundColor(.pink)
                )
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                        .offset(x: 12, y: -10)
                    , alignment: .trailing
                )

                (Text("match.modal.description.prefix".localized)
                 + Text(firstName(from: otherUser.name)).fontWeight(.bold)
                 + Text("match.modal.description.suffix".localized))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    onSendMessage()
                }) {
                    Text("match.modal.send.message".localized)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green)
                        )
                }
                
                Button(action: {
                    onMaybeLater()
                }) {
                    Text("match.modal.maybe.later".localized)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray4))
                        )
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(modalBackgroundColor)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
        )
        .padding(.horizontal, 12)
        .background(Color.clear)
        .confettiCelebration(isVisible: $showConfetti)
        .onAppear {
            showConfetti = true
        }
    }
}

#Preview {
    MatchModalView(
        otherUser: ProfileCard(
            userId: "preview",
            name: "Sarah",
            age: 25,
            bio: "Love hiking and coffee",
            interests: ["Hiking", "Coffee", "Photography"],
            distance: "2 miles away",
            imageURL: nil,
            gender: "Woman",
            interestedIn: ["Man"],
            lookingFor: ["Relationship"],
            photos: [],
            lifestyle: "independent",
            shareLifestyle: true,
            bodyType: "",
            shareBodyType: false,
            preferredAgeMin: 24,
            preferredAgeMax: 30,
            isOnline: false,
            lastSeen: Date(),
            idealFirstDate: [],
            shareIdealFirstDate: false,
            energyLevel: 4
        ),
        onSendMessage: {},
        onMaybeLater: {}
    )
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .presentationBackground(.clear)
}

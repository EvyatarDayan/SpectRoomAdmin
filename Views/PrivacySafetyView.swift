//
//  PrivacySafetyView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-11-16.
//

import SwiftUI

struct PrivacySafetyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                SpectRoomBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Introduction
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Privacy & Safety")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(SpectRoomTheme.text)
                                .padding(.top, 16)
                            
                            Text("Your privacy, comfort, and safety are our highest priorities. Our app is designed to support neurodivergent individuals in a respectful, secure, and transparent way. The following principles explain how we protect your information and how you can stay safe while using our platform.")
                                .font(.body)
                                .foregroundColor(SpectRoomTheme.text)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Section 1
                        sectionView(
                            title: "1. Your Data, Your Control",
                            content: """
                            • You choose what personal information to share in your profile.
                            
                            • Sensitive information-such as accessibility needs, support levels, health-related details, or communication preferences-is always optional.
                            
                            • You can edit or remove your information at any time in your profile settings.
                            
                            • You can delete your account at any time, and all associated data will be permanently removed from our servers within a reasonable timeframe.
                            """
                        )
                        
                        // Section 2
                        sectionView(
                            title: "2. How We Use Your Information",
                            content: """
                            We use the information you provide to:
                            
                            • Create your profile
                            • Match you with compatible users
                            • Improve your in-app experience
                            • Maintain a safe, supportive community
                            
                            We never sell your data to third parties.
                            
                            We only share your data with trusted service providers who help us operate the app (e.g., secure servers, analytics). These providers follow strict privacy and security standards.
                            """
                        )
                        
                        // Section 3
                        sectionView(
                            title: "3. Protecting Your Safety",
                            content: """
                            We use several measures to keep you safe, including:
                            
                            • Profile moderation and automated detection of harmful behavior
                            • Reporting tools available on every profile and message
                            • Optional account verification
                            • Internal review of reports and timely action against violations
                            
                            We do not tolerate harassment, discrimination, hate speech, or exploitation of any kind.
                            """
                        )
                        
                        // Section 4
                        sectionView(
                            title: "4. Sensitive Information",
                            content: """
                            Because our community includes neurodivergent users and people with accessibility needs, you may choose to share personal details.
                            
                            If you do, please remember:
                            
                            • Sharing is always voluntary
                            • You control who can view sensitive sections of your profile
                            • Sensitive details are never used for advertising or sold to third parties
                            • Use caution when sharing personal information with others.
                            """
                        )
                        
                        // Section 5
                        sectionView(
                            title: "5. Communication & Boundaries",
                            content: """
                            Always communicate at your own pace and comfort level.
                            
                            We encourage:
                            
                            • Clear communication
                            • Respect for different communication styles
                            • Patience and understanding
                            
                            If someone makes you uncomfortable, you can:
                            
                            • Block the user
                            • Report their profile
                            • Limit who can contact you in your preferences
                            """
                        )
                        
                        // Section 6
                        sectionView(
                            title: "6. Meeting in Person",
                            content: """
                            If you decide to meet someone:
                            
                            • Use a public place
                            • Tell a friend or family member where you're going
                            • Consider using the app's check-in feature (if available)
                            • Trust your instincts-if something feels wrong, leave immediately
                            
                            Your safety always comes first.
                            """
                        )
                        
                        // Section 7
                        sectionView(
                            title: "7. Security Measures",
                            content: """
                            We use industry-standard security technologies to protect your information, including:
                            
                            • Encrypted data transmission
                            • Secure password storage
                            • Fraud detection systems
                            • Continuous security monitoring
                            
                            If a data or security issue is ever detected, we will notify you promptly and transparently.
                            """
                        )
                        
                        // Section 8
                        sectionView(
                            title: "8. Your Responsibility",
                            content: """
                            While we work hard to create a safe environment, you also play an important role.
                            
                            Please:
                            
                            • Keep personal details (address, financial info, work details) private
                            • Be cautious about sharing photos or videos
                            • Report any suspicious or harmful behavior
                            
                            Together, we can maintain a respectful and safe community.
                            """
                        )
                        
                        // Section 9
                        sectionView(
                            title: "9. Contact & Support",
                            content: """
                            If you have any questions about privacy, need to report an issue, or want support:
                            
                            • In-app Support → Help & Safety
                            • Or email us at: spectroom.support@gmail.com
                            
                            We are here to help and respond as quickly as possible.
                            """
                        )
                        
                        Spacer().frame(height: 40)
                            .padding(.bottom, 70)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Privacy & Safety")
                        .font(.system(size: 20, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func sectionView(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SpectRoomTheme.text)
            
            Text(content)
                .font(.body)
                .foregroundColor(SpectRoomTheme.text)
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    PrivacySafetyView()
}


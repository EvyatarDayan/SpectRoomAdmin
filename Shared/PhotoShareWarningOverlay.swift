//
//  PhotoShareWarningOverlay.swift
//  SpectRoom
//

import SwiftUI

struct PhotoShareWarningOverlay: View {
    let onContinue: (_ dontShowAgain: Bool) -> Void
    let onCancel: () -> Void
    
    @State private var dontShowAgain = false
    
    private let bulletKeys = [
        "messages.photo.share.warning.bullet.intimate",
        "messages.photo.share.warning.bullet.address",
        "messages.photo.share.warning.bullet.workplace"
    ]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            
            VStack(alignment: .leading, spacing: 14) {
                Text("messages.photo.share.warning.subtitle".localized)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("messages.photo.share.warning.bullets.intro".localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.leading)
                    
                    ForEach(bulletKeys, id: \.self) { key in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                            Text(key.localized)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: { dontShowAgain.toggle() }) {
                    HStack(spacing: 10) {
                        Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundColor(.white)
                        Text("messages.photo.share.warning.dont.show.again".localized)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                
                Button(action: {
                    onContinue(dontShowAgain)
                }) {
                    Text("messages.photo.share.warning.continue".localized)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding(.horizontal, 28)
        }
    }
    
    static var shouldShowWarning: Bool {
        !UserDefaults.standard.bool(forKey: "dontShowPhotoShareWarning")
    }
    
    static func setDontShowAgain(_ value: Bool) {
        guard value else { return }
        UserDefaults.standard.set(true, forKey: "dontShowPhotoShareWarning")
    }
}

//
//  BlockedUserAlertOverlay.swift
//  SpectRoom
//

import SwiftUI

struct BlockedUserAlertOverlay: View {
    let firstName: String
    let onDismiss: (_ dontShowAgain: Bool) -> Void
    
    @State private var dontShowAgain = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                
                VStack(spacing: 8) {
                    Text(String(format: "messages.blocked.alert.title".localized, firstName))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                    
                    Text("messages.blocked.alert.detail".localized)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Button(action: { dontShowAgain.toggle() }) {
                    HStack(spacing: 10) {
                        Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundColor(.white)
                        Text("messages.blocked.alert.dont.show.again".localized)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: { onDismiss(dontShowAgain) }) {
                    Text("common.ok".localized)
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                }
            }
            .padding(24)
            .background(Color.red)
            .cornerRadius(16)
            .padding(.horizontal, 32)
        }
    }
}

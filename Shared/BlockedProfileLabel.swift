//
//  BlockedProfileLabel.swift
//  SpectRoom
//

import SwiftUI

struct BlockedProfileLabel: View {
    var dimmed: Bool = true
    var slanted: Bool = true
    
    private var labelColor: Color {
        dimmed ? Color.red.opacity(0.7) : .red
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(labelColor)
                .frame(width: 120, height: 1.5)
            
            blockedText
            
            Rectangle()
                .fill(labelColor)
                .frame(width: 120, height: 1.5)
        }
        .rotationEffect(.degrees(slanted ? -12 : 0))
    }
    
    @ViewBuilder
    private var blockedText: some View {
        if slanted {
            Text("messages.conversation.blocked".localized)
                .font(.headline)
                .fontWeight(.bold)
                .italic()
                .foregroundColor(labelColor)
        } else {
            Text("messages.conversation.blocked".localized)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(labelColor)
        }
    }
}

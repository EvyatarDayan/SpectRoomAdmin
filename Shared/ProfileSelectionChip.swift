//
//  ProfileSelectionChip.swift
//  SpectRoom
//
//  Shared selectable chip for interests and preference options in Edit Profile.
//

import SwiftUI

struct ProfileSelectionChip: View {
    let title: String
    let isSelected: Bool
    var showsCheckmark: Bool = true
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if showsCheckmark {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .blue : .secondary.opacity(0.45))
                }
                
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.12) : SpectRoomTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.blue.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

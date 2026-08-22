//
//  EnergyLevelSlider.swift
//  SpectRoom
//
//  Discrete 5-step energy slider. Thumb and step dots share the same X math.
//  Only the thumb is interactive — the track does not steal scroll gestures.
//

import SwiftUI

struct EnergyLevelSlider: View {
    @Binding var energyLevel: Int
    let levelColor: Color
    var isEnabled: Bool = true
    
    private let thumbSize: CGFloat = 28
    private let thumbHitSlop: CGFloat = 12
    private let trackHeight: CGFloat = 10
    private let maxLevel = 4
    private let coordinateSpaceName = "energyLevelSlider"
    
    var body: some View {
        GeometryReader { geometry in
            let inset = thumbSize / 2
            let usableWidth = max(geometry.size.width - thumbSize, 1)
            let midY = geometry.size.height / 2
            let thumbX = xPosition(for: energyLevel, inset: inset, usableWidth: usableWidth)
            
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: usableWidth, height: trackHeight)
                    .position(x: geometry.size.width / 2, y: midY)
                    .allowsHitTesting(false)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [levelColor.opacity(0.45), levelColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumbX - inset, trackHeight), height: trackHeight)
                    .position(x: inset + max(thumbX - inset, trackHeight) / 2, y: midY)
                    .allowsHitTesting(false)
                
                ForEach(0...maxLevel, id: \.self) { level in
                    Circle()
                        .fill(level <= energyLevel ? Color.white : Color.primary.opacity(0.22))
                        .frame(width: 8, height: 8)
                        .shadow(
                            color: level <= energyLevel ? levelColor.opacity(0.35) : .clear,
                            radius: 2, x: 0, y: 1
                        )
                        .position(
                            x: xPosition(for: level, inset: inset, usableWidth: usableWidth),
                            y: midY
                        )
                        .allowsHitTesting(false)
                }
                
                // Interactive thumb only — drag here to change level.
                Circle()
                    .fill(SpectRoomTheme.card)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().strokeBorder(levelColor, lineWidth: 3))
                    .overlay(
                        Circle()
                            .fill(levelColor)
                            .frame(width: 11, height: 11)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 2)
                    .frame(
                        width: thumbSize + thumbHitSlop * 2,
                        height: thumbSize + thumbHitSlop * 2
                    )
                    .contentShape(Circle())
                    .position(x: thumbX, y: midY)
                    .gesture(
                        DragGesture(
                            minimumDistance: 0,
                            coordinateSpace: .named(coordinateSpaceName)
                        )
                        .onChanged { value in
                            guard isEnabled else { return }
                            let level = level(for: value.location.x, inset: inset, usableWidth: usableWidth)
                            if level != energyLevel {
                                energyLevel = level
                            }
                        }
                    )
                    .allowsHitTesting(isEnabled)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: coordinateSpaceName)
        }
        .animation(
            isEnabled ? .interactiveSpring(response: 0.28, dampingFraction: 0.86) : .default,
            value: energyLevel
        )
    }
    
    private func xPosition(for level: Int, inset: CGFloat, usableWidth: CGFloat) -> CGFloat {
        inset + CGFloat(level) / CGFloat(maxLevel) * usableWidth
    }
    
    private func level(for locationX: CGFloat, inset: CGFloat, usableWidth: CGFloat) -> Int {
        let relative = (locationX - inset) / usableWidth
        return max(0, min(maxLevel, Int((relative * CGFloat(maxLevel)).rounded())))
    }
}

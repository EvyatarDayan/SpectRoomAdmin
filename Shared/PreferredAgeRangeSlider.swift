//
//  PreferredAgeRangeSlider.swift
//  SpectRoom
//
//  Dual-thumb age range slider styled like EnergyLevelSlider.
//  Only the thumbs are interactive — the track does not steal scroll gestures.
//

import SwiftUI

struct PreferredAgeRangeSlider: View {
    @Binding var minAge: Double
    @Binding var maxAge: Double
    let absoluteMin: Double
    let absoluteMax: Double
    var accentColor: Color = .blue
    var onChangeMin: (Double) -> Void
    var onChangeMax: (Double) -> Void
    
    private let thumbSize: CGFloat = 28
    private let thumbHitSlop: CGFloat = 12
    private let trackHeight: CGFloat = 10
    private let coordinateSpaceName = "preferredAgeRangeSlider"
    
    var body: some View {
        GeometryReader { geometry in
            let inset = thumbSize / 2
            let usableWidth = max(geometry.size.width - thumbSize, 1)
            let midY = geometry.size.height / 2
            let minX = xPosition(for: minAge, inset: inset, usableWidth: usableWidth)
            let maxX = xPosition(for: maxAge, inset: inset, usableWidth: usableWidth)
            let fillWidth = max(maxX - minX, trackHeight)
            
            ZStack {
                // Background track
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: usableWidth, height: trackHeight)
                    .position(x: geometry.size.width / 2, y: midY)
                    .allowsHitTesting(false)
                
                // Active fill between thumbs
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.45), accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: trackHeight)
                    .position(x: minX + fillWidth / 2, y: midY)
                    .allowsHitTesting(false)
                
                thumbView(
                    at: minX,
                    midY: midY,
                    inset: inset,
                    usableWidth: usableWidth,
                    onDrag: onChangeMin
                )
                .zIndex(1)
                
                thumbView(
                    at: maxX,
                    midY: midY,
                    inset: inset,
                    usableWidth: usableWidth,
                    onDrag: onChangeMax
                )
                .zIndex(2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: coordinateSpaceName)
        }
    }
    
    private func thumbView(
        at x: CGFloat,
        midY: CGFloat,
        inset: CGFloat,
        usableWidth: CGFloat,
        onDrag: @escaping (Double) -> Void
    ) -> some View {
        Circle()
            .fill(SpectRoomTheme.card)
            .frame(width: thumbSize, height: thumbSize)
            .overlay(Circle().strokeBorder(accentColor, lineWidth: 3))
            .overlay(
                Circle()
                    .fill(accentColor)
                    .frame(width: 11, height: 11)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 2)
            .frame(
                width: thumbSize + thumbHitSlop * 2,
                height: thumbSize + thumbHitSlop * 2
            )
            .contentShape(Circle())
            .position(x: x, y: midY)
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(coordinateSpaceName)
                )
                .onChanged { value in
                    onDrag(age(for: value.location.x, inset: inset, usableWidth: usableWidth))
                }
            )
    }
    
    private func xPosition(for age: Double, inset: CGFloat, usableWidth: CGFloat) -> CGFloat {
        let progress = (age - absoluteMin) / max(absoluteMax - absoluteMin, 1)
        return inset + CGFloat(progress) * usableWidth
    }
    
    private func age(for locationX: CGFloat, inset: CGFloat, usableWidth: CGFloat) -> Double {
        let relative = (locationX - inset) / usableWidth
        let raw = absoluteMin + Double(relative) * (absoluteMax - absoluteMin)
        return raw.rounded()
    }
}

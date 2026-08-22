//
//  ConfettiAnimation.swift
//  SpectRoom
//

import SwiftUI

struct StarShape: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.4

        var path = Path()
        let angleStep = .pi * 2 / Double(points * 2)

        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = Double(index) * angleStep - .pi / 2
            let x = center.x + CGFloat(cos(angle)) * radius
            let y = center.y + CGFloat(sin(angle)) * radius

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        return path
    }
}

private var isIPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone
}

struct ShinyStarParticle: View {
    let color: Color
    let angle: Double
    let scale: CGFloat

    var body: some View {
        ZStack {
            StarShape(points: 5)
                .fill(color)

            StarShape(points: 5)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: isIPhone ? 15 : 25, height: isIPhone ? 15 : 25)
        .rotationEffect(.degrees(angle))
        .scaleEffect(scale)
    }
}

private struct ConfettiParticle {
    let id: Int
    var position: CGPoint
    var angle: Double
    var scale: CGFloat
    var opacity: Double
    var color: Color
    var velocity: CGPoint
    var angularVelocity: Double
}

struct ParticleSystem: View {
    @Binding var isActive: Bool
    let center: CGPoint

    private let colors: [Color] = [
        .init(red: 1, green: 0, blue: 0),
        .init(red: 0, green: 0, blue: 1),
        .init(red: 0, green: 1, blue: 0),
        .init(red: 1, green: 1, blue: 0),
        .init(red: 1, green: 0, blue: 1),
        .init(red: 0, green: 1, blue: 1),
        .init(red: 1, green: 0.5, blue: 0),
        .init(red: 0.5, green: 0, blue: 1),
    ]

    @State private var particles: [ConfettiParticle] = []
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            ForEach(particles, id: \.id) { particle in
                ShinyStarParticle(
                    color: particle.color,
                    angle: particle.angle,
                    scale: particle.scale
                )
                .position(particle.position)
                .opacity(particle.opacity)
            }
        }
        .onAppear {
            if isActive {
                startConfetti()
            }
        }
        .onChange(of: isActive) { _, isRunning in
            if isRunning {
                startConfetti()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startConfetti() {
        particles = (0..<150).map { id in
            let speed = Double.random(in: 400...800)
            let angle = Double.random(in: 0...360)
            let radians = angle * .pi / 180

            return ConfettiParticle(
                id: id,
                position: center,
                angle: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.3...1.0),
                opacity: 1.0,
                color: colors.randomElement() ?? .yellow,
                velocity: CGPoint(
                    x: cos(radians) * speed,
                    y: -abs(sin(radians) * speed) - 600
                ),
                angularVelocity: Double.random(in: 360...720)
            )
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            withAnimation(.linear(duration: 0.016)) {
                updateParticles()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            timer?.invalidate()
            timer = nil
            isActive = false
            particles = []
        }
    }

    private func updateParticles() {
        particles = particles.map { particle in
            var updated = particle

            updated.position.x += particle.velocity.x * 0.016
            updated.position.y += particle.velocity.y * 0.016
            updated.velocity.y += 1500 * 0.016
            updated.velocity.x *= 0.97
            updated.velocity.y *= 0.97
            updated.angle += abs(particle.angularVelocity) * 0.016
            updated.angularVelocity *= 0.995
            updated.opacity -= 0.006

            return updated
        }
        .filter { $0.opacity > 0 }
    }
}

private struct ConfettiBurstAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>?

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        if let next = nextValue() {
            value = next
        }
    }
}

extension View {
    func confettiBurstAnchor() -> some View {
        anchorPreference(key: ConfettiBurstAnchorKey.self, value: .center) { $0 }
    }
}

struct ConfettiAnimation: View {
    @Binding var isVisible: Bool
    var burstCenter: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ParticleSystem(
                isActive: $isVisible,
                center: burstCenter ?? CGPoint(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )
            )
        }
    }
}

extension View {
    func confettiCelebration(isVisible: Binding<Bool>) -> some View {
        overlay {
            ConfettiCelebrationLayer(isVisible: isVisible)
        }
    }
}

private struct ConfettiCelebrationLayer: View {
    @Binding var isVisible: Bool

    var body: some View {
        Color.clear
            .backgroundPreferenceValue(ConfettiBurstAnchorKey.self) { anchor in
                GeometryReader { geometry in
                    if isVisible {
                        ConfettiAnimation(
                            isVisible: $isVisible,
                            burstCenter: anchor.map { geometry[$0] }
                        )
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

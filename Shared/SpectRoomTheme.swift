import SwiftUI

enum SpectRoomTheme {
    /// Soft Cream (#F7F4EF) / Deep canvas (#121216)
    static let background = Color("AppBackground")
    /// Pure White (#FFFFFF) / Elevated surface (#25252E)
    static let card = Color("AppCard")
    /// Dark Gray (#1C1C1E) / Off-White (#E5E5EA)
    static let text = Color("AppText")
    static let secondaryText = Color("AppSecondaryText")
    
    /// 1px edge definition without glow — ~12% white on dark, soft black on light.
    static func subtleBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }
    
    /// Brighter frame for canvas-floating pills (distance / energy) so they don't blend in dark mode.
    static func floatingPillBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.28)
            : Color.black.opacity(0.10)
    }
}

/// Screen wash that never participates in layout.
struct SpectRoomBackground: View {
    var body: some View {
        SpectRoomTheme.background
            .ignoresSafeArea()
    }
}

extension View {
    /// Apply the app screen wash behind content (safe-area friendly).
    func spectRoomScreenBackground() -> some View {
        background(SpectRoomTheme.background.ignoresSafeArea())
    }
    
    /// Match the navigation bar to the screen wash so header and body read as one surface.
    func spectRoomNavigationChrome(colorScheme: ColorScheme) -> some View {
        self
            .toolbarBackground(SpectRoomTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
    }
}

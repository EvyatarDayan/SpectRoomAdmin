//
//  DiscoverDistanceLimit.swift
//  SpectRoom
//
//  Per-account discover radius: 5 / 10 / 20 / 50 km / unlimited (default 20 km).
//

import Foundation
import SwiftUI

enum DiscoverDistanceOption: Int, CaseIterable, Identifiable {
    case fiveKm = 0
    case tenKm = 1
    case twentyKm = 2
    case fiftyKm = 3
    case unlimited = 4
    
    var id: Int { rawValue }
    
    static let `default`: DiscoverDistanceOption = .twentyKm
    
    /// `nil` means unlimited.
    var maxKilometers: Double? {
        switch self {
        case .fiveKm: return 5
        case .tenKm: return 10
        case .twentyKm: return 20
        case .fiftyKm: return 50
        case .unlimited: return nil
        }
    }
    
    var title: String {
        switch self {
        case .fiveKm:
            return "settings.distance.5km".localized
        case .tenKm:
            return "settings.distance.10km".localized
        case .twentyKm:
            return "settings.distance.20km".localized
        case .fiftyKm:
            return "settings.distance.50km".localized
        case .unlimited:
            return "settings.distance.unlimited".localized
        }
    }
    
    /// Compact label for the Home corner button (e.g. "20km").
    var shortButtonTitle: String {
        switch self {
        case .fiveKm: return "5km"
        case .tenKm: return "10km"
        case .twentyKm: return "20km"
        case .fiftyKm: return "50km"
        case .unlimited: return "∞"
        }
    }
    
    var accentColor: Color {
        Color(red: 0x69 / 255.0, green: 0xc4 / 255.0, blue: 0x40 / 255.0) // same green as Fully Social
    }
}

enum DiscoverDistanceLimit {
    private static let legacyLevelKey = "discoverMaxDistanceLevel"
    private static let legacyPendingRefreshKey = "discoverDistancePendingDeckRefresh"
    
    /// Prefer Firebase uid; fall back to email so the setting is per account.
    private static var accountKey: String? {
        if let uid = FirebaseAuthService.shared.auth.currentUser?.uid, !uid.isEmpty {
            return uid
        }
        if let email = FirebaseAuthService.shared.auth.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !email.isEmpty {
            return email
        }
        return nil
    }
    
    private static func levelStorageKey(for accountKey: String) -> String {
        "discoverMaxDistanceLevel_\(accountKey)"
    }
    
    private static func pendingRefreshStorageKey(for accountKey: String) -> String {
        "discoverDistancePendingDeckRefresh_\(accountKey)"
    }
    
    static var currentOption: DiscoverDistanceOption {
        get {
            guard let accountKey else { return .default }
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: legacyLevelKey)
            if defaults.object(forKey: levelStorageKey(for: accountKey)) == nil {
                return .default
            }
            let raw = defaults.integer(forKey: levelStorageKey(for: accountKey))
            return DiscoverDistanceOption(rawValue: raw) ?? .default
        }
        set {
            guard let accountKey else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: levelStorageKey(for: accountKey))
        }
    }
    
    /// Distance changed while the daily swipe limit was active - apply on next unlock.
    static var hasPendingDeckRefresh: Bool {
        get {
            guard let accountKey else { return false }
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: legacyPendingRefreshKey)
            return defaults.bool(forKey: pendingRefreshStorageKey(for: accountKey))
        }
        set {
            guard let accountKey else { return }
            UserDefaults.standard.set(newValue, forKey: pendingRefreshStorageKey(for: accountKey))
        }
    }
    
    static func resetToDefault() {
        currentOption = .default
        hasPendingDeckRefresh = false
    }
}

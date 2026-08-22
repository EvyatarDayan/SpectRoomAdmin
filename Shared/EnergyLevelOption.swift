import SwiftUI

enum EnergyLevelOption: Int, CaseIterable {
    case lowBattery = 0
    case moderateSocial = 2
    case fullySocialMode = 4
    
    static func resolved(from stored: Int) -> EnergyLevelOption {
        switch stored {
        case ...1:
            return .lowBattery
        case 2, 3:
            return .moderateSocial
        default:
            return .fullySocialMode
        }
    }
    
    var title: String {
        switch self {
        case .lowBattery:
            return "profile.energy.low.battery".localized
        case .moderateSocial:
            return "profile.energy.moderate.social".localized
        case .fullySocialMode:
            return "profile.edit.energy.fully.social".localized
        }
    }
    
    var subtitle: String {
        switch self {
        case .lowBattery:
            return "profile.energy.low.battery.detail".localized
        case .moderateSocial:
            return "profile.energy.moderate.social.detail".localized
        case .fullySocialMode:
            return "profile.energy.fully.social.detail".localized
        }
    }
    
    var emoji: String {
        switch self {
        case .lowBattery:
            return "🌙"
        case .moderateSocial:
            return "⛅"
        case .fullySocialMode:
            return "☀️"
        }
    }
    
    var color: Color {
        switch self {
        case .lowBattery:
            return Color(hex: "#64B5F6")
        case .moderateSocial:
            return Color(hex: "#FFB74D")
        case .fullySocialMode:
            return Color(hex: "#66BB6A")
        }
    }
}

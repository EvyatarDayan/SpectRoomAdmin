import Foundation

enum SensoryPreferenceOption: String, CaseIterable {
    case lowNoiseEnvironments
    case dimSoftLighting
    case activeWalkingDates
    case shortLowPressureMeetups
    case fidgetStimFriendlySpaces
    case predictableSafeFoods
    case scentFreeEnvironments
    case comfortableTemperatureZones
    case visuallyCalmSpaces
    case deepPressureClearTouch

    var title: String {
        switch self {
        case .lowNoiseEnvironments:
            return "profile.sensory.low.noise.title".localized
        case .dimSoftLighting:
            return "profile.sensory.dim.lighting.title".localized
        case .activeWalkingDates:
            return "profile.sensory.active.walking.title".localized
        case .shortLowPressureMeetups:
            return "profile.sensory.short.meetups.title".localized
        case .fidgetStimFriendlySpaces:
            return "profile.sensory.fidget.stim.title".localized
        case .predictableSafeFoods:
            return "profile.sensory.safe.foods.title".localized
        case .scentFreeEnvironments:
            return "profile.sensory.scent.free.title".localized
        case .comfortableTemperatureZones:
            return "profile.sensory.temperature.title".localized
        case .visuallyCalmSpaces:
            return "profile.sensory.visually.calm.title".localized
        case .deepPressureClearTouch:
            return "profile.sensory.clear.touch.title".localized
        }
    }

    var subtitle: String {
        switch self {
        case .lowNoiseEnvironments:
            return "profile.sensory.low.noise.subtitle".localized
        case .dimSoftLighting:
            return "profile.sensory.dim.lighting.subtitle".localized
        case .activeWalkingDates:
            return "profile.sensory.active.walking.subtitle".localized
        case .shortLowPressureMeetups:
            return "profile.sensory.short.meetups.subtitle".localized
        case .fidgetStimFriendlySpaces:
            return "profile.sensory.fidget.stim.subtitle".localized
        case .predictableSafeFoods:
            return "profile.sensory.safe.foods.subtitle".localized
        case .scentFreeEnvironments:
            return "profile.sensory.scent.free.subtitle".localized
        case .comfortableTemperatureZones:
            return "profile.sensory.temperature.subtitle".localized
        case .visuallyCalmSpaces:
            return "profile.sensory.visually.calm.subtitle".localized
        case .deepPressureClearTouch:
            return "profile.sensory.clear.touch.subtitle".localized
        }
    }

    static func formattedTitles(_ rawValues: [String]) -> String {
        rawValues.compactMap { SensoryPreferenceOption(rawValue: $0)?.title }.joined(separator: ", ")
    }
}

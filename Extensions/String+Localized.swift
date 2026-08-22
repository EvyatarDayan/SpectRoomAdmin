//
//  String+Localized.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation

extension String {
    /// Returns a localized version of the string
    /// Respects the user's selected language preference
    var localized: String {
        // Get the selected language code from UserDefaults
        let selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en"
        
        // Get the bundle path for the selected language
        guard let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            // Fallback to default localization
            return NSLocalizedString(self, comment: "")
        }
        
        // Return localized string from the selected language bundle
        return bundle.localizedString(forKey: self, value: nil, table: nil)
    }
    
    /// Returns a localized version of the string with arguments
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}


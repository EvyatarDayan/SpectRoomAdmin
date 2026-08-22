//
//  LanguageSelectionModal.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI

struct Language: Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let flag: String
    
    static let english = Language(id: "en", code: "en", name: "English", flag: "🇺🇸")
    static let spanish = Language(id: "es", code: "es", name: "Spanish", flag: "🇪🇸")
    static let swedish = Language(id: "sv", code: "sv", name: "Swedish", flag: "🇸🇪")
    static let french = Language(id: "fr", code: "fr", name: "French", flag: "🇫🇷")
    static let german = Language(id: "de", code: "de", name: "German", flag: "🇩🇪")
    
    static let allLanguages = [english, spanish, swedish, french, german]
}

struct LanguageSelectionModal: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedLanguage") private var selectedLanguageCode: String = "en"
    @State private var currentSelection: String
    
    init() {
        // Initialize with current selection from AppStorage
        _currentSelection = State(initialValue: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en")
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Language.allLanguages) { language in
                    HStack {
                        Text(language.flag)
                            .font(.title2)
                        
                        Text(language.name)
                            .font(.body)
                            .foregroundColor(SpectRoomTheme.text)
                        
                        Spacer()
                        
                        if currentSelection == language.code {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        currentSelection = language.code
                        selectedLanguageCode = language.code
                        // Update app language immediately
                        updateAppLanguage(to: language.code)
                    }
                }
            }
            .navigationTitle("language.selection.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func updateAppLanguage(to languageCode: String) {
        // Save the selected language
        UserDefaults.standard.set(languageCode, forKey: "selectedLanguage")
        UserDefaults.standard.synchronize()
        
        // Post notification to reload the app with new language
        NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
    }
}

#Preview {
    LanguageSelectionModal()
}


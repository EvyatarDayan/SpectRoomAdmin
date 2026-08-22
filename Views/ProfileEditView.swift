import SwiftUI
import PhotosUI
import MapKit
import Foundation
import UniformTypeIdentifiers
import UIKit

private enum ProfileValidationSection: String, Hashable {
    case profilePhoto
    case photos
    case name
    case age
    case location
    case genderPreferences
    case aboutMe
    case idealFirstDate
    case interests
}

struct ProfileEditView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Parameters
    let isMandatoryCompletion: Bool
    let embedsInTabBar: Bool
    @Binding var selectedTab: Int
    
    init(
        isMandatoryCompletion: Bool = false,
        embedsInTabBar: Bool = false,
        selectedTab: Binding<Int> = .constant(2)
    ) {
        self.isMandatoryCompletion = isMandatoryCompletion
        self.embedsInTabBar = embedsInTabBar
        self._selectedTab = selectedTab
        _showingCompleteProfileWelcome = State(
            initialValue: isMandatoryCompletion && CompleteProfileWelcomeOverlay.shouldShowWelcome
        )
    }
    
    // MARK: - State Variables
    @State private var name: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var location: String = ""
    @State private var locationLatitude: Double? = nil
    @State private var locationLongitude: Double? = nil
    @State private var bio: String = ""
    @State private var existingPhotos: [String] = []
    @State private var newPhotos: [LocalGalleryImage] = []
    @State private var photosToDelete: Set<String> = []
    @State private var selectedInterests: Set<String> = []
    @State private var customInterest: String = ""
    @State private var gender: String = ""
    @State private var customGender: String = ""
    @State private var selectedInterestedIn: Set<String> = []
    @State private var customInterestedIn: String = ""
    @State private var selectedLookingFor: Set<String> = []
    @State private var customLookingFor: String = ""
    @State private var preferredAgeMin: Double = 18
    @State private var preferredAgeMax: Double = 30
    @State private var energyLevel: Int = 4 // Default to "Fully Social Mode" (index 4, locked to 0-4)
    
    private let absoluteAgeMin = 18.0
    private let absoluteAgeMax = 80.0
    private let maxPreferredAgeSpan = 12.0
    
    // MARK: - Suggested Interests
    private let suggestedInterests = [
        "Photography", "Music", "Art", "Reading", "Cooking", "Travel", "Sports", "Gaming",
        "Movies", "Nature", "Technology", "Fitness", "Dancing", "Writing", "Gardening",
        "Animals", "Science", "History", "Languages", "Volunteering"
    ]
    private let lifestyleColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    private enum LifestyleOption: String, CaseIterable {
        case preferNot
        case independent
        case familySupport
        case assistedSetting
        
        var title: String {
            switch self {
            case .preferNot:
                return "profile.edit.lifestyle.prefer.not".localized
            case .independent:
                return "profile.edit.lifestyle.independent".localized
            case .familySupport:
                return "profile.edit.lifestyle.family".localized
            case .assistedSetting:
                return "profile.edit.lifestyle.assisted".localized
            }
        }
    }
    
    private enum BodyTypeOption: String, CaseIterable {
        case preferNot
        case slim
        case average
        case athletic
        case fullBodied
        
        var title: String {
            switch self {
            case .preferNot:
                return "profile.edit.body.type.prefer.not".localized
            case .slim:
                return "profile.edit.body.type.slim".localized
            case .average:
                return "profile.edit.body.type.average".localized
            case .athletic:
                return "profile.edit.body.type.athletic".localized
            case .fullBodied:
                return "profile.edit.body.type.full.bodied".localized
            }
        }
    }
    
    private enum LookingForOption: String, CaseIterable {
        case romanticRelationship = "Romantic relationship"
        case inPersonFriendship = "In-Person Friendship"
        case onlineFriendship = "Online Friendship"
        case hobbyBuddy = "Hobby Buddy"
        case notSureYet = "Not Sure Yet"
        
        var title: String {
            switch self {
            case .romanticRelationship:
                return "profile.edit.looking.romantic.relationship".localized
            case .inPersonFriendship:
                return "profile.edit.looking.in.person.friendship".localized
            case .onlineFriendship:
                return "profile.edit.looking.online.friendship".localized
            case .hobbyBuddy:
                return "profile.edit.looking.hobby.buddy".localized
            case .notSureYet:
                return "profile.edit.looking.not.sure".localized
            }
        }
        
        static func migratedValue(from stored: String) -> String {
            switch stored {
            case "Relationship":
                return LookingForOption.romanticRelationship.rawValue
            case "Friendship":
                return LookingForOption.inPersonFriendship.rawValue
            case "Not sure yet", "Other":
                return LookingForOption.notSureYet.rawValue
            default:
                if LookingForOption(rawValue: stored) != nil {
                    return stored
                }
                return LookingForOption.notSureYet.rawValue
            }
        }
    }
    
    private enum IdealFirstDateOption: String, CaseIterable {
        case relaxingParkWalk
        case cozyCafeMeet
        case museumGalleryStroll
        case cinemaMovieNight
        case friendlyVideoChat
        
        var title: String {
            switch self {
            case .relaxingParkWalk:
                return "profile.edit.ideal.date.relaxing.park.walk".localized
            case .cozyCafeMeet:
                return "profile.edit.ideal.date.cozy.cafe.meet".localized
            case .museumGalleryStroll:
                return "profile.edit.ideal.date.museum.gallery.stroll".localized
            case .cinemaMovieNight:
                return "profile.edit.ideal.date.cinema.movie.night".localized
            case .friendlyVideoChat:
                return "profile.edit.ideal.date.friendly.video.chat".localized
            }
        }
    }

// MARK: - UI State
    @State private var showingImagePicker = false
    @State private var showingGalleryPicker = false
    @State private var isEditingProfilePhoto = false
    @State private var profilePhoto: UIImage? = nil
    @State private var isLoading = false
    @State private var showingSaveErrorAlert = false
    @State private var saveErrorMessage = ""
    @State private var hasAttemptedSave = false
    @State private var scrollToValidationSection: ProfileValidationSection?
    @State private var showingAddressSearch = false
    @State private var selectedLifestyle = LifestyleOption.preferNot.rawValue
    @State private var isDataLoaded = false // Track when profile data is loaded
    @State private var selectedBodyType: String = BodyTypeOption.preferNot.rawValue
    @State private var selectedIdealFirstDate: [String] = []
    @State private var selectedSensoryPreferences: [String] = []
    @State private var sensoryInfoOption: SensoryPreferenceOption? = nil
    @State private var isDatePickerExpanded = false
    @State private var showingCompleteProfileWelcome: Bool
    @State private var isCompletionBarVisible = true
    /// After a 100% save (or opening an already-complete profile), hide the bar until
    /// the user drops below 100% and taps Save again.
    @State private var suppressCompletionBarUntilIncompleteSave = false
    
    private let minGalleryPhotos = 2
    private let maxGalleryPhotos = 5
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            profilePhotoSection
                                .id(ProfileValidationSection.profilePhoto)
                            
                            myPhotosSection
                                .id(ProfileValidationSection.photos)
                            
                            nameSection
                                .id(ProfileValidationSection.name)
                            
                            dateOfBirthSection
                                .id(ProfileValidationSection.age)
                            
                            locationSection
                                .id(ProfileValidationSection.location)
                            
                            genderPreferencesSection
                                .id(ProfileValidationSection.genderPreferences)
                            
                            aboutMeSection
                                .id(ProfileValidationSection.aboutMe)
                            
                            lifestyleSection
                            
                            bodyTypeSection
                            
                            idealFirstDateSection
                                .id(ProfileValidationSection.idealFirstDate)
                            
                            sensoryPreferencesSection
                            
                            myInterestsSection
                                .id(ProfileValidationSection.interests)
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, embedsInTabBar ? 130 : 40)
                    }
                    .safeAreaInset(edge: .top, spacing: isCompletionBarVisible ? 24 : 0) {
                        if isCompletionBarVisible {
                            profileCompletionBar
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: isCompletionBarVisible)
                    .profileEditScrollEdgeChrome()
                    .background(
                        SpectRoomBackground()
                    )
                    .opacity(isDataLoaded ? 1.0 : 0.3)
                    .disabled(!isDataLoaded)
                    
                    if !isDataLoaded {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.blue)
                            Text("profile.edit.loading".localized)
                                .font(.headline)
                                .foregroundColor(SpectRoomTheme.text)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SpectRoomTheme.card.opacity(0.8))
                    }
                }
                .onChange(of: scrollToValidationSection) { _, section in
                    guard let section else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(section, anchor: .top)
                        }
                        scrollToValidationSection = nil
                    }
                }
                .onChange(of: profileCompletionPercentage) { oldValue, newValue in
                    guard isDataLoaded, oldValue != newValue else { return }
                    guard !suppressCompletionBarUntilIncompleteSave else { return }
                    revealCompletionBar()
                }
            }
            .navigationTitle(isMandatoryCompletion ? "profile.edit.complete.title".localized : "profile.edit.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isMandatoryCompletion ? "common.close".localized : "profile.edit.cancel".localized) {
                        closeEdit()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("profile.edit.save".localized) {
                        if isFormValid() {
                            saveProfile()
                        } else {
                            suppressCompletionBarUntilIncompleteSave = false
                            revealCompletionBar()
                            hasAttemptedSave = true
                            scrollToValidationSection = firstMissingValidationSection()
                        }
                    }
                    .disabled(isLoading || !isDataLoaded)
                }
            }
        }
        .onAppear {
            // Show cached profile immediately when available
            let hadCachedUser = appState.currentUser != nil
            if hadCachedUser {
                loadCurrentProfile()
                syncProfileNameFromAccount()
                isDataLoaded = true
                syncCompletionBarVisibilityAfterLoad()
            } else {
                isDataLoaded = false
            }
            
            // Refresh cache from Firebase in the background
            Task {
                await FirebaseAuthService.shared.forceRefreshUserData()
                
                await MainActor.run {
                    // Only block on network when there was no cache to show.
                    // If cache was already applied, keep it on screen and avoid
                    // overwriting any edits the user may have started.
                    if !hadCachedUser {
                        loadCurrentProfile()
                        syncProfileNameFromAccount()
                        isDataLoaded = true
                        syncCompletionBarVisibilityAfterLoad()
                    } else {
                        syncProfileNameFromAccount()
                    }
                }
                
                // Sync photos from Firebase Storage (in background)
                Task {
                    await FirebaseAuthService.shared.syncPhotosFromStorage()
                    
                    // Clean up any orphaned profile photos (in background)
                    if let userID = FirebaseAuthService.shared.auth.currentUser?.uid {
                        await PhotoStorageService.shared.cleanupOrphanedProfilePhotos(
                            for: userID,
                            currentProfilePhotoURL: appState.currentUser?.profilePhotoURL
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $profilePhoto, isEditingProfilePhoto: isEditingProfilePhoto)
        }
        .sheet(isPresented: $showingGalleryPicker) {
            GalleryImagePicker(images: $newPhotos)
        }
        .sheet(isPresented: $showingAddressSearch) {
            AddressSearchView(
                selectedAddress: $location,
                selectedLatitude: $locationLatitude,
                selectedLongitude: $locationLongitude
            )
        }
        .alert("common.error".localized, isPresented: $showingSaveErrorAlert) {
            Button("common.ok".localized) { }
        } message: {
            Text(saveErrorMessage)
        }
        .alert(
            sensoryInfoOption?.title ?? "",
            isPresented: Binding(
                get: { sensoryInfoOption != nil },
                set: { if !$0 { sensoryInfoOption = nil } }
            )
        ) {
            Button("common.got.it".localized) {
                sensoryInfoOption = nil
            }
        } message: {
            Text(sensoryInfoOption?.subtitle ?? "")
        }
        .overlay {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.blue)
                    Text("profile.edit.saving".localized)
                        .font(.headline)
                        .foregroundColor(SpectRoomTheme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SpectRoomTheme.card.opacity(0.8))
            }
        }
        .overlay {
            if showingCompleteProfileWelcome {
                CompleteProfileWelcomeOverlay {
                    CompleteProfileWelcomeOverlay.markWelcomeSeen()
                    showingCompleteProfileWelcome = false
                }
            }
        }
    }
    
    // MARK: - Profile Photo Section
    private var profilePhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.profile.photo".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            ProfileMainPhotoCard(
                imageURL: profilePhoto == nil ? appState.currentUser?.profilePhotoURL : nil,
                localImage: profilePhoto,
                placeholderSystemName: "camera",
                showsCameraBadge: true,
                onTap: {
                    isEditingProfilePhoto = true
                    showingImagePicker = true
                }
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ProfilePhotoStyle.cardCorner, style: .continuous)
                .fill(SpectRoomTheme.card)
        )
        .overlay(validationFrame(isValid: isProfilePhotoValid))
    }
    
    private var displayName: String {
        let resolved = resolvedProfileName(from: appState.currentUser)
        return resolved.isEmpty ? "—" : resolved
    }
    
    private func resolvedProfileName(from user: SpectRoomUser?) -> String {
        let profileName = (user?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !profileName.isEmpty {
            return profileName
        }
        
        let signupName = appState.signUpName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !signupName.isEmpty {
            return signupName
        }
        
        let authName = (FirebaseAuthService.shared.auth.currentUser?.displayName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !authName.isEmpty {
            return authName
        }
        
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func syncProfileNameFromAccount() {
        let resolved = resolvedProfileName(from: appState.currentUser)
        if !resolved.isEmpty {
            name = resolved
        }
    }
    
    private func syncCompletionBarVisibilityAfterLoad() {
        if profileCompletionPercentage == 100 {
            suppressCompletionBarUntilIncompleteSave = true
            isCompletionBarVisible = false
        } else {
            suppressCompletionBarUntilIncompleteSave = false
            isCompletionBarVisible = true
        }
    }
    
    private func revealCompletionBar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isCompletionBarVisible = true
        }
    }
    
    private func hideCompletionBarAfterCompleteSave() {
        suppressCompletionBarUntilIncompleteSave = true
        withAnimation(.easeInOut(duration: 0.25)) {
            isCompletionBarVisible = false
        }
    }
    
    // MARK: - Name Section
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("profile.edit.name".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(displayName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(SpectRoomTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
                )
                .textSelection(.enabled)
            
            Text("profile.edit.email".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.top, 4)
            
            Text(displayEmail)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(SpectRoomTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
                )
                .textSelection(.enabled)
            
            Text("profile.email.privacy.notice".localized)
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .overlay(validationFrame(isValid: isNameValid))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var displayEmail: String {
        let profileEmail = (appState.currentUser?.email ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let authEmail = (FirebaseAuthService.shared.auth.currentUser?.email ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Firestore profile often has an empty email string; Auth still has the real one.
        let email = profileEmail.isEmpty ? authEmail : profileEmail
        return email.isEmpty ? "—" : email
    }
    
    // MARK: - Date of Birth Section
    private var dateOfBirthSection: some View {
        let age = calculateAge(from: dateOfBirth)
        let maxBirthDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
        let minBirthDate = Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
        
        return VStack(alignment: .leading, spacing: 14) {
            Text("profile.edit.date.of.birth".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDatePickerExpanded.toggle()
                }
            } label: {
                ZStack {
                    VStack(spacing: 6) {
                        Text(formattedBirthDate(dateOfBirth))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(SpectRoomTheme.text)
                        
                        Text(String(format: "profile.edit.my.age".localized, "\(age)"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    
                    HStack {
                        Spacer()
                        Image(systemName: isDatePickerExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            
            if isDatePickerExpanded {
                DatePicker(
                    "",
                    selection: $dateOfBirth,
                    in: minBirthDate...maxBirthDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .clipped()
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SpectRoomTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .overlay(validationFrame(isValid: isAgeValid))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .animation(.easeInOut(duration: 0.25), value: isDatePickerExpanded)
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.location".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                Text(location.isEmpty ? "profile.edit.location.placeholder".localized : location)
                    .foregroundColor(SpectRoomTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                Button(action: {
                    showingAddressSearch = true
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
            )
            
            Text("profile.location.privacy.notice".localized)
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .overlay(validationFrame(isValid: isLocationValid))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - About Me Section
    private var aboutMeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.about.me".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: bioTextBinding)
                    .frame(height: 200)
                    .foregroundColor(SpectRoomTheme.text)
                    .scrollContentBackground(.hidden)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
                    )
                
                HStack {
                    Spacer()
                    Text(characterCounterText)
                        .font(.caption)
                        .foregroundColor(bio.count >= 500 ? .red : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .overlay(validationFrame(isValid: isBioValid))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Lifestyle Section
    private var lifestyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.lifestyle.title".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 10) {
                ForEach(LifestyleOption.allCases, id: \.self) { option in
                    ProfileSelectionChip(
                        title: option.title,
                        isSelected: selectedLifestyle == option.rawValue
                    ) {
                        selectedLifestyle = option.rawValue
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Body Type Section
    private var bodyTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.body.type".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 10) {
                ForEach(BodyTypeOption.allCases, id: \.self) { option in
                    ProfileSelectionChip(
                        title: option.title,
                        isSelected: selectedBodyType == option.rawValue
                    ) {
                        selectedBodyType = option.rawValue
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Ideal First Date Section
    private var idealFirstDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.ideal.first.date".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 10) {
                ForEach(IdealFirstDateOption.allCases, id: \.self) { option in
                    ProfileSelectionChip(
                        title: option.title,
                        isSelected: selectedIdealFirstDate.contains(option.rawValue)
                    ) {
                        if selectedIdealFirstDate.contains(option.rawValue) {
                            selectedIdealFirstDate.removeAll { $0 == option.rawValue }
                        } else {
                            selectedIdealFirstDate.append(option.rawValue)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .overlay(validationFrame(isValid: isIdealFirstDateValid))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Sensory Preferences Section
    private var sensoryPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.sensory.preferences".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 10) {
                ForEach(SensoryPreferenceOption.allCases, id: \.self) { option in
                    HStack(spacing: 10) {
                        ProfileSelectionChip(
                            title: option.title,
                            isSelected: selectedSensoryPreferences.contains(option.rawValue)
                        ) {
                            if selectedSensoryPreferences.contains(option.rawValue) {
                                selectedSensoryPreferences.removeAll { $0 == option.rawValue }
                            } else {
                                selectedSensoryPreferences.append(option.rawValue)
                            }
                        }
                        
                        Button {
                            sensoryInfoOption = option
                        } label: {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.subtitle)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Gender & Preferences Section
    private var genderPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("profile.my.preferences".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            // I am section
            VStack(alignment: .leading, spacing: 8) {
                Text("profile.edit.i.am".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ProfileSelectionChip(
                        title: "profile.edit.gender.man".localized,
                        isSelected: gender == "Man"
                    ) {
                        gender = "Man"
                        customGender = ""
                    }
                    
                    ProfileSelectionChip(
                        title: "profile.edit.gender.woman".localized,
                        isSelected: gender == "Woman"
                    ) {
                        gender = "Woman"
                        customGender = ""
                    }
                    
                    ProfileSelectionChip(
                        title: "profile.edit.gender.nonbinary".localized,
                        isSelected: gender == "Non-binary"
                    ) {
                        gender = "Non-binary"
                        customGender = ""
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Interested in section
            VStack(alignment: .leading, spacing: 8) {
                Text("profile.edit.interested.in".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ProfileSelectionChip(
                        title: "profile.edit.gender.man".localized,
                        isSelected: selectedInterestedIn.contains("Man")
                    ) {
                        toggleInterestedIn("Man")
                    }
                    
                    ProfileSelectionChip(
                        title: "profile.edit.gender.woman".localized,
                        isSelected: selectedInterestedIn.contains("Woman")
                    ) {
                        toggleInterestedIn("Woman")
                    }
                    
                    ProfileSelectionChip(
                        title: "profile.edit.gender.nonbinary".localized,
                        isSelected: selectedInterestedIn.contains("Non-binary")
                    ) {
                        toggleInterestedIn("Non-binary")
                    }
                }
                
                // Show selected custom preferences (only for old custom text entries)
                if !selectedInterestedIn.isEmpty {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100))
                    ], spacing: 8) {
                        ForEach(Array(selectedInterestedIn), id: \.self) { preference in
                            if preference != "Man" && preference != "Woman" && preference != "Non-binary" {
                                HStack {
                                    Text(preference)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                    
                                    Button(action: {
                                        selectedInterestedIn.remove(preference)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Looking for section
            VStack(alignment: .leading, spacing: 8) {
                Text("profile.edit.looking.for".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(spacing: 10) {
                    ForEach(LookingForOption.allCases, id: \.self) { option in
                        ProfileSelectionChip(
                            title: option.title,
                            isSelected: selectedLookingFor.contains(option.rawValue)
                        ) {
                            toggleLookingFor(option.rawValue)
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Preferred Age section
            VStack(alignment: .leading, spacing: 14) {
                Text("profile.edit.preferred.age".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Int(preferredAgeMin))–\(Int(preferredAgeMax))")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.45), lineWidth: 1.5)
                    )
                    .multilineTextAlignment(.center)
                
                PreferredAgeRangeSlider(
                    minAge: $preferredAgeMin,
                    maxAge: $preferredAgeMax,
                    absoluteMin: absoluteAgeMin,
                    absoluteMax: absoluteAgeMax,
                    accentColor: .blue,
                    onChangeMin: { updatePreferredAgeMin($0) },
                    onChangeMax: { updatePreferredAgeMax($0) }
                )
                .frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .overlay(validationFrame(isValid: isGenderValid && isInterestedInValid && isLookingForValid))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - My Interests Section
    private var myInterestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.interests".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(suggestedInterests, id: \.self) { interest in
                    ProfileSelectionChip(
                        title: localizedInterest(interest),
                        isSelected: selectedInterests.contains(interest)
                    ) {
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else {
                            selectedInterests.insert(interest)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .overlay(validationFrame(isValid: isInterestsValid))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - My Photos Section
    private var myPhotosSection: some View {
        ProfileGalleryPhotosCard(
            photoURLs: existingPhotos,
            localImages: newPhotos,
            allowsPaging: false,
            onDeleteRemote: { photoURL in
                deletePhoto(photoURL)
            },
                onDeleteLocal: { photoID in
                    removeNewPhoto(id: photoID)
                },
            onAdd: {
                guard remainingGallerySlots > 0 else { return }
                showingGalleryPicker = true
            },
            maxRemoteVisible: maxGalleryPhotos,
            usesWhiteBackground: true,
            footerText: "Min 2 photos, Max 5 photos"
        )
        .overlay(validationFrame(isValid: isPhotosValid))
    }
    
    
    // MARK: - Validation Computed Properties
    private var isProfilePhotoValid: Bool {
        if profilePhoto != nil {
            return true
        }
        
        if let profilePhotoURL = appState.currentUser?.profilePhotoURL?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !profilePhotoURL.isEmpty,
           URL(string: profilePhotoURL) != nil {
            return true
        }
        
        return false
    }
    
    private var isNameValid: Bool {
        let nameComponents = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        return nameComponents.count >= 2 && nameComponents.allSatisfy { !$0.isEmpty }
    }
    
    private var isAgeValid: Bool {
        return calculateAge(from: dateOfBirth) >= 18
    }
    
    private var isLocationValid: Bool {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else { return false }
        
        if let latitude = locationLatitude, let longitude = locationLongitude {
            return SwedenLocation.contains(latitude: latitude, longitude: longitude)
        }
        
        return true
    }
    
    private var isBioValid: Bool {
        return bio.trimmingCharacters(in: .whitespacesAndNewlines).count >= 30
    }
    
    private var isPhotosValid: Bool {
        let galleryCount = existingPhotos.count + newPhotos.count
        return galleryCount >= minGalleryPhotos && galleryCount <= maxGalleryPhotos
    }
    
    private var remainingGallerySlots: Int {
        max(0, maxGalleryPhotos - (existingPhotos.count + newPhotos.count))
    }
    
    private var isInterestsValid: Bool {
        return selectedInterests.count >= 3
    }
    
    private var isGenderValid: Bool {
        return !gender.isEmpty
    }
    
    private var isLookingForValid: Bool {
        return !selectedLookingFor.isEmpty
    }
    
    private var isInterestedInValid: Bool {
        return !selectedInterestedIn.isEmpty
    }
    
    private var isIdealFirstDateValid: Bool {
        return !selectedIdealFirstDate.isEmpty
    }
    
    private var profileCompletionPercentage: Int {
        let checks = [
            isProfilePhotoValid,
            isNameValid,
            isAgeValid,
            isLocationValid,
            isBioValid,
            isPhotosValid,
            isInterestsValid,
            isGenderValid,
            isInterestedInValid,
            isLookingForValid,
            isIdealFirstDateValid
        ]
        let completed = checks.filter { $0 }.count
        return Int((Double(completed) / Double(checks.count)) * 100)
    }
    
    private var profileCompletionBar: some View {
        let progressColor: Color = profileCompletionPercentage == 100 ? .green : .blue
        let barBackground = SpectRoomTheme.card
        
        return VStack(spacing: 0) {
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: profileCompletionPercentage == 100 ? "checkmark.circle.fill" : "chart.bar.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(progressColor)
                    
                    Text(String(format: "profile.edit.completion".localized, profileCompletionPercentage))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(SpectRoomTheme.text)
                    
                    Spacer(minLength: 8)
                    
                    Text("\(profileCompletionPercentage)%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(progressColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(progressColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                        )
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.1))
                        
                        Capsule()
                            .fill(progressColor)
                            .frame(width: geometry.size.width * CGFloat(profileCompletionPercentage) / 100)
                    }
                }
                .frame(height: 10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(barBackground)
            
            Divider()
        }
        .background(barBackground)
    }
    
    private func firstMissingValidationSection() -> ProfileValidationSection? {
        if !isProfilePhotoValid { return .profilePhoto }
        if !isPhotosValid { return .photos }
        if !isNameValid { return .name }
        if !isAgeValid { return .age }
        if !isLocationValid { return .location }
        if !isGenderValid || !isInterestedInValid || !isLookingForValid { return .genderPreferences }
        if !isBioValid { return .aboutMe }
        if !isIdealFirstDateValid { return .idealFirstDate }
        if !isInterestsValid { return .interests }
        return nil
    }
    
    private var isSharingBodyType: Bool {
        selectedBodyType != BodyTypeOption.preferNot.rawValue && !selectedBodyType.isEmpty
    }
    
    private var bodyTypeToSave: String {
        isSharingBodyType ? selectedBodyType : ""
    }
    
    private var isSharingLifestyle: Bool {
        selectedLifestyle != LifestyleOption.preferNot.rawValue && !selectedLifestyle.isEmpty
    }
    
    private var lifestyleToSave: String {
        isSharingLifestyle ? selectedLifestyle : ""
    }
    
    // MARK: - Character Counter Text
    private var characterCounterText: String {
        let currentCount = bio.count
        
        if currentCount < 30 {
            return String(format: "profile.edit.character.counter.min".localized, "\(30 - currentCount)")
        } else if currentCount >= 500 {
            return String(format: "profile.edit.character.counter.max".localized, "500")
        } else {
            return String(format: "profile.edit.character.counter.max".localized, "\(500 - currentCount)")
        }
    }
    
    // MARK: - Bio Text Binding with Character Limit
    private var bioTextBinding: Binding<String> {
        Binding(
            get: { bio },
            set: { newValue in
                if newValue.count <= 500 {
                    bio = newValue
                }
            }
        )
    }
    
    // MARK: - Helper Methods
    private func closeEdit() {
        if isMandatoryCompletion {
            appState.deferInitialProfileCompletion()
        } else if embedsInTabBar {
            selectedTab = 2 // Home / Discover
        } else {
            dismiss()
        }
    }
    
    private func updatePreferredAgeMin(_ proposed: Double) {
        let newMin = max(absoluteAgeMin, min(proposed, absoluteAgeMax))
        
        if preferredAgeMax - newMin > maxPreferredAgeSpan {
            // Dragging min left past the 12-year window - slide max with it
            let newMax = newMin + maxPreferredAgeSpan
            if newMax > absoluteAgeMax {
                preferredAgeMax = absoluteAgeMax
                preferredAgeMin = max(absoluteAgeMin, absoluteAgeMax - maxPreferredAgeSpan)
            } else {
                preferredAgeMin = newMin
                preferredAgeMax = newMax
            }
        } else if newMin > preferredAgeMax {
            preferredAgeMin = preferredAgeMax
        } else {
            preferredAgeMin = newMin
        }
    }
    
    private func updatePreferredAgeMax(_ proposed: Double) {
        let newMax = max(absoluteAgeMin, min(proposed, absoluteAgeMax))
        
        if newMax - preferredAgeMin > maxPreferredAgeSpan {
            // Dragging max right past the 12-year window - slide min with it
            let newMin = newMax - maxPreferredAgeSpan
            if newMin < absoluteAgeMin {
                preferredAgeMin = absoluteAgeMin
                preferredAgeMax = min(absoluteAgeMax, absoluteAgeMin + maxPreferredAgeSpan)
            } else {
                preferredAgeMin = newMin
                preferredAgeMax = newMax
            }
        } else if newMax < preferredAgeMin {
            preferredAgeMax = preferredAgeMin
        } else {
            preferredAgeMax = newMax
        }
    }
    
    private func clampPreferredAgeSpanIfNeeded() {
        preferredAgeMin = max(absoluteAgeMin, min(preferredAgeMin, absoluteAgeMax))
        preferredAgeMax = max(absoluteAgeMin, min(preferredAgeMax, absoluteAgeMax))
        if preferredAgeMin > preferredAgeMax {
            swap(&preferredAgeMin, &preferredAgeMax)
        }
        if preferredAgeMax - preferredAgeMin > maxPreferredAgeSpan {
            preferredAgeMax = min(absoluteAgeMax, preferredAgeMin + maxPreferredAgeSpan)
        }
    }
    
    private func toggleInterestedIn(_ value: String) {
        if selectedInterestedIn.contains(value) {
            selectedInterestedIn.remove(value)
        } else {
            selectedInterestedIn.insert(value)
        }
    }
    
    private func toggleLookingFor(_ value: String) {
        if selectedLookingFor.contains(value) {
            selectedLookingFor.remove(value)
        } else {
            selectedLookingFor.insert(value)
        }
    }
    
    private func loadCurrentProfile() {
        // Clear any local photo cache first
        profilePhoto = nil
        newPhotos = []
        photosToDelete = []
        
        if let user = appState.currentUser {
            name = resolvedProfileName(from: user)
            // Load actual date of birth from database if available, otherwise calculate from age
            if let savedDateOfBirth = user.dateOfBirth {
                dateOfBirth = savedDateOfBirth
            } else {
                // Fallback: Convert age to date of birth (approximate)
                let calendar = Calendar.current
                dateOfBirth = calendar.date(byAdding: .year, value: -user.age, to: Date()) ?? Date()
            }
            location = user.location.displayString
            locationLatitude = user.location.latitude
            locationLongitude = user.location.longitude
            bio = user.bio
            // Handle migration from "preferNot" / empty / not shared
            if !user.shareLifestyle || user.lifestyle == "preferNot" || user.lifestyle.isEmpty {
                selectedLifestyle = LifestyleOption.preferNot.rawValue
            } else {
                selectedLifestyle = user.lifestyle
            }
            if !user.shareBodyType || user.bodyType.isEmpty || user.bodyType == "preferNot" {
                selectedBodyType = BodyTypeOption.preferNot.rawValue
            } else {
                selectedBodyType = user.bodyType
            }
            selectedIdealFirstDate = user.idealFirstDate
            selectedSensoryPreferences = user.sensoryPreferences
            
            print("🔍 ProfileEditView - Loaded lifestyle: \(selectedLifestyle)")
            print("🔍 ProfileEditView - Loaded bodyType: \(selectedBodyType)")
            print("🔍 ProfileEditView - Loaded idealFirstDate: \(selectedIdealFirstDate)")
            print("🔍 ProfileEditView - Loaded sensoryPreferences: \(selectedSensoryPreferences)")
            
            // Load interests from database
            let previousInterests = selectedInterests
            selectedInterests = Set(user.interests)
            
            // Load gender and preferences (handle migration from "Other" to "Non-binary")
            if user.gender == "Man" || user.gender == "Woman" {
                gender = user.gender
                customGender = ""
            } else if user.gender == "Non-binary" {
                gender = "Non-binary"
                customGender = ""
            } else if user.gender == "Other" || !user.gender.isEmpty {
                // Migrate old "Other" or custom gender text to "Non-binary"
                gender = "Non-binary"
                customGender = ""
            } else {
                gender = ""
                customGender = ""
            }
            // Load interested in preferences (handle migration from "Other"/"Anyone")
            var loadedInterestedIn = Set(user.interestedIn)
            customInterestedIn = ""
            
            // Migrate old "Other" values to "Non-binary" (or remove custom text)
            let standardOptions = ["Man", "Woman", "Non-binary"]
            var migratedInterestedIn = Set<String>()
            var hadAnyone = false
            for preference in loadedInterestedIn {
                if preference == "Anyone" {
                    hadAnyone = true
                } else if standardOptions.contains(preference) {
                    migratedInterestedIn.insert(preference)
                } else if preference == "Other" {
                    // Migrate old "Other" to "Non-binary"
                    migratedInterestedIn.insert("Non-binary")
                }
                // Old custom text entries are simply removed (not migrated)
            }
            // "Anyone" is removed from the UI — expand it to all gender options.
            if hadAnyone {
                migratedInterestedIn.formUnion(standardOptions)
            }
            
            selectedInterestedIn = migratedInterestedIn
            
            // Load looking for data (migrate legacy values to the current options)
            customLookingFor = ""
            selectedLookingFor = Set(user.lookingFor.map { LookingForOption.migratedValue(from: $0) })
            
            // Load preferred age range (18–80 absolute, max 12-year span)
            let savedMin = max(Int(absoluteAgeMin), min(user.preferredAgeMin, Int(absoluteAgeMax)))
            let savedMax = max(Int(absoluteAgeMin), min(user.preferredAgeMax, Int(absoluteAgeMax)))
            
            if savedMin <= savedMax {
                preferredAgeMin = Double(savedMin)
                preferredAgeMax = Double(savedMax)
            } else {
                preferredAgeMin = Double(user.age)
                preferredAgeMax = Double(min(user.age + 5, Int(absoluteAgeMax)))
            }
            clampPreferredAgeSpanIfNeeded()
            
            print("🔍 ProfileEditView - Loaded preferred age from user: \(user.preferredAgeMin)-\(user.preferredAgeMax)")
            print("🔍 ProfileEditView - Loaded preferred age (validated): \(Int(preferredAgeMin))-\(Int(preferredAgeMax))")
            
            // Load energy level
            energyLevel = user.energyLevel
            
            // Load photos from app state (app state is source of truth)
            existingPhotos = user.photos
            
            print("🔍 ProfileEditView - loadCurrentProfile() called")
            print("🔍 ProfileEditView - User from DB has \(user.interests.count) interests: \(user.interests)")
            print("🔍 ProfileEditView - Previous selectedInterests: \(previousInterests)")
            print("🔍 ProfileEditView - New selectedInterests: \(selectedInterests)")
            print("🔍 ProfileEditView - About me from DB: '\(user.bio)'")
            print("🔍 ProfileEditView - Bio length: \(user.bio.count) characters")
            print("🔍 ProfileEditView - Date of birth from DB: \(user.dateOfBirth?.description ?? "nil")")
            print("🔍 ProfileEditView - Loaded dateOfBirth: \(dateOfBirth)")
            print("🔍 ProfileEditView - Loaded gender: '\(user.gender)', UI gender: '\(gender)', customGender: '\(customGender)'")
            print("🔍 ProfileEditView - Loaded interestedIn: \(user.interestedIn), UI selectedInterestedIn: \(selectedInterestedIn), customInterestedIn: '\(customInterestedIn)'")
            print("📸 Loaded \(existingPhotos.count) photos from app state")
        } else {
            name = resolvedProfileName(from: nil)
            if !name.isEmpty {
                print("📝 Using sign up name: \(name)")
            }
            dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
            location = ""
            locationLatitude = nil
            locationLongitude = nil
            bio = ""
            gender = ""
            selectedInterestedIn = []
            existingPhotos = []
            selectedLifestyle = LifestyleOption.preferNot.rawValue
        }
    }
    
    private func validationFrame(isValid: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                (hasAttemptedSave && !isValid) ? Color.red : Color.clear,
                lineWidth: 1.5
            )
    }
    
    // MARK: - Validation Functions
    private func isFormValid() -> Bool {
        return isProfilePhotoValid && isNameValid && isAgeValid && isLocationValid && isBioValid && isPhotosValid && isInterestsValid && isGenderValid && isInterestedInValid && isLookingForValid && isIdealFirstDateValid
    }
    
    private func getValidationErrors() -> [String] {
        var errors: [String] = []
        
        if !isProfilePhotoValid {
            errors.append("profile.edit.validation.profile.photo".localized)
        }
        
        if !isNameValid {
            errors.append("profile.edit.validation.full.name".localized)
        }
        
        if !isAgeValid {
            errors.append("profile.edit.validation.age".localized)
        }
        
        if !isLocationValid {
            errors.append("profile.edit.validation.location".localized)
        }
        
        if !isBioValid {
            errors.append("profile.edit.validation.bio".localized)
        }
        
        if !isPhotosValid {
            errors.append("profile.edit.validation.photos".localized)
        }
        
        if !isInterestsValid {
            errors.append("profile.edit.validation.interests".localized)
        }
        
        if !isGenderValid {
            errors.append("profile.edit.validation.gender".localized)
        }
        
        if !isInterestedInValid {
            errors.append("profile.edit.validation.interested.in".localized)
        }
        
        if !isLookingForValid {
            errors.append("profile.edit.validation.looking.for".localized)
        }
        
        if !isIdealFirstDateValid {
            errors.append("profile.edit.validation.ideal.first.date".localized)
        }
        
        return errors
    }
    
    private func getFormattedValidationErrors() -> String {
        let errors = getValidationErrors()
        if errors.count == 1 {
            return errors[0]
        } else {
            return errors.map { "• \($0)" }.joined(separator: "\n")
        }
    }
    
    private func calculateAge(from dateOfBirth: Date) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: now)
        return ageComponents.year ?? 0
    }
    
    private func formattedBirthDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        return formatter.string(from: date)
    }
    
    private func deletePhoto(_ photoURL: String) {
        photosToDelete.insert(photoURL)
        existingPhotos.removeAll { $0 == photoURL }
    }
    
    private func removeNewPhoto(id: UUID) {
        newPhotos.removeAll { $0.id == id }
    }
    
    private func saveProfile() {
        let ageInt = calculateAge(from: dateOfBirth)
        
        isLoading = true
        
        Task {
            await performSave(ageInt: ageInt)
        }
    }
    
    @MainActor
    private func performSave(ageInt: Int) async {
        do {
                syncProfileNameFromAccount()
                
                // Handle photo uploads
                var galleryPhotoURLs: [String] = []
                var newProfilePhotoURL: String? = nil
                
                // Upload profile photo if selected
                if let profilePhoto = profilePhoto {
                    // Delete old profile photo if it exists
                    if let user = appState.currentUser,
                       let existingProfilePhotoURL = user.profilePhotoURL {
                        do {
                            try await PhotoStorageService.shared.deletePhoto(url: existingProfilePhotoURL)
                            print("🗑️ Deleted old profile photo: \(existingProfilePhotoURL)")
                        } catch {
                            print("⚠️ Failed to delete old profile photo (may not exist): \(existingProfilePhotoURL)")
                            // Continue with upload even if deletion fails
                        }
                    }
                    
                    // Upload new profile photo
                    let userID = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                    newProfilePhotoURL = try await PhotoStorageService.shared.uploadProfilePhoto(profilePhoto, for: userID)
                    print("📸 Uploaded new profile photo: \(newProfilePhotoURL ?? "nil")")
                }
                
                // Upload new gallery photos
                if !newPhotos.isEmpty {
                    let userID = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                    let uploadedGalleryPhotos = try await PhotoStorageService.shared.uploadMultipleGalleryPhotos(
                        newPhotos.map(\.image),
                        for: userID
                    )
                    galleryPhotoURLs.append(contentsOf: uploadedGalleryPhotos)
                }
                
                // Delete photos from storage
                for photoURL in photosToDelete {
                    try await PhotoStorageService.shared.deletePhoto(url: photoURL)
                }
                
                // Update user data
                if var user = appState.currentUser {
                    user.name = name
                    user.age = ageInt
                    user.bio = bio
                    user.interests = Array(selectedInterests)
                    // Save gender (directly use selected value, no custom text)
                    user.gender = gender
                    // Save interested in preferences (directly use selected values, no custom text)
                    var finalInterestedIn = Array(selectedInterestedIn)
                    // Remove legacy options no longer offered in the UI
                    finalInterestedIn.removeAll { $0 == "Other" || $0 == "Anyone" }
                    user.interestedIn = finalInterestedIn
                    
                    // Save looking for preferences (directly use selected values, no custom text)
                    var finalLookingFor = Array(selectedLookingFor)
                    // Remove any old "Other" entries if they exist (migration cleanup)
                    finalLookingFor.removeAll { $0 == "Other" }
                    user.lookingFor = finalLookingFor
                    
                    // Update preferred age range
                    user.preferredAgeMin = Int(preferredAgeMin)
                    user.preferredAgeMax = Int(preferredAgeMax)
                    
                    // Keep the latest energy level from Home if it was changed there
                    user.energyLevel = appState.currentUser?.energyLevel ?? energyLevel
                    
                    // Update location with coordinates
                    user.location = Location(
                        displayString: location,
                        city: appState.currentUser?.location.city ?? "",
                        state: appState.currentUser?.location.state ?? "",
                        country: SwedenLocation.countryName,
                        latitude: locationLatitude,
                        longitude: locationLongitude
                    )
                    user.lifestyle = lifestyleToSave
                    user.shareLifestyle = isSharingLifestyle
                    user.bodyType = bodyTypeToSave
                    user.shareBodyType = isSharingBodyType
                    user.idealFirstDate = selectedIdealFirstDate
                    user.shareIdealFirstDate = true
                    user.sensoryPreferences = selectedSensoryPreferences
                    user.shareSensoryPreferences = !selectedSensoryPreferences.isEmpty
                    
                    // Update profile photo URL only if a new one was selected
                    if let newProfilePhotoURL = newProfilePhotoURL {
                        user.profilePhotoURL = newProfilePhotoURL
                    }
                    // If no new profile photo was selected, keep the existing one unchanged
                    
                    // Update gallery photos array
                    user.photos.removeAll { photosToDelete.contains($0) }
                    user.photos.append(contentsOf: galleryPhotoURLs)
                    
                    // Update both AppStateManager and FirebaseAuthService to ensure sync
                    appState.currentUser = user
                    FirebaseAuthService.shared.currentUser = user
                } else {
                    // Create new user
                    // Handle gender for new user (directly use selected value, no custom text)
                    let finalGender = gender
                    
                    // Handle interested in preferences for new user (directly use selected values, no custom text)
                    var finalInterestedIn = Array(selectedInterestedIn)
                    // Remove any old "Other" entries if they exist (migration cleanup)
                    finalInterestedIn.removeAll { $0 == "Other" || $0 == "Anyone" }
                    
                    // Handle looking for for new user (directly use selected values, no custom text)
                    var finalLookingFor = Array(selectedLookingFor)
                    // Remove any old "Other" entries if they exist (migration cleanup)
                    finalLookingFor.removeAll { $0 == "Other" }
                    
                    var newUser = SpectRoomUser(
                        name: name,
                        age: ageInt,
                        email: FirebaseAuthService.shared.auth.currentUser?.email ?? "",
                        bio: bio,
                        interests: Array(selectedInterests),
                        location: Location(
                            displayString: location,
                            country: SwedenLocation.countryName,
                            latitude: locationLatitude,
                            longitude: locationLongitude
                        ),
                        gender: finalGender,
                        interestedIn: finalInterestedIn,
                        lookingFor: finalLookingFor,
                        preferredAgeMin: Int(preferredAgeMin),
                        preferredAgeMax: Int(preferredAgeMax),
                        lifestyle: lifestyleToSave,
                        shareLifestyle: isSharingLifestyle,
                        bodyType: bodyTypeToSave,
                        shareBodyType: isSharingBodyType,
                        idealFirstDate: selectedIdealFirstDate,
                        shareIdealFirstDate: true,
                        sensoryPreferences: selectedSensoryPreferences,
                        shareSensoryPreferences: !selectedSensoryPreferences.isEmpty,
                        energyLevel: appState.currentUser?.energyLevel ?? energyLevel
                    )
                    newUser.profilePhotoURL = newProfilePhotoURL
                    newUser.photos = galleryPhotoURLs
                    // Update both AppStateManager and FirebaseAuthService to ensure sync
                    appState.currentUser = newUser
                    FirebaseAuthService.shared.currentUser = newUser
                }
                
                // Save to Firebase
                let interestsArray = Array(selectedInterests)
                // Handle gender (directly use selected value, no custom text)
                let finalGender = gender
                let finalLifestyleValue = lifestyleToSave
                print("🔍 ProfileEditView - Saving interests to Firebase: \(interestsArray)")
                print("🔍 ProfileEditView - Interests count: \(interestsArray.count)")
                print("🔍 ProfileEditView - Saving gender: \(finalGender)")
                
                // Handle interested in preferences for Firebase (directly use selected values, no custom text)
                var finalInterestedIn = Array(selectedInterestedIn)
                // Remove legacy options no longer offered in the UI
                finalInterestedIn.removeAll { $0 == "Other" || $0 == "Anyone" }
                
                // Handle looking for for Firebase
                var finalLookingFor = Array(selectedLookingFor)
                if selectedLookingFor.contains("Other") && !customLookingFor.isEmpty {
                    // Replace "Other" with custom text
                    finalLookingFor.removeAll { $0 == "Other" }
                    finalLookingFor.append(customLookingFor)
                }
                
                print("🔍 ProfileEditView - Saving preferred age to Firebase: \(Int(preferredAgeMin))-\(Int(preferredAgeMax))")
                
                var userData: Dictionary<String, Any> = [
                    "name": name,
                    "age": ageInt,
                    "dateOfBirth": dateOfBirth.timeIntervalSince1970, // Save actual date of birth
                    "bio": bio,
                    "interests": interestsArray,
                    "gender": finalGender,
                    "interestedIn": finalInterestedIn,
                    "lookingFor": finalLookingFor,
                    "preferredAgeMin": Int(preferredAgeMin),
                    "preferredAgeMax": Int(preferredAgeMax),
                    "lifestyle": finalLifestyleValue,
                    "shareLifestyle": isSharingLifestyle,
                    "bodyType": bodyTypeToSave,
                    "shareBodyType": isSharingBodyType,
                    "idealFirstDate": selectedIdealFirstDate,
                    "shareIdealFirstDate": true,
                    "sensoryPreferences": selectedSensoryPreferences,
                    "shareSensoryPreferences": !selectedSensoryPreferences.isEmpty,
                    "energyLevel": appState.currentUser?.energyLevel ?? energyLevel,
                    "location": [
                        "displayString": location,
                        "city": appState.currentUser?.location.city ?? "",
                        "state": appState.currentUser?.location.state ?? "",
                        "country": SwedenLocation.countryName,
                        "latitude": (locationLatitude ?? NSNull()) as Any,
                        "longitude": (locationLongitude ?? NSNull()) as Any
                    ] as [String: Any],
                    "profilePhotoURL": appState.currentUser?.profilePhotoURL ?? NSNull(),
                    "photos": appState.currentUser?.photos ?? []
                ]
                let profileEmail = (FirebaseAuthService.shared.auth.currentUser?.email ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if !profileEmail.isEmpty {
                    userData["email"] = profileEmail
                }
                
                try await FirebaseAuthService.shared.updateUserData(userData)
                
                appState.saveAppState()
                applyUnlimitedRadiusIfLookingForOnlineFriendship()
                
                // Refresh user data from Firebase to ensure ProfileView shows latest data
                // This will update FirebaseAuthService.currentUser, which will propagate to AppStateManager
                await FirebaseAuthService.shared.forceRefreshUserData()
                
                // Keep AppState in sync on this run loop so Home's first discover load
                // sees location coordinates and preferences (Combine can lag one tick).
                if let refreshed = FirebaseAuthService.shared.currentUser {
                    appState.currentUser = refreshed
                }
                
                isLoading = false
                
                // Clear discover cache before switching to Home so SearchView's first
                // appear is the only load (invalidate-after-complete caused a race).
                appState.invalidateDiscoverDeckAfterProfileUpdate()
                appState.completeInitialProfile()
                hideCompletionBarAfterCompleteSave()
                
                if !isMandatoryCompletion {
                    closeEdit()
                }
                
            } catch {
                isLoading = false
                saveErrorMessage = String(format: "profile.edit.error.updating".localized, error.localizedDescription)
                showingSaveErrorAlert = true
            }
    }
    
    /// Online friendship isn't distance-bound — expand discover radius to unlimited.
    private func applyUnlimitedRadiusIfLookingForOnlineFriendship() {
        guard selectedLookingFor.contains(LookingForOption.onlineFriendship.rawValue) else { return }
        guard DiscoverDistanceLimit.currentOption != .unlimited else { return }
        
        DiscoverDistanceLimit.currentOption = .unlimited
        appState.invalidateDiscoverDeckAfterProfileUpdate()
    }
    
    // MARK: - Helper function to localize interest names
    private func localizedInterest(_ interest: String) -> String {
        let key = "profile.edit.interest.\(interest.lowercased())"
        let localized = key.localized
        // If localization key doesn't exist, return original
        return localized == key ? interest : localized
    }
}

private extension View {
    /// iOS 26 applies a dimming/blur scroll-edge effect under the nav bar.
    /// Hide it so the title area stays a solid color while scrolling.
    @ViewBuilder
    func profileEditScrollEdgeChrome() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

// MARK: - Supporting Views
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var isEditingProfilePhoto: Bool
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct GalleryImagePicker: UIViewControllerRepresentable {
    @Binding var images: [LocalGalleryImage]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        // One photo per open — picker closes as soon as a photo is tapped.
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: GalleryImagePicker
        
        init(_ parent: GalleryImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            let provider = result.itemProvider
            
            // Prefer loading raw image data — loadObject(UIImage.self) often yields blank/unusable images.
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    guard let data, let image = UIImage(data: data) else {
                        print("❌ GalleryImagePicker failed to load image data: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    let normalized = image.normalizedForUpload()
                    DispatchQueue.main.async {
                        self.parent.images.append(LocalGalleryImage(image: normalized))
                    }
                }
                return
            }
            
            provider.loadObject(ofClass: UIImage.self) { object, error in
                guard let image = object as? UIImage else {
                    print("❌ GalleryImagePicker failed to load UIImage: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                let normalized = image.normalizedForUpload()
                DispatchQueue.main.async {
                    self.parent.images.append(LocalGalleryImage(image: normalized))
                }
            }
        }
    }
}

private extension UIImage {
    /// Flatten orientation and materialize bitmap so SwiftUI can render gallery picks reliably.
    func normalizedForUpload() -> UIImage {
        if imageOrientation == .up, cgImage != nil {
            return self
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#Preview {
    ProfileEditView()
        .environmentObject(AppStateManager.shared)
}

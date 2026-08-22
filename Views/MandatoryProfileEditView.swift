//
//  MandatoryProfileEditView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import PhotosUI

struct MandatoryProfileEditView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var bio: String = ""
    @State private var profilePhoto: UIImage?
    @State private var galleryPhotos: [LocalGalleryImage] = []
    @State private var existingPhotos: [String] = []
    @State private var photosToDelete: Set<String> = []
    @State private var showingImagePicker = false
    @State private var showingGalleryPicker = false
    @State private var isEditingProfilePhoto = false
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""


    // MARK: - Validation Properties
    private var isNameValid: Bool {
        let components = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        return components.count >= 2 && components.allSatisfy { !$0.isEmpty }
    }
    
    private var calculatedAge: Int {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: now)
        return ageComponents.year ?? 0
    }

    private var isAgeValid: Bool {
        return calculatedAge >= 18 && calculatedAge <= 100
    }

    private var isBioValid: Bool {
        bio.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
    }


    private var totalValidPhotos: Int {
        let currentPhotos = existingPhotos.filter { !$0.isEmpty && URL(string: $0) != nil }
        return currentPhotos.count + galleryPhotos.count
    }

    private var isPhotosValid: Bool {
        totalValidPhotos >= 2
    }

    private var isProfilePhotoValid: Bool {
        profilePhoto != nil || (!existingPhotos.isEmpty && !photosToDelete.contains(existingPhotos[0]))
    }

    private var isFormComplete: Bool {
        isNameValid && isAgeValid && isBioValid && isPhotosValid && isProfilePhotoValid
    }
    
    
    private var photosCounterText: String {
        let count = totalValidPhotos
        if count == 0 {
            return "(Select 3)"
        } else if count == 1 {
            return "(2 more)"
        } else if count == 2 {
            return "(1 more)"
        } else {
            return ""
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    profilePhotoSection
                    basicInfoSection
                    galleryPhotosSection
                    saveButton
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Sync photos from Firebase Storage and update database
            Task {
                // Sync photos from Firebase Storage first
                await FirebaseAuthService.shared.syncPhotosFromStorage()
                
                // Update database to match current app state
                await FirebaseAuthService.shared.updateDatabaseWithAppState()
                
                await MainActor.run {
                    loadCurrentProfile()
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $profilePhoto, isEditingProfilePhoto: isEditingProfilePhoto)
        }
        .sheet(isPresented: $showingGalleryPicker) {
            GalleryImagePicker(images: $galleryPhotos)
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Profile Update"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .overlay(loadingOverlay)
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            Text("Complete Your Profile")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Please complete your profile to start using SpectRoom")
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var profilePhotoSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Profile Photo")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: isProfilePhotoValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isProfilePhotoValid ? .green : .red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            profilePhotoButton
            
            if !existingPhotos.isEmpty && profilePhoto == nil {
                Button(action: {
                    if !existingPhotos.isEmpty {
                        deleteExistingPhoto(existingPhotos[0])
                    }
                }) {
                    Text("Remove Profile Photo")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var profilePhotoButton: some View {
        Button(action: {
            isEditingProfilePhoto = true
            showingImagePicker = true
        }) {
            ZStack {
                profilePhotoImage
                profilePhotoOverlay
            }
        }
    }
    
    private var profilePhotoImage: some View {
        Group {
            if let profilePhoto = profilePhoto {
                Image(uiImage: profilePhoto)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            } else if !existingPhotos.isEmpty {
                AsyncImage(url: URL(string: existingPhotos[0])) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.title)
                                .foregroundColor(.gray)
                            Text("Add Photo")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
            }
        }
    }
    
    private var profilePhotoOverlay: some View {
        Circle()
            .stroke(Color.blue, lineWidth: 3)
            .frame(width: 120, height: 120)
            .overlay(
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .background(
                        Circle()
                            .fill(SpectRoomTheme.card)
                            .frame(width: 32, height: 32)
                    )
                    .offset(x: 40, y: 40)
            )
    }
    
    private var basicInfoSection: some View {
        VStack(spacing: 16) {
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                nameTextField
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Date of Birth")
                    .font(.subheadline)
                    .fontWeight(.medium)
                dateOfBirthPicker
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("About Me")
                    .font(.subheadline)
                    .fontWeight(.medium)
                bioTextEditor
            }
        }
        .padding(.horizontal)
    }
    
    private var nameTextField: some View {
        TextField("Full Name (First and Last)", text: $name)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .autocapitalization(.words)
            .overlay(
                HStack {
                    Spacer()
                    if !isNameValid && !name.isEmpty {
                        Text("Requires first and last name")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.trailing, 5)
                    }
                }
                , alignment: .trailing
            )
    }
    
    private var dateOfBirthPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                    .labelsHidden()
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Age: \(calculatedAge)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(isAgeValid ? .primary : .red)
                    
                    if !isAgeValid {
                        Text("Must be 18-100")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    private var bioTextEditor: some View {
        TextEditor(text: $bio)
            .frame(height: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .padding(.vertical, 4)
            .overlay(
                HStack {
                    Spacer()
                    if !isBioValid && !bio.isEmpty {
                        Text("Min 20 characters")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.trailing, 5)
                    }
                }
                , alignment: .bottomTrailing
            )
    }
    
    
    private var galleryPhotosSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Photos \(photosCounterText)")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("First photo is your profile photo")
                        .font(.caption)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
                Spacer()
                Image(systemName: isPhotosValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isPhotosValid ? .green : .red)
            }
            
            if totalValidPhotos == 0 {
                emptyPhotosView
            } else {
                photosGridView
            }
        }
        .padding(.horizontal)
    }
    
    private var emptyPhotosView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No photos yet")
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
            
            Text("Add photos to show more of yourself")
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showingGalleryPicker = true
            }) {
                Text("Add Photos")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var photosGridView: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(existingPhotos, id: \.self) { photoURL in
                existingPhotoView(photoURL: photoURL)
            }
            
            ForEach(galleryPhotos) { photo in
                newPhotoView(photo: photo)
            }
            
            addMorePhotosButton
        }
    }
    
    private func existingPhotoView(photoURL: String) -> some View {
        ZStack {
            AsyncImage(url: URL(string: photoURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
            .frame(height: 100)
            .clipped()
            .cornerRadius(8)
            
            Button(action: {
                deleteExistingPhoto(photoURL)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .background(SpectRoomTheme.card)
                    .clipShape(Circle())
            }
            .offset(x: 40, y: -40)
        }
    }
    
    private func newPhotoView(photo: LocalGalleryImage) -> some View {
        ZStack {
            Image(uiImage: photo.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 100)
                .clipped()
                .cornerRadius(8)
            
            Button(action: {
                removeGalleryPhoto(id: photo.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .background(SpectRoomTheme.card)
                    .clipShape(Circle())
            }
            .offset(x: 40, y: -40)
        }
    }
    
    private var addMorePhotosButton: some View {
        Button(action: {
            showingGalleryPicker = true
        }) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .frame(height: 100)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Add More")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                )
        }
    }
    
    private var saveButton: some View {
        Button(action: {
            saveProfile()
        }) {
            Text("Complete Profile")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isFormComplete ? Color.blue : Color.gray)
                .cornerRadius(12)
        }
        .disabled(isLoading || !isFormComplete)
        .padding(.horizontal)
        .padding(.bottom, 30)
    }
    
    private var loadingOverlay: some View {
        Group {
            if isLoading {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                ProgressView("Saving...")
                    .padding()
                    .background(SpectRoomTheme.card)
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Helper Methods
    private func loadCurrentProfile() {
        // Clear any local photo cache first
        profilePhoto = nil
        galleryPhotos = []
        photosToDelete = []
        
        if let user = appState.currentUser {
            name = user.name
            // Convert age to date of birth (approximate)
            let calendar = Calendar.current
            dateOfBirth = calendar.date(byAdding: .year, value: -user.age, to: Date()) ?? Date()
            bio = user.bio

            // Load photos from app state (app state is source of truth)
            existingPhotos = user.photos
            print("📸 Loaded \(existingPhotos.count) photos from app state: \(existingPhotos)")
        } else {
            // User doesn't exist yet - start with empty profile or use sign up name
            print("📝 No existing user profile - starting fresh")
            if !appState.signUpName.isEmpty {
                name = appState.signUpName
                print("📝 Using sign up name: \(appState.signUpName)")
            } else {
                let authName = (FirebaseAuthService.shared.auth.currentUser?.displayName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                name = authName
                if !authName.isEmpty {
                    print("📝 Using Auth display name: \(authName)")
                }
            }
            dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
            bio = ""
            existingPhotos = []
        }
    }


    private func removeGalleryPhoto(id: UUID) {
        galleryPhotos.removeAll { $0.id == id }
    }

    private func deleteExistingPhoto(_ photoURL: String) {
        photosToDelete.insert(photoURL)
        existingPhotos.removeAll { $0 == photoURL }
        print("🗑️ Marked photo for deletion: \(photoURL)")
    }

    private func saveProfile() {
        let ageInt = calculatedAge

        isLoading = true
        print("🔄 Starting profile save...")

        Task {
            do {
                if var user = appState.currentUser {
                    user.name = name
                    user.age = ageInt
                    user.bio = bio
                    user.photos = user.photos.filter { !$0.isEmpty && URL(string: $0) != nil }
                    print("🧹 Cleaned up invalid photos, now have \(user.photos.count) valid photos")
                    appState.currentUser = user
                    print("✅ User data updated locally")
                    appState.saveAppState()
                    print("✅ User data saved to UserDefaults")
                } else {
                    // Create new user if one doesn't exist
                    var newUser = SpectRoomUser(
                        name: name,
                        age: ageInt,
                        email: FirebaseAuthService.shared.auth.currentUser?.email ?? "",
                        bio: bio
                    )
                    appState.currentUser = newUser
                    print("✅ Created new user locally")
                    appState.saveAppState()
                    print("✅ New user data saved to UserDefaults")
                }

                var userData: [String: Any] = [
                    "name": name,
                    "age": ageInt,
                    "bio": bio,
                    "profilePhotoURL": appState.currentUser?.profilePhotoURL ?? NSNull()
                ]
                let profileEmail = (FirebaseAuthService.shared.auth.currentUser?.email ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if !profileEmail.isEmpty {
                    userData["email"] = profileEmail
                }

                print("🔄 Saving to Firebase...")
                try await FirebaseAuthService.shared.updateUserData(userData)
                print("✅ Profile data saved to Firebase")

                var deletionErrors: [String] = []
                for photoURL in photosToDelete {
                    do {
                        print("🗑️ Deleting photo from storage: \(photoURL)")
                        try await PhotoStorageService.shared.deletePhoto(url: photoURL)
                        print("✅ Photo deleted successfully")
                    } catch {
                        print("❌ Failed to delete photo: \(error)")
                        deletionErrors.append("Failed to delete photo: \(error.localizedDescription)")
                    }
                }

                var photoURLs: [String] = []
                var uploadErrors: [String] = []

                var newProfilePhotoURL: String? = nil
                if let profilePhoto = profilePhoto {
                    do {
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
                        
                        print("🔄 Uploading profile photo...")
                        let userID = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                        newProfilePhotoURL = try await withTimeout(seconds: 30) {
                            try await PhotoStorageService.shared.uploadProfilePhoto(profilePhoto, for: userID)
                        }
                        print("✅ Profile photo uploaded")
                    } catch {
                        print("❌ Profile photo upload failed: \(error)")
                        uploadErrors.append("Profile photo: \(error.localizedDescription)")
                    }
                }

                if !galleryPhotos.isEmpty {
                    do {
                        print("🔄 Uploading gallery photos...")
                        let userID = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                        let galleryPhotoURLs = try await withTimeout(seconds: 60) {
                            try await PhotoStorageService.shared.uploadMultipleGalleryPhotos(
                                galleryPhotos.map(\.image),
                                for: userID
                            )
                        }
                        photoURLs.append(contentsOf: galleryPhotoURLs)
                        print("✅ Gallery photos uploaded")
                    } catch {
                        print("❌ Gallery photos upload failed: \(error)")
                        uploadErrors.append("Gallery photos: \(error.localizedDescription)")
                    }
                }

                if var user = appState.currentUser {
                    print("📸 Before update - user has \(user.photos.count) photos: \(user.photos)")
                    
                    // Update profile photo URL
                    if let newProfilePhotoURL = newProfilePhotoURL {
                        user.profilePhotoURL = newProfilePhotoURL
                    }
                    
                    // Update gallery photos
                    var finalPhotos = existingPhotos
                    finalPhotos.append(contentsOf: photoURLs)
                    user.photos = finalPhotos
                    print("📸 After update - user has \(user.photos.count) photos: \(user.photos)")
                    appState.currentUser = user

                    let photoData: [String: Any] = [
                        "profilePhotoURL": user.profilePhotoURL ?? NSNull(),
                        "photos": user.photos
                    ]

                    print("🔄 Updating photos in Firebase...")
                    do {
                        try await FirebaseAuthService.shared.updateUserData(photoData)
                        print("✅ Photos updated in Firebase")
                    } catch {
                        print("⚠️ Firebase photo update failed: \(error)")
                    }
                }

                await MainActor.run {
                    self.isLoading = false

                    var allErrors: [String] = []
                    allErrors.append(contentsOf: deletionErrors)
                    allErrors.append(contentsOf: uploadErrors)

                    if !allErrors.isEmpty {
                        self.alertMessage = "Profile updated, but some operations failed:\n\(allErrors.joined(separator: "\n"))"
                        self.showingAlert = true
                    } else {
                        self.alertMessage = "Profile updated successfully!"
                        self.showingAlert = true
                        appState.completeInitialProfile() // Mark profile as complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.dismiss()
                        }
                    }
                }

            } catch {
                print("❌ Profile save failed: \(error)")
                await MainActor.run {
                    self.isLoading = false
                    self.alertMessage = "Failed to update profile: \(error.localizedDescription)"
                    self.showingAlert = true
                }
            }
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }

            group.cancelAll()
            return result
        }
    }

    struct TimeoutError: LocalizedError {
        var errorDescription: String? {
            return "Operation timed out"
        }
    }
}

// MARK: - Image Picker Components (reused from ProfileEditView)
// Note: ImagePicker and GalleryImagePicker are defined in ProfileEditView.swift


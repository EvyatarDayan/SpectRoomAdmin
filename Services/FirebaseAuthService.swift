//
//  FirebaseAuthService.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseMessaging
import FirebaseFunctions

class FirebaseAuthService: ObservableObject {
    static let shared = FirebaseAuthService()
    
    @Published var currentUser: SpectRoomUser?
    /// Restored synchronously from Firebase's persisted session so launch UI does not flash logged-out screens.
    @Published var isAuthenticated: Bool
    /// Becomes true after Firebase emits the first auth-state callback.
    @Published var hasResolvedAuthState = false
    /// Becomes true after the first Firestore profile load attempt finishes for the current session.
    @Published var hasResolvedUserProfile = false
    
    let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var matchesListener: ListenerRegistration?
    private var blockedByListener: ListenerRegistration?
    private var moderationListener: ListenerRegistration?
    private var pendingAdminReportsListener: ListenerRegistration?
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    /// Keeps the app on the login screen while we verify the account isn't soft-deleted.
    private var isVerifyingSignIn = false
    
    private init() {
        // Firebase restores the session from the keychain synchronously when available.
        isAuthenticated = auth.currentUser != nil
        
        // Listen for authentication state changes
        authStateListenerHandle = auth.addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasResolvedAuthState = true
                
                // During sign-in verification, don't flip UI to authenticated yet.
                if self.isVerifyingSignIn {
                    return
                }
                
                self.isAuthenticated = firebaseUser != nil
                if let firebaseUser = firebaseUser {
                    self.hasResolvedUserProfile = false
                    // Load user data from Firestore when Firebase user changes
                    await self.loadUserData(for: firebaseUser.uid)
                    // Update FCM token when user logs in
                    await self.updateFCMTokenIfNeeded()
                } else {
                    self.currentUser = nil
                    self.hasResolvedUserProfile = true
                }
            }
        }
    }
    
    // Update FCM token when user logs in
    private func updateFCMTokenIfNeeded() async {
        guard let userId = auth.currentUser?.uid else { return }
        
        // Get FCM token from Messaging
        guard let fcmToken = try? await Messaging.messaging().token() else {
            print("⚠️ Could not get FCM token")
            return
        }
        
        print("📱 Updating FCM token for user: \(userId)")
        
        do {
            try await updateUserData(["fcmToken": fcmToken])
            print("✅ FCM token updated in Firestore")
        } catch {
            print("❌ Failed to update FCM token: \(error.localizedDescription)")
        }
    }
    
    /// Re-register the current device token after the user enables notifications.
    func refreshFCMToken() async {
        await updateFCMTokenIfNeeded()
    }
    
    // MARK: - Authentication Methods
    
    func signUp(email: String, password: String, name: String, age: Int) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if try await isEmailPendingDeletion(normalizedEmail) {
            throw SpectRoomAuthError.emailPendingDeletion
        }
        
        do {
            _ = try await auth.createUser(withEmail: normalizedEmail, password: password)
        } catch {
            // Soft-deleted Auth users still occupy the email until hard delete.
            if isEmailAlreadyInUseError(error),
               (try? await isEmailPendingDeletion(normalizedEmail)) == true {
                throw SpectRoomAuthError.emailPendingDeletion
            }
            throw error
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firebaseUser = auth.currentUser, !trimmedName.isEmpty {
            let changeRequest = firebaseUser.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            try await changeRequest.commitChanges()
            print("✅ Saved signup name on Auth account: \(trimmedName)")
        }

        // Persist name/age/email so Admin → All profiles can show them before profile completion.
        if let uid = auth.currentUser?.uid {
            var payload: [String: Any] = [
                "email": normalizedEmail,
                "createdAt": FieldValue.serverTimestamp(),
                UserProfileStatus.firestoreKey: UserProfileStatus.incomplete.rawValue,
                "isOnline": false
            ]
            if !trimmedName.isEmpty {
                payload["name"] = trimmedName
                payload["displayName"] = trimmedName
            }
            if age > 0 {
                payload["age"] = age
            }
            try await db.collection("users").document(uid).setData(payload, merge: true)
        }

        print("✅ User account created: \(auth.currentUser?.uid ?? "unknown")")
        print("📝 User can now complete their profile through the app")
    }
    
    /// Returns true when this email belongs to a soft-deleted account still within the 14-day window.
    private func isEmailPendingDeletion(_ normalizedEmail: String) async throws -> Bool {
        let result = try await Functions.functions(region: "us-central1")
            .httpsCallable("checkEmailPendingDeletion")
            .call(["email": normalizedEmail])
        
        guard let data = result.data as? [String: Any] else {
            print("⚠️ checkEmailPendingDeletion returned unexpected payload: \(String(describing: result.data))")
            return false
        }
        
        let pending = boolValue(from: data, key: "pendingDeletion")
        print("🔍 Email pending deletion check for \(normalizedEmail): \(pending)")
        return pending
    }
    
    private func boolValue(from data: [String: Any], key: String) -> Bool {
        if let value = data[key] as? Bool {
            return value
        }
        if let number = data[key] as? NSNumber {
            return number.boolValue
        }
        return false
    }
    
    private func isEmailAlreadyInUseError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if let authCode = AuthErrorCode(_bridgedNSError: nsError)?.code {
            return authCode == .emailAlreadyInUse
        }
        return false
    }
    
    func signIn(email: String, password: String) async throws {
        await MainActor.run {
            self.isVerifyingSignIn = true
            self.hasResolvedUserProfile = false
        }
        
        do {
            _ = try await auth.signIn(withEmail: email, password: password)
            
            if let userData = try await fetchUserData() {
                if userData["isDeleted"] as? Bool == true {
                    try auth.signOut()
                    await MainActor.run {
                        self.isVerifyingSignIn = false
                        self.isAuthenticated = false
                        self.currentUser = nil
                        self.hasResolvedUserProfile = true
                    }
                    throw SpectRoomAuthError.accountPendingDeletion
                }
                if userData["isBanned"] as? Bool == true {
                    try auth.signOut()
                    await MainActor.run {
                        self.isVerifyingSignIn = false
                        self.isAuthenticated = false
                        self.currentUser = nil
                        self.hasResolvedUserProfile = true
                    }
                    throw SpectRoomAuthError.accountBanned
                }
                if let freezeUntil = Self.parseDiscoverFreezeUntil(from: userData),
                   freezeUntil > Date() {
                    try auth.signOut()
                    await MainActor.run {
                        self.isVerifyingSignIn = false
                        self.isAuthenticated = false
                        self.currentUser = nil
                        self.hasResolvedUserProfile = true
                    }
                    throw SpectRoomAuthError.accountFrozen(until: freezeUntil)
                }
            }
            
            let userId = auth.currentUser?.uid
            await MainActor.run {
                self.isVerifyingSignIn = false
                self.hasResolvedUserProfile = false
                self.isAuthenticated = self.auth.currentUser != nil
            }
            
            if let userId {
                await loadUserData(for: userId)
                await updateFCMTokenIfNeeded()
            }
        } catch {
            await MainActor.run {
                self.isVerifyingSignIn = false
                if self.auth.currentUser == nil {
                    self.isAuthenticated = false
                }
            }
            throw error
        }
    }
    
    func signOut() throws {
        try auth.signOut()
    }
    
    func resetPassword(email: String) async throws {
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.contains("@") else {
            throw SpectRoomAuthError.notAuthenticated
        }

        // Branded SpectRoom email (blue "Click here…" link) via Cloud Function.
        // Same Firebase reset action link as Auth's built-in forgot-password flow.
        _ = try await Functions.functions(region: "us-central1")
            .httpsCallable("sendSpectRoomPasswordResetEmail")
            .call(["email": normalized])
    }
    
    /// Soft-deletes the account. Hard deletion runs via Cloud Function after 14 days
    /// unless an admin clears `isDeleted` / related fields in Firestore first.
    /// Also write `deletedEmails/{email}` so signup can block reuse until hard delete.
    /// Admin revive: remove isDeleted/deletedAt/scheduledHardDeleteAt from users/{uid}
    /// and delete deletedEmails/{email}.
    func requestAccountDeletion() async throws {
        guard let user = auth.currentUser else {
            throw SpectRoomAuthError.notAuthenticated
        }
        
        let now = Date().timeIntervalSince1970
        let hardDeleteAt = now + (14 * 24 * 60 * 60)
        let normalizedEmail = (user.email ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        try await db.collection("users").document(user.uid).setData([
            "isDeleted": true,
            "deletedAt": now,
            "deletedBy": "user",
            "lastDeletedBy": "user",
            "deletedByAdmin": false,
            "lastDeletedByAdmin": false,
            "scheduledHardDeleteAt": hardDeleteAt,
            "isOnline": false,
            "fcmToken": FieldValue.delete()
        ], merge: true)
        
        if !normalizedEmail.isEmpty {
            try await db.collection("deletedEmails").document(normalizedEmail).setData([
                "uid": user.uid,
                "email": normalizedEmail,
                "deletedAt": now,
                "scheduledHardDeleteAt": hardDeleteAt
            ])
        }
        
        print("🗑️ Account marked for deletion: \(user.uid), hard delete after \(hardDeleteAt)")
    }
    
    func reauthenticate(withPassword password: String) async throws {
        guard let user = auth.currentUser, let email = user.email else {
            throw SpectRoomAuthError.notAuthenticated
        }
        
        guard !password.isEmpty else {
            throw SpectRoomAuthError.wrongPassword
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        do {
            try await user.reauthenticate(with: credential)
        } catch {
            // Any failed reauth in this flow is treated as an incorrect password for UX.
            print("⚠️ Reauthentication failed: \(error.localizedDescription)")
            throw SpectRoomAuthError.wrongPassword
        }
    }
    
    // MARK: - User Data Methods
    
    func fetchUserData(preferServer: Bool = false) async throws -> [String: Any]? {
        guard let user = auth.currentUser else { return nil }

        let document: DocumentSnapshot
        if preferServer {
            document = try await db.collection("users").document(user.uid).getDocument(source: .server)
        } else {
            document = try await db.collection("users").document(user.uid).getDocument()
        }
        return document.data()
    }
    
    private func loadUserData(for userID: String) async {
        defer {
            Task { @MainActor in
                self.hasResolvedUserProfile = true
            }
        }
        
        do {
            if let userData = try await fetchUserData() {
                if userData["isDeleted"] as? Bool == true {
                    print("🗑️ Account \(userID) is marked deleted — signing out")
                    try? auth.signOut()
                    await MainActor.run {
                        self.currentUser = nil
                    }
                    return
                }

                if userData["isBanned"] as? Bool == true {
                    // Keep session briefly so the ban acknowledgement popup can show.
                    print("🚫 Account \(userID) is banned — waiting for acknowledgement")
                    return
                }
                
                // Load photos and profile photo from Firestore
                let photos = userData["photos"] as? [String] ?? []
                let profilePhotoURL = userData["profilePhotoURL"] as? String
                print("📸 Loaded \(photos.count) photos from Firestore")
                print("🖼️ Loaded profile photo URL: \(profilePhotoURL ?? "nil")")
                
                // Parse location data from Firebase
                let location = Self.parseLocation(from: userData)
                
                let interests = userData["interests"] as? [String] ?? []
                print("🔍 Firebase - Loaded interests from database: \(interests)")
                print("🔍 Firebase - Interests count: \(interests.count)")
                
                // Load gender and preferences
                let gender = userData["gender"] as? String ?? ""
                let interestedIn = userData["interestedIn"] as? [String] ?? []
                let lookingFor = userData["lookingFor"] as? [String] ?? []
                let savedPreferredAgeMin = userData["preferredAgeMin"] as? Int
                let savedPreferredAgeMax = userData["preferredAgeMax"] as? Int
                let userAge = userData["age"] as? Int ?? 18
                
                // Set default preferred age range based on user's age if not saved
                let preferredAgeMin = savedPreferredAgeMin ?? userAge
                let preferredAgeMax = savedPreferredAgeMax ?? min(userAge + 5, 80)
                
                print("🔍 Firebase - Loaded gender: \(gender)")
                print("🔍 Firebase - Loaded interestedIn: \(interestedIn)")
                print("🔍 Firebase - Loaded lookingFor: \(lookingFor)")
                print("🔍 Firebase - Loaded preferredAgeMin: \(preferredAgeMin)")
                print("🔍 Firebase - Loaded preferredAgeMax: \(preferredAgeMax)")
                
                // Load date of birth from database
                let dateOfBirth: Date?
                if let dateOfBirthTimestamp = userData["dateOfBirth"] as? TimeInterval {
                    dateOfBirth = Date(timeIntervalSince1970: dateOfBirthTimestamp)
                    print("🔍 Firebase - Loaded date of birth from database: \(String(describing: dateOfBirth))")
                } else {
                    dateOfBirth = nil
                    print("🔍 Firebase - No date of birth found in database")
                }
                
                let lifestyle = userData["lifestyle"] as? String ?? ""
                let shareLifestyle = userData["shareLifestyle"] as? Bool ?? false
                let bodyType = userData["bodyType"] as? String ?? ""
                let shareBodyType = userData["shareBodyType"] as? Bool ?? false
                let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []
                let shareIdealFirstDate = userData["shareIdealFirstDate"] as? Bool ?? false
                let sensoryPreferences = userData["sensoryPreferences"] as? [String] ?? []
                let shareSensoryPreferences = userData["shareSensoryPreferences"] as? Bool ?? false
                let energyLevel = userData["energyLevel"] as? Int ?? 4
                
                print("🔍 Firebase - Loaded lifestyle: \(lifestyle), shareLifestyle: \(shareLifestyle)")
                print("🔍 Firebase - Loaded bodyType: \(bodyType), shareBodyType: \(shareBodyType)")
                print("🔍 Firebase - Loaded idealFirstDate: \(idealFirstDate), shareIdealFirstDate: \(shareIdealFirstDate)")
                print("🔍 Firebase - Loaded sensoryPreferences: \(sensoryPreferences), shareSensoryPreferences: \(shareSensoryPreferences)")
                print("🔍 Firebase - Loaded energyLevel: \(energyLevel)")
                
                let firestoreEmail = (userData["email"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let authEmail = (auth.currentUser?.email ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedEmail = firestoreEmail.isEmpty ? authEmail : firestoreEmail

                // Backfill missing email on the user doc so admin search-by-email works.
                if firestoreEmail.isEmpty, !authEmail.isEmpty {
                    Task {
                        try? await self.updateUserData(["email": authEmail.lowercased()])
                    }
                }
                
                let firestoreName = (userData["name"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let authName = (auth.currentUser?.displayName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedName = firestoreName.isEmpty ? authName : firestoreName
                
                let spectRoomUser = SpectRoomUser(
                    name: resolvedName,
                    age: userData["age"] as? Int ?? 0,
                    email: resolvedEmail,
                    bio: userData["bio"] as? String ?? "",
                    interests: interests,
                    location: location,
                    preferences: UserPreferences(), // You might want to parse preferences
                    gender: gender,
                    interestedIn: interestedIn,
                    lookingFor: lookingFor,
                    preferredAgeMin: preferredAgeMin,
                    preferredAgeMax: preferredAgeMax,
                    lifestyle: lifestyle,
                    shareLifestyle: shareLifestyle,
                    bodyType: bodyType,
                    shareBodyType: shareBodyType,
                    idealFirstDate: idealFirstDate,
                    shareIdealFirstDate: shareIdealFirstDate,
                    sensoryPreferences: sensoryPreferences,
                    shareSensoryPreferences: shareSensoryPreferences,
                    energyLevel: energyLevel
                )
                
                // Load isOnline and lastSeen from Firebase
                let isOnline = userData["isOnline"] as? Bool ?? false
                let lastSeenInterval = userData["lastSeen"] as? TimeInterval
                let lastSeen = lastSeenInterval.map { Date(timeIntervalSince1970: $0) } ?? Date()
                
                // Create a mutable copy and set the photos, profile photo, date of birth, and online status
                var userWithPhotos = spectRoomUser
                userWithPhotos.photos = photos
                userWithPhotos.profilePhotoURL = profilePhotoURL
                userWithPhotos.dateOfBirth = dateOfBirth
                userWithPhotos.isOnline = isOnline
                userWithPhotos.lastSeen = lastSeen

                // Fetch blocked users subcollection (non-fatal)
                do {
                    let blockedSnapshot = try await db.collection("users")
                        .document(userID)
                        .collection("blockedUsers")
                        .getDocuments()
                    userWithPhotos.blockedUsers = blockedSnapshot.documents.compactMap { document in
                        let data = document.data()
                        let name = data["name"] as? String ?? "Unknown"
                        let blockedAtInterval = data["blockedAt"] as? TimeInterval
                        let blockedAt = blockedAtInterval.map { Date(timeIntervalSince1970: $0) }
                        return BlockedUser(id: document.documentID, name: name, blockedAt: blockedAt)
                    }
                    
                    await syncBlockedByMirrors(
                        for: userWithPhotos.blockedUsers,
                        blockerName: userWithPhotos.name
                    )
                } catch {
                    userWithPhotos.blockedUsers = []
                    print("⚠️ Failed to load blocked users for \(userID): \(error.localizedDescription)")
                }

                do {
                    let blockedBySnapshot = try await db.collection("users")
                        .document(userID)
                        .collection("blockedBy")
                        .getDocuments()
                    userWithPhotos.blockedByUsers = blockedBySnapshot.documents.compactMap { document in
                        let data = document.data()
                        let name = data["name"] as? String ?? "Unknown"
                        let blockedAtInterval = data["blockedAt"] as? TimeInterval
                        let blockedAt = blockedAtInterval.map { Date(timeIntervalSince1970: $0) }
                        return BlockedUser(id: document.documentID, name: name, blockedAt: blockedAt)
                    }
                } catch {
                    userWithPhotos.blockedByUsers = []
                    print("⚠️ Failed to load blockedBy users for \(userID): \(error.localizedDescription)")
                }
                let resolvedUser = userWithPhotos
                await MainActor.run {
                    self.currentUser = resolvedUser
                }
                
                // Preload photos from Firebase Storage to improve user experience
                print("🔄 Preloading photos from Firebase Storage...")
                await syncPhotosFromStorage()
            } else {
                // User document doesn't exist - don't create automatically
                print("⚠️ User document not found for \(userID)")
                print("📝 User needs to complete their profile")
                await MainActor.run {
                    self.currentUser = nil
                }
            }
        } catch {
            print("Load user data error: \(error.localizedDescription)")
            // If there's an error, don't create default document
            await MainActor.run {
                self.currentUser = nil
            }
        }
    }
    
    
    func updateUserData(_ data: [String: Any]) async throws {
        guard let user = auth.currentUser else { return }

        // Keep `email` on the user doc so Admin → All profiles can search by it.
        // Profile saves often omit email; Auth is the source of truth.
        var payload = data
        if payload["email"] == nil,
           let authEmail = user.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !authEmail.isEmpty {
            payload["email"] = authEmail
        }

        // Use setData with merge to create document if it doesn't exist
        try await db.collection("users").document(user.uid).setData(payload, merge: true)
    }
    
    // MARK: - Force Refresh User Data
    func forceRefreshUserData() async {
        guard let user = auth.currentUser else { return }
        
        print("🔄 Force refreshing user data from Firebase...")
        await loadUserData(for: user.uid)
    }
    
    // MARK: - Update Database with App State
    func updateDatabaseWithAppState() async {
        guard auth.currentUser != nil else { return }
        
        print("🔄 Updating database with current app state...")
        
        // Get current app state from AppStateManager
        if let currentUser = self.currentUser {
            print("📸 App state has \(currentUser.photos.count) photos: \(currentUser.photos)")
            print("🖼️ App state profile photo: \(currentUser.profilePhotoURL ?? "nil")")
            
            // Update database to match app state exactly (no validation)
            let userData: [String: Any] = [
                "name": currentUser.name,
                "age": currentUser.age,
                "bio": currentUser.bio,
                "interests": currentUser.interests,
                "lifestyle": currentUser.lifestyle,
                "profilePhotoURL": currentUser.profilePhotoURL ?? NSNull(),
                "photos": currentUser.photos
            ]
            
            do {
                try await updateUserData(userData)
                print("✅ Database updated to match app state")
            } catch {
                print("❌ Error updating database with app state: \(error)")
            }
        } else {
            print("⚠️ No current user in app state")
        }
    }
    
    // MARK: - Debug: Test Firebase Connection
    func testFirebaseConnection() async {
        print("🔍 Testing Firebase connection...")
        do {
            let snapshot = try await db.collection("users").getDocuments()
            print("🔍 Firebase connection successful!")
            print("🔍 Total documents in users collection: \(snapshot.documents.count)")
            
            for document in snapshot.documents {
                let data = document.data()
                let name = data["name"] as? String ?? "No name"
                let email = data["email"] as? String ?? "No email"
                print("🔍 Document ID: \(document.documentID), Name: \(name), Email: \(email)")
            }
        } catch {
            print("❌ Firebase connection failed: \(error)")
        }
    }
    
    // MARK: - Fetch Users for Search
    
    struct UsersPage {
        let users: [SpectRoomUser]
        let lastDocumentId: String?
        let hasMore: Bool
    }
    
    func fetchUsersPage(limit: Int = 15, startAfterDocumentId: String? = nil) async throws -> UsersPage {
        let currentUserID = auth.currentUser?.uid
        
        let snapshot: QuerySnapshot
        do {
            var query: Query = db.collection("users")
                .order(by: FieldPath.documentID())
                .limit(to: limit)
            
            if let startAfterDocumentId {
                let previousDoc = try await db.collection("users").document(startAfterDocumentId).getDocument()
                if previousDoc.exists {
                    query = query.start(afterDocument: previousDoc)
                }
            }
            
            snapshot = try await query.getDocuments()
        } catch {
            print("⚠️ Paginated users fetch failed, falling back to full read: \(error.localizedDescription)")
            snapshot = try await db.collection("users").getDocuments()
        }
        
        let users = snapshot.documents.compactMap { document in
            parseSpectRoomUser(documentID: document.documentID, userData: document.data(), excludingUserId: currentUserID)
        }
        
        let lastDocumentId = snapshot.documents.last?.documentID
        let hasMore = snapshot.documents.count == limit
        
        return UsersPage(users: users, lastDocumentId: lastDocumentId, hasMore: hasMore)
    }
    
    func fetchUsers(byIds userIds: [String]) async throws -> [SpectRoomUser] {
        guard !userIds.isEmpty else { return [] }
        
        let currentUserID = auth.currentUser?.uid
        var users: [SpectRoomUser] = []
        
        var startIndex = userIds.startIndex
        while startIndex < userIds.endIndex {
            let endIndex = userIds.index(startIndex, offsetBy: 10, limitedBy: userIds.endIndex) ?? userIds.endIndex
            let chunk = Array(userIds[startIndex..<endIndex])
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            
            for document in snapshot.documents {
                if let user = parseSpectRoomUser(
                    documentID: document.documentID,
                    userData: document.data(),
                    excludingUserId: currentUserID
                ) {
                    users.append(user)
                }
            }
            
            startIndex = endIndex
        }
        
        return users
    }
    
    func fetchAllUsers() async throws -> [SpectRoomUser] {
        var allUsers: [SpectRoomUser] = []
        var cursor: String?
        var hasMore = true
        
        while hasMore {
            let page = try await fetchUsersPage(limit: 50, startAfterDocumentId: cursor)
            allUsers.append(contentsOf: page.users)
            cursor = page.lastDocumentId
            hasMore = page.hasMore
        }
        
        print("🔍 Fetched \(allUsers.count) users from database")
        return allUsers
    }
    
    private func parseSpectRoomUser(
        documentID: String,
        userData: [String: Any],
        excludingUserId: String?
    ) -> SpectRoomUser? {
        if documentID == excludingUserId {
            return nil
        }
        
        if userData["isDeleted"] as? Bool == true {
            return nil
        }

        if userData["isBanned"] as? Bool == true {
            return nil
        }

        if let freezeUntil = Self.parseDiscoverFreezeUntil(from: userData),
           freezeUntil > Date() {
            return nil
        }
        
        let lifestyle = userData["lifestyle"] as? String ?? ""
        
        let location = Self.parseLocation(from: userData)
        
        let interests = userData["interests"] as? [String] ?? []
        let gender = userData["gender"] as? String ?? ""
        let interestedIn = userData["interestedIn"] as? [String] ?? []
        let lookingFor = userData["lookingFor"] as? [String] ?? []
        let preferredAgeMin = userData["preferredAgeMin"] as? Int ?? 18
        let preferredAgeMax = userData["preferredAgeMax"] as? Int ?? 80
        
        let dateOfBirth: Date?
        if let timestamp = userData["dateOfBirth"] as? TimeInterval {
            dateOfBirth = Date(timeIntervalSince1970: timestamp)
        } else {
            dateOfBirth = nil
        }
        
        let shareLifestyle = userData["shareLifestyle"] as? Bool ?? false
        let bodyType = userData["bodyType"] as? String ?? ""
        let shareBodyType = userData["shareBodyType"] as? Bool ?? false
        let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []
        let shareIdealFirstDate = userData["shareIdealFirstDate"] as? Bool ?? false
        let sensoryPreferences = userData["sensoryPreferences"] as? [String] ?? []
        let shareSensoryPreferences = userData["shareSensoryPreferences"] as? Bool ?? false
        let energyLevel = userData["energyLevel"] as? Int ?? 4
        let isOnline = userData["isOnline"] as? Bool ?? false
        let lastSeenInterval = userData["lastSeen"] as? TimeInterval
        let lastSeen = lastSeenInterval.map { Date(timeIntervalSince1970: $0) } ?? Date()
        
        let user = SpectRoomUser(
            name: userData["name"] as? String ?? "",
            age: userData["age"] as? Int ?? 0,
            email: userData["email"] as? String ?? "",
            bio: userData["bio"] as? String ?? "",
            interests: interests,
            location: location,
            preferences: UserPreferences(),
            gender: gender,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            preferredAgeMin: preferredAgeMin,
            preferredAgeMax: preferredAgeMax,
            lifestyle: lifestyle,
            shareLifestyle: shareLifestyle,
            bodyType: bodyType,
            shareBodyType: shareBodyType,
            idealFirstDate: idealFirstDate,
            shareIdealFirstDate: shareIdealFirstDate,
            sensoryPreferences: sensoryPreferences,
            shareSensoryPreferences: shareSensoryPreferences,
            energyLevel: energyLevel
        )
        
        var userWithPhotos = user
        userWithPhotos.photos = userData["photos"] as? [String] ?? []
        userWithPhotos.profilePhotoURL = userData["profilePhotoURL"] as? String
        userWithPhotos.dateOfBirth = dateOfBirth
        userWithPhotos.firebaseDocumentId = documentID
        userWithPhotos.isOnline = isOnline
        userWithPhotos.lastSeen = lastSeen
        
        return userWithPhotos
    }
    
    // MARK: - Sync Photos from Storage
    private var isSyncingPhotos = false
    
    func syncPhotosFromStorage() async {
        guard let user = auth.currentUser else { return }
        
        // Prevent multiple simultaneous syncs
        guard !isSyncingPhotos else {
            print("📸 Photo sync already in progress, skipping...")
            return
        }
        
        isSyncingPhotos = true
        print("🔄 Syncing photos from Firebase Storage for user: \(user.uid)...")
        
        do {
            // Get only the current user's gallery photos
            let photoURLs = try await PhotoStorageService.shared.getUserGalleryPhotos(for: user.uid)
            
            print("📸 Found \(photoURLs.count) photos for user \(user.uid): \(photoURLs)")
            
            // Update the current user's photos array
            if var currentUser = self.currentUser {
                currentUser.photos = photoURLs
                let updatedUser = currentUser
                await MainActor.run {
                    self.currentUser = updatedUser
                }
                
                // Update Firestore with the synced photos
                let userData: [String: Any] = [
                    "photos": photoURLs
                ]
                
                try await updateUserData(userData)
                print("✅ Synced \(photoURLs.count) photos from Storage to Firestore")
            }
            
        } catch {
            print("❌ Error syncing photos from Storage: \(error)")
        }
        
        isSyncingPhotos = false
    }
    
    // MARK: - Photo URL Validation
    private func validatePhotoURLs(_ photoURLs: [String]) async -> [String] {
        var validURLs: [String] = []
        
        for url in photoURLs {
            if await isPhotoURLValid(url) {
                validURLs.append(url)
            } else {
                print("⚠️ Removing invalid photo URL: \(url)")
            }
        }
        
        return validURLs
    }
    
    private func validateProfilePhotoURL(_ profilePhotoURL: String?) async -> String? {
        guard let url = profilePhotoURL else { return nil }
        
        if await isPhotoURLValid(url) {
            return url
        } else {
            print("⚠️ Removing invalid profile photo URL: \(url)")
            return nil
        }
    }
    
    private func isPhotoURLValid(_ url: String) async -> Bool {
        guard let url = URL(string: url) else { return false }
        
        do {
            let storageRef = Storage.storage().reference(forURL: url.absoluteString)
            _ = try await storageRef.getMetadata()
            return true
        } catch {
            print("⚠️ Photo URL is invalid (file doesn't exist): \(url.absoluteString)")
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    func getCurrentUserID() -> String? {
        return auth.currentUser?.uid
    }
    
    func getCurrentUserEmail() -> String? {
        return auth.currentUser?.email
    }
    
    // MARK: - Blocked Users
    
    private func blockedByMirrorData(blockerName: String, blockedAt: Date) -> [String: Any] {
        [
            "name": blockerName,
            "blockedAt": blockedAt.timeIntervalSince1970
        ]
    }
    
    private func syncBlockedByMirror(blockedUserId: String, blockerName: String, blockedAt: Date) async throws {
        guard let currentUserId = auth.currentUser?.uid else { return }
        
        try await db.collection("users")
            .document(blockedUserId)
            .collection("blockedBy")
            .document(currentUserId)
            .setData(blockedByMirrorData(blockerName: blockerName, blockedAt: blockedAt))
    }
    
    private func removeBlockedByMirror(blockedUserId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else { return }
        
        try await db.collection("users")
            .document(blockedUserId)
            .collection("blockedBy")
            .document(currentUserId)
            .delete()
    }
    
    private func syncBlockedByMirrors(for blockedUsers: [BlockedUser], blockerName: String) async {
        for blockedUser in blockedUsers {
            do {
                try await syncBlockedByMirror(
                    blockedUserId: blockedUser.id,
                    blockerName: blockerName,
                    blockedAt: blockedUser.blockedAt ?? Date()
                )
            } catch {
                print("⚠️ Failed to sync blockedBy mirror for \(blockedUser.id): \(error.localizedDescription)")
            }
        }
    }
    
    func blockUser(userId: String, name: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        let blockedAt = Date()
        let data: [String: Any] = [
            "name": name,
            "blockedAt": blockedAt.timeIntervalSince1970
        ]
        
        try await db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(userId)
            .setData(data)
        
        let blockerName = await MainActor.run { self.currentUser?.name ?? "Someone" }
        try await syncBlockedByMirror(blockedUserId: userId, blockerName: blockerName, blockedAt: blockedAt)
        
        await MainActor.run {
            if var current = self.currentUser,
               current.blockedUsers.contains(where: { $0.id == userId }) == false {
                current.blockedUsers.append(BlockedUser(id: userId, name: name, blockedAt: blockedAt))
                self.currentUser = current
            }
        }
    }

    /// Writes a user report to the top-level `reports` collection with an evidence snapshot.
    func submitUserReport(
        reportedUserId: String,
        category: String,
        details: String?,
        reportedProfile: ProfileCard
    ) async throws {
        guard let reporterUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }

        async let messagesTask = fetchConversationMessagesPage(with: reportedUserId, limit: 10)
        async let reportedUserDocTask = db.collection("users").document(reportedUserId).getDocument()

        let recentMessages: [MessageDisplay]
        do {
            recentMessages = try await messagesTask.messages
        } catch {
            print("⚠️ Report snapshot: could not load messages — \(error.localizedDescription)")
            recentMessages = []
        }

        var bio = reportedProfile.bio
        var name = reportedProfile.name
        var photoURLs: [String] = []
        if let imageURL = reportedProfile.imageURL, !imageURL.isEmpty {
            photoURLs.append(imageURL)
        }
        for url in reportedProfile.photos where !url.isEmpty && !photoURLs.contains(url) {
            photoURLs.append(url)
        }

        if let snapshot = try? await reportedUserDocTask, let userData = snapshot.data() {
            if let freshBio = userData["bio"] as? String {
                bio = freshBio
            }
            if let freshName = userData["name"] as? String, !freshName.isEmpty {
                name = freshName
            }
            if let profilePhotoURL = userData["profilePhotoURL"] as? String, !profilePhotoURL.isEmpty {
                photoURLs.removeAll { $0 == profilePhotoURL }
                photoURLs.insert(profilePhotoURL, at: 0)
            }
            if let photos = userData["photos"] as? [String] {
                for url in photos where !url.isEmpty && !photoURLs.contains(url) {
                    photoURLs.append(url)
                }
            }
        }

        let messageSnapshots: [[String: Any]] = recentMessages.map { message in
            var entry: [String: Any] = [
                "message_id": message.id,
                "sender_id": message.senderId,
                "recipient_id": message.recipientId,
                "content": message.content,
                "type": message.messageType.rawValue,
                "created_at": Timestamp(date: message.createdAt)
            ]
            if let voiceDuration = message.voiceDuration {
                entry["voice_duration"] = voiceDuration
            }
            return entry
        }

        let contextSnapshot: [String: Any] = [
            "name": name,
            "bio": bio,
            "profile_photo_urls": photoURLs,
            "messages": messageSnapshots
        ]

        let reportRef = db.collection("reports").document()
        var data: [String: Any] = [
            "report_id": reportRef.documentID,
            "reporter_user_id": reporterUserId,
            "reported_user_id": reportedUserId,
            "category": category,
            "context_snapshot": contextSnapshot,
            "status": "pending",
            "created_at": FieldValue.serverTimestamp()
        ]
        if let details = details?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            data["details"] = details
        } else {
            data["details"] = NSNull()
        }

        try await reportRef.setData(data)
        print("✅ Report submitted: \(reportRef.documentID)")
    }

    /// Reports submitted by the current user, newest first.
    func fetchMyReports() async throws -> [UserReport] {
        guard let reporterUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }

        let snapshot = try await db.collection("reports")
            .whereField("reporter_user_id", isEqualTo: reporterUserId)
            .getDocuments()

        let reports = snapshot.documents.compactMap { document -> UserReport? in
            Self.parseUserReport(documentID: document.documentID, data: document.data())
        }

        return reports.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    /// All reports for admin review, newest first.
    func fetchAllReportsForAdmin() async throws -> [UserReport] {
        try requireAdmin()

        let snapshot = try await db.collection("reports").getDocuments()
        let reports = snapshot.documents.compactMap { document -> UserReport? in
            Self.parseUserReport(documentID: document.documentID, data: document.data())
        }
        .sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }

        return await enrichReportsWithUserEmails(reports)
    }

    private func enrichReportsWithUserEmails(_ reports: [UserReport]) async -> [UserReport] {
        let userIds = Array(Set(reports.flatMap { [$0.reporterUserId, $0.reportedUserId] }))
            .filter { !$0.isEmpty }
        guard !userIds.isEmpty else { return reports }

        var emails: [String: String] = [:]
        var names: [String: String] = [:]
        var photoURLs: [String: String] = [:]

        // Fast path: Firestore user docs.
        for chunk in stride(from: 0, to: userIds.count, by: 30).map({ Array(userIds[$0..<min($0 + 30, userIds.count)]) }) {
            await withTaskGroup(of: (String, String?, String?, String?).self) { group in
                for userId in chunk {
                    group.addTask {
                        do {
                            let snap = try await self.db.collection("users").document(userId).getDocument()
                            let data = snap.data() ?? [:]
                            let email = (data["email"] as? String)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .lowercased()
                            let name = (data["name"] as? String)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let profilePhoto = (data["profilePhotoURL"] as? String)?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            let galleryFirst = (data["photos"] as? [String])?
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .first(where: { !$0.isEmpty })
                            let photo = (profilePhoto?.isEmpty == false) ? profilePhoto : galleryFirst
                            return (
                                userId,
                                (email?.isEmpty == false) ? email : nil,
                                (name?.isEmpty == false) ? name : nil,
                                photo
                            )
                        } catch {
                            return (userId, nil, nil, nil)
                        }
                    }
                }
                for await (userId, email, name, photo) in group {
                    if let email { emails[userId] = email }
                    if let name { names[userId] = name }
                    if let photo { photoURLs[userId] = photo }
                }
            }
        }

        // Fill gaps from Auth via existing admin callable.
        let missingIds = userIds.filter { emails[$0] == nil }
        if !missingIds.isEmpty {
            do {
                let lookup = try await resolveAdminUserIdentities(userIds: missingIds)
                for (uid, email) in lookup.emails {
                    emails[uid] = email
                }
                for (uid, name) in lookup.names where names[uid] == nil {
                    names[uid] = name
                }
            } catch {
                print("⚠️ enrichReportsWithUserEmails Auth lookup failed: \(error.localizedDescription)")
            }
        }

        return reports.map { report in
            report.withIdentities(
                reporterEmail: emails[report.reporterUserId],
                reportedEmail: emails[report.reportedUserId],
                reporterName: names[report.reporterUserId],
                reporterPhotoURL: photoURLs[report.reporterUserId]
            )
        }
    }

    /// Live pending report IDs for admin badge counts.
    func startListeningForPendingAdminReports(onChange: @escaping ([String]) -> Void) {
        guard AdminAccess.isAdmin(email: auth.currentUser?.email) else {
            stopListeningForPendingAdminReports()
            onChange([])
            return
        }

        stopListeningForPendingAdminReports()
        pendingAdminReportsListener = db.collection("reports")
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("⚠️ Error listening for pending admin reports: \(error.localizedDescription)")
                    return
                }
                let pendingIds = (snapshot?.documents ?? []).compactMap { document -> String? in
                    let status = (document.data()["status"] as? String ?? "pending")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    guard status == "pending" else { return nil }
                    return document.documentID
                }
                DispatchQueue.main.async {
                    onChange(pendingIds)
                }
            }
    }

    func stopListeningForPendingAdminReports() {
        pendingAdminReportsListener?.remove()
        pendingAdminReportsListener = nil
    }

    struct SupportTicketsPage {
        let tickets: [SupportTicket]
        let lastDocumentId: String?
        let hasMore: Bool
        let totalCount: Int
    }

    enum AdminSupportTicketsStatusFilter {
        case open
        case resolved
    }

    /// Help & Support tickets for the admin Support section, newest first.
    func fetchSupportTicketsForAdmin() async throws -> [SupportTicket] {
        try requireAdmin()

        let snapshot = try await db.collection("supportMessages").getDocuments()
        let tickets = snapshot.documents.compactMap { document -> SupportTicket? in
            Self.parseSupportTicket(documentID: document.documentID, data: document.data())
        }
        return tickets.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    /// Paginated Support tickets for the given status / topic / search filters.
    /// Scans `supportMessages`, filters, then returns one page plus the full matching total.
    func fetchSupportTicketsPage(
        status: AdminSupportTicketsStatusFilter,
        topicAliases: Set<String>? = nil,
        searchQuery: String? = nil,
        limit: Int = 25,
        startAfterDocumentId: String? = nil
    ) async throws -> SupportTicketsPage {
        try requireAdmin()

        let snapshot = try await db.collection("supportMessages").getDocuments()
        var tickets = snapshot.documents.compactMap { document -> SupportTicket? in
            Self.parseSupportTicket(documentID: document.documentID, data: document.data())
        }

        switch status {
        case .open:
            tickets = tickets.filter(\.isOpen)
        case .resolved:
            tickets = tickets.filter { !$0.isOpen }
        }

        if let topicAliases, !topicAliases.isEmpty {
            tickets = tickets.filter { ticket in
                topicAliases.contains(
                    ticket.topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
        }

        if let searchQuery {
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !query.isEmpty {
                tickets = tickets.filter { ticket in
                    ticket.userName.lowercased().contains(query)
                        || ticket.userEmail.lowercased().contains(query)
                        || ticket.message.lowercased().contains(query)
                        || ticket.displayTicketNumber.lowercased().contains(query)
                }
            }
        }

        tickets.sort {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }

        let startIndex: Int
        if let startAfterDocumentId,
           let index = tickets.firstIndex(where: { $0.id == startAfterDocumentId }) {
            startIndex = index + 1
        } else {
            startIndex = 0
        }

        let page = Array(tickets.dropFirst(startIndex).prefix(limit))
        return SupportTicketsPage(
            tickets: page,
            lastDocumentId: page.last?.id,
            hasMore: startIndex + page.count < tickets.count,
            totalCount: tickets.count
        )
    }

    func updateSupportTicketStatus(ticketId: String, status: String) async throws {
        try requireAdmin()
        guard let adminId = auth.currentUser?.uid else {
            throw SpectRoomAuthError.notAuthenticated
        }

        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var payload: [String: Any] = [
            "status": normalized,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": adminId
        ]
        if normalized == "resolved" || normalized == "closed" {
            payload["resolvedAt"] = FieldValue.serverTimestamp()
            payload["resolvedBy"] = adminId
        } else {
            payload["resolvedAt"] = FieldValue.delete()
            payload["resolvedBy"] = FieldValue.delete()
        }

        try await db.collection("supportMessages").document(ticketId).setData(payload, merge: true)
    }

    private static func parseSupportTicket(documentID: String, data: [String: Any]) -> SupportTicket? {
        let message = (data["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !message.isEmpty else { return nil }

        let createdAt: Date?
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else if let interval = data["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: interval)
        } else {
            createdAt = nil
        }

        let resolvedAt: Date?
        if let timestamp = data["resolvedAt"] as? Timestamp {
            resolvedAt = timestamp.dateValue()
        } else if let interval = data["resolvedAt"] as? TimeInterval {
            resolvedAt = Date(timeIntervalSince1970: interval)
        } else {
            resolvedAt = nil
        }

        let userName = (data["userName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let topic = (data["topic"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status = (data["status"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ticketNumber = (data["ticketId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (data["ticketNumber"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        return SupportTicket(
            id: documentID,
            ticketNumber: ticketNumber,
            userId: data["userId"] as? String ?? "",
            userName: userName.isEmpty ? "Unknown" : userName,
            userEmail: (data["userEmail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            topic: topic.isEmpty ? "General" : topic,
            message: message,
            status: status.isEmpty ? "new" : status,
            createdAt: createdAt,
            resolvedAt: resolvedAt
        )
    }

    func dismissReport(reportId: String) async throws {
        try requireAdmin()
        try await applyReportModeration(
            reportId: reportId,
            status: "dismissed",
            action: .dismiss
        )
    }

    func issueWarningForReport(
        reportId: String,
        reportedUserId: String,
        message: String? = nil
    ) async throws {
        try await issueWarningToUser(
            userId: reportedUserId,
            message: message,
            reportId: reportId
        )
        try await applyReportModeration(
            reportId: reportId,
            status: "actioned",
            action: .warning
        )
    }

    /// In-app warning from admin screens (report optional).
    func issueWarningToUser(
        userId: String,
        message: String? = nil,
        reportId: String? = nil
    ) async throws {
        try requireAdmin()

        let trimmed = message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let warningMessage = (trimmed?.isEmpty == false)
            ? trimmed!
            : "admin.warning.default.message".localized

        let resolvedReportId = (reportId?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "admin-profile-\(userId)-\(Int(Date().timeIntervalSince1970))"

        // Unique notice_id so push + client listeners treat each warning as new.
        let noticeId = "\(resolvedReportId)-\(Int(Date().timeIntervalSince1970))"
        let createdAt = Date().timeIntervalSince1970
        try await db.collection("users").document(userId).setData([
            "pendingSystemWarning": [
                "message": warningMessage,
                "report_id": resolvedReportId,
                "notice_id": noticeId,
                "created_at": createdAt,
                "acknowledged": false
            ]
        ], merge: true)

        // Best-effort history row for All profiles → History tab.
        try? await createWarningHistoryRecord(
            userId: userId,
            message: warningMessage,
            reportId: resolvedReportId,
            noticeId: noticeId
        )
    }

    func freezeUserForReport(
        reportId: String,
        reportedUserId: String,
        duration: ModerationFreezeDuration
    ) async throws {
        try await freezeUserAccount(
            userId: reportedUserId,
            duration: duration,
            reportId: reportId,
            markReportActioned: true
        )
    }

    /// Freeze (or re-freeze) a user from admin screens.
    func freezeUserAccount(
        userId: String,
        duration: ModerationFreezeDuration,
        reportId: String?,
        markReportActioned: Bool
    ) async throws {
        try requireAdmin()

        let freezeUntil = Date().addingTimeInterval(TimeInterval(duration.rawValue * 3600))
        let resolvedReportId = (reportId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "admin-freeze-\(userId)-\(Int(Date().timeIntervalSince1970))"

        let userSnapshot = try await db.collection("users").document(userId).getDocument()
        let userData = userSnapshot.data() ?? [:]

        try await db.collection("users").document(userId).setData([
            "discoverFrozenUntil": Timestamp(date: freezeUntil),
            "discoverFreezeHours": duration.rawValue,
            "discoverFrozenReportId": resolvedReportId,
            "pendingAccountUnfreeze": FieldValue.delete(),
            "pendingAccountFreeze": [
                "report_id": resolvedReportId,
                "kind": "new",
                "freeze_until": freezeUntil.timeIntervalSince1970,
                "hours": duration.rawValue,
                "created_at": Date().timeIntervalSince1970,
                "acknowledged": false,
                "message": String(
                    format: "Your account has been temporarily frozen for %d hours. Try to login after %@.",
                    duration.rawValue,
                    ModerationNotice.formattedUnlockDate(freezeUntil)
                )
            ]
        ], merge: true)

        try await closeActiveFreezeHistory(userId: userId, status: .lifted)
        do {
            try await createFreezeHistoryRecord(
                userId: userId,
                userData: userData,
                freezeUntil: freezeUntil,
                freezeHours: duration.rawValue,
                reportId: resolvedReportId,
                status: .active
            )
        } catch {
            print("⚠️ Unable to write freeze history record: \(error.localizedDescription)")
        }

        if markReportActioned, let reportId, !reportId.isEmpty,
           !reportId.hasPrefix("admin-freeze-"),
           !reportId.hasPrefix("admin-extend-") {
            try await applyReportModeration(
                reportId: reportId,
                status: "actioned",
                action: .freeze,
                extraFields: [
                    "freeze_hours": duration.rawValue,
                    "freeze_until": Timestamp(date: freezeUntil)
                ]
            )
        }
    }

    func banUserForReport(reportId: String, reportedUserId: String) async throws {
        try await banUserPermanently(userId: reportedUserId, reportId: reportId)
    }

    /// Permanent ban from admin screens (report optional).
    func banUserPermanently(userId: String, reportId: String?) async throws {
        try requireAdmin()
        guard let adminUserId = auth.currentUser?.uid else {
            throw SpectRoomAuthError.notAuthenticated
        }

        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()
        let userData = snapshot.data() ?? [:]

        var payload: [String: Any] = [
            "isBanned": true,
            "bannedAt": FieldValue.serverTimestamp(),
            "isOnline": false,
            "discoverFrozenUntil": FieldValue.delete(),
            "discoverFreezeHours": FieldValue.delete(),
            "discoverFrozenReportId": FieldValue.delete(),
            "pendingAccountFreeze": FieldValue.delete(),
            "pendingAccountUnfreeze": FieldValue.delete(),
            "pendingAccountUnban": FieldValue.delete(),
            "pendingAccountBan": [
                "notice_id": "ban-\(userId)-\(Int(Date().timeIntervalSince1970))",
                "created_at": Date().timeIntervalSince1970,
                "acknowledged": false,
                "banned_by": adminUserId,
                "message": "Your SpectRoom account has been permanently banned."
            ]
        ]
        let resolvedReportId = reportId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedReportId, !resolvedReportId.isEmpty {
            payload["bannedReportId"] = resolvedReportId
        } else {
            payload["bannedReportId"] = FieldValue.delete()
        }
        // Hide from History while actively banned; lastBanLiftedAt is rewritten on next lift.
        payload["lastBanLiftedAt"] = FieldValue.delete()

        try await userRef.setData(payload, merge: true)
        try await closeActiveFreezeHistory(userId: userId, status: .banned)
        try await closeActiveBanHistory(userId: userId, status: .lifted)
        // Best-effort separate collection (may fail until Firestore rules allow moderationBans).
        try? await createBanHistoryRecord(
            userId: userId,
            userData: userData,
            reportId: resolvedReportId,
            status: .active
        )

        if let resolvedReportId, !resolvedReportId.isEmpty,
           !resolvedReportId.hasPrefix("admin-freeze-"),
           !resolvedReportId.hasPrefix("admin-extend-"),
           !resolvedReportId.hasPrefix("admin-ban-") {
            try await applyReportModeration(
                reportId: resolvedReportId,
                status: "actioned",
                action: .ban
            )
        }
    }

    /// Unified moderation timeline for All profiles → History tab.
    func fetchAdminProfileModerationHistory(for userId: String) async throws -> [AdminProfileHistoryEvent] {
        try requireAdmin()
        let trimmedId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return [] }

        async let reportsTask = db.collection("reports")
            .whereField("reported_user_id", isEqualTo: trimmedId)
            .getDocuments()
        async let freezesTask = db.collection("moderationFreezes")
            .whereField("userId", isEqualTo: trimmedId)
            .getDocuments()
        async let bansTask = db.collection("moderationBans")
            .whereField("userId", isEqualTo: trimmedId)
            .getDocuments()
        async let warningsTask = db.collection("moderationWarnings")
            .whereField("userId", isEqualTo: trimmedId)
            .getDocuments()
        async let userTask = db.collection("users").document(trimmedId).getDocument()

        var events: [AdminProfileHistoryEvent] = []

        do {
            let snapshot = try await reportsTask
            for document in snapshot.documents {
                if let event = Self.parseReportHistoryEvent(documentID: document.documentID, data: document.data()) {
                    events.append(event)
                }
            }
        } catch {
            print("⚠️ Profile history reports failed: \(error.localizedDescription)")
        }

        do {
            let snapshot = try await freezesTask
            for document in snapshot.documents {
                events.append(contentsOf: Self.parseFreezeHistoryEvents(
                    documentID: document.documentID,
                    data: document.data()
                ))
            }
        } catch {
            print("⚠️ Profile history freezes failed: \(error.localizedDescription)")
        }

        do {
            let snapshot = try await bansTask
            for document in snapshot.documents {
                events.append(contentsOf: Self.parseBanHistoryEvents(
                    documentID: document.documentID,
                    data: document.data()
                ))
            }
        } catch {
            print("⚠️ Profile history bans failed: \(error.localizedDescription)")
        }

        do {
            let snapshot = try await warningsTask
            for document in snapshot.documents {
                if let event = Self.parseWarningHistoryEvent(documentID: document.documentID, data: document.data()) {
                    events.append(event)
                }
            }
        } catch {
            print("⚠️ Profile history warnings failed: \(error.localizedDescription)")
        }

        // Fallback from user doc when collection history is incomplete.
        if let userData = try? await userTask.data() {
            events.append(contentsOf: Self.fallbackHistoryEventsFromUser(userId: trimmedId, data: userData, existing: events))
        }

        return events.sorted { $0.date > $1.date }
    }

    /// Active bans for the admin banned-profiles screen.
    func fetchBannedProfilesForAdmin() async throws -> [BannedProfile] {
        try requireAdmin()

        let snapshot = try await db.collection("users")
            .whereField("isBanned", isEqualTo: true)
            .getDocuments()

        let profiles = snapshot.documents.compactMap { document -> BannedProfile? in
            Self.parseBannedProfile(documentID: document.documentID, data: document.data())
        }
        return profiles.sorted {
            ($0.bannedAt ?? .distantPast) > ($1.bannedAt ?? .distantPast)
        }
    }

    /// Past bans that were lifted by admin.
    /// Primary source: fields on the user document (works with existing admin user-update rules).
    /// Secondary: `moderationBans` collection when rules allow it.
    func fetchBanHistoryForAdmin() async throws -> [BannedProfile] {
        try requireAdmin()

        try? await reconcileOrphanedBanHistory()

        var profilesByUserId: [String: BannedProfile] = [:]

        // 1) User documents marked as previously banned / ban lifted.
        do {
            let snapshot = try await db.collection("users")
                .whereField("lastBanLiftedAt", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
                .getDocuments()

            for document in snapshot.documents {
                let data = document.data()
                guard data["isBanned"] as? Bool != true,
                      let profile = Self.parseLiftedBanFromUser(documentID: document.documentID, data: data)
                else { continue }
                profilesByUserId[profile.userId] = profile
            }
        } catch {
            print("⚠️ Unable to load user-based ban history: \(error.localizedDescription)")
        }

        // 2) Optional moderationBans collection.
        do {
            let snapshot = try await db.collection("moderationBans").getDocuments()
            for document in snapshot.documents {
                guard let profile = Self.parseBanHistoryProfile(
                    documentID: document.documentID,
                    data: document.data()
                ), profile.isHistoryItem else { continue }

                if let existing = profilesByUserId[profile.userId] {
                    let existingEnded = existing.endedAt ?? .distantPast
                    let newEnded = profile.endedAt ?? .distantPast
                    if newEnded >= existingEnded {
                        profilesByUserId[profile.userId] = profile
                    }
                } else {
                    profilesByUserId[profile.userId] = profile
                }
            }
        } catch {
            print("⚠️ Unable to load moderationBans history: \(error.localizedDescription)")
        }

        return profilesByUserId.values.sorted {
            ($0.endedAt ?? $0.bannedAt ?? .distantPast) > ($1.endedAt ?? $1.bannedAt ?? .distantPast)
        }
    }

    func removeAccountBan(userId: String) async throws {
        try requireAdmin()
        guard let adminUserId = auth.currentUser?.uid else {
            throw SpectRoomAuthError.notAuthenticated
        }

        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()
        let userData = snapshot.data() ?? [:]
        let bannedAt = (userData["bannedAt"] as? Timestamp)?.dateValue() ?? Date()
        let reportId = userData["bannedReportId"] as? String

        // Best-effort collection update (ignored if rules block it).
        let closedCount = (try? await closeActiveBanHistory(userId: userId, status: .lifted)) ?? 0
        if closedCount == 0 {
            try? await createBanHistoryRecord(
                userId: userId,
                userData: userData,
                reportId: reportId,
                status: .lifted
            )
        }

        // Authoritative history for the History tab — written on the user doc.
        let noticeId = "unban-\(userId)-\(Int(Date().timeIntervalSince1970))"
        var payload: [String: Any] = [
            "isBanned": FieldValue.delete(),
            "bannedAt": FieldValue.delete(),
            "bannedReportId": FieldValue.delete(),
            "pendingAccountBan": FieldValue.delete(),
            "lastBanLiftedAt": FieldValue.serverTimestamp(),
            "lastBannedAt": Timestamp(date: bannedAt),
            "pendingAccountUnban": [
                "notice_id": noticeId,
                "created_at": Date().timeIntervalSince1970,
                "acknowledged": false,
                // Lets the push function skip delivery when this device token is the admin's.
                "lifted_by": adminUserId,
                "message": "Your SpectRoom account ban has been lifted. You can log in again."
            ]
        ]
        if let reportId, !reportId.isEmpty {
            payload["lastBannedReportId"] = reportId
        } else {
            payload["lastBannedReportId"] = FieldValue.delete()
        }

        try await userRef.setData(payload, merge: true)
    }

    // MARK: - Freeze list / history

    /// Active freezes for the admin frozen-profiles screen.
    func fetchFrozenProfilesForAdmin() async throws -> [FrozenProfile] {
        try requireAdmin()

        // Best-effort: don't block the active list if history collection rules/indexes are missing.
        try? await expireStaleFreezeHistoryRecords()

        let now = Timestamp(date: Date())
        let snapshot = try await db.collection("users")
            .whereField("discoverFrozenUntil", isGreaterThan: now)
            .getDocuments()

        let profiles = snapshot.documents.compactMap { document -> FrozenProfile? in
            Self.parseFrozenProfile(documentID: document.documentID, data: document.data())
        }
        return profiles.sorted { $0.frozenUntil < $1.frozenUntil }
    }

    /// Past freezes (expired or lifted by admin). Banned entries are included for context.
    func fetchFreezeHistoryForAdmin() async throws -> [FrozenProfile] {
        try requireAdmin()
        try? await expireStaleFreezeHistoryRecords()

        var profiles: [FrozenProfile] = []

        do {
            let snapshot = try await db.collection("moderationFreezes").getDocuments()
            profiles = snapshot.documents.compactMap { document -> FrozenProfile? in
                Self.parseFreezeHistoryProfile(documentID: document.documentID, data: document.data())
            }
            .filter { $0.isHistoryItem }
        } catch {
            print("⚠️ Unable to load moderationFreezes history: \(error.localizedDescription)")
        }

        // Legacy: users whose freeze field is still present but already expired.
        do {
            let expiredUsers = try await db.collection("users")
                .whereField("discoverFrozenUntil", isLessThanOrEqualTo: Timestamp(date: Date()))
                .getDocuments()

            let historyUserIds = Set(profiles.map(\.userId))
            for document in expiredUsers.documents {
                let data = document.data()
                guard data["isBanned"] as? Bool != true,
                      let profile = Self.parseFrozenProfile(
                        documentID: document.documentID,
                        data: data,
                        forceStatus: .expired
                      ),
                      !historyUserIds.contains(profile.userId)
                else { continue }
                profiles.append(profile)
            }
        } catch {
            print("⚠️ Unable to load legacy expired freezes: \(error.localizedDescription)")
        }

        return profiles.sorted {
            ($0.endedAt ?? $0.frozenUntil) > ($1.endedAt ?? $1.frozenUntil)
        }
    }

    func removeAccountFreeze(userId: String) async throws {
        try requireAdmin()

        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()
        let userData = snapshot.data() ?? [:]

        // Ensure history exists even for freezes created before history tracking.
        do {
            let activeHistory = try await activeFreezeHistoryDocuments(userId: userId)
            if activeHistory.isEmpty,
               let until = Self.parseDiscoverFreezeUntil(from: userData),
               until > Date() || userData["discoverFreezeHours"] != nil {
                try await createFreezeHistoryRecord(
                    userId: userId,
                    userData: userData,
                    freezeUntil: until,
                    freezeHours: userData["discoverFreezeHours"] as? Int ?? 24,
                    reportId: userData["discoverFrozenReportId"] as? String,
                    status: .active
                )
            }
        } catch {
            print("⚠️ Unable to backfill freeze history before lift: \(error.localizedDescription)")
        }

        try await closeActiveFreezeHistory(userId: userId, status: .lifted)

        let noticeId = "unfreeze-\(userId)-\(Int(Date().timeIntervalSince1970))"
        try await userRef.setData([
            "discoverFrozenUntil": FieldValue.delete(),
            "discoverFreezeHours": FieldValue.delete(),
            "discoverFrozenReportId": FieldValue.delete(),
            "pendingAccountFreeze": FieldValue.delete(),
            "pendingAccountUnfreeze": [
                "notice_id": noticeId,
                "created_at": Date().timeIntervalSince1970,
                "message": "Your SpectRoom account freeze has been lifted. You can log in again."
            ]
        ], merge: true)
    }

    /// Extends an existing freeze by adding hours on top of the current unlock time.
    func extendAccountFreeze(
        userId: String,
        reportId: String?,
        duration: ModerationFreezeDuration
    ) async throws {
        try requireAdmin()

        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()
        let data = snapshot.data() ?? [:]
        let currentUntil = Self.parseDiscoverFreezeUntil(from: data)
        let base = max(currentUntil ?? Date(), Date())
        let freezeUntil = base.addingTimeInterval(TimeInterval(duration.rawValue * 3600))
        let totalHours = max(
            Int(ceil(freezeUntil.timeIntervalSinceNow / 3600)),
            duration.rawValue
        )
        let resolvedReportId = reportId
            ?? (data["discoverFrozenReportId"] as? String)
            ?? "admin-extend-\(userId)"

        // Unique report_id so the freeze push Cloud Function fires again on extend.
        let noticeReportId = "\(resolvedReportId)-ext-\(Int(Date().timeIntervalSince1970))"
        let unlockLabel = ModerationNotice.formattedUnlockDate(freezeUntil)

        try await userRef.setData([
            "discoverFrozenUntil": Timestamp(date: freezeUntil),
            "discoverFreezeHours": totalHours,
            "discoverFrozenReportId": resolvedReportId,
            "pendingAccountUnfreeze": FieldValue.delete(),
            "pendingAccountFreeze": [
                "report_id": noticeReportId,
                "kind": "extended",
                "freeze_until": freezeUntil.timeIntervalSince1970,
                "hours": totalHours,
                "created_at": Date().timeIntervalSince1970,
                "acknowledged": false,
                "message": String(
                    format: "Your account freeze has been extended. Try to login after %@.",
                    unlockLabel
                )
            ]
        ], merge: true)

        try await updateActiveFreezeHistory(
            userId: userId,
            freezeUntil: freezeUntil,
            freezeHours: totalHours,
            reportId: resolvedReportId,
            userData: data
        )
    }

    // MARK: - Freeze history helpers

    private func createFreezeHistoryRecord(
        userId: String,
        userData: [String: Any],
        freezeUntil: Date,
        freezeHours: Int,
        reportId: String?,
        status: FreezeRecordStatus
    ) async throws {
        let snapshot = Self.freezeUserSnapshot(from: userData)
        var payload: [String: Any] = [
            "userId": userId,
            "userName": snapshot.name,
            "userEmail": snapshot.email as Any,
            "userAge": snapshot.age as Any,
            "photoURL": snapshot.photoURL as Any,
            "freezeHours": freezeHours,
            "frozenUntil": Timestamp(date: freezeUntil),
            "reportId": reportId as Any,
            "status": status.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if status != .active {
            payload["endedAt"] = FieldValue.serverTimestamp()
        }
        try await db.collection("moderationFreezes").addDocument(data: payload)
    }

    private func activeFreezeHistoryDocuments(userId: String) async throws -> [QueryDocumentSnapshot] {
        let snapshot = try await db.collection("moderationFreezes")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: FreezeRecordStatus.active.rawValue)
            .getDocuments()
        return snapshot.documents
    }

    private func closeActiveFreezeHistory(userId: String, status: FreezeRecordStatus) async throws {
        do {
            let documents = try await activeFreezeHistoryDocuments(userId: userId)
            for document in documents {
                try await document.reference.setData([
                    "status": status.rawValue,
                    "endedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        } catch {
            print("⚠️ Unable to close freeze history for \(userId): \(error.localizedDescription)")
        }
    }

    private func updateActiveFreezeHistory(
        userId: String,
        freezeUntil: Date,
        freezeHours: Int,
        reportId: String?,
        userData: [String: Any]
    ) async throws {
        do {
            let documents = try await activeFreezeHistoryDocuments(userId: userId)
            if documents.isEmpty {
                try await createFreezeHistoryRecord(
                    userId: userId,
                    userData: userData,
                    freezeUntil: freezeUntil,
                    freezeHours: freezeHours,
                    reportId: reportId,
                    status: .active
                )
                return
            }
            for document in documents {
                try await document.reference.setData([
                    "frozenUntil": Timestamp(date: freezeUntil),
                    "freezeHours": freezeHours,
                    "reportId": reportId as Any,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        } catch {
            print("⚠️ Unable to update freeze history for \(userId): \(error.localizedDescription)")
        }
    }

    private func expireStaleFreezeHistoryRecords() async throws {
        do {
            let now = Timestamp(date: Date())
            let snapshot = try await db.collection("moderationFreezes")
                .whereField("status", isEqualTo: FreezeRecordStatus.active.rawValue)
                .whereField("frozenUntil", isLessThanOrEqualTo: now)
                .getDocuments()

            for document in snapshot.documents {
                try await document.reference.setData([
                    "status": FreezeRecordStatus.expired.rawValue,
                    "endedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        } catch {
            print("⚠️ Unable to expire stale freeze history: \(error.localizedDescription)")
        }
    }

    private struct FreezeUserSnapshot {
        let name: String
        let email: String?
        let age: Int?
        let photoURL: String?
    }

    private static func freezeUserSnapshot(from data: [String: Any]) -> FreezeUserSnapshot {
        let name = (data["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false) ? name! : "Unknown"
        var photoURL = data["profilePhotoURL"] as? String
        if photoURL == nil || photoURL?.isEmpty == true, let photos = data["photos"] as? [String] {
            photoURL = photos.first(where: { !$0.isEmpty })
        }
        return FreezeUserSnapshot(
            name: resolvedName,
            email: data["email"] as? String,
            age: data["age"] as? Int,
            photoURL: photoURL
        )
    }

    private static func parseFrozenProfile(
        documentID: String,
        data: [String: Any],
        forceStatus: FreezeRecordStatus? = nil
    ) -> FrozenProfile? {
        if forceStatus == nil, data["isBanned"] as? Bool == true { return nil }
        guard let frozenUntil = parseDiscoverFreezeUntil(from: data) else {
            return nil
        }
        if forceStatus == nil, frozenUntil <= Date() {
            return nil
        }

        let snapshot = freezeUserSnapshot(from: data)
        let hours = data["discoverFreezeHours"] as? Int
            ?? (data["pendingAccountFreeze"] as? [String: Any])?["hours"] as? Int
            ?? 24
        let reportId = data["discoverFrozenReportId"] as? String
            ?? (data["pendingAccountFreeze"] as? [String: Any])?["report_id"] as? String
        let status = forceStatus ?? .active

        return FrozenProfile(
            id: documentID,
            userId: documentID,
            historyRecordId: nil,
            name: snapshot.name,
            age: snapshot.age,
            email: snapshot.email,
            photoURL: snapshot.photoURL,
            frozenUntil: frozenUntil,
            freezeHours: hours,
            reportId: reportId,
            status: status,
            createdAt: nil,
            endedAt: forceStatus == nil ? nil : frozenUntil
        )
    }

    private static func parseFreezeHistoryProfile(documentID: String, data: [String: Any]) -> FrozenProfile? {
        guard let userId = data["userId"] as? String,
              let statusRaw = data["status"] as? String,
              let status = FreezeRecordStatus(rawValue: statusRaw)
        else {
            return nil
        }

        let frozenUntil: Date
        if let timestamp = data["frozenUntil"] as? Timestamp {
            frozenUntil = timestamp.dateValue()
        } else if let interval = data["frozenUntil"] as? TimeInterval {
            frozenUntil = Date(timeIntervalSince1970: interval)
        } else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        let name = (data["userName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false) ? name! : "Unknown"

        // Treat leftover "active" past-due rows as expired for display.
        let resolvedStatus: FreezeRecordStatus = {
            if status == .active, frozenUntil <= Date() { return .expired }
            return status
        }()

        return FrozenProfile(
            id: documentID,
            userId: userId,
            historyRecordId: documentID,
            name: resolvedName,
            age: data["userAge"] as? Int,
            email: data["userEmail"] as? String,
            photoURL: data["photoURL"] as? String,
            frozenUntil: frozenUntil,
            freezeHours: data["freezeHours"] as? Int ?? 24,
            reportId: data["reportId"] as? String,
            status: resolvedStatus,
            createdAt: createdAt,
            endedAt: endedAt ?? (resolvedStatus == .active ? nil : frozenUntil)
        )
    }

    // MARK: - Ban history helpers

    private func createWarningHistoryRecord(
        userId: String,
        message: String,
        reportId: String?,
        noticeId: String
    ) async throws {
        var payload: [String: Any] = [
            "userId": userId,
            "message": message,
            "noticeId": noticeId,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let reportId, !reportId.isEmpty {
            payload["reportId"] = reportId
        }
        try await db.collection("moderationWarnings").addDocument(data: payload)
    }

    private func createBanHistoryRecord(
        userId: String,
        userData: [String: Any],
        reportId: String?,
        status: BanRecordStatus
    ) async throws {
        let snapshot = Self.freezeUserSnapshot(from: userData)
        var payload: [String: Any] = [
            "userId": userId,
            "userName": snapshot.name,
            "status": status.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let email = snapshot.email { payload["userEmail"] = email }
        if let age = snapshot.age { payload["userAge"] = age }
        if let photoURL = snapshot.photoURL { payload["photoURL"] = photoURL }
        if let reportId, !reportId.isEmpty { payload["reportId"] = reportId }
        if status != .active {
            payload["endedAt"] = FieldValue.serverTimestamp()
        }
        try await db.collection("moderationBans").addDocument(data: payload)
    }

    private func activeBanHistoryDocuments(userId: String) async throws -> [QueryDocumentSnapshot] {
        // Single-field query only — no composite index required.
        let snapshot = try await db.collection("moderationBans")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents.filter {
            ($0.data()["status"] as? String) == BanRecordStatus.active.rawValue
        }
    }

    @discardableResult
    private func closeActiveBanHistory(userId: String, status: BanRecordStatus) async throws -> Int {
        do {
            let documents = try await activeBanHistoryDocuments(userId: userId)
            for document in documents {
                try await document.reference.setData([
                    "status": status.rawValue,
                    "endedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
            return documents.count
        } catch {
            print("⚠️ Unable to close ban history for \(userId): \(error.localizedDescription)")
            return 0
        }
    }

    /// Marks leftover "active" ban history rows as lifted when the user is no longer banned.
    private func reconcileOrphanedBanHistory() async throws {
        do {
            let snapshot = try await db.collection("moderationBans").getDocuments()
            let activeDocs = snapshot.documents.filter {
                ($0.data()["status"] as? String) == BanRecordStatus.active.rawValue
            }
            guard !activeDocs.isEmpty else { return }

            let userIds = Set(activeDocs.compactMap { $0.data()["userId"] as? String })
            var stillBanned = Set<String>()
            for userId in userIds {
                let userSnap = try await db.collection("users").document(userId).getDocument()
                if userSnap.data()?["isBanned"] as? Bool == true {
                    stillBanned.insert(userId)
                }
            }

            for document in activeDocs {
                guard let userId = document.data()["userId"] as? String,
                      !stillBanned.contains(userId)
                else { continue }
                try await document.reference.setData([
                    "status": BanRecordStatus.lifted.rawValue,
                    "endedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        } catch {
            print("⚠️ Unable to reconcile orphaned ban history: \(error.localizedDescription)")
        }
    }

    private static func parseBannedProfile(documentID: String, data: [String: Any]) -> BannedProfile? {
        guard data["isBanned"] as? Bool == true else { return nil }
        let snapshot = freezeUserSnapshot(from: data)
        let bannedAt = (data["bannedAt"] as? Timestamp)?.dateValue()
        return BannedProfile(
            id: documentID,
            userId: documentID,
            historyRecordId: nil,
            name: snapshot.name,
            age: snapshot.age,
            email: snapshot.email,
            photoURL: snapshot.photoURL,
            reportId: data["bannedReportId"] as? String,
            status: .active,
            bannedAt: bannedAt,
            endedAt: nil
        )
    }

    /// History entry from user fields written when a ban is removed.
    private static func parseLiftedBanFromUser(documentID: String, data: [String: Any]) -> BannedProfile? {
        let liftedAt: Date?
        if let timestamp = data["lastBanLiftedAt"] as? Timestamp {
            liftedAt = timestamp.dateValue()
        } else if let interval = data["lastBanLiftedAt"] as? TimeInterval {
            liftedAt = Date(timeIntervalSince1970: interval)
        } else {
            return nil
        }

        let bannedAt: Date?
        if let timestamp = data["lastBannedAt"] as? Timestamp {
            bannedAt = timestamp.dateValue()
        } else if let interval = data["lastBannedAt"] as? TimeInterval {
            bannedAt = Date(timeIntervalSince1970: interval)
        } else if let timestamp = data["bannedAt"] as? Timestamp {
            bannedAt = timestamp.dateValue()
        } else {
            bannedAt = nil
        }

        let snapshot = freezeUserSnapshot(from: data)
        return BannedProfile(
            id: "lifted-\(documentID)",
            userId: documentID,
            historyRecordId: nil,
            name: snapshot.name,
            age: snapshot.age,
            email: snapshot.email,
            photoURL: snapshot.photoURL,
            reportId: data["lastBannedReportId"] as? String ?? data["bannedReportId"] as? String,
            status: .lifted,
            bannedAt: bannedAt,
            endedAt: liftedAt
        )
    }

    private static func parseBanHistoryProfile(documentID: String, data: [String: Any]) -> BannedProfile? {
        guard let userId = data["userId"] as? String,
              let statusRaw = data["status"] as? String,
              let status = BanRecordStatus(rawValue: statusRaw)
        else {
            return nil
        }

        let name = (data["userName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false) ? name! : "Unknown"
        let bannedAt = (data["createdAt"] as? Timestamp)?.dateValue()
        let endedAt = (data["endedAt"] as? Timestamp)?.dateValue()

        return BannedProfile(
            id: documentID,
            userId: userId,
            historyRecordId: documentID,
            name: resolvedName,
            age: data["userAge"] as? Int,
            email: data["userEmail"] as? String,
            photoURL: data["photoURL"] as? String,
            reportId: data["reportId"] as? String,
            status: status,
            bannedAt: bannedAt,
            endedAt: endedAt
        )
    }

    func clearPendingSystemWarning() async throws {
        guard let userId = auth.currentUser?.uid else { return }
        try await db.collection("users").document(userId).updateData([
            "pendingSystemWarning": FieldValue.delete()
        ])
    }

    func clearPendingAccountFreezeNotice() async throws {
        guard let userId = auth.currentUser?.uid else { return }
        // Keep discoverFrozenUntil — only clear the acknowledgment payload.
        try await db.collection("users").document(userId).updateData([
            "pendingAccountFreeze": FieldValue.delete()
        ])
    }

    func clearPendingAccountBanNotice() async throws {
        guard let userId = auth.currentUser?.uid else { return }
        // Keep fcmToken so a later ban-lift push can still be delivered.
        try await db.collection("users").document(userId).updateData([
            "pendingAccountBan": FieldValue.delete()
        ])
    }

    func clearPendingAccountUnbanNotice() async throws {
        guard let userId = auth.currentUser?.uid else { return }
        try await db.collection("users").document(userId).updateData([
            "pendingAccountUnban": FieldValue.delete()
        ])
    }

    func fetchPendingModerationNotice(preferServer: Bool = false) async throws -> ModerationNotice? {
        guard let userData = try await fetchUserData(preferServer: preferServer) else { return nil }

        if userData["isBanned"] as? Bool == true {
            return ModerationNotice(kind: .banAcknowledgement)
        }

        if let unban = userData["pendingAccountUnban"] as? [String: Any],
           (unban["acknowledged"] as? Bool) != true {
            return ModerationNotice(kind: .banLifted)
        }

        if let freeze = userData["pendingAccountFreeze"] as? [String: Any],
           (freeze["acknowledged"] as? Bool) != true,
           let until = Self.parseFreezeUntilValue(freeze["freeze_until"]) ?? Self.parseDiscoverFreezeUntil(from: userData),
           until > Date() {
            let hours = freeze["hours"] as? Int
                ?? userData["discoverFreezeHours"] as? Int
                ?? 24
            return ModerationNotice(kind: .freezeAcknowledgement(until: until, hours: hours))
        }

        if let warning = userData["pendingSystemWarning"] as? [String: Any],
           (warning["acknowledged"] as? Bool) != true {
            let message = (warning["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = (message?.isEmpty == false)
                ? message!
                : "admin.warning.default.message".localized
            return ModerationNotice(kind: .warning(message: resolved))
        }

        // Session restored while freeze is still active (notice already cleared).
        if let until = Self.parseDiscoverFreezeUntil(from: userData), until > Date() {
            let hours = userData["discoverFreezeHours"] as? Int ?? 24
            return ModerationNotice(kind: .freezeAcknowledgement(until: until, hours: hours))
        }

        return nil
    }

    func fetchPendingSystemWarning() async throws -> String? {
        try await fetchPendingModerationNotice().map(\.message)
    }

    private static func parseFreezeUntilValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    private func requireAdmin() throws {
        guard AdminAccess.isAdmin(email: auth.currentUser?.email) else {
            throw SpectRoomAuthError.notAdmin
        }
    }

    // MARK: - Admin dashboard

    /// Aggregate health metrics for the admin dashboard.
    func fetchAdminDashboardStats() async throws -> AdminDashboardStats {
        try requireAdmin()

        async let usersTask = db.collection("users").getDocuments()
        async let reportsTask = db.collection("reports").getDocuments()

        let usersSnapshot = try await usersTask
        let reportsSnapshot = try await reportsTask

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        var totalUsers = 0
        var activeUsers = 0
        var onlineUsers = 0
        var newRegistrationsToday = 0
        var activeBans = 0
        var activeFreezes = 0

        let now = Date()
        for document in usersSnapshot.documents {
            let data = document.data()
            totalUsers += 1

            let isBanned = data["isBanned"] as? Bool == true
            let isDeleted = data["isDeleted"] as? Bool == true
            if isBanned { activeBans += 1 }
            if !isBanned && !isDeleted { activeUsers += 1 }
            if !isBanned && !isDeleted, data["isOnline"] as? Bool == true {
                onlineUsers += 1
            }

            if let frozenUntil = Self.parseDiscoverFreezeUntil(from: data), frozenUntil > now, !isBanned {
                activeFreezes += 1
            }

            if let createdAt = Self.parseDashboardDate(from: data["createdAt"]),
               createdAt >= startOfToday {
                newRegistrationsToday += 1
            }
        }

        var pendingReports = 0
        var reportsResolvedToday = 0
        for document in reportsSnapshot.documents {
            let data = document.data()
            let status = (data["status"] as? String ?? "pending").lowercased()
            if status == "pending" {
                pendingReports += 1
            } else if status == "actioned" || status == "dismissed" || status == "reviewed" {
                if let resolvedAt = Self.parseDashboardDate(from: data["moderated_at"])
                    ?? Self.parseDashboardDate(from: data["createdAt"]),
                   resolvedAt >= startOfToday {
                    reportsResolvedToday += 1
                }
            }
        }

        return AdminDashboardStats(
            totalUsers: totalUsers,
            activeUsers: activeUsers,
            onlineUsers: onlineUsers,
            pendingReports: pendingReports,
            newRegistrationsToday: newRegistrationsToday,
            activeBans: activeBans,
            activeFreezes: activeFreezes,
            reportsResolvedToday: reportsResolvedToday
        )
    }

    private static func parseDashboardDate(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    // MARK: - Admin all profiles

    struct AdminUsersPage {
        let users: [AdminUserProfile]
        let lastDocumentId: String?
        let hasMore: Bool
        /// Full matching total from the DB (not just this page). Nil when unknown.
        let totalCount: Int?

        init(
            users: [AdminUserProfile],
            lastDocumentId: String?,
            hasMore: Bool,
            totalCount: Int? = nil
        ) {
            self.users = users
            self.lastDocumentId = lastDocumentId
            self.hasMore = hasMore
            self.totalCount = totalCount
        }
    }

    enum AdminUsersCountFilter {
        case all
        case frozen
        case banned
        case deleted
        case incomplete
    }

    /// Server-side total for All profiles (and status filters). Uses Firestore aggregation
    /// where possible; incomplete uses a full evaluate pass so it matches the Incomplete list.
    func fetchAdminUsersTotalCount(filter: AdminUsersCountFilter) async throws -> Int {
        try requireAdmin()

        switch filter {
        case .all:
            return try await aggregationCount(for: db.collection("users"))
        case .deleted:
            return try await aggregationCount(
                for: db.collection("users").whereField("isDeleted", isEqualTo: true)
            )
        case .banned:
            return try await aggregationCount(
                for: db.collection("users").whereField("isBanned", isEqualTo: true)
            )
        case .frozen:
            return try await aggregationCount(
                for: db.collection("users")
                    .whereField("discoverFrozenUntil", isGreaterThan: Timestamp(date: Date()))
            )
        case .incomplete:
            let snapshot = try await db.collection("users").getDocuments()
            return snapshot.documents.reduce(0) { partial, document in
                guard let profile = Self.parseAdminUserProfile(document: document) else {
                    return partial
                }
                return (profile.isIncomplete && !profile.isDeleted) ? partial + 1 : partial
            }
        }
    }

    private func aggregationCount(for query: Query) async throws -> Int {
        let snapshot = try await query.count.getAggregation(source: .server)
        return Int(truncating: snapshot.count)
    }

    /// Paginated users for Admin → All profiles (includes banned / frozen / deleted).
    func fetchAdminUsersPage(limit: Int = 25, startAfterDocumentId: String? = nil) async throws -> AdminUsersPage {
        try requireAdmin()

        var query: Query = db.collection("users")
            .order(by: FieldPath.documentID())
            .limit(to: limit)

        if let startAfterDocumentId {
            let previousDoc = try await db.collection("users").document(startAfterDocumentId).getDocument()
            if previousDoc.exists {
                query = query.start(afterDocument: previousDoc)
            }
        }

        let snapshot = try await query.getDocuments()
        let parsed = snapshot.documents.compactMap { document in
            Self.parseAdminUserProfile(document: document)
        }
        let users = await enrichAdminProfilesFromAuth(parsed)
        return AdminUsersPage(
            users: users,
            lastDocumentId: snapshot.documents.last?.documentID,
            hasMore: snapshot.documents.count == limit
        )
    }

    /// Incomplete sign-ups for Admin → All profiles.
    /// Uses `profileStatus == incomplete` when present, and also includes profiles that are
    /// unfinished but missing the field (common for older / mid-completion accounts).
    func fetchIncompleteAdminUsersPage(limit: Int = 25, startAfterDocumentId: String? = nil) async throws -> AdminUsersPage {
        try requireAdmin()

        let snapshot = try await db.collection("users").getDocuments()
        let parsed = snapshot.documents.compactMap { document in
            Self.parseAdminUserProfile(document: document)
        }
        let enriched = await enrichAdminProfilesFromAuth(parsed)
        let incomplete = enriched
            .filter { $0.isIncomplete && !$0.isDeleted }
            .sorted { lhs, rhs in
                (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }

        // Backfill missing profileStatus so future indexed queries stay accurate.
        if startAfterDocumentId == nil {
            Task {
                await self.backfillMissingIncompleteProfileStatus(from: snapshot.documents)
            }
        }

        let startIndex: Int
        if let startAfterDocumentId,
           let index = incomplete.firstIndex(where: { $0.id == startAfterDocumentId }) {
            startIndex = index + 1
        } else {
            startIndex = 0
        }

        let page = Array(incomplete.dropFirst(startIndex).prefix(limit))
        return AdminUsersPage(
            users: page,
            lastDocumentId: page.last?.id,
            hasMore: startIndex + page.count < incomplete.count,
            totalCount: incomplete.count
        )
    }

    private func backfillMissingIncompleteProfileStatus(from documents: [QueryDocumentSnapshot]) async {
        for document in documents {
            let data = document.data()
            let evaluated = UserProfileStatus.evaluate(from: data)
            let stored = (data[UserProfileStatus.firestoreKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard stored != evaluated.rawValue else { continue }
            do {
                try await db.collection("users").document(document.documentID).setData([
                    UserProfileStatus.firestoreKey: evaluated.rawValue
                ], merge: true)
            } catch {
                print("⚠️ Failed syncing profileStatus for \(document.documentID): \(error.localizedDescription)")
            }
        }
    }

    /// Name / email search for Admin → All profiles (scans users collection, filtered client-side).
    func searchAdminUsers(query: String, limit: Int = 80) async throws -> [AdminUserProfile] {
        try requireAdmin()

        let trimmed = Self.normalizedAdminSearchQuery(query)
        guard trimmed.count >= 2 else { return [] }

        var matchesById: [String: AdminUserProfile] = [:]

        // Fast path for full / near-full emails (indexed equality + common casing).
        if trimmed.contains("@") {
            let exactSnapshot = try await db.collection("users")
                .whereField("email", isEqualTo: trimmed)
                .limit(to: limit)
                .getDocuments()
            for document in exactSnapshot.documents {
                if let profile = Self.parseAdminUserProfile(document: document) {
                    matchesById[profile.id] = profile
                }
            }
        }

        // Full scan so partial email / name queries still work (e.g. "test20", "yopmail").
        let snapshot = try await db.collection("users").getDocuments()
        for document in snapshot.documents {
            guard let profile = Self.parseAdminUserProfile(document: document) else {
                continue
            }
            guard Self.adminProfileMatchesSearch(profile, query: trimmed) else { continue }
            matchesById[profile.id] = profile
        }

        // Fill Auth emails for matches whose Firestore docs omitted `email`.
        let enriched = await enrichAdminProfilesFromAuth(Array(matchesById.values))

        let matches = enriched.sorted { lhs, rhs in
            let lhsEmail = lhs.email.lowercased()
            let rhsEmail = rhs.email.lowercased()
            let lhsExact = !lhsEmail.isEmpty && lhsEmail == trimmed
            let rhsExact = !rhsEmail.isEmpty && rhsEmail == trimmed
            if lhsExact != rhsExact { return lhsExact && !rhsExact }

            let lhsEmailHit = !lhsEmail.isEmpty && lhsEmail.contains(trimmed)
            let rhsEmailHit = !rhsEmail.isEmpty && rhsEmail.contains(trimmed)
            if lhsEmailHit != rhsEmailHit { return lhsEmailHit && !rhsEmailHit }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return Array(matches.prefix(limit))
    }

    /// Fill missing email / name / createdAt from Auth when Firestore docs are incomplete.
    private func enrichAdminProfilesFromAuth(_ profiles: [AdminUserProfile]) async -> [AdminUserProfile] {
        let missingIds = profiles
            .filter { profile in
                profile.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || Self.isPlaceholderAdminName(profile.name)
                    || profile.createdAt == nil
            }
            .map(\.id)
        guard !missingIds.isEmpty else { return profiles }

        do {
            let lookup = try await resolveAdminUserIdentities(userIds: missingIds)
            guard !lookup.emails.isEmpty || !lookup.names.isEmpty || !lookup.createdAts.isEmpty else {
                return profiles
            }
            return profiles.map { profile in
                var updated = profile
                let existingEmail = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
                if existingEmail.isEmpty, let email = lookup.emails[profile.id], !email.isEmpty {
                    updated = updated.withEmail(email)
                }
                if Self.isPlaceholderAdminName(updated.name),
                   let name = lookup.names[profile.id],
                   !Self.isPlaceholderAdminName(name) {
                    updated = updated.withName(name)
                }
                if updated.createdAt == nil, let createdAt = lookup.createdAts[profile.id] {
                    updated = updated.withCreatedAt(createdAt)
                }
                return updated
            }
        } catch {
            print("⚠️ resolveAdminUserEmails failed: \(error.localizedDescription)")
            return profiles
        }
    }

    private struct AdminAuthIdentityLookup {
        var emails: [String: String] = [:]
        var names: [String: String] = [:]
        var createdAts: [String: Date] = [:]
    }

    /// Soft-deletes the Firestore profile (kept for admin as Deleted) and removes Auth so login/MFA cannot continue.
    /// Schedules hard purge after 14 days via `scheduledHardDeleteAt` (same as user self-delete).
    /// Admin-only; cannot delete the signed-in admin or other configured admin accounts.
    func hardDeleteAdminUser(userId: String) async throws {
        try requireAdmin()
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "User id required"]
            )
        }
        if trimmed == Auth.auth().currentUser?.uid {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "You cannot delete your own admin account"]
            )
        }

        _ = try await Functions.functions(region: "us-central1")
            .httpsCallable("adminHardDeleteUser")
            .call(["userId": trimmed])

        // Record actor even if the callable omits it (needed for admin Deleted profiles UI).
        try? await db.collection("users").document(trimmed).setData([
            "deletedBy": "admin",
            "lastDeletedBy": "admin",
            "deletedByAdmin": true,
            "lastDeletedByAdmin": true
        ], merge: true)
    }

    /// Restores a soft-deleted account (clears delete flags, recreates Auth if needed).
    func undeleteAdminUser(userId: String) async throws {
        try requireAdmin()
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "User id required"]
            )
        }

        _ = try await Functions.functions(region: "us-central1")
            .httpsCallable("adminUndeleteUser")
            .call(["userId": trimmed])
    }

    /// Soft-deleted + fully purged tombstones for Restrict → Deleted profiles.
    func fetchDeletedProfilesForAdmin() async throws -> [DeletedProfile] {
        try requireAdmin()

        var profilesByUserId: [String: DeletedProfile] = [:]

        let softDeleted = try await db.collection("users")
            .whereField("isDeleted", isEqualTo: true)
            .getDocuments()
        for document in softDeleted.documents {
            if let profile = Self.parseDeletedProfile(documentID: document.documentID, data: document.data()) {
                profilesByUserId[profile.userId] = profile
            }
        }

        do {
            let records = try await db.collection("deletedAccountRecords").getDocuments()
            for document in records.documents {
                guard let profile = Self.parseFullyDeletedAccountRecord(
                    documentID: document.documentID,
                    data: document.data()
                ) else { continue }
                // Soft-deleted live users take precedence over an older tombstone.
                if profilesByUserId[profile.userId] == nil {
                    profilesByUserId[profile.userId] = profile
                }
            }
        } catch {
            print("⚠️ Unable to load deletedAccountRecords: \(error.localizedDescription)")
        }

        return profilesByUserId.values.sorted {
            ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
        }
    }

    /// Accounts that were deleted and later restored by admin.
    func fetchDeleteHistoryForAdmin() async throws -> [DeletedProfile] {
        try requireAdmin()

        var profilesByUserId: [String: DeletedProfile] = [:]

        do {
            let snapshot = try await db.collection("users")
                .whereField("lastAccountRestoredAt", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
                .getDocuments()

            for document in snapshot.documents {
                let data = document.data()
                guard data["isDeleted"] as? Bool != true,
                      let profile = Self.parseRestoredDeleteFromUser(documentID: document.documentID, data: data)
                else { continue }
                profilesByUserId[profile.userId] = profile
            }
        } catch {
            print("⚠️ Unable to load user-based delete history: \(error.localizedDescription)")
        }

        return profilesByUserId.values.sorted {
            ($0.restoredAt ?? $0.deletedAt ?? .distantPast) > ($1.restoredAt ?? $1.deletedAt ?? .distantPast)
        }
    }

    private static func parseDeletedByActor(from data: [String: Any], preferLast: Bool = false) -> DeletedByActor {
        // Explicit string fields (newer admin/client writes).
        let primaryKeys = preferLast
            ? ["lastDeletedBy", "deletedBy", "deleted_by"]
            : ["deletedBy", "deleted_by", "lastDeletedBy"]
        for key in primaryKeys {
            if let raw = data[key] as? String {
                let parsed = DeletedByActor.parse(from: raw)
                if parsed != .unknown { return parsed }
            }
        }

        // Existing Cloud Function / registry flags.
        let adminFlags = preferLast
            ? ["lastDeletedByAdmin", "deletedByAdmin"]
            : ["deletedByAdmin", "lastDeletedByAdmin"]
        for key in adminFlags {
            if data[key] as? Bool == true {
                return .admin
            }
        }

        if data["pendingAccountDeleted"] is [String: Any] {
            return .admin
        }

        // Self-delete and admin delete both schedule hard purge via this field.
        // Prefer deletedByAdmin / pendingAccountDeleted above when present.
        if data["scheduledHardDeleteAt"] != nil {
            return .user
        }

        // Active soft-delete without admin markers is a user self-delete.
        if !preferLast, data["isDeleted"] as? Bool == true {
            return .user
        }

        return .unknown
    }

    private static func parseEpochDate(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    private static func parseDeletedProfile(documentID: String, data: [String: Any]) -> DeletedProfile? {
        guard data["isDeleted"] as? Bool == true else { return nil }
        let snapshot = freezeUserSnapshot(from: data)
        let deletedAt = parseEpochDate(from: data["deletedAt"])
        let fullyDeletedAt = parseEpochDate(from: data["scheduledHardDeleteAt"])

        return DeletedProfile(
            id: documentID,
            userId: documentID,
            name: snapshot.name,
            age: snapshot.age,
            email: snapshot.email,
            photoURL: snapshot.photoURL,
            status: .active,
            deletedBy: parseDeletedByActor(from: data),
            deletedAt: deletedAt,
            fullyDeletedAt: fullyDeletedAt,
            restoredAt: nil
        )
    }

    private static func parseFullyDeletedAccountRecord(documentID: String, data: [String: Any]) -> DeletedProfile? {
        guard data["isFullyDeleted"] as? Bool == true else { return nil }
        let snapshot = freezeUserSnapshot(from: data)
        let userId = (data["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUserId = (userId?.isEmpty == false) ? userId! : documentID

        return DeletedProfile(
            id: "fully-\(resolvedUserId)",
            userId: resolvedUserId,
            name: snapshot.name,
            age: snapshot.age,
            email: snapshot.email,
            photoURL: snapshot.photoURL,
            status: .fullyDeleted,
            deletedBy: parseDeletedByActor(from: data),
            deletedAt: parseEpochDate(from: data["deletedAt"]),
            fullyDeletedAt: parseEpochDate(from: data["fullyDeletedAt"]),
            restoredAt: nil
        )
    }

    private static func parseRestoredDeleteFromUser(documentID: String, data: [String: Any]) -> DeletedProfile? {
        let restoredAt = parseEpochDate(from: data["lastAccountRestoredAt"])
        guard restoredAt != nil else { return nil }

        let deletedAt = parseEpochDate(from: data["lastDeletedAt"])
        let snapshot = freezeUserSnapshot(from: data)
        return DeletedProfile(
            id: "restored-\(documentID)",
            userId: documentID,
            name: snapshot.name,
            age: snapshot.age,
            email: snapshot.email,
            photoURL: snapshot.photoURL,
            status: .restored,
            deletedBy: parseDeletedByActor(from: data, preferLast: true),
            deletedAt: deletedAt,
            fullyDeletedAt: nil,
            restoredAt: restoredAt
        )
    }

    private func resolveAdminUserIdentities(userIds: [String]) async throws -> AdminAuthIdentityLookup {
        let uniqueIds = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !uniqueIds.isEmpty else { return AdminAuthIdentityLookup() }

        let result = try await Functions.functions(region: "us-central1")
            .httpsCallable("resolveAdminUserEmails")
            .call(["userIds": uniqueIds])

        guard let data = result.data as? [String: Any] else {
            print("⚠️ resolveAdminUserEmails returned unexpected payload: \(String(describing: result.data))")
            return AdminAuthIdentityLookup()
        }

        return AdminAuthIdentityLookup(
            emails: Self.stringMap(from: data["emails"]),
            names: Self.stringMap(from: data["names"]),
            createdAts: Self.dateMap(from: data["createdAts"])
        )
    }

    private static func dateMap(from value: Any?) -> [String: Date] {
        guard let raw = value as? [String: Any] else { return [:] }
        var result: [String: Date] = [:]
        for (key, rawValue) in raw {
            if let interval = timeIntervalValue(rawValue), interval > 0 {
                result[key] = Date(timeIntervalSince1970: interval)
            } else if let string = rawValue as? String,
                      let date = ISO8601DateFormatter().date(from: string) {
                result[key] = date
            }
        }
        return result
    }

    private static func stringMap(from value: Any?) -> [String: String] {
        if let emails = value as? [String: String] {
            return emails.filter { !$0.value.isEmpty }
        }
        if let emails = value as? [String: Any] {
            var mapped: [String: String] = [:]
            for (uid, raw) in emails {
                if let email = raw as? String, !email.isEmpty {
                    mapped[uid] = email
                }
            }
            return mapped
        }
        return [:]
    }

    private static func isPlaceholderAdminName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lowered = trimmed.lowercased()
        return lowered == "unknown" || lowered == "unknown user"
    }

    private static func normalizedAdminSearchQuery(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .lowercased()
    }

    private static func adminProfileMatchesSearch(_ profile: AdminUserProfile, query: String) -> Bool {
        let name = profile.name.lowercased()
        let email = profile.email.lowercased()
        if name.contains(query) { return true }
        if !email.isEmpty, email.contains(query) { return true }
        // Match local-part only when the query looks like an email ("test20@…" → "test20").
        if query.contains("@"), let local = query.split(separator: "@").first, local.count >= 2 {
            if email.hasPrefix(String(local) + "@") { return true }
        }
        return false
    }

    /// Latest conversation previews for a given user (admin-only).
    func fetchAdminRecentConversations(for userId: String, limit: Int = 40) async throws -> [AdminRecentConversation] {
        try requireAdmin()

        let recentLimit = 100
        // Load each collection independently so a rules denial on one side
        // (or on users with no message docs) does not surface as a hard error.
        async let sentDocsTask = fetchAdminMessageDocuments(
            userId: userId,
            collection: "sentMessages",
            limit: recentLimit
        )
        async let incomingDocsTask = fetchAdminMessageDocuments(
            userId: userId,
            collection: "incomingMessages",
            limit: recentLimit
        )

        let sentDocuments = try await sentDocsTask
        let incomingDocuments = try await incomingDocsTask

        struct Candidate {
            let partnerId: String
            let preview: String
            let createdAt: TimeInterval
            let isOutgoing: Bool
        }

        var latestByPartner: [String: Candidate] = [:]

        for document in sentDocuments {
            let data = document.data()
            guard let partnerId = data["recipientId"] as? String,
                  let createdAt = Self.timeIntervalValue(data["createdAt"]) else { continue }
            if let existing = latestByPartner[partnerId], existing.createdAt >= createdAt { continue }
            latestByPartner[partnerId] = Candidate(
                partnerId: partnerId,
                preview: Self.adminMessagePreview(from: data),
                createdAt: createdAt,
                isOutgoing: true
            )
        }

        for document in incomingDocuments {
            let data = document.data()
            guard let partnerId = data["senderId"] as? String,
                  let createdAt = Self.timeIntervalValue(data["createdAt"]) else { continue }
            if let existing = latestByPartner[partnerId], existing.createdAt >= createdAt { continue }
            latestByPartner[partnerId] = Candidate(
                partnerId: partnerId,
                preview: Self.adminMessagePreview(from: data),
                createdAt: createdAt,
                isOutgoing: false
            )
        }

        let summaries = await fetchUserSummaries(for: Array(latestByPartner.keys))
        let conversations = latestByPartner.values.map { candidate in
            let summary = summaries[candidate.partnerId]
            return AdminRecentConversation(
                id: candidate.partnerId,
                partnerId: candidate.partnerId,
                partnerName: summary?.name ?? "Unknown",
                partnerPhotoURL: summary?.photoURL,
                preview: candidate.preview,
                isOutgoing: candidate.isOutgoing,
                createdAt: Date(timeIntervalSince1970: candidate.createdAt)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }

        return Array(conversations.prefix(limit))
    }

    /// Reads a user's message collection for admin review.
    /// Permission-denied is treated as empty so users with no chats don't show a Firestore rules error.
    private func fetchAdminMessageDocuments(
        userId: String,
        collection: String,
        limit: Int
    ) async throws -> [QueryDocumentSnapshot] {
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection(collection)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents
        } catch {
            if Self.isFirestorePermissionDenied(error) {
                print("⚠️ Admin \(collection) read denied for \(userId) — treating as empty. Ensure Firestore rules allow isAdmin() on message subcollections.")
                return []
            }
            throw error
        }
    }

    private static func isFirestorePermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return true
        }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("insufficient permissions") || message.contains("permission denied")
    }

    /// Filtered message docs for admin thread view; permission-denied → empty.
    private func fetchAdminFilteredMessageDocuments(
        collection: String,
        filterField: String,
        filterValue: String,
        userId: String,
        limit: Int
    ) async throws -> [QueryDocumentSnapshot] {
        do {
            return try await fetchFilteredMessageDocuments(
                collection: collection,
                filterField: filterField,
                filterValue: filterValue,
                userId: userId,
                limit: limit,
                before: nil
            )
        } catch {
            if Self.isFirestorePermissionDenied(error) {
                print("⚠️ Admin filtered \(collection) read denied for \(userId) — treating as empty.")
                return []
            }
            throw error
        }
    }


    /// Last N messages between a subject user and a partner (admin-only). Chronological order.
    func fetchAdminConversationMessages(
        subjectUserId: String,
        partnerId: String,
        limit: Int = 20
    ) async throws -> [AdminConversationMessage] {
        try requireAdmin()

        async let sentDocsTask = fetchAdminFilteredMessageDocuments(
            collection: "sentMessages",
            filterField: "recipientId",
            filterValue: partnerId,
            userId: subjectUserId,
            limit: limit
        )
        async let incomingDocsTask = fetchAdminFilteredMessageDocuments(
            collection: "incomingMessages",
            filterField: "senderId",
            filterValue: partnerId,
            userId: subjectUserId,
            limit: limit
        )

        let sentDocs = try await sentDocsTask
        let incomingDocs = try await incomingDocsTask

        var merged: [AdminConversationMessage] = []

        for document in sentDocs {
            if let message = Self.parseAdminConversationMessage(
                documentID: document.documentID,
                data: document.data(),
                isFromSubject: true
            ) {
                merged.append(message)
            }
        }

        for document in incomingDocs {
            if let message = Self.parseAdminConversationMessage(
                documentID: document.documentID,
                data: document.data(),
                isFromSubject: false
            ) {
                merged.append(message)
            }
        }

        // Newest first from queries — keep the most recent `limit`, then show oldest→newest.
        merged.sort { $0.createdAt > $1.createdAt }
        return Array(merged.prefix(limit)).sorted { $0.createdAt < $1.createdAt }
    }

    private static func parseAdminConversationMessage(
        documentID: String,
        data: [String: Any],
        isFromSubject: Bool
    ) -> AdminConversationMessage? {
        guard let content = data["content"] as? String,
              let createdAt = timeIntervalValue(data["createdAt"])
        else {
            return nil
        }

        let typeString = (data["type"] as? String ?? "text").lowercased()
        var type = MessageType(rawValue: typeString) ?? .text
        // Older / mis-tagged docs may store a video URL as plain text.
        if type == .text, Self.looksLikeVideoMessageURL(content) {
            type = .video
        }
        let voiceDuration = timeIntervalValue(data["voiceDuration"])
        let thumbnailURL = (data["thumbnailURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let videoDuration = timeIntervalValue(data["videoDuration"])

        return AdminConversationMessage(
            id: (data["id"] as? String) ?? documentID,
            content: content,
            type: type,
            isFromSubject: isFromSubject,
            createdAt: Date(timeIntervalSince1970: createdAt),
            voiceDuration: voiceDuration,
            thumbnailURL: (thumbnailURL?.isEmpty == false) ? thumbnailURL : nil,
            videoDuration: videoDuration
        )
    }

    private static func looksLikeVideoMessageURL(_ content: String) -> Bool {
        let lower = content.lowercased()
        guard lower.hasPrefix("http"), lower.contains("firebasestorage") else { return false }
        return lower.contains("message_videos") || lower.contains(".mp4")
    }

    private static func adminMessagePreview(from data: [String: Any]) -> String {
        let rawType = (data["type"] as? String ?? "text").lowercased()
        let content = (data["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let type: String = {
            if rawType == "video" || looksLikeVideoMessageURL(content) { return "video" }
            return rawType
        }()
        switch type {
        case "image":
            return "📷 Image"
        case "voice", "audio":
            return "🎤 Voice message"
        case "video":
            return "🎬 Video"
        default:
            return content.isEmpty ? "—" : content
        }
    }

    private static func parseAdminUserProfile(document: QueryDocumentSnapshot) -> AdminUserProfile? {
        parseAdminUserProfile(documentID: document.documentID, data: document.data())
    }

    private static func parseAdminUserProfile(
        documentID: String,
        data: [String: Any]
    ) -> AdminUserProfile? {
        let name = resolvedAdminProfileName(from: data)
        // Prefer `email`; fall back to legacy keys some docs may still use.
        let rawEmail = (data["email"] as? String)
            ?? (data["userEmail"] as? String)
            ?? (data["Email"] as? String)
            ?? ""
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPlaceholderAdminName(name) && email.isEmpty { return nil }

        let photos = data["photos"] as? [String] ?? []
        var photoURL = data["profilePhotoURL"] as? String
        if photoURL == nil || photoURL?.isEmpty == true {
            photoURL = photos.first(where: { !$0.isEmpty })
        }

        let location = Self.parseLocation(from: data)
        let frozenUntil = Self.parseDiscoverFreezeUntil(from: data)
        let lastSeen: Date?
        if let interval = data["lastSeen"] as? TimeInterval {
            lastSeen = Date(timeIntervalSince1970: interval)
        } else if let timestamp = data["lastSeen"] as? Timestamp {
            lastSeen = timestamp.dateValue()
        } else if let number = data["lastSeen"] as? NSNumber {
            lastSeen = Date(timeIntervalSince1970: number.doubleValue)
        } else {
            lastSeen = nil
        }

        let createdAt = parseAdminCreatedAt(from: data)

        let profileStatus = UserProfileStatus.resolve(from: data)

        return AdminUserProfile(
            id: documentID,
            name: isPlaceholderAdminName(name) ? "Unknown" : name,
            age: resolvedAdminProfileAge(from: data),
            email: email,
            bio: data["bio"] as? String ?? "",
            photoURL: photoURL,
            photos: photos,
            gender: data["gender"] as? String ?? "",
            interests: data["interests"] as? [String] ?? [],
            interestedIn: data["interestedIn"] as? [String] ?? [],
            lookingFor: data["lookingFor"] as? [String] ?? [],
            locationDisplay: location.displayString,
            isOnline: data["isOnline"] as? Bool ?? false,
            lastSeen: lastSeen,
            isBanned: data["isBanned"] as? Bool == true,
            isFrozen: (frozenUntil ?? .distantPast) > Date(),
            frozenUntil: frozenUntil,
            isDeleted: data["isDeleted"] as? Bool == true,
            isIncomplete: profileStatus == .incomplete,
            createdAt: createdAt
        )
    }

    private static func parseAdminCreatedAt(from data: [String: Any]) -> Date? {
        let candidates: [Any?] = [
            data["createdAt"],
            data["created_at"],
            data["CreatedAt"],
            data["signupAt"],
            data["signedUpAt"]
        ]
        for candidate in candidates {
            if let date = parseDashboardDate(from: candidate) {
                return date
            }
            if let date = dateValue(from: candidate) {
                return date
            }
            if let interval = timeIntervalValue(candidate), interval > 0 {
                // Support both seconds and milliseconds since epoch.
                if interval > 10_000_000_000 {
                    return Date(timeIntervalSince1970: interval / 1000)
                }
                return Date(timeIntervalSince1970: interval)
            }
        }
        return nil
    }

    private static func resolvedAdminProfileName(from data: [String: Any]) -> String {
        let candidates = [
            data["name"] as? String,
            data["displayName"] as? String,
            data["fullName"] as? String
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !isPlaceholderAdminName(trimmed) {
                return trimmed
            }
        }

        let first = (data["firstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = (data["lastName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return combined
    }

    private static func resolvedAdminProfileAge(from data: [String: Any]) -> Int? {
        if let age = intValue(from: data["age"]), age > 0, age < 130 {
            return age
        }
        if let birthDate = dateValue(from: data["dateOfBirth"]) {
            let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
            if years > 0, years < 130 {
                return years
            }
        }
        return nil
    }

    private static func intValue(from raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func dateValue(from raw: Any?) -> Date? {
        if let timestamp = raw as? Timestamp {
            return timestamp.dateValue()
        }
        if let interval = raw as? TimeInterval, interval > 1_000_000_000 {
            return Date(timeIntervalSince1970: interval)
        }
        if let number = raw as? NSNumber, number.doubleValue > 1_000_000_000 {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    private func applyReportModeration(
        reportId: String,
        status: String,
        action: ReportModerationAction,
        extraFields: [String: Any] = [:]
    ) async throws {
        guard let adminId = auth.currentUser?.uid else {
            throw SpectRoomAuthError.notAuthenticated
        }

        var data: [String: Any] = [
            "status": status,
            "moderation_action": action.rawValue,
            "moderated_at": FieldValue.serverTimestamp(),
            "moderated_by": adminId
        ]
        for (key, value) in extraFields {
            data[key] = value
        }

        try await db.collection("reports").document(reportId).setData(data, merge: true)
    }

    private static func parseDiscoverFreezeUntil(from userData: [String: Any]) -> Date? {
        if let timestamp = userData["discoverFrozenUntil"] as? Timestamp {
            return timestamp.dateValue()
        }
        if let interval = userData["discoverFrozenUntil"] as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        return nil
    }

    private static func parseUserReport(documentID: String, data: [String: Any]) -> UserReport? {
        let reportId = data["report_id"] as? String ?? documentID
        guard
            let reporterUserId = data["reporter_user_id"] as? String,
            let reportedUserId = data["reported_user_id"] as? String,
            let category = data["category"] as? String
        else {
            return nil
        }

        let details = data["details"] as? String
        let status = data["status"] as? String ?? "pending"
        let createdAt: Date?
        if let timestamp = data["created_at"] as? Timestamp {
            createdAt = timestamp.dateValue()
        } else if let interval = data["created_at"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: interval)
        } else {
            createdAt = nil
        }

        let snapshot = data["context_snapshot"] as? [String: Any] ?? [:]
        let reportedName = (snapshot["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bio = snapshot["bio"] as? String ?? ""
        let photoURLs = snapshot["profile_photo_urls"] as? [String] ?? []

        return UserReport(
            id: reportId,
            reporterUserId: reporterUserId,
            reportedUserId: reportedUserId,
            reportedName: (reportedName?.isEmpty == false) ? reportedName! : "Unknown",
            reporterName: nil,
            reporterEmail: nil,
            reportedEmail: nil,
            reporterPhotoURL: nil,
            category: category,
            details: details,
            status: status,
            createdAt: createdAt,
            bio: bio,
            profilePhotoURLs: photoURLs
        )
    }

    private static func parseReportHistoryEvent(documentID: String, data: [String: Any]) -> AdminProfileHistoryEvent? {
        guard let report = parseUserReport(documentID: documentID, data: data) else { return nil }
        let date = report.createdAt ?? Date.distantPast
        let statusKey: String
        switch report.status.lowercased() {
        case "pending": statusKey = "settings.reported.profiles.status.pending"
        case "reviewed": statusKey = "settings.reported.profiles.status.reviewed"
        case "dismissed": statusKey = "settings.reported.profiles.status.dismissed"
        case "actioned": statusKey = "settings.reported.profiles.status.actioned"
        default: statusKey = report.status
        }
        let detailParts = [report.category, report.details]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        return AdminProfileHistoryEvent(
            id: "report-\(report.id)",
            kind: .reported,
            title: "admin.all.profiles.history.reported".localized,
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
            status: statusKey.contains(".") ? statusKey.localized : statusKey.capitalized,
            date: date
        )
    }

    private static func parseFreezeHistoryEvents(documentID: String, data: [String: Any]) -> [AdminProfileHistoryEvent] {
        let statusRaw = (data["status"] as? String ?? FreezeRecordStatus.active.rawValue).lowercased()
        let status = FreezeRecordStatus(rawValue: statusRaw) ?? .active
        let hours = data["freezeHours"] as? Int ?? 24
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
            ?? Date.distantPast
        let endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        let until = (data["frozenUntil"] as? Timestamp)?.dateValue()

        var detailParts: [String] = [
            String(format: "admin.frozen.hours".localized, hours)
        ]
        if let until {
            detailParts.append(
                String(
                    format: "admin.all.profiles.history.until".localized,
                    ModerationNotice.formattedUnlockDate(until)
                )
            )
        }
        if let reportId = data["reportId"] as? String, !reportId.isEmpty,
           !reportId.hasPrefix("admin-freeze-"),
           !reportId.hasPrefix("admin-extend-") {
            detailParts.append(
                String(format: "admin.all.profiles.history.report.id".localized, reportId)
            )
        }
        let detail = detailParts.joined(separator: " · ")

        var events: [AdminProfileHistoryEvent] = [
            AdminProfileHistoryEvent(
                id: "freeze-\(documentID)",
                kind: .freeze,
                title: "admin.all.profiles.history.freeze".localized,
                detail: detail,
                status: FreezeRecordStatus.active.localizationKey.localized,
                date: createdAt
            )
        ]

        if status != .active, let endedAt {
            let endTitleKey: String
            switch status {
            case .lifted: endTitleKey = "admin.all.profiles.history.freeze.lifted"
            case .expired: endTitleKey = "admin.all.profiles.history.freeze.expired"
            case .banned: endTitleKey = "admin.all.profiles.history.freeze.ended.ban"
            case .active: endTitleKey = "admin.all.profiles.history.freeze.lifted"
            }
            events.append(
                AdminProfileHistoryEvent(
                    id: "freeze-end-\(documentID)",
                    kind: .freezeEnded,
                    title: endTitleKey.localized,
                    detail: detail,
                    status: status.localizationKey.localized,
                    date: endedAt
                )
            )
        }

        return events
    }

    private static func parseBanHistoryEvents(documentID: String, data: [String: Any]) -> [AdminProfileHistoryEvent] {
        let statusRaw = (data["status"] as? String ?? BanRecordStatus.active.rawValue).lowercased()
        let status = BanRecordStatus(rawValue: statusRaw) ?? .active
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
            ?? Date.distantPast
        let endedAt = (data["endedAt"] as? Timestamp)?.dateValue()

        var detail: String?
        if let reportId = data["reportId"] as? String, !reportId.isEmpty,
           !reportId.hasPrefix("admin-ban-"),
           !reportId.hasPrefix("admin-freeze-") {
            detail = String(format: "admin.all.profiles.history.report.id".localized, reportId)
        }

        var events: [AdminProfileHistoryEvent] = [
            AdminProfileHistoryEvent(
                id: "ban-\(documentID)",
                kind: .ban,
                title: "admin.all.profiles.history.ban".localized,
                detail: detail,
                status: BanRecordStatus.active.localizationKey.localized,
                date: createdAt
            )
        ]

        if status == .lifted, let endedAt {
            events.append(
                AdminProfileHistoryEvent(
                    id: "ban-lift-\(documentID)",
                    kind: .banLifted,
                    title: "admin.all.profiles.history.ban.lifted".localized,
                    detail: detail,
                    status: BanRecordStatus.lifted.localizationKey.localized,
                    date: endedAt
                )
            )
        }

        return events
    }

    private static func parseWarningHistoryEvent(documentID: String, data: [String: Any]) -> AdminProfileHistoryEvent? {
        let message = (data["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
            ?? Date.distantPast
        var detail = message
        if let reportId = data["reportId"] as? String, !reportId.isEmpty,
           !reportId.hasPrefix("admin-profile-") {
            let reportLine = String(format: "admin.all.profiles.history.report.id".localized, reportId)
            detail = [detail, reportLine].compactMap { $0 }.joined(separator: " · ")
        }
        return AdminProfileHistoryEvent(
            id: "warning-\(documentID)",
            kind: .warning,
            title: "admin.all.profiles.history.warning".localized,
            detail: detail,
            status: nil,
            date: createdAt
        )
    }

    private static func fallbackHistoryEventsFromUser(
        userId: String,
        data: [String: Any],
        existing: [AdminProfileHistoryEvent]
    ) -> [AdminProfileHistoryEvent] {
        var extras: [AdminProfileHistoryEvent] = []
        let hasBanEvent = existing.contains { $0.kind == .ban }
        let hasBanLiftedEvent = existing.contains { $0.kind == .banLifted }
        let hasFreezeEvent = existing.contains { $0.kind == .freeze }
        let hasWarningEvent = existing.contains { $0.kind == .warning }

        if data["isBanned"] as? Bool == true {
            if !hasBanEvent {
                let bannedAt = (data["bannedAt"] as? Timestamp)?.dateValue() ?? Date()
                var detail: String?
                if let reportId = data["bannedReportId"] as? String, !reportId.isEmpty {
                    detail = String(format: "admin.all.profiles.history.report.id".localized, reportId)
                }
                extras.append(
                    AdminProfileHistoryEvent(
                        id: "ban-user-\(userId)",
                        kind: .ban,
                        title: "admin.all.profiles.history.ban".localized,
                        detail: detail,
                        status: BanRecordStatus.active.localizationKey.localized,
                        date: bannedAt
                    )
                )
            }
        } else if let liftedAt = (data["lastBanLiftedAt"] as? Timestamp)?.dateValue() {
            var detail: String?
            if let reportId = data["lastBannedReportId"] as? String ?? data["bannedReportId"] as? String,
               !reportId.isEmpty {
                detail = String(format: "admin.all.profiles.history.report.id".localized, reportId)
            }

            if !hasBanEvent {
                let bannedAt = (data["lastBannedAt"] as? Timestamp)?.dateValue() ?? liftedAt
                extras.append(
                    AdminProfileHistoryEvent(
                        id: "ban-user-\(userId)",
                        kind: .ban,
                        title: "admin.all.profiles.history.ban".localized,
                        detail: detail,
                        status: BanRecordStatus.active.localizationKey.localized,
                        date: bannedAt
                    )
                )
            }

            if !hasBanLiftedEvent {
                extras.append(
                    AdminProfileHistoryEvent(
                        id: "ban-lifted-user-\(userId)",
                        kind: .banLifted,
                        title: "admin.all.profiles.history.ban.lifted".localized,
                        detail: detail,
                        status: BanRecordStatus.lifted.localizationKey.localized,
                        date: liftedAt
                    )
                )
            }
        }

        if !hasFreezeEvent,
           let freezeUntil = parseDiscoverFreezeUntil(from: data),
           freezeUntil > Date() {
            let hours = data["discoverFreezeHours"] as? Int ?? 24
            extras.append(
                AdminProfileHistoryEvent(
                    id: "freeze-user-\(userId)",
                    kind: .freeze,
                    title: "admin.all.profiles.history.freeze".localized,
                    detail: [
                        String(format: "admin.frozen.hours".localized, hours),
                        String(
                            format: "admin.all.profiles.history.until".localized,
                            ModerationNotice.formattedUnlockDate(freezeUntil)
                        )
                    ].joined(separator: " · "),
                    status: FreezeRecordStatus.active.localizationKey.localized,
                    date: Date()
                )
            )
        }

        if !hasWarningEvent,
           let warning = data["pendingSystemWarning"] as? [String: Any],
           warning["acknowledged"] as? Bool != true {
            let message = (warning["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let createdAt: Date
            if let interval = warning["created_at"] as? TimeInterval {
                createdAt = Date(timeIntervalSince1970: interval)
            } else {
                createdAt = Date()
            }
            extras.append(
                AdminProfileHistoryEvent(
                    id: "warning-user-\(userId)",
                    kind: .warning,
                    title: "admin.all.profiles.history.warning".localized,
                    detail: message,
                    status: nil,
                    date: createdAt
                )
            )
        }

        return extras
    }
    
    func unblockUser(userId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        try await db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(userId)
            .delete()
        
        try await removeBlockedByMirror(blockedUserId: userId)
        
        await MainActor.run {
            if var current = self.currentUser {
                current.blockedUsers.removeAll { $0.id == userId }
                self.currentUser = current
            }
        }
    }
    
    func isBlockedBy(userId otherUserId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        let document = try await db.collection("users")
            .document(currentUserId)
            .collection("blockedBy")
            .document(otherUserId)
            .getDocument()
        
        return document.exists
    }
    
    func fetchBlockedByUsers() async throws -> [BlockedUser] {
        guard let currentUserId = auth.currentUser?.uid else { return [] }
        
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("blockedBy")
            .getDocuments()
        
        return snapshot.documents.compactMap { document in
            Self.parseBlockedUser(documentID: document.documentID, data: document.data())
        }
    }
    
    func stopListeningForBlockedByUsers() {
        blockedByListener?.remove()
        blockedByListener = nil
    }

    func stopListeningForModerationStatus() {
        moderationListener?.remove()
        moderationListener = nil
    }

    /// Live updates for ban / warning / freeze notice on the signed-in user.
    func listenForModerationStatus(
        onBanned: @escaping () -> Void,
        onNotice: @escaping (ModerationNotice) -> Void,
        onNoticeCleared: @escaping () -> Void
    ) {
        guard let currentUserId = auth.currentUser?.uid else { return }

        stopListeningForModerationStatus()
        moderationListener = db.collection("users").document(currentUserId)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("⚠️ Error listening for moderation status: \(error.localizedDescription)")
                    return
                }
                guard let data = snapshot?.data() else { return }

                if data["isBanned"] as? Bool == true {
                    print("🚫 Pending account ban notice for \(currentUserId)")
                    DispatchQueue.main.async {
                        onNotice(ModerationNotice(kind: .banAcknowledgement))
                    }
                    return
                }

                if let unban = data["pendingAccountUnban"] as? [String: Any],
                   (unban["acknowledged"] as? Bool) != true {
                    print("✅ Pending account unban notice for \(currentUserId)")
                    DispatchQueue.main.async {
                        onNotice(ModerationNotice(kind: .banLifted))
                    }
                    return
                }

                if let freeze = data["pendingAccountFreeze"] as? [String: Any],
                   (freeze["acknowledged"] as? Bool) != true,
                   let until = Self.parseFreezeUntilValue(freeze["freeze_until"]) ?? Self.parseDiscoverFreezeUntil(from: data),
                   until > Date() {
                    let hours = freeze["hours"] as? Int
                        ?? data["discoverFreezeHours"] as? Int
                        ?? 24
                    print("❄️ Pending account freeze notice for \(currentUserId)")
                    DispatchQueue.main.async {
                        onNotice(ModerationNotice(kind: .freezeAcknowledgement(until: until, hours: hours)))
                    }
                    return
                }

                if let warning = data["pendingSystemWarning"] as? [String: Any],
                   (warning["acknowledged"] as? Bool) != true {
                    let message = (warning["message"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolved = (message?.isEmpty == false)
                        ? message!
                        : "admin.warning.default.message".localized
                    // Ignore stale cache snapshots that omit a warning we already know about —
                    // handled by not clearing warnings in onNoticeCleared.
                    print("⚠️ Pending system warning for \(currentUserId)")
                    DispatchQueue.main.async {
                        onNotice(ModerationNotice(kind: .warning(message: resolved)))
                    }
                    return
                }

                // Skip "cleared" signals from cache — wait for a server confirmation when possible.
                if snapshot?.metadata.isFromCache == true {
                    return
                }

                // Active freeze without pending notice (e.g. after ack race) — still require sign-out via UI notice.
                if let until = Self.parseDiscoverFreezeUntil(from: data), until > Date() {
                    let hours = data["discoverFreezeHours"] as? Int ?? 24
                    DispatchQueue.main.async {
                        onNotice(ModerationNotice(kind: .freezeAcknowledgement(until: until, hours: hours)))
                    }
                    return
                }

                DispatchQueue.main.async {
                    onNoticeCleared()
                }
            }
    }
    
    /// Live updates when someone blocks/unblocks the current user (mutual hide).
    func listenForBlockedByUsers(completion: @escaping ([BlockedUser]) -> Void) {
        guard let currentUserId = auth.currentUser?.uid else { return }
        
        stopListeningForBlockedByUsers()
        let ref = db.collection("users").document(currentUserId).collection("blockedBy")
        blockedByListener = ref.addSnapshotListener { snapshot, error in
            if let error = error {
                print("⚠️ Error listening for blockedBy: \(error.localizedDescription)")
                return
            }
            guard let documents = snapshot?.documents else { return }
            let users = documents.compactMap { document in
                Self.parseBlockedUser(documentID: document.documentID, data: document.data())
            }
            DispatchQueue.main.async {
                completion(users)
            }
        }
    }
    
    private static func parseBlockedUser(documentID: String, data: [String: Any]) -> BlockedUser? {
        let name = data["name"] as? String ?? "Unknown"
        let blockedAtInterval = data["blockedAt"] as? TimeInterval
        let blockedAt = blockedAtInterval.map { Date(timeIntervalSince1970: $0) }
        return BlockedUser(id: documentID, name: name, blockedAt: blockedAt)
    }
    
    // MARK: - Matching Functions
    
    func recordSwipe(to targetUserId: String, action: SwipeType) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Recording swipe: \(action.rawValue) from \(currentUserId) to \(targetUserId)")
        
        var swipeData: [String: Any] = [
            "id": UUID().uuidString,
            "fromUserId": currentUserId,
            "toUserId": targetUserId,
            "action": action.rawValue,
            "createdAt": Date().timeIntervalSince1970
        ]
        
        // Passes are counted: 1st pass = hide for 1 month, 2nd pass = never show again.
        if action == .pass {
            let passCount = try await nextPassCount(for: targetUserId, currentUserId: currentUserId)
            swipeData["passCount"] = passCount
            print("💕 Pass count for \(targetUserId): \(passCount)")
        }
        
        // Save swipe action to current user's swipes collection
        let swipeRef = db.collection("users").document(currentUserId).collection("swipes").document()
        try await swipeRef.setData(swipeData)
        
        print("✅ Swipe recorded successfully")
    }
    
    /// Deletes the most recent swipe to `targetUserId` (like or pass) for single-step undo.
    func undoLastSwipe(to targetUserId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("swipes")
            .whereField("toUserId", isEqualTo: targetUserId)
            .getDocuments()
        
        guard let newest = snapshot.documents.max(by: {
            ($0.data()["createdAt"] as? TimeInterval ?? 0) < ($1.data()["createdAt"] as? TimeInterval ?? 0)
        }) else {
            print("⚠️ No swipe found to undo for \(targetUserId)")
            return
        }
        
        let action = newest.data()["action"] as? String
        try await newest.reference.delete()
        print("✅ Undid swipe (\(action ?? "unknown")) to \(targetUserId)")
        
        if action == SwipeType.like.rawValue || action == SwipeType.superLike.rawValue {
            try? await deleteMatch(with: targetUserId)
        }
    }
    
    /// Next pass number for a target (1 or 2+), based on existing pass docs.
    private func nextPassCount(for targetUserId: String, currentUserId: String) async throws -> Int {
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("swipes")
            .whereField("toUserId", isEqualTo: targetUserId)
            .whereField("action", isEqualTo: SwipeType.pass.rawValue)
            .getDocuments()
        
        let previous = effectivePassCount(from: snapshot.documents.map { $0.data() })
        return previous + 1
    }
    
    /// Prefer stored `passCount`; fall back to number of pass docs for legacy rows.
    private func effectivePassCount(from passDocuments: [[String: Any]]) -> Int {
        guard !passDocuments.isEmpty else { return 0 }
        let maxStored = passDocuments.compactMap { $0["passCount"] as? Int }.max() ?? 0
        return max(passDocuments.count, maxStored)
    }
    
    // MARK: - Fetch Swipe Filter State
    
    struct SwipeFilterState {
        /// Latest action is like / super_like.
        let likedUserIds: Set<String>
        /// Currently hidden from discover: 1st pass still in cooldown, or 2nd+ pass forever.
        let passedUserIds: Set<String>
        /// 2nd (or more) pass - never show again.
        let permanentlyPassedUserIds: Set<String>
        /// 1st pass still within the 1-month cooldown (eligible for "review passed" / start over).
        let reviewablePassedUserIds: Set<String>
    }
    
    private static let firstPassCooldownDays: TimeInterval = 30 * 24 * 60 * 60
    
    func fetchSwipeFilterState(preferServer: Bool = false) async throws -> SwipeFilterState {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Fetching swipe filter state\(preferServer ? " from server" : "")...")
        
        let swipesRef = db.collection("users").document(currentUserId).collection("swipes")
        let snapshot: QuerySnapshot
        if preferServer {
            snapshot = try await swipesRef.getDocuments(source: .server)
        } else {
            snapshot = try await swipesRef.getDocuments()
        }
        
        var latestSwipeByUser: [String: (action: String, createdAt: TimeInterval)] = [:]
        var passDocsByUser: [String: [[String: Any]]] = [:]
        
        for document in snapshot.documents {
            let data = document.data()
            guard let toUserId = data["toUserId"] as? String,
                  let action = data["action"] as? String else {
                continue
            }
            
            let createdAt = data["createdAt"] as? TimeInterval ?? 0
            if let existing = latestSwipeByUser[toUserId], existing.createdAt >= createdAt {
                // keep existing as latest
            } else {
                latestSwipeByUser[toUserId] = (action, createdAt)
            }
            
            if action == SwipeType.pass.rawValue {
                passDocsByUser[toUserId, default: []].append(data)
            }
        }
        
        var likedUserIds = Set<String>()
        var passedUserIds = Set<String>()
        var permanentlyPassedUserIds = Set<String>()
        var reviewablePassedUserIds = Set<String>()
        let now = Date().timeIntervalSince1970
        
        for (userId, state) in latestSwipeByUser {
            switch state.action {
            case SwipeType.like.rawValue, SwipeType.superLike.rawValue:
                likedUserIds.insert(userId)
            case SwipeType.pass.rawValue:
                let passDocs = passDocsByUser[userId] ?? []
                let passCount = effectivePassCount(from: passDocs)
                let latestPassAt = passDocs.compactMap { $0["createdAt"] as? TimeInterval }.max() ?? state.createdAt
                
                if passCount >= 2 {
                    permanentlyPassedUserIds.insert(userId)
                    passedUserIds.insert(userId)
                } else if now - latestPassAt < Self.firstPassCooldownDays {
                    // 1st pass still within 1 month - hide for now, reviewable via start over
                    passedUserIds.insert(userId)
                    reviewablePassedUserIds.insert(userId)
                }
                // else: 1st pass older than 1 month → eligible again (not in passedUserIds)
            default:
                print("⚠️ Unknown swipe action '\(state.action)' for user \(userId)")
            }
        }
        
        print("💕 Swipe filter: \(likedUserIds.count) liked, \(passedUserIds.count) hidden (\(permanentlyPassedUserIds.count) permanent, \(reviewablePassedUserIds.count) in cooldown)")
        return SwipeFilterState(
            likedUserIds: likedUserIds,
            passedUserIds: passedUserIds,
            permanentlyPassedUserIds: permanentlyPassedUserIds,
            reviewablePassedUserIds: reviewablePassedUserIds
        )
    }
    
    // MARK: - Fetch Liked Users
    func fetchLikedUserIds(preferServer: Bool = false) async throws -> Set<String> {
        try await fetchSwipeFilterState(preferServer: preferServer).likedUserIds
    }
    
    func fetchPassedUserIds(preferServer: Bool = false) async throws -> Set<String> {
        try await fetchSwipeFilterState(preferServer: preferServer).passedUserIds
    }
    
    /// User IDs the current user passed today (unique), for the second-thoughts review.
    func fetchTodaysPassedUserIds() async throws -> [String] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("swipes")
            .whereField("action", isEqualTo: SwipeType.pass.rawValue)
            .getDocuments(source: .server)
        
        var latestPassTodayByUser: [String: TimeInterval] = [:]
        for document in snapshot.documents {
            let data = document.data()
            guard let toUserId = data["toUserId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval,
                  createdAt >= startOfDay else {
                continue
            }
            if let existing = latestPassTodayByUser[toUserId], existing >= createdAt {
                continue
            }
            latestPassTodayByUser[toUserId] = createdAt
        }
        
        // Stable order: most recently passed first
        return latestPassTodayByUser
            .sorted { $0.value > $1.value }
            .map(\.key)
    }
    
    private func isPositiveSwipe(_ action: SwipeType?) -> Bool {
        action == .like || action == .superLike
    }
    
    private func latestSwipeAction(from fromUserId: String, to toUserId: String) async throws -> SwipeType? {
        let snapshot = try await db.collection("users")
            .document(fromUserId)
            .collection("swipes")
            .whereField("toUserId", isEqualTo: toUserId)
            .getDocuments()
        
        var latestAction: String?
        var latestCreatedAt: TimeInterval = 0
        
        for document in snapshot.documents {
            let data = document.data()
            guard let action = data["action"] as? String else { continue }
            let createdAt = data["createdAt"] as? TimeInterval ?? 0
            if createdAt >= latestCreatedAt {
                latestCreatedAt = createdAt
                latestAction = action
            }
        }
        
        guard let latestAction, let swipeType = SwipeType(rawValue: latestAction) else {
            return nil
        }
        return swipeType
    }
    
    func hasMutualLike(currentUserId: String, with otherUserId: String) async throws -> Bool {
        async let currentUserActionTask = latestSwipeAction(from: currentUserId, to: otherUserId)
        async let otherUserActionTask = latestSwipeAction(from: otherUserId, to: currentUserId)
        
        let currentUserAction = try await currentUserActionTask
        let otherUserAction = try await otherUserActionTask
        
        let isMutual = isPositiveSwipe(currentUserAction) && isPositiveSwipe(otherUserAction)
        print("💕 Mutual like check \(currentUserId) <-> \(otherUserId): current=\(currentUserAction?.rawValue ?? "none"), other=\(otherUserAction?.rawValue ?? "none"), mutual=\(isMutual)")
        return isMutual
    }
    
    func matchExists(with targetUserId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else { return false }
        let matchId = matchDocumentId(for: currentUserId, and: targetUserId)
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("matches")
            .document(matchId)
            .getDocument()
        return snapshot.exists
    }
    
    func matchDocumentId(for userId1: String, and userId2: String) -> String {
        let sortedIds = [userId1, userId2].sorted()
        return "\(sortedIds[0])_\(sortedIds[1])"
    }
    
    func checkForMatch(with targetUserId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Checking for match between \(currentUserId) and \(targetUserId)")
        
        guard try await hasMutualLike(currentUserId: currentUserId, with: targetUserId) else {
            print("💕 No mutual like yet between \(currentUserId) and \(targetUserId)")
            return false
        }
        
        let matchId = matchDocumentId(for: currentUserId, and: targetUserId)
        let existingMatch = try await db.collection("users")
            .document(currentUserId)
            .collection("matches")
            .document(matchId)
            .getDocument()
        
        if existingMatch.exists {
            print("💕 Match already exists between \(currentUserId) and \(targetUserId)")
            return true
        }
        
        try await createMatch(with: targetUserId, matchId: matchId)
        return true
    }
    
    func checkIfConversationExists(with userId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Checking if conversation exists with user: \(userId)")
        
        // Check sent messages
        let sentMessagesRef = db.collection("users").document(currentUserId).collection("sentMessages")
        let sentMessagesSnapshot = try await sentMessagesRef.whereField("recipientId", isEqualTo: userId).limit(to: 1).getDocuments()
        
        if !sentMessagesSnapshot.documents.isEmpty {
            print("💬 Found existing sent message to user: \(userId)")
            return true
        }
        
        // Check incoming messages
        let incomingMessagesRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let incomingMessagesSnapshot = try await incomingMessagesRef.whereField("senderId", isEqualTo: userId).limit(to: 1).getDocuments()
        
        if !incomingMessagesSnapshot.documents.isEmpty {
            print("💬 Found existing incoming message from user: \(userId)")
            return true
        }
        
        print("💬 No existing conversation found with user: \(userId)")
        return false
    }
    
    func checkForAnyMessages() async throws -> (sentCount: Int, incomingCount: Int) {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Checking for any messages in database...")
        
        // Check sent messages
        let sentSnapshot = try await db.collection("users").document(currentUserId).collection("sentMessages").getDocuments()
        let sentCount = sentSnapshot.documents.count
        
        // Check incoming messages
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        let incomingCount = incomingSnapshot.documents.count
        
        print("💬 Database check: \(sentCount) sent messages, \(incomingCount) incoming messages")
        return (sentCount: sentCount, incomingCount: incomingCount)
    }
    
    func countUnreadIncomingMessages() async throws -> Int {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Counting unread incoming messages...")
        
        // Fetch incoming messages and filter for unread ones
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        
        var unreadCount = 0
        for document in incomingSnapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            if !isRead {
                unreadCount += 1
            }
        }
        
        print("💬 Found \(unreadCount) unread incoming messages")
        return unreadCount
    }
    
    func fetchUnreadCountsBySender() async throws -> [String: Int] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let incomingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("incomingMessages")
            .getDocuments()
        
        var unreadCounts: [String: Int] = [:]
        for document in incomingSnapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            guard !isRead, let senderId = data["senderId"] as? String else { continue }
            unreadCounts[senderId, default: 0] += 1
        }
        
        return unreadCounts
    }
    
    func countUnreadMessagesFromUser(_ otherUserId: String) async throws -> Int {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Counting unread messages from user: \(otherUserId)")
        
        // Fetch all incoming messages from this user
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: otherUserId).getDocuments()
        
        var unreadCount = 0
        for document in snapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            if !isRead {
                unreadCount += 1
            }
        }
        
        print("💬 Found \(unreadCount) unread messages from user: \(otherUserId)")
        return unreadCount
    }
    
    func markMessagesAsRead(from otherUserId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Marking messages as read from user: \(otherUserId)")
        
        // Fetch all incoming messages from this user
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: otherUserId).getDocuments()
        
        let batch = db.batch()
        let readAt = Date().timeIntervalSince1970
        
        for document in snapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            
            // Only update unread messages
            if !isRead {
                let messageRef = incomingRef.document(document.documentID)
                batch.updateData([
                    "isRead": true,
                    "readAt": readAt
                ], forDocument: messageRef)
            }
        }
        
        try await batch.commit()
        print("💬 Marked messages as read from user: \(otherUserId)")
    }
    
    private func createMatch(with targetUserId: String, matchId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        guard try await hasMutualLike(currentUserId: currentUserId, with: targetUserId) else {
            print("💕 Skipping match creation - mutual like requirement not met")
            return
        }
        
        print("💕 Creating match between \(currentUserId) and \(targetUserId)")
        
        let sortedIds = [currentUserId, targetUserId].sorted()
        let matchData: [String: Any] = [
            "id": matchId,
            "user1Id": sortedIds[0],
            "user2Id": sortedIds[1],
            "matchedAt": Date().timeIntervalSince1970,
            "isActive": true,
            "lastMessageAt": NSNull(),
            "conversationId": UUID().uuidString
        ]
        
        let currentUserMatchRef = db.collection("users").document(currentUserId).collection("matches").document(matchId)
        let targetUserMatchRef = db.collection("users").document(targetUserId).collection("matches").document(matchId)
        
        let existingForCurrentUser = try await currentUserMatchRef.getDocument()
        let existingForTargetUser = try await targetUserMatchRef.getDocument()
        
        if existingForCurrentUser.exists && existingForTargetUser.exists {
            print("💕 Match document already exists for both users")
            return
        }
        
        if !existingForCurrentUser.exists {
            try await currentUserMatchRef.setData(matchData)
        }
        if !existingForTargetUser.exists {
            try await targetUserMatchRef.setData(matchData)
        }
        
        print("✅ Match created successfully")
    }
    
    /// Removes the match for both users (best-effort on the other side).
    func deleteMatch(with otherUserId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let matchId = matchDocumentId(for: currentUserId, and: otherUserId)
        print("💕 Deleting match \(matchId) between \(currentUserId) and \(otherUserId)")
        
        let currentUserMatchRef = db.collection("users")
            .document(currentUserId)
            .collection("matches")
            .document(matchId)
        let otherUserMatchRef = db.collection("users")
            .document(otherUserId)
            .collection("matches")
            .document(matchId)
        
        try await currentUserMatchRef.delete()
        
        do {
            try await otherUserMatchRef.delete()
        } catch {
            print("⚠️ Unable to delete match on other user (\(otherUserId)): \(error.localizedDescription)")
        }
        
        print("✅ Match deleted for current user")
    }
    
    func fetchMatches() async throws -> [MatchDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Fetching matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        let snapshot = try await matchesRef.order(by: "matchedAt", descending: true).getDocuments()
        
        print("💕 Found \(snapshot.documents.count) match documents in database")
        
        var matches: [MatchDisplay] = []
        var processedUserIds: Set<String> = []
        let currentUserLocation = try await fetchCurrentUserLocation()
        
        for (index, document) in snapshot.documents.enumerated() {
            let data = document.data()
            guard let user1Id = data["user1Id"] as? String,
                  let user2Id = data["user2Id"] as? String,
                  let matchedAt = data["matchedAt"] as? TimeInterval else { 
                print("💕 Skipping document \(index + 1) - missing required fields")
                continue 
            }
            
            // Determine the other user's ID
            let otherUserId = user1Id == currentUserId ? user2Id : user1Id
            print("💕 Processing match \(index + 1): user1=\(user1Id), user2=\(user2Id), otherUserId=\(otherUserId)")
            
            // Check for duplicate users
            if processedUserIds.contains(otherUserId) {
                print("💕 Skipping duplicate match for user: \(otherUserId)")
                continue
            }
            processedUserIds.insert(otherUserId)
            
            // Fetch the other user's profile information
            do {
                let otherUserProfile = try await fetchUserProfile(
                    for: otherUserId,
                    currentUserLocation: currentUserLocation,
                    forMatches: true
                )
                let matchDisplay = MatchDisplay(
                    id: document.documentID,
                    otherUser: otherUserProfile,
                    matchedAt: Date(timeIntervalSince1970: matchedAt),
                    lastMessageAt: nil // We'll implement this later
                )
                matches.append(matchDisplay)
            } catch {
                print("❌ Error fetching profile for user \(otherUserId): \(error)")
                continue
            }
        }
        
        print("💕 Successfully fetched \(matches.count) matches")
        for (index, match) in matches.enumerated() {
            print("💕 Match \(index + 1): \(match.otherUser.name) (matched at: \(match.matchedAt))")
        }
        return matches
    }
    
    /// Latest energy levels from the server (not the local Firestore cache).
    func fetchEnergyLevels(for userIds: [String]) async -> [String: Int] {
        let uniqueIds = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !uniqueIds.isEmpty else { return [:] }
        
        return await withTaskGroup(of: (String, Int)?.self, returning: [String: Int].self) { group in
            for userId in uniqueIds {
                group.addTask {
                    do {
                        let document = try await self.db.collection("users")
                            .document(userId)
                            .getDocument(source: .server)
                        let level = document.data()?["energyLevel"] as? Int ?? 4
                        return (userId, level)
                    } catch {
                        print("❌ Error fetching energy level for \(userId): \(error)")
                        return nil
                    }
                }
            }
            
            var levels: [String: Int] = [:]
            for await result in group {
                if let result {
                    levels[result.0] = result.1
                }
            }
            return levels
        }
    }
    
    func fetchUserProfile(for userId: String, currentUserLocation: Location? = nil, forMatches: Bool = false) async throws -> ProfileCard {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw NSError(domain: "FirebaseAuthService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let resolvedCurrentUserLocation: Location?
        if let currentUserLocation {
            resolvedCurrentUserLocation = currentUserLocation
        } else {
            resolvedCurrentUserLocation = try await fetchCurrentUserLocation()
        }
        
        let otherUserLocation = Self.parseLocation(from: userData)
        let distanceString: String
        if let resolvedCurrentUserLocation,
           let distanceKm = Self.distance(from: resolvedCurrentUserLocation, to: otherUserLocation) {
            distanceString = Self.formatDistance(distanceKm, forMatches: forMatches)
        } else {
            distanceString = "Matched"
        }
        
        let rawName = (userData["name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (userData["displayName"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String = {
            if !rawName.isEmpty,
               rawName.caseInsensitiveCompare("Unknown") != .orderedSame,
               rawName.caseInsensitiveCompare("Unknown User") != .orderedSame {
                return rawName
            }
            if !displayName.isEmpty {
                return displayName
            }
            return rawName.isEmpty ? "Unknown" : rawName
        }()
        let age = userData["age"] as? Int ?? 0
        let bio = userData["bio"] as? String ?? ""
        let interests = userData["interests"] as? [String] ?? []
        let gender = userData["gender"] as? String ?? ""
        let interestedIn = userData["interestedIn"] as? [String] ?? []
        let lookingFor = userData["lookingFor"] as? [String] ?? []
        let photos = userData["photos"] as? [String] ?? []
        let profilePhotoURL = userData["profilePhotoURL"] as? String
        let lifestyle = userData["lifestyle"] as? String ?? ""
        let shareLifestyle = userData["shareLifestyle"] as? Bool ?? false
        let bodyType = userData["bodyType"] as? String ?? ""
        let shareBodyType = userData["shareBodyType"] as? Bool ?? false
        let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []
        let shareIdealFirstDate = userData["shareIdealFirstDate"] as? Bool ?? false
        let sensoryPreferences = userData["sensoryPreferences"] as? [String] ?? []
        let shareSensoryPreferences = userData["shareSensoryPreferences"] as? Bool ?? false
        let energyLevel = userData["energyLevel"] as? Int ?? 4
        let preferredAgeMin = userData["preferredAgeMin"] as? Int ?? age
        let preferredAgeMax = userData["preferredAgeMax"] as? Int ?? min(age + 5, 80)
        let isOnline = userData["isOnline"] as? Bool ?? false
        let lastSeenInterval = userData["lastSeen"] as? TimeInterval
        let lastSeen = lastSeenInterval.map { Date(timeIntervalSince1970: $0) } ?? Date()
        
        let matchPercentage: Int
        let viewer = currentUser ?? AppStateManager.shared.currentUser
        if let viewer {
            matchPercentage = ProfileCard.calculateMatchPercentage(
                interests: interests,
                age: age,
                gender: gender,
                lookingFor: lookingFor,
                sensoryPreferences: sensoryPreferences,
                shareSensoryPreferences: shareSensoryPreferences,
                lifestyle: lifestyle,
                shareLifestyle: shareLifestyle,
                idealFirstDate: idealFirstDate,
                shareIdealFirstDate: shareIdealFirstDate,
                currentUser: viewer
            )
        } else {
            matchPercentage = 0
        }
        
        return ProfileCard(
            userId: userId,
            name: name,
            age: age,
            bio: bio,
            interests: interests,
            distance: distanceString,
            imageURL: profilePhotoURL,
            gender: gender,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            photos: photos,
            lifestyle: lifestyle,
            shareLifestyle: shareLifestyle,
            bodyType: bodyType,
            shareBodyType: shareBodyType,
            preferredAgeMin: preferredAgeMin,
            preferredAgeMax: preferredAgeMax,
            isOnline: isOnline,
            lastSeen: lastSeen,
            idealFirstDate: idealFirstDate,
            shareIdealFirstDate: shareIdealFirstDate,
            sensoryPreferences: sensoryPreferences,
            shareSensoryPreferences: shareSensoryPreferences,
            energyLevel: energyLevel,
            matchPercentage: matchPercentage
        )
    }
    
    func stopListeningForMatches() {
        matchesListener?.remove()
        matchesListener = nil
        print("💕 Stopped listening for new matches")
    }
    
    func listenForNewMatches(completion: @escaping (MatchDisplay) -> Void) {
        guard let currentUserId = auth.currentUser?.uid else {
            print("❌ User not authenticated for match listening")
            return
        }
        
        stopListeningForMatches()
        print("💕 Starting to listen for new matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        
        matchesListener = matchesRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Error listening for matches: \(error)")
                return
            }
            
            guard let snapshot = snapshot else {
                print("❌ No snapshot received for matches")
                return
            }
            
            // Check for new matches (documents that were added)
            for documentChange in snapshot.documentChanges {
                print("💕 Document change type: \(documentChange.type.rawValue)")
                print("💕 Document ID: \(documentChange.document.documentID)")
                
                if documentChange.type == .added {
                    print("💕 New match document added")
                    let data = documentChange.document.data()
                    guard let user1Id = data["user1Id"] as? String,
                          let user2Id = data["user2Id"] as? String,
                          let matchedAt = data["matchedAt"] as? TimeInterval else { 
                        print("❌ Missing required fields in match document")
                        continue 
                    }
                    
                    print("💕 Match between \(user1Id) and \(user2Id)")
                    
                    // Determine the other user's ID
                    let otherUserId = user1Id == currentUserId ? user2Id : user1Id
                    print("💕 Other user ID: \(otherUserId)")
                    
                    // Log match timing for debugging
                    let matchTime = Date(timeIntervalSince1970: matchedAt)
                    let timeDifference = Date().timeIntervalSince(matchTime)
                    print("💕 Match created \(timeDifference) seconds ago")
                    
                    // Only trigger notification for recently created matches (within last 30 seconds)
                    guard timeDifference < 30.0 else {
                        print("💕 Match is older than 30 seconds, skipping notification (likely initial listener setup)")
                        continue
                    }
                    
                    // Fetch the other user's profile information
                    Task {
                        do {
                            let otherUserProfile = try await self.fetchUserProfile(for: otherUserId, forMatches: true)
                            let matchDisplay = MatchDisplay(
                                id: documentChange.document.documentID,
                                otherUser: otherUserProfile,
                                matchedAt: Date(timeIntervalSince1970: matchedAt),
                                lastMessageAt: nil
                            )
                            
                            print("💕 Calling completion with match: \(otherUserProfile.name)")
                            await MainActor.run {
                                completion(matchDisplay)
                            }
                        } catch {
                            print("❌ Error fetching profile for new match: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    func listenForNewMessages(completion: @escaping (String, String, String?, String, String, MessageType, TimeInterval?, Date, Bool) -> Void) {
        guard let currentUserId = auth.currentUser?.uid else {
            print("❌ User not authenticated for message listening")
            return
        }
        
        print("💬 Starting to listen for new messages for user: \(currentUserId)")
        
        // Listen to incoming messages collection
        let incomingMessagesRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        
        incomingMessagesRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Error listening for messages: \(error)")
                return
            }
            
            guard let snapshot = snapshot else {
                print("❌ No snapshot received for messages")
                return
            }
            
            print("💬 Snapshot received: \(snapshot.documentChanges.count) document changes, \(snapshot.documents.count) total documents")
            print("💬 Snapshot metadata - hasPendingWrites: \(snapshot.metadata.hasPendingWrites), isFromCache: \(snapshot.metadata.isFromCache)")
            print("💬 All document change types in snapshot:")
            for change in snapshot.documentChanges {
                print("💬   - Type: \(change.type.rawValue), Doc ID: \(change.document.documentID)")
            }
            
            // Skip notifications for initial cache load
            if snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites {
                print("💬 Snapshot is from cache (initial load), skipping notifications for existing messages")
                return
            }
            
            // Check for new messages (documents that were added)
            for documentChange in snapshot.documentChanges {
                print("💬 Processing document change type: \(documentChange.type.rawValue)")
                print("💬 Message document ID: \(documentChange.document.documentID)")
                
                if documentChange.type == .added {
                    print("💬 New message document added")
                    let data = documentChange.document.data()
                    print("💬 Message data fields: \(data.keys)")
                    guard let senderId = data["senderId"] as? String,
                          let createdAt = data["createdAt"] as? TimeInterval else {
                        print("❌ Missing required fields in message document - senderId: \(data["senderId"] ?? "nil"), createdAt: \(data["createdAt"] ?? "nil")")
                        continue
                    }
                    
                    // Only show notification for recent messages (within last 10 seconds)
                    // This ensures we notify for newly received messages, not old ones when listener first starts
                    let messageTime = Date(timeIntervalSince1970: createdAt)
                    let timeDifference = Date().timeIntervalSince(messageTime)
                    guard timeDifference < 10.0 else {
                        print("💬 Message is older than 10 seconds, skipping notification (likely initial listener setup)")
                        continue
                    }
                    
                    let messageDocId = documentChange.document.documentID
                    print("💬 New message from sender: \(senderId), created \(timeDifference) seconds ago, document ID: \(messageDocId)")
                    
                    let content = data["content"] as? String ?? ""
                    let typeString = data["type"] as? String ?? "text"
                    let messageType = MessageType(rawValue: typeString) ?? .text
                    let voiceDuration = data["voiceDuration"] as? TimeInterval
                    
                    DispatchQueue.main.async {
                        completion(
                            senderId,
                            "",
                            nil,
                            messageDocId,
                            content,
                            messageType,
                            voiceDuration,
                            messageTime,
                            false
                        )
                    }
                    
                    // Fetch sender's profile information for notifications
                    Task {
                        do {
                            let senderProfile = try await self.fetchUserProfile(for: senderId)
                            print("💬 Calling completion with sender: \(senderProfile.name)")
                            await MainActor.run {
                                completion(
                                    senderId,
                                    senderProfile.name,
                                    senderProfile.imageURL,
                                    messageDocId,
                                    content,
                                    messageType,
                                    voiceDuration,
                                    messageTime,
                                    true
                                )
                            }
                        } catch {
                            print("❌ Error fetching sender profile for new message: \(error)")
                            // Lighter fallback - name-only lookup often still works.
                            let fallbackName = (try? await self.fetchSenderName(for: senderId)) ?? "Unknown User"
                            let fallbackPhoto = try? await self.fetchUserProfilePhotoURL(for: senderId)
                            await MainActor.run {
                                completion(
                                    senderId,
                                    fallbackName,
                                    fallbackPhoto,
                                    messageDocId,
                                    content,
                                    messageType,
                                    voiceDuration,
                                    messageTime,
                                    true
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Message Functions (Simplified Structure)
    
    func sendMessage(to recipientId: String, content: String) async throws -> String {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        if try await isBlockedBy(userId: recipientId) {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "You have been blocked by this user"]
            )
        }
        
        print("💬 Sending message from \(currentUserId) to \(recipientId)")
        
        let messageId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        // Create message data
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": currentUserId,
            "recipientId": recipientId,
            "content": content,
            "type": "text",
            "createdAt": timestamp,
            "isRead": false,
            "readAt": NSNull()
        ]
        
        // Save to sender's "sent" collection
        let senderRef = db.collection("users").document(currentUserId).collection("sentMessages").document(messageId)
        try await senderRef.setData(messageData)
        
        // Save to recipient's "incoming" collection
        let recipientRef = db.collection("users").document(recipientId).collection("incomingMessages").document(messageId)
        try await recipientRef.setData(messageData)
        
        print("✅ Message sent successfully with ID: \(messageId)")
        return messageId
    }
    
    func sendImageMessage(to recipientId: String, imageURL: String) async throws -> String {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        if try await isBlockedBy(userId: recipientId) {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "You have been blocked by this user"]
            )
        }
        
        print("💬 Sending image message from \(currentUserId) to \(recipientId)")
        
        let messageId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        // Create message data with image type
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": currentUserId,
            "recipientId": recipientId,
            "content": imageURL, // Store image URL in content field
            "type": "image",
            "createdAt": timestamp,
            "isRead": false,
            "readAt": NSNull()
        ]
        
        // Save to sender's "sent" collection
        let senderRef = db.collection("users").document(currentUserId).collection("sentMessages").document(messageId)
        try await senderRef.setData(messageData)
        
        // Save to recipient's "incoming" collection
        let recipientRef = db.collection("users").document(recipientId).collection("incomingMessages").document(messageId)
        try await recipientRef.setData(messageData)
        
        print("✅ Image message sent successfully with ID: \(messageId)")
        return messageId
    }
    
    func sendVoiceMessage(to recipientId: String, audioURL: String, duration: TimeInterval) async throws -> String {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        if try await isBlockedBy(userId: recipientId) {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "You have been blocked by this user"]
            )
        }
        
        print("🎙️ Sending voice message from \(currentUserId) to \(recipientId)")
        
        let messageId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": currentUserId,
            "recipientId": recipientId,
            "content": audioURL,
            "type": "voice",
            "voiceDuration": duration,
            "createdAt": timestamp,
            "isRead": false,
            "readAt": NSNull()
        ]
        
        let senderRef = db.collection("users").document(currentUserId).collection("sentMessages").document(messageId)
        try await senderRef.setData(messageData)
        
        let recipientRef = db.collection("users").document(recipientId).collection("incomingMessages").document(messageId)
        try await recipientRef.setData(messageData)
        
        print("✅ Voice message sent successfully with ID: \(messageId)")
        return messageId
    }
    
    func fetchSentMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching sent messages for user: \(currentUserId)")
        
        let sentRef = db.collection("users").document(currentUserId).collection("sentMessages")
        let snapshot = try await sentRef.order(by: "createdAt", descending: true).getDocuments()
        
        var messages: [MessageDisplay] = []
        
        for document in snapshot.documents {
            let data = document.data()
            print("💬 fetchSentMessages: Processing document: \(document.documentID)")
            print("💬 fetchSentMessages: Document data: \(data)")
            
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { 
                print("❌ fetchSentMessages: Missing required fields in document")
                continue 
            }
            
            print("💬 fetchSentMessages: Message content: \(content)")
            print("💬 fetchSentMessages: Sender ID: \(senderId)")
            print("💬 fetchSentMessages: Recipient ID: \(recipientId)")
            
            // Create a UUID from the Firebase UID string
            // Firebase UIDs are not valid UUID strings, so we'll create a deterministic UUID
            let senderUUID = UUID(uuidString: senderId) ?? UUID()
            
            let message = Message(
                conversationId: UUID(), // Not used in this structure
                senderId: senderUUID,
                senderFirebaseId: senderId,
                content: content,
                type: MessageType(rawValue: (data["type"] as? String) ?? "text") ?? .text,
                voiceDuration: data["voiceDuration"] as? TimeInterval
            )
            
            // Fetch recipient name and profile photo
            let recipientName = try await fetchRecipientName(for: recipientId)
            let recipientProfilePhotoURL = try await fetchUserProfilePhotoURL(for: recipientId)
            
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: "You", // Current user is the sender
                recipientName: recipientName,
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: nil, // Current user's profile photo not needed for sent messages
                recipientProfilePhotoURL: recipientProfilePhotoURL
            )
            
            messages.append(messageDisplay)
        }
        
        print("💬 Fetched \(messages.count) sent messages")
        return messages
    }
    
    func fetchIncomingMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching incoming messages for user: \(currentUserId)")
        
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.order(by: "createdAt", descending: true).getDocuments()
        
        var messages: [MessageDisplay] = []
        
        for document in snapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            // Create a UUID from the Firebase UID string
            // Firebase UIDs are not valid UUID strings, so we'll create a deterministic UUID
            let senderUUID = UUID(uuidString: senderId) ?? UUID()
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(), // Not used in this structure
                senderId: senderUUID,
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            // Fetch sender name and profile photo
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You", // Current user is the recipient
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil // Current user's profile photo not needed for incoming messages
            )
            
            messages.append(messageDisplay)
        }
        
        print("💬 Fetched \(messages.count) incoming messages")
        return messages
    }
    
    func fetchAllConversationsForExport(
        forUserId subjectUserId: String? = nil,
        userName subjectUserName: String? = nil
    ) async throws -> (currentUserName: String, currentUserId: String, conversations: [MessagesExportConversation]) {
        let exportUserId: String
        let exportUserName: String

        if let subjectUserId {
            try requireAdmin()
            exportUserId = subjectUserId
            let trimmed = subjectUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            exportUserName = trimmed.isEmpty ? "settings.export.messages.you".localized : trimmed
        } else {
            guard let currentUserId = auth.currentUser?.uid else {
                throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
            }
            exportUserId = currentUserId
            exportUserName = currentUser?.name
                ?? AppStateManager.shared.currentUser?.name
                ?? "settings.export.messages.you".localized
        }

        let cutoffDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date().addingTimeInterval(-15_552_000)
        let cutoffTimestamp = cutoffDate.timeIntervalSince1970

        async let sentSnapshotTask = db.collection("users")
            .document(exportUserId)
            .collection("sentMessages")
            .whereField("createdAt", isGreaterThanOrEqualTo: cutoffTimestamp)
            .getDocuments()
        async let incomingSnapshotTask = db.collection("users")
            .document(exportUserId)
            .collection("incomingMessages")
            .whereField("createdAt", isGreaterThanOrEqualTo: cutoffTimestamp)
            .getDocuments()

        let sentSnapshot = try await sentSnapshotTask
        let incomingSnapshot = try await incomingSnapshotTask

        struct RawMessage {
            let data: [String: Any]
            let otherUserId: String
            let isOutgoing: Bool
        }

        var rawMessages: [RawMessage] = []
        var partnerIds = Set<String>()

        for document in sentSnapshot.documents {
            let data = document.data()
            guard let recipientId = data["recipientId"] as? String, !recipientId.isEmpty else { continue }
            if let createdAt = data["createdAt"] as? TimeInterval, createdAt < cutoffTimestamp {
                continue
            }
            partnerIds.insert(recipientId)
            rawMessages.append(RawMessage(data: data, otherUserId: recipientId, isOutgoing: true))
        }

        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let senderId = data["senderId"] as? String, !senderId.isEmpty else { continue }
            if let createdAt = data["createdAt"] as? TimeInterval, createdAt < cutoffTimestamp {
                continue
            }
            partnerIds.insert(senderId)
            rawMessages.append(RawMessage(data: data, otherUserId: senderId, isOutgoing: false))
        }

        let profiles = await fetchUserSummaries(for: Array(partnerIds))

        var grouped: [String: [MessageDisplay]] = [:]
        for raw in rawMessages {
            let partnerName = profiles[raw.otherUserId]?.name ?? "Unknown User"
            guard let display = messageDisplay(
                from: raw.data,
                currentUserId: exportUserId,
                otherUserId: raw.otherUserId,
                otherUserName: partnerName,
                otherUserPhotoURL: profiles[raw.otherUserId]?.photoURL,
                currentUserPhotoURL: nil,
                isOutgoing: raw.isOutgoing
            ) else { continue }
            guard display.createdAt >= cutoffDate else { continue }
            grouped[raw.otherUserId, default: []].append(display)
        }

        let conversations = grouped.compactMap { partnerId, messages -> MessagesExportConversation? in
            let sorted = messages.sorted { $0.createdAt < $1.createdAt }
            guard !sorted.isEmpty else { return nil }
            return MessagesExportConversation(
                partnerName: profiles[partnerId]?.name ?? sorted.first?.recipientName ?? "Unknown User",
                messages: sorted
            )
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.messages.last?.createdAt ?? .distantPast
            let rhsDate = rhs.messages.last?.createdAt ?? .distantPast
            return lhsDate > rhsDate
        }

        return (exportUserName, exportUserId, conversations)
    }

    func fetchSenderName(for senderId: String) async throws -> String {
        let userDoc = try await db.collection("users").document(senderId).getDocument()
        guard let userData = userDoc.data() else {
            return "Unknown User"
        }
        
        let rawName = (userData["name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawName.isEmpty,
           rawName.caseInsensitiveCompare("Unknown") != .orderedSame,
           rawName.caseInsensitiveCompare("Unknown User") != .orderedSame {
            return rawName
        }
        
        let displayName = (userData["displayName"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            return displayName
        }
        
        return "Unknown User"
    }
    
    func fetchRecipientName(for recipientId: String) async throws -> String {
        print("💬 fetchRecipientName: Looking up recipient ID: \(recipientId)")
        
        let userDoc = try await db.collection("users").document(recipientId).getDocument()
        
        if !userDoc.exists {
            print("❌ fetchRecipientName: User document does not exist for ID: \(recipientId)")
            return "Unknown User"
        }
        
        guard let userData = userDoc.data() else {
            print("❌ fetchRecipientName: No data found for user ID: \(recipientId)")
            return "Unknown User"
        }
        
        guard let name = userData["name"] as? String else {
            print("❌ fetchRecipientName: No name field found for user ID: \(recipientId)")
            print("💬 fetchRecipientName: User data: \(userData)")
            return "Unknown User"
        }
        
        print("✅ fetchRecipientName: Found name '\(name)' for user ID: \(recipientId)")
        return name
    }
    
    func fetchUserProfilePhotoURL(for userId: String) async throws -> String? {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            return nil
        }
        return userData["profilePhotoURL"] as? String
    }
    
    /// Fetch the latest message content from a sender (for notifications)
    func fetchLatestMessageContent(from senderId: String) async throws -> String? {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest message content from sender: \(senderId)")
        
        // Fetch incoming messages from this sender
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: senderId).order(by: "createdAt", descending: true).limit(to: 1).getDocuments()
        
        if let document = snapshot.documents.first {
            let data = document.data()
            guard let content = data["content"] as? String else {
                print("❌ Missing content field in message document")
                return nil
            }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            
            // If it's an image message, return a placeholder text
            if messageType == .image {
                return "messages.preview.photo".localized
            }
            
            if messageType == .voice {
                return "messages.preview.voice".localized
            }
            
            return content
        }
        
        return nil
    }
    
    func fetchLatestMessageFromSender(senderId: String) async throws -> MessageDisplay? {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest message from sender: \(senderId)")
        
        // Fetch incoming messages from this sender
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: senderId).order(by: "createdAt", descending: true).limit(to: 1).getDocuments()
        
        if let document = snapshot.documents.first {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else {
                print("❌ Missing required fields in message document")
                return nil
            }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(),
                senderId: UUID(uuidString: senderId) ?? UUID(),
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            // Fetch sender name and photo
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You",
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil
            )
            
            print("💬 Created MessageDisplay for sender: \(senderName)")
            return messageDisplay
        }
        
        print("💬 No message found from sender: \(senderId)")
        return nil
    }
    
    // Fetch a page of conversation messages (newest first, returned oldest-first for display)
    func fetchConversationMessagesPage(
        with otherUserId: String,
        limit: Int = 10,
        before: Date? = nil
    ) async throws -> ConversationMessagesPage {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching conversation page (limit: \(limit), before: \(before?.formattedTimestamp() ?? "nil")) with \(otherUserId)")
        
        async let otherUserNameTask = fetchSenderName(for: otherUserId)
        async let otherUserPhotoTask = fetchUserProfilePhotoURL(for: otherUserId)
        async let currentUserPhotoTask = fetchUserProfilePhotoURL(for: currentUserId)
        async let sentDocsTask = fetchFilteredMessageDocuments(
            collection: "sentMessages",
            filterField: "recipientId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: limit,
            before: before
        )
        async let incomingDocsTask = fetchFilteredMessageDocuments(
            collection: "incomingMessages",
            filterField: "senderId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: limit,
            before: before
        )
        
        let otherUserName = try await otherUserNameTask
        let otherUserPhoto = try await otherUserPhotoTask
        let currentUserPhoto = try await currentUserPhotoTask
        let sentDocs = try await sentDocsTask
        let incomingDocs = try await incomingDocsTask
        
        var merged: [(createdAt: TimeInterval, display: MessageDisplay)] = []
        
        for document in sentDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: true
            ) {
                merged.append((display.createdAt.timeIntervalSince1970, display))
            }
        }
        
        for document in incomingDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: false
            ) {
                merged.append((display.createdAt.timeIntervalSince1970, display))
            }
        }
        
        merged.sort { $0.createdAt > $1.createdAt }
        let pageMessages = Array(merged.prefix(limit)).map(\.display).sorted { $0.createdAt < $1.createdAt }
        let hasMoreOlder = merged.count > limit || sentDocs.count == limit || incomingDocs.count == limit
        
        print("💬 Fetched conversation page: \(pageMessages.count) messages, hasMoreOlder: \(hasMoreOlder)")
        return ConversationMessagesPage(messages: pageMessages, hasMoreOlder: hasMoreOlder)
    }
    
    /// Fetch only messages newer than a timestamp (for lightweight refresh)
    func fetchConversationMessagesNewerThan(with otherUserId: String, since: Date) async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let sinceTimestamp = since.timeIntervalSince1970
        
        async let otherUserNameTask = fetchSenderName(for: otherUserId)
        async let otherUserPhotoTask = fetchUserProfilePhotoURL(for: otherUserId)
        async let currentUserPhotoTask = fetchUserProfilePhotoURL(for: currentUserId)
        async let sentDocsTask = fetchFilteredMessageDocuments(
            collection: "sentMessages",
            filterField: "recipientId",
            filterValue: otherUserId,
            userId: currentUserId,
            after: sinceTimestamp
        )
        async let incomingDocsTask = fetchFilteredMessageDocuments(
            collection: "incomingMessages",
            filterField: "senderId",
            filterValue: otherUserId,
            userId: currentUserId,
            after: sinceTimestamp
        )
        
        let otherUserName = try await otherUserNameTask
        let otherUserPhoto = try await otherUserPhotoTask
        let currentUserPhoto = try await currentUserPhotoTask
        let sentDocs = try await sentDocsTask
        let incomingDocs = try await incomingDocsTask
        
        var messages: [MessageDisplay] = []
        
        for document in sentDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: true
            ) {
                messages.append(display)
            }
        }
        
        for document in incomingDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: false
            ) {
                messages.append(display)
            }
        }
        
        return messages.sorted { $0.createdAt < $1.createdAt }
    }
    
    // Fetch all messages between current user and another user (legacy - prefer paginated API)
    func fetchConversationMessages(with otherUserId: String) async throws -> [MessageDisplay] {
        let page = try await fetchConversationMessagesPage(with: otherUserId, limit: 10)
        return page.messages
    }
    
    // Fetch only message content without profile photos (for auto-refresh)
    func fetchConversationMessagesContentOnly(with otherUserId: String) async throws -> [Message] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching recent conversation message content only with \(otherUserId)")
        
        async let sentDocsTask = fetchFilteredMessageDocuments(
            collection: "sentMessages",
            filterField: "recipientId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: 20
        )
        async let incomingDocsTask = fetchFilteredMessageDocuments(
            collection: "incomingMessages",
            filterField: "senderId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: 20
        )
        
        let sentDocs = try await sentDocsTask
        let incomingDocs = try await incomingDocsTask
        
        var allMessages: [Message] = []
        
        for document in sentDocs + incomingDocs {
            if let message = messageFromDocument(document.data()) {
                allMessages.append(message)
            }
        }
        
        return allMessages.sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Scan all of the current user's sent + incoming messages and return partner IDs
    /// whose message content matches `query` (case-insensitive).
    func findConversationPartnerIds(matching query: String) async throws -> Set<String> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        async let sentSnapshotTask = db.collection("users")
            .document(currentUserId)
            .collection("sentMessages")
            .getDocuments()
        async let incomingSnapshotTask = db.collection("users")
            .document(currentUserId)
            .collection("incomingMessages")
            .getDocuments()
        
        let sentSnapshot = try await sentSnapshotTask
        let incomingSnapshot = try await incomingSnapshotTask
        
        var matchingPartnerIds = Set<String>()
        
        for document in sentSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  content.localizedCaseInsensitiveContains(trimmed),
                  let recipientId = data["recipientId"] as? String else { continue }
            matchingPartnerIds.insert(recipientId)
        }
        
        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  content.localizedCaseInsensitiveContains(trimmed),
                  let senderId = data["senderId"] as? String else { continue }
            matchingPartnerIds.insert(senderId)
        }
        
        print("💬 History search for \"\(trimmed)\": \(matchingPartnerIds.count) conversation(s)")
        return matchingPartnerIds
    }
    
    // Get latest message from each user (for conversation list)
    func fetchLatestMessagesFromEachUser() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest messages from each user...")
        
        let recentLimit = 100
        
        async let sentSnapshotTask = db.collection("users")
            .document(currentUserId)
            .collection("sentMessages")
            .order(by: "createdAt", descending: true)
            .limit(to: recentLimit)
            .getDocuments()
        async let incomingSnapshotTask = db.collection("users")
            .document(currentUserId)
            .collection("incomingMessages")
            .order(by: "createdAt", descending: true)
            .limit(to: recentLimit)
            .getDocuments()
        
        let sentSnapshot = try await sentSnapshotTask
        let incomingSnapshot = try await incomingSnapshotTask
        
        struct LatestCandidate {
            let otherUserId: String
            let data: [String: Any]
            let createdAt: TimeInterval
            let isOutgoing: Bool
        }
        
        var latestByUser: [String: LatestCandidate] = [:]
        
        for document in sentSnapshot.documents {
            let data = document.data()
            guard let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            if let existing = latestByUser[recipientId], existing.createdAt >= createdAt {
                continue
            }
            
            latestByUser[recipientId] = LatestCandidate(
                otherUserId: recipientId,
                data: data,
                createdAt: createdAt,
                isOutgoing: true
            )
        }
        
        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let senderId = data["senderId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            if let existing = latestByUser[senderId], existing.createdAt >= createdAt {
                continue
            }
            
            latestByUser[senderId] = LatestCandidate(
                otherUserId: senderId,
                data: data,
                createdAt: createdAt,
                isOutgoing: false
            )
        }
        
        let profiles = await fetchUserSummaries(for: Array(latestByUser.keys))
        
        var latestMessages: [MessageDisplay] = []
        for candidate in latestByUser.values {
            let summary = profiles[candidate.otherUserId]
            let otherName = summary?.name ?? "Unknown User"
            let otherPhoto = summary?.photoURL
            
            if let display = messageDisplay(
                from: candidate.data,
                currentUserId: currentUserId,
                otherUserId: candidate.otherUserId,
                otherUserName: otherName,
                otherUserPhotoURL: otherPhoto,
                currentUserPhotoURL: nil,
                isOutgoing: candidate.isOutgoing
            ) {
                latestMessages.append(display)
            }
        }
        
        latestMessages.sort { $0.createdAt > $1.createdAt }
        
        print("💬 Final result: \(latestMessages.count) unique conversations")
        return latestMessages
    }
    
    func fetchLatestMessageForConversation(with otherUserId: String) async throws -> MessageDisplay? {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let sentSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("sentMessages")
            .whereField("recipientId", isEqualTo: otherUserId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        let incomingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("incomingMessages")
            .whereField("senderId", isEqualTo: otherUserId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        var sentMessage: MessageDisplay?
        if let document = sentSnapshot.documents.first,
           let candidate = try await conversationCandidate(
            from: document.data(),
            currentUserId: currentUserId,
            isOutgoing: true
           ) {
            sentMessage = candidate.message
        }
        
        var incomingMessage: MessageDisplay?
        if let document = incomingSnapshot.documents.first,
           let candidate = try await conversationCandidate(
            from: document.data(),
            currentUserId: currentUserId,
            isOutgoing: false
           ) {
            incomingMessage = candidate.message
        }
        
        switch (sentMessage, incomingMessage) {
        case (nil, nil):
            return nil
        case (let sent?, nil):
            return sent
        case (nil, let incoming?):
            return incoming
        case (let sent?, let incoming?):
            return sent.createdAt >= incoming.createdAt ? sent : incoming
        }
    }
    
    private func fetchFilteredMessageDocuments(
        collection: String,
        filterField: String,
        filterValue: String,
        userId: String,
        limit: Int? = nil,
        before: Date? = nil,
        after: TimeInterval? = nil
    ) async throws -> [QueryDocumentSnapshot] {
        var query: Query = db.collection("users")
            .document(userId)
            .collection(collection)
            .whereField(filterField, isEqualTo: filterValue)
        
        if let after {
            query = query
                .whereField("createdAt", isGreaterThan: after)
                .order(by: "createdAt", descending: false)
        } else if let before {
            query = query
                .whereField("createdAt", isLessThan: before.timeIntervalSince1970)
                .order(by: "createdAt", descending: true)
        } else {
            query = query.order(by: "createdAt", descending: true)
        }
        
        if let limit {
            query = query.limit(to: limit)
        }
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents
    }
    
    private func messageFromDocument(_ data: [String: Any]) -> Message? {
        guard let content = data["content"] as? String,
              let senderId = data["senderId"] as? String,
              let createdAt = Self.timeIntervalValue(data["createdAt"]) else {
            return nil
        }
        
        let messageTypeString = data["type"] as? String ?? "text"
        let messageType = MessageType(rawValue: messageTypeString) ?? .text
        let voiceDuration = Self.timeIntervalValue(data["voiceDuration"])
        
        return Message(
            conversationId: UUID(),
            senderId: UUID(uuidString: senderId) ?? UUID(),
            senderFirebaseId: senderId,
            content: content,
            createdAt: Date(timeIntervalSince1970: createdAt),
            type: messageType,
            voiceDuration: voiceDuration
        )
    }
    
    /// Firestore may return Int or Double for numeric fields.
    private static func timeIntervalValue(_ value: Any?) -> TimeInterval? {
        if let value = value as? TimeInterval {
            return value
        }
        if let value = value as? Int {
            return TimeInterval(value)
        }
        if let value = value as? Float {
            return TimeInterval(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
    
    private func messageDisplay(
        from data: [String: Any],
        currentUserId: String,
        otherUserId: String,
        otherUserName: String,
        otherUserPhotoURL: String?,
        currentUserPhotoURL: String?,
        isOutgoing: Bool
    ) -> MessageDisplay? {
        guard let message = messageFromDocument(data) else { return nil }
        
        if isOutgoing {
            return MessageDisplay(
                message: message,
                senderName: "You",
                recipientName: otherUserName,
                senderId: currentUserId,
                recipientId: otherUserId,
                senderProfilePhotoURL: currentUserPhotoURL,
                recipientProfilePhotoURL: otherUserPhotoURL
            )
        }
        
        return MessageDisplay(
            message: message,
            senderName: otherUserName,
            recipientName: "You",
            senderId: otherUserId,
            recipientId: currentUserId,
            senderProfilePhotoURL: otherUserPhotoURL,
            recipientProfilePhotoURL: currentUserPhotoURL
        )
    }
    
    private struct UserSummary {
        let name: String
        let photoURL: String?
    }
    
    private func fetchUserSummaries(for userIds: [String]) async -> [String: UserSummary] {
        guard !userIds.isEmpty else { return [:] }
        
        var summaries: [String: UserSummary] = [:]
        
        await withTaskGroup(of: (String, UserSummary?).self) { group in
            for userId in userIds {
                group.addTask {
                    do {
                        let name = try await self.fetchSenderName(for: userId)
                        let photoURL = try await self.fetchUserProfilePhotoURL(for: userId)
                        return (userId, UserSummary(name: name, photoURL: photoURL))
                    } catch {
                        return (userId, nil)
                    }
                }
            }
            
            for await (userId, summary) in group {
                if let summary {
                    summaries[userId] = summary
                }
            }
        }
        
        return summaries
    }
    
    private func conversationCandidate(
        from data: [String: Any],
        currentUserId: String,
        isOutgoing: Bool
    ) async throws -> (otherUserId: String, message: MessageDisplay, createdAt: TimeInterval)? {
        guard let content = data["content"] as? String,
              let senderId = data["senderId"] as? String,
              let recipientId = data["recipientId"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval else {
            return nil
        }
        
        let messageTypeString = data["type"] as? String ?? "text"
        let messageType = MessageType(rawValue: messageTypeString) ?? .text
        let voiceDuration = data["voiceDuration"] as? TimeInterval
        
        let message = Message(
            conversationId: UUID(),
            senderId: UUID(uuidString: senderId) ?? UUID(),
            senderFirebaseId: senderId,
            content: content,
            createdAt: Date(timeIntervalSince1970: createdAt),
            type: messageType,
            voiceDuration: voiceDuration
        )
        
        if isOutgoing {
            let recipientName = try await fetchRecipientName(for: recipientId)
            let recipientProfilePhotoURL = try await fetchUserProfilePhotoURL(for: recipientId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: "You",
                recipientName: recipientName,
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: nil,
                recipientProfilePhotoURL: recipientProfilePhotoURL
            )
            return (recipientId, messageDisplay, createdAt)
        } else {
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You",
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil
            )
            return (senderId, messageDisplay, createdAt)
        }
    }
    
    // Get latest sent message to each user
    func fetchLatestSentMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest sent messages...")
        
        var recipientLatestMessages: [String: MessageDisplay] = [:]
        
        // Fetch sent messages
        let sentSnapshot = try await db.collection("users").document(currentUserId).collection("sentMessages").getDocuments()
        for document in sentSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(),
                senderId: UUID(uuidString: senderId) ?? UUID(),
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            let recipientName = try await fetchRecipientName(for: recipientId)
            let recipientProfilePhotoURL = try await fetchUserProfilePhotoURL(for: recipientId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: "You",
                recipientName: recipientName,
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: nil,
                recipientProfilePhotoURL: recipientProfilePhotoURL
            )
            
            // Keep only the latest message for each recipient
            if let existingMessage = recipientLatestMessages[recipientId] {
                if messageDisplay.createdAt > existingMessage.createdAt {
                    recipientLatestMessages[recipientId] = messageDisplay
                }
            } else {
                recipientLatestMessages[recipientId] = messageDisplay
            }
        }
        
        // Convert to array and sort by latest message time
        let latestMessages = Array(recipientLatestMessages.values)
            .sorted { $0.createdAt > $1.createdAt }
        
        print("💬 Fetched \(latestMessages.count) latest sent messages")
        return latestMessages
    }
    
    // Get latest incoming message from each user
    func fetchLatestIncomingMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest incoming messages...")
        
        var senderLatestMessages: [String: MessageDisplay] = [:]
        
        // Fetch incoming messages
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(),
                senderId: UUID(uuidString: senderId) ?? UUID(),
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You",
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil
            )
            
            // Keep only the latest message for each sender
            if let existingMessage = senderLatestMessages[senderId] {
                if messageDisplay.createdAt > existingMessage.createdAt {
                    senderLatestMessages[senderId] = messageDisplay
                }
            } else {
                senderLatestMessages[senderId] = messageDisplay
            }
        }
        
        // Convert to array and sort by latest message time
        let latestMessages = Array(senderLatestMessages.values)
            .sorted { $0.createdAt > $1.createdAt }
        
        print("💬 Fetched \(latestMessages.count) latest incoming messages")
        return latestMessages
    }
    
    // MARK: - Delete All User Data
    
    /// Delete all swipes for the current user
    func deleteAllSwipes() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("🗑️ Deleting all swipes for user: \(currentUserId)")
        
        let swipesRef = db.collection("users").document(currentUserId).collection("swipes")
        let snapshot = try await swipesRef.getDocuments()
        
        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        print("✅ Deleted \(snapshot.documents.count) swipes")
    }

    /// Resets first-pass (cooldown) swipes so those profiles can show again.
    /// Permanent 2nd+ passes are kept and never reappear.
    func resetPassSwipesToNew() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        print("🔄 Resetting first-pass swipes to new for user: \(currentUserId)")

        let swipesRef = db.collection("users").document(currentUserId).collection("swipes")
        let snapshot = try await swipesRef.whereField("action", isEqualTo: SwipeType.pass.rawValue).getDocuments(source: .server)

        guard !snapshot.documents.isEmpty else {
            print("✅ No pass swipes to reset")
            return
        }

        var passDocsByUser: [String: [QueryDocumentSnapshot]] = [:]
        for document in snapshot.documents {
            guard let toUserId = document.data()["toUserId"] as? String else { continue }
            passDocsByUser[toUserId, default: []].append(document)
        }

        var documentsToDelete: [QueryDocumentSnapshot] = []
        for (_, docs) in passDocsByUser {
            let passCount = effectivePassCount(from: docs.map { $0.data() })
            // Only clear first-pass history; keep permanent (2+) bans.
            if passCount < 2 {
                documentsToDelete.append(contentsOf: docs)
            }
        }

        guard !documentsToDelete.isEmpty else {
            print("✅ No first-pass swipes to reset (permanent passes kept)")
            return
        }

        let batchSize = 450
        for batchStart in stride(from: 0, to: documentsToDelete.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, documentsToDelete.count)
            let batch = db.batch()
            for document in documentsToDelete[batchStart..<batchEnd] {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }

        let remainingSnapshot = try await swipesRef.whereField("action", isEqualTo: SwipeType.pass.rawValue).getDocuments(source: .server)
        print("✅ Reset \(documentsToDelete.count) first-pass swipes. Remaining pass swipes: \(remainingSnapshot.documents.count)")
    }
    
    /// Delete only pass swipes for the current user.
    /// Keeps likes intact, so matches history remains untouched.
    func deletePassSwipes() async throws {
        try await resetPassSwipesToNew()
    }
    
    /// Delete all matches for the current user and the other user in each match pair.
    func deleteAllMatches() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("🗑️ Deleting all matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        let snapshot = try await matchesRef.getDocuments()
        
        var deletedCount = 0
        
        for document in snapshot.documents {
            let data = document.data()
            let matchId = document.documentID
            let user1Id = data["user1Id"] as? String
            let user2Id = data["user2Id"] as? String
            
            var refsToDelete = [document.reference]
            
            if let user1Id, let user2Id {
                let otherUserId = user1Id == currentUserId ? user2Id : user1Id
                let otherRef = db.collection("users")
                    .document(otherUserId)
                    .collection("matches")
                    .document(matchId)
                refsToDelete.append(otherRef)
            }
            
            let batch = db.batch()
            refsToDelete.forEach { batch.deleteDocument($0) }
            try await batch.commit()
            deletedCount += 1
        }
        
        print("✅ Deleted \(deletedCount) match pair(s)")
    }
    
    /// Delete all messages for the current user (both incoming and sent)
    func deleteAllMessages() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("🗑️ Deleting all messages for user: \(currentUserId)")
        
        // Delete incoming messages
        let incomingMessagesRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let incomingSnapshot = try await incomingMessagesRef.getDocuments()
        
        // Delete sent messages
        let sentMessagesRef = db.collection("users").document(currentUserId).collection("sentMessages")
        let sentSnapshot = try await sentMessagesRef.getDocuments()
        
        let batch = db.batch()
        for document in incomingSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        for document in sentSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        print("✅ Deleted \(incomingSnapshot.documents.count) incoming messages and \(sentSnapshot.documents.count) sent messages")
        
        // Note: Messages sent by this user that are stored in other users' incomingMessages collections
        // will remain, as we cannot easily query all users' collections to find them.
        // This is a limitation but acceptable for a reset operation.
    }
    
    /// Count total matches for the current user
    func countMatches() async throws -> Int {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Counting matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        let snapshot = try await matchesRef.getDocuments()
        
        let count = snapshot.documents.count
        print("💕 Found \(count) matches")
        return count
    }
    
    /// Delete all swipes, matches, and messages for the current user
    func deleteAllUserInteractions() async throws {
        try await deleteAllSwipes()
        try await deleteAllMatches()
        try await deleteAllMessages()
        print("✅ All user interactions deleted successfully")
    }
    
    private func fetchCurrentUserLocation() async throws -> Location? {
        guard let currentUserId = auth.currentUser?.uid else { return nil }
        
        let currentUserDoc = try await db.collection("users").document(currentUserId).getDocument()
        guard let userData = currentUserDoc.data() else { return nil }
        
        return Self.parseLocation(from: userData)
    }
}

extension FirebaseAuthService {
    /// Firestore may return numbers as `Double` or `NSNumber`; `as? Double` alone often fails.
    static func firestoreDouble(from value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }

    static func parseLocation(from userData: [String: Any]) -> Location {
        let locationData = userData["location"] as? [String: Any] ?? [:]
        return Location(
            displayString: locationData["displayString"] as? String ?? "",
            city: locationData["city"] as? String ?? "",
            state: locationData["state"] as? String ?? "",
            country: locationData["country"] as? String ?? "",
            latitude: firestoreDouble(from: locationData["latitude"]),
            longitude: firestoreDouble(from: locationData["longitude"])
        )
    }
}

private extension FirebaseAuthService {
    static func distance(from sourceLocation: Location, to targetLocation: Location) -> Double? {
        guard let sourceLat = sourceLocation.latitude,
              let sourceLon = sourceLocation.longitude,
              let targetLat = targetLocation.latitude,
              let targetLon = targetLocation.longitude else {
            return nil
        }
        
        let earthRadius: Double = 6371
        let dLat = (targetLat - sourceLat) * .pi / 180.0
        let dLon = (targetLon - sourceLon) * .pi / 180.0
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(sourceLat * .pi / 180.0) * cos(targetLat * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
    
    static func formatDistance(_ distanceKm: Double, forMatches: Bool = false) -> String {
        if distanceKm < 1.0 {
            let key = forMatches ? "matches.distance.km" : "search.distance.km"
            return String(format: key.localized, "1")
        }

        let roundedDistance = round(distanceKm * 10) / 10
        let key = forMatches ? "matches.distance.km" : "search.distance.km"
        if roundedDistance == floor(roundedDistance) {
            return String(format: key.localized, "\(Int(roundedDistance))")
        }

        return String(format: key.localized, String(format: "%.1f", roundedDistance))
    }
}

enum SpectRoomAuthError: LocalizedError {
    case accountPendingDeletion
    case accountBanned
    case accountFrozen(until: Date)
    case emailPendingDeletion
    case notAuthenticated
    case wrongPassword
    case notAdmin
    
    var errorDescription: String? {
        switch self {
        case .accountPendingDeletion:
            return "auth.error.account.pending.deletion".localized
        case .accountBanned:
            return "auth.error.account.banned".localized
        case .accountFrozen(let until):
            return String(
                format: "admin.freeze.login.message".localized,
                ModerationNotice.formattedUnlockDate(until)
            )
        case .emailPendingDeletion:
            return "auth.error.email.pending.deletion".localized
        case .notAuthenticated:
            return "auth.error".localized
        case .wrongPassword:
            return "settings.delete.account.wrong.password".localized
        case .notAdmin:
            return "admin.error.not.authorized".localized
        }
    }
}

import Foundation
import FirebaseStorage
import UIKit

class PhotoStorageService {
    static let shared = PhotoStorageService()
    private let storage = Storage.storage()
    
    private init() {}
    
    // MARK: - Profile Photo Upload
    func uploadProfilePhoto(_ image: UIImage, for userID: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoStorageError.invalidImageData
        }
        
        let fileName = "profile_\(userID)_\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("profile_photos/\(fileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        let _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Gallery Photos Upload
    func uploadMultipleGalleryPhotos(_ images: [UIImage], for userID: String) async throws -> [String] {
        var urls: [String] = []
        
        for image in images {
            let url = try await uploadGalleryPhoto(image, for: userID)
            urls.append(url)
        }
        
        return urls
    }
    
    private func uploadGalleryPhoto(_ image: UIImage, for userID: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoStorageError.invalidImageData
        }
        
        let fileName = "gallery_\(userID)_\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("gallery_photos/\(fileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        let _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Message Image Upload
    func uploadMessageImage(_ image: UIImage, for userID: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoStorageError.invalidImageData
        }
        
        let fileName = "message_\(userID)_\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("message_images/\(fileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        let _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Voice Message Upload
    func uploadVoiceMessage(_ fileURL: URL, for userID: String) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)
        
        let fileName = "voice_\(userID)_\(UUID().uuidString).m4a"
        let storageRef = storage.reference().child("voice_messages/\(fileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "audio/m4a"
        
        let _ = try await storageRef.putDataAsync(audioData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    // MARK: - Photo Deletion
    func deletePhoto(url: String) async throws {
        guard let url = URL(string: url) else {
            throw PhotoStorageError.invalidURL
        }
        
        let storageRef = storage.reference(forURL: url.absoluteString)
        
        // Check if the file exists before trying to delete it
        do {
            _ = try await storageRef.getMetadata()
            // File exists, proceed with deletion
            try await storageRef.delete()
            print("✅ Successfully deleted photo: \(url.absoluteString)")
        } catch {
            // Check if the error is because the file doesn't exist
            if let storageError = error as NSError?,
               storageError.domain == "FIRStorageErrorDomain",
               storageError.code == 404 {
                print("⚠️ Photo doesn't exist, skipping deletion: \(url.absoluteString)")
                // File doesn't exist, which is fine - just continue
                return
            } else {
                // Some other error occurred
                print("❌ Error deleting photo: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    // MARK: - Get User-Specific Photos
    func getUserGalleryPhotos(for userID: String) async throws -> [String] {
        print("📸 Getting gallery photos for user: \(userID)")
        
        do {
            // List all files in the gallery_photos folder
            let galleryPhotosRef = storage.reference().child("gallery_photos")
            let listResult = try await galleryPhotosRef.listAll()
            
            // Filter to only files that belong to this user
            let userGalleryPhotos = listResult.items.filter { item in
                return item.name.contains("gallery_\(userID)_")
            }
            
            // Get download URLs for user's gallery photos
            var photoURLs: [String] = []
            for item in userGalleryPhotos {
                let downloadURL = try await item.downloadURL()
                photoURLs.append(downloadURL.absoluteString)
            }
            
            print("📸 Found \(photoURLs.count) gallery photos for user \(userID)")
            return photoURLs
        } catch {
            print("❌ Error getting user gallery photos: \(error)")
            throw error
        }
    }
    
    // MARK: - Cleanup Orphaned Profile Photos
    func cleanupOrphanedProfilePhotos(for userID: String, currentProfilePhotoURL: String?) async {
        print("🧹 Cleaning up orphaned profile photos for user: \(userID)")
        
        do {
            // List all files in the profile_photos folder
            let profilePhotosRef = storage.reference().child("profile_photos")
            let listResult = try await profilePhotosRef.listAll()
            
            // Filter to only files that belong to this user
            let userProfilePhotos = listResult.items.filter { item in
                return item.name.contains("profile_\(userID)_")
            }
            
            // Delete all profile photos except the current one
            for photoRef in userProfilePhotos {
                if let currentURL = currentProfilePhotoURL {
                    // Don't delete the current profile photo
                    if !currentURL.contains(photoRef.name) {
                        do {
                            try await photoRef.delete()
                            print("🗑️ Deleted orphaned profile photo: \(photoRef.fullPath)")
                        } catch {
                            print("⚠️ Failed to delete orphaned profile photo \(photoRef.fullPath): \(error)")
                        }
                    }
                } else {
                    // No current profile photo, delete all user's profile photos
                    do {
                        try await photoRef.delete()
                        print("🗑️ Deleted orphaned profile photo: \(photoRef.fullPath)")
                    } catch {
                        print("⚠️ Failed to delete orphaned profile photo \(photoRef.fullPath): \(error)")
                    }
                }
            }
            
            print("✅ Profile photo cleanup completed")
        } catch {
            print("❌ Error during profile photo cleanup: \(error)")
        }
    }
}

// MARK: - Error Types
enum PhotoStorageError: Error, LocalizedError {
    case invalidImageData
    case invalidURL
    case uploadFailed
    case deletionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data"
        case .invalidURL:
            return "Invalid URL"
        case .uploadFailed:
            return "Photo upload failed"
        case .deletionFailed:
            return "Photo deletion failed"
        }
    }
}
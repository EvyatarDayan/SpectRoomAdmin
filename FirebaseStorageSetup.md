# Firebase Storage Setup Guide for SpectRoom

## 🔥 Setting up Firebase Storage for Photo Uploads

### Step 1: Enable Firebase Storage in Firebase Console

1. **Go to your Firebase Console**: https://console.firebase.google.com/
2. **Select your SpectRoom project**
3. **Navigate to Storage** in the left sidebar
4. **Click "Get started"**
5. **Choose "Start in test mode"** (for development)
6. **Select a location** (choose the closest to your users)
7. **Click "Done"**

### Step 2: Add Firebase Storage SDK to Xcode

1. **Open your project in Xcode**
2. **File → Add Package Dependencies**
3. **Enter URL**: `https://github.com/firebase/firebase-ios-sdk`
4. **Select "FirebaseStorage"** package
5. **Click "Add Package"**

### Step 3: Configure Storage Rules

In Firebase Console → Storage → Rules, replace the default rules with:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Users can only access their own photos
    match /users/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Allow public read access to profile photos (optional)
    match /users/{userId}/profile.jpg {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### Step 4: Update Your App Code

Once Firebase Storage is set up, update the ProfileEditView to enable photo uploads:

```swift
// In ProfileEditView.swift, replace the photo upload section with:

// Upload profile photo if selected
if let profilePhoto = profilePhoto {
    do {
        let profilePhotoURL = try await PhotoStorageService.shared.uploadProfilePhoto(profilePhoto)
        photoURLs.append(profilePhotoURL)
    } catch {
        uploadErrors.append("Profile photo: \(error.localizedDescription)")
    }
}

// Upload gallery photos if selected
if !galleryPhotos.isEmpty {
    do {
        let galleryPhotoURLs = try await PhotoStorageService.shared.uploadMultipleGalleryPhotos(galleryPhotos)
        photoURLs.append(contentsOf: galleryPhotoURLs)
    } catch {
        uploadErrors.append("Gallery photos: \(error.localizedDescription)")
    }
}
```

### Step 5: Storage Structure

The app will organize photos as follows:

```
Firebase Storage/
├── users/
│   ├── {userID1}/
│   │   ├── profile.jpg
│   │   ├── gallery_0.jpg
│   │   ├── gallery_1.jpg
│   │   └── ...
│   ├── {userID2}/
│   │   ├── profile.jpg
│   │   └── ...
│   └── ...
```

### Step 6: Test the Setup

1. **Build and run your app**
2. **Go to Profile → Edit Profile**
3. **Try uploading a photo**
4. **Check Firebase Console → Storage** to see if the photo appears

### Troubleshooting

**Error: "Object does not exist"**
- Make sure Firebase Storage is enabled
- Check that Storage rules allow your user to write
- Verify the Firebase Storage SDK is added to your project

**Error: "Permission denied"**
- Update your Storage rules to allow authenticated users
- Make sure the user is properly authenticated

**Error: "Network error"**
- Check your internet connection
- Verify Firebase project configuration

### Security Notes

- **Test Mode**: Only use for development
- **Production**: Update rules to be more restrictive
- **Authentication**: Always require user authentication for uploads
- **File Types**: Only allow image files
- **File Size**: Consider adding size limits

### Cost Considerations

- **Storage**: ~$0.026 per GB per month
- **Downloads**: ~$0.12 per GB
- **Operations**: ~$0.05 per 10,000 operations

For a dating app with photos, expect minimal costs for small to medium user bases.





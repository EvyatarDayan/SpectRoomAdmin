# How to Configure APNs for Firebase Cloud Messaging

## Error
```
Auth error from APNS or Web Push Service
messaging/third-party-auth-error
```

This means Firebase doesn't have APNs (Apple Push Notification service) authentication configured.

## Step 1: Get APNs Authentication Key from Apple Developer

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Sign in with your Apple Developer account
3. Click **"Keys"** in the left sidebar
4. Click the **"+"** button to create a new key
5. Enter a **Key Name** (e.g., "SpectRoom APNs Key")
6. Check **"Apple Push Notifications service (APNs)"**
7. Click **"Continue"** then **"Register"**
8. **Download the .p8 file** (you can only download it once!)
9. **Note the Key ID** displayed on the page

## Step 2: Upload APNs Key to Firebase

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **spectroom-553a0**
3. Click on the **⚙️ gear icon** (Settings) next to "Project Overview"
4. Select **"Project settings"**
5. Go to the **"Cloud Messaging"** tab
6. Scroll down to **"Apple app configuration"**
7. Under **"APNs Authentication Key"**:
   - Click **"Upload"**
   - Select the **.p8 file** you downloaded
   - Enter the **Key ID** from Apple Developer Portal
   - Enter your **Team ID** (found in Apple Developer account - top right corner)
   - Click **"Upload"**

## Alternative: Using APNs Certificate (Older Method)

If you prefer using a certificate instead:

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list)
2. Click **"+"** to create a new certificate
3. Select **"Apple Push Notification service SSL (Sandbox & Production)"**
4. Follow the steps to create and download the certificate
5. Convert it to .p12 format:
   - Open Keychain Access
   - Import the certificate
   - Export it as .p12 with a password
6. Upload the .p12 file to Firebase Console (same location as above)

## Step 3: Verify Configuration

1. After uploading, you should see:
   - ✅ "APNs Authentication Key" or "APNs Certificate" configured
   - The Key ID or Certificate ID displayed

2. Test by sending a push notification from your app

## Important Notes

- **Team ID**: Found in Apple Developer account (top right corner, under your name)
- **Key ID**: Displayed when you create the APNs key in Apple Developer Portal
- **.p8 file**: Can only be downloaded once! Save it securely.
- **App ID**: Make sure your app's Bundle ID matches the one in Apple Developer Portal

## Troubleshooting

### If you get "Invalid key" error:
- Make sure the Key ID matches exactly
- Make sure the Team ID is correct
- Make sure the .p8 file is not corrupted

### If notifications still don't work:
- Check that your app's Bundle ID matches the one in Firebase Console
- Make sure you're testing on a real device (not simulator)
- Check that notification permissions are granted in iOS Settings

### If you can't find the Team ID:
1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Look at the top right corner - it's under your name/company
3. It's a 10-character alphanumeric string (e.g., "ABC123DEFG")




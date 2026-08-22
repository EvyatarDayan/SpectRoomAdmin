# How to Fix Firebase Cloud Function

## Step 1: Access Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **spectroom-553a0** (or your project name)

## Step 2: Navigate to Cloud Functions

1. In the left sidebar, click on **"Functions"** (or look for the ⚡ icon)
2. If you don't see "Functions" in the sidebar:
   - Click on the **"Build"** section (or look for the build icon)
   - Then click **"Functions"** from the submenu

## Step 3: Find Your Cloud Function

1. You should see a list of functions:
   - `sendmessagenotification` - This is the one with the error
   - `sendmatchnotification` - This might also need fixing

2. Click on **`sendmessagenotification`** to see details

## Step 4: View/Edit the Function Code

### Option A: If you have Firebase CLI set up locally

1. Open Terminal
2. Navigate to your project directory (where you have `firebase.json`)
3. If you don't have a `functions` folder, create one:
   ```bash
   mkdir functions
   cd functions
   npm init -y
   npm install firebase-functions@latest firebase-admin@latest
   ```

4. Create/edit `functions/index.js` with the fixed code (see below)

5. Deploy:
   ```bash
   firebase deploy --only functions:sendmessagenotification
   ```

### Option B: If you're using Firebase Console (Web UI)

**Note:** Firebase Console doesn't allow direct code editing. You need to use Firebase CLI or Firebase Cloud Functions Editor (if available).

## Step 5: Fix the Code

The fixed code should be in `functions/index.js`:

```javascript
const functions = require('firebase-functions/v2');
const admin = require('firebase-admin');

admin.initializeApp();

exports.sendmessagenotification = functions.firestore
  .document('users/{userId}/incomingMessages/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      // ✅ FIX: Get messageData from snapshot FIRST
      const messageData = snap.data();
      
      if (!messageData) {
        console.log('No message data found');
        return null;
      }

      const senderId = messageData.senderId;
      const recipientId = messageData.recipientId;
      const content = messageData.content || 'New message';
      const messageType = messageData.type || 'text';
      
      // Get recipient's FCM token
      const recipientDoc = await admin.firestore()
        .collection('users')
        .doc(recipientId)
        .get();
      
      if (!recipientDoc.exists) {
        console.log('Recipient not found');
        return null;
      }
      
      const recipientData = recipientDoc.data();
      const fcmToken = recipientData.fcmToken;
      
      if (!fcmToken) {
        console.log('No FCM token for recipient');
        return null;
      }
      
      // Get sender's name
      const senderDoc = await admin.firestore()
        .collection('users')
        .doc(senderId)
        .get();
      
      const senderName = senderDoc.exists ? (senderDoc.data().name || 'Someone') : 'Someone';
      
      // Prepare notification payload
      const messageBody = messageType === 'image' ? '📷 Photo' : (content.length > 50 ? content.substring(0, 50) + '...' : content);
      
      const payload = {
        notification: {
          title: `New message from ${senderName}`,
          body: messageBody,
          sound: 'default',
        },
        data: {
          type: 'message',
          senderId: senderId,
          messageId: context.params.messageId,
        },
        token: fcmToken,
      };
      
      // Send notification
      await admin.messaging().send(payload);
      console.log('✅ Message notification sent successfully');
      
      return null;
    } catch (error) {
      console.error('❌ Error sending message notification:', error);
      return null;
    }
  });
```

## Step 6: Deploy the Function

If using Firebase CLI:

```bash
# Make sure you're in the project root (where firebase.json is)
firebase deploy --only functions:sendmessagenotification
```

Or deploy all functions:

```bash
firebase deploy --only functions
```

## Alternative: If You Don't Have Firebase CLI

1. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```

2. Login:
   ```bash
   firebase login
   ```

3. Initialize (if not already):
   ```bash
   firebase init functions
   ```

4. Then deploy as shown above

## Troubleshooting

### If you can't find Functions in Firebase Console:

1. Make sure you have the right Firebase project selected
2. Check if Cloud Functions are enabled for your project
3. You might need to upgrade to the Blaze plan (pay-as-you-go) - Cloud Functions require a paid plan

### If you get permission errors:

1. Make sure you're logged in with the correct account
2. Check that you have "Owner" or "Editor" permissions on the project

### If the function still doesn't work:

1. Check the Firebase Console logs for the function
2. Look for the error message to see what's wrong
3. Make sure FCM tokens are being saved in Firestore (check the `users` collection for `fcmToken` field)




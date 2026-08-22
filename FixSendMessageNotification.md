# Fix sendMessageNotification Function

## Step 1: Access the Function Source Code

Since you can see `sendMessageNotification` in the Firebase Console, you have two options to edit it:

### Option A: View in Google Cloud Console (Easier for viewing)

1. Click on the **`sendMessageNotification`** function in the Firebase Console
2. Or click on the "logs view" link in the blue banner
3. This will open Google Cloud Console where you can see logs

### Option B: Edit via Firebase CLI (Recommended for fixing)

1. Open Terminal
2. Navigate to your project directory:
   ```bash
   cd "/Users/evyatardayan/Desktop/My projects/swift/SpectRoom"
   ```

3. Check if you have a `functions` folder:
   ```bash
   ls -la
   ```

4. If you don't have a `functions` folder, create one:
   ```bash
   mkdir functions
   cd functions
   npm init -y
   npm install firebase-functions@latest firebase-admin@latest
   ```

5. Create `functions/index.js` with the fixed code (see below)

6. Deploy:
   ```bash
   firebase deploy --only functions:sendMessageNotification
   ```

## Step 2: The Fixed Code

Create/edit `functions/index.js` with this code:

```javascript
const functions = require('firebase-functions/v2');
const admin = require('firebase-admin');

admin.initializeApp();

exports.sendMessageNotification = functions.firestore
  .document('users/{userId}/incomingMessages/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      // ✅ FIX: Get messageData from snapshot FIRST (before using it)
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

// Also fix sendMatchNotification while you're at it
exports.sendMatchNotification = functions.firestore
  .document('users/{userId}/matches/{matchId}')
  .onCreate(async (snap, context) => {
    try {
      // ✅ FIX: Get matchData from snapshot FIRST
      const matchData = snap.data();
      
      if (!matchData) {
        console.log('No match data found');
        return null;
      }

      const userId = context.params.userId;
      const otherUserId = matchData.userId1 === userId ? matchData.userId2 : matchData.userId1;
      
      // Get user's FCM token
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(userId)
        .get();
      
      if (!userDoc.exists) {
        console.log('User not found');
        return null;
      }
      
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      
      if (!fcmToken) {
        console.log('No FCM token for user');
        return null;
      }
      
      // Get other user's name
      const otherUserDoc = await admin.firestore()
        .collection('users')
        .doc(otherUserId)
        .get();
      
      const otherUserName = otherUserDoc.exists ? (otherUserDoc.data().name || 'Someone') : 'Someone';
      
      // Prepare notification payload
      const payload = {
        notification: {
          title: "It's a match! 💕",
          body: `You and ${otherUserName} like each other!`,
          sound: 'default',
        },
        data: {
          type: 'match',
          matchId: context.params.matchId,
          otherUserId: otherUserId,
        },
        token: fcmToken,
      };
      
      // Send notification
      await admin.messaging().send(payload);
      console.log('✅ Match notification sent successfully');
      
      return null;
    } catch (error) {
      console.error('❌ Error sending match notification:', error);
      return null;
    }
  });
```

## Step 3: Deploy

```bash
# Make sure you're in the project root (where firebase.json is)
firebase deploy --only functions
```

Or deploy individually:
```bash
firebase deploy --only functions:sendMessageNotification
firebase deploy --only functions:sendMatchNotification
```

## The Key Fix

The error was: `ReferenceError: messageData is not defined`

**Before (broken):**
```javascript
// messageData was used before being defined
const senderId = messageData.senderId; // ❌ ERROR HERE
const messageData = snap.data(); // Too late!
```

**After (fixed):**
```javascript
// ✅ Get messageData FIRST
const messageData = snap.data();
const senderId = messageData.senderId; // ✅ Works now!
```




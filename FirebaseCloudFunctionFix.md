# Firebase Cloud Function Fix

## Error
```
❌ Error sending message notification: ReferenceError: messageData is not defined
at /workspace/index.js:38:24
```

## Fix for Cloud Function

The Cloud Function `sendmessagenotification` has a bug where `messageData` is referenced before it's defined. Here's the corrected function:

```javascript
const functions = require('firebase-functions/v2');
const admin = require('firebase-admin');

admin.initializeApp();

exports.sendmessagenotification = functions.firestore
  .document('users/{userId}/incomingMessages/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      // Get the message data from the snapshot
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
      
      // Count total unread messages for the app icon badge
      const incomingSnapshot = await admin.firestore()
        .collection('users')
        .doc(recipientId)
        .collection('incomingMessages')
        .get();
      
      let unreadCount = 0;
      incomingSnapshot.forEach((doc) => {
        const data = doc.data();
        if (data.isRead === false) {
          unreadCount += 1;
        }
      });
      
      // Prepare notification payload
      const messageBody = messageType === 'image' ? '📷 Photo' : (content.length > 50 ? content.substring(0, 50) + '...' : content);
      
      const payload = {
        notification: {
          title: `New message from ${senderName}`,
          body: messageBody,
        },
        apns: {
          payload: {
            aps: {
              badge: unreadCount,
              sound: 'default',
            },
          },
        },
        android: {
          notification: {
            notificationCount: unreadCount,
          },
        },
        data: {
          type: 'message',
          senderId: senderId,
          messageId: context.params.messageId,
          badge: String(unreadCount),
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

## Similar Fix for Match Notification

```javascript
exports.sendmatchnotification = functions.firestore
  .document('users/{userId}/matches/{matchId}')
  .onCreate(async (snap, context) => {
    try {
      // Get the match data from the snapshot
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

## Deployment

After fixing the functions, deploy them:

```bash
cd "/Users/evyatardayan/Desktop/My projects/swift/SpectRoom"
firebase deploy --only functions:sendMessageNotification
```

## App Icon Badge Troubleshooting

If the badge does not appear when the app is closed, check these items in order:

1. **Deploy the updated cloud function** (badge code only works after deploy)
2. **APNs key in Firebase Console** → Project Settings → Cloud Messaging → Apple app configuration
3. **Test on a real iPhone** (not the simulator - push badges do not work on simulator)
4. **Notification permission granted** including badge (iOS Settings → SpectRoom → Notifications → Badges ON)
5. **Recipient has `fcmToken` in Firestore** under `users/{userId}/fcmToken` (open app once while logged in)
6. **Build type matches APNs environment**:
   - Debug/Xcode run → `SpectRoom.entitlements` uses `development`
   - TestFlight/App Store → `SpectRoom-Release.entitlements` uses `production`
7. **Stale `openConversationUserId`** - fixed: app now clears this when backgrounded; cloud function only skips push when app is active AND chat is open

### Verify push is being sent

In Firebase Console → Functions → `sendMessageNotification` → Logs, look for:
- `✅ Message notification sent successfully (badge: N)` - working
- `No FCM token for recipient` - recipient needs to open the app while logged in
- `APNs authentication error` - upload APNs .p8 key in Firebase Console
- `Conversation with ... is open and app is active, skipping` - expected only when user is actively in that chat



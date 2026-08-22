# Deploy Fixed Functions

## Step 1: Install Dependencies

Open Terminal and run:

```bash
cd "/Users/evyatardayan/Desktop/My projects/swift/SpectRoom/functions"
npm install
```

## Step 2: Login to Firebase (if not already logged in)

```bash
firebase login
```

## Step 3: Initialize Firebase (if not already done)

```bash
cd "/Users/evyatardayan/Desktop/My projects/swift/SpectRoom"
firebase init
```

When prompted:
- Select **Functions** (use arrow keys and space to select)
- Select your existing project: **spectroom-553a0**
- Use existing functions directory: **functions**
- Use JavaScript: **Yes**
- Install dependencies: **Yes**

## Step 4: Deploy the Functions

```bash
firebase deploy --only functions
```

Or deploy individually:

```bash
firebase deploy --only functions:sendMessageNotification
firebase deploy --only functions:sendMatchNotification
```

## Step 5: Verify

After deployment:
1. Go back to Firebase Console
2. Check the Functions dashboard
3. The functions should show as "Deployed" with the latest version
4. Test by sending a message - the error should be gone!

## What Was Fixed?

The error was: `ReferenceError: messageData is not defined`

**The Problem:**
- The code was trying to use `messageData` before it was defined
- `const messageData = snap.data();` was called too late

**The Fix:**
- Moved `const messageData = snap.data();` to the **very beginning** of the function
- Now `messageData` is defined before it's used




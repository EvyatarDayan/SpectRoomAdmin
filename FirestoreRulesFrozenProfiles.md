# Firestore rules — Frozen / Banned profiles history

## Banned profiles History (works without extra rules)

Ban **History** is stored on the user document (`lastBanLiftedAt`, `lastBannedAt`, `lastBannedReportId`) when you remove a ban. Admins already need permission to update `users/{userId}` for this.

After updating the app: **ban → Remove ban** once more for any profile that was unbanned earlier (those older lifts had no history fields).

## Admin “Last messages” (All profiles)

**Deployed** in `firestore.rules` (project `spectroom-553a0`): admins (`admin1@yopmail.com`) can **read** any user’s `sentMessages` and `incomingMessages`.

```
match /users/{userId}/sentMessages/{messageId} {
  allow read: if isSignedIn() && (request.auth.uid == userId || isAdmin());
  allow write: if isSignedIn() && request.auth.uid == userId;
}

match /users/{userId}/incomingMessages/{messageId} {
  allow read: if isSignedIn() && (request.auth.uid == userId || isAdmin());
  allow write: if isSignedIn();
}
```

`isAdmin()` uses the same email as `AdminAccess.swift` (`admin1@yopmail.com`). Re-open a profile’s **Last messages** after deploy — you should see chats or the empty state, not a permissions error.

## Optional: dedicated history collections

Add these blocks if you also want `moderationFreezes` / `moderationBans` collections:

```
match /moderationFreezes/{freezeId} {
  allow read, write: if isAdmin();
}

match /moderationBans/{banId} {
  allow read, write: if isAdmin();
}
```

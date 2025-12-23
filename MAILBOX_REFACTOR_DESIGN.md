# Mailbox Request Processing Refactor - Design Proposal

## Executive Summary

This document proposes a refactor to move mailbox request processing from sign-in only to periodic checking on key screens (Top Screen and Friends Screen), enabling real-time notification of friend and review requests even when users remain signed in for extended periods.

---

## Current Implementation Analysis

### Where Mailbox Processing Currently Happens

**Location:** `lib/signin_screen.dart` → `_processPendingFriendRequests()` method (lines 480-770)

**Trigger:** Only when user signs in

**Database Paths:**
- **Mailbox location:** `users_by_email/<normalizedEmail>/requests/<requestId>`
- **Friend stubs:** `users/<uid>/friends/<friendUid>`
- **Public profiles:** `public_profiles/<uid>`

### Current Mailbox Request Types & Status Codes

The mailbox processes 6 different request types based on `statusCode`:

| StatusCode | Type | Meaning | Action Taken |
|------------|------|---------|--------------|
| **0** | FR-ASKED | Incoming friend request | Create recipient's friend stub with statusCode=2 |
| **1** | FR-ACCEPTED | Friend acceptance notification | Update sender's stub to statusCode=1 (accepted) |
| **8** | FR-DECLINED | Friend rejection notification | Update sender's stub to statusCode=8 (declined) |
| **3** | RV-WANTED | Review request from friend | Update stub to statusCode=3, add review_request structure, calculate rvCount |
| **5** | RV-PROVIDED | Reviews provided notification | Update stub to statusCode=5 with metadata (rqCount, provider message, etc.) |
| **6** | RV-DECLINED | Review request declined notification | Update stub to statusCode=6 with provider message |

### Current Processing Logic Flow

For each request in the mailbox:

1. **Read** request from `users_by_email/<normalizedEmail>/requests/<requestId>`
2. **Parse** statusCode, fromUid, clientRequestId, comment, and additional metadata
3. **Resolve** sender's profile using `_resolveCanonicalProfile()` helper
   - Prefers mailbox mapping data
   - Falls back to `public_profiles/<uid>` if needed
   - Never reads private `/users/<uid>` for security
4. **Check idempotency** - skip if friend stub already has same clientRequestId
5. **Process based on statusCode:**
   - Create/update friend stub in `users/<myUid>/friends/<fromUid>`
   - Delete mailbox entry (atomic operation)
   - For review requests (statusCode=3): calculate matching review count via `countMatchingReviews()`
6. **Atomic updates** via multi-path Firebase update to ensure consistency

### Current Acceptance/Rejection Flow (in friends_screen.dart)

When user accepts/rejects a friend/review request in Friends Screen:

**Accept Friend Request:**
- Uses `buildAcceptUpdateMap()` helper (db_utils.dart:175-230)
- Updates actor's stub to statusCode=1 (accepted)
- Deletes mailbox entry
- **Creates mailbox notification** for friend with statusCode=1 (acceptance notification)

**Reject Friend Request:**
- Uses `buildRejectUpdateMap()` helper (db_utils.dart:232-290)
- Updates actor's stub to statusCode=9 (unknown/rejected)
- Deletes mailbox entry
- **Creates mailbox notification** for friend with statusCode=8 (rejection notification)

**Accept Review Request:**
- Reads requester's reviews using filters from `review_request` structure
- Writes up to 50 matching reviews to requester's mailbox
- Updates provider's stub to statusCode=5 (provided)
- **Creates mailbox notification** for requester with statusCode=5 and metadata

**Decline Review Request:**
- Updates provider's stub to statusCode=1 (back to friend)
- **Creates mailbox notification** for requester with statusCode=6 and provider message

---

## Problem Statement

**Current Issue:** Mailbox is only checked on sign-in, but users stay signed in for days/weeks. This means:
- Friend requests go unnoticed until next sign-in
- Review requests are not seen in real-time
- Poor user experience with delayed notifications

**Required Solution:** 
- Periodic mailbox checking on key screens
- Visual indication on Friends button when new requests pending
- Immediate processing and display of new requests

---

## Proposed Solution Design

### 1. Extract Mailbox Processing to Reusable Service

**New File:** `lib/services/mailbox_helper.dart`

**Purpose:** Centralized mailbox processing logic that can be called from multiple screens

**Key Functions:**

```dart
// Main mailbox processing function
Future<MailboxProcessResult> processUserMailbox(String myUid, String normalizedMailbox)

// Helper to check if mailbox has pending requests (lightweight check)
Future<bool> hasMailboxRequests(String normalizedMailbox)

// Profile resolution (extracted from signin_screen.dart)
Future<Map<String, String>> resolveCanonicalProfile(String uid, Map<dynamic, dynamic>? mapping)

// Result class
class MailboxProcessResult {
  final bool hasRequests;
  final int friendRequestsProcessed;
  final int reviewRequestsProcessed;
  final int notificationsProcessed;
  final List<String> errors;
}
```

**Logic to Extract from `signin_screen.dart`:**
1. Lines 480-770: `_processPendingFriendRequests()` → becomes `processUserMailbox()`
2. Lines 425-475: `_resolveCanonicalProfile()` → becomes `resolveCanonicalProfile()`
3. All statusCode processing logic
4. Atomic update composition
5. Idempotency checks

### 2. Update Top Screen

**File:** `lib/top_screen.dart`

**Changes Needed:**

1. **Add state variables:**
   ```dart
   bool _hasPendingMailboxRequests = false;
   StreamSubscription<DatabaseEvent>? _mailboxSub;
   ```

2. **Add mailbox checking in initState():**
   ```dart
   @override
   void initState() {
     super.initState();
     _loadAcceptsFriends();
     _checkRequestedReviews();
     _checkFriends();
     _checkMailbox(); // NEW
     _subscribeToMailbox(); // NEW - real-time listener
   }
   ```

3. **Add mailbox checking methods:**
   ```dart
   Future<void> _checkMailbox() async {
     final user = FirebaseAuth.instance.currentUser;
     if (user == null || user.email == null) return;
     
     final String normalizedEmail = normalizeEmailForPath(user.email!.toLowerCase());
     
     // Quick check for existence of requests
     bool hasPending = await hasMailboxRequests(normalizedEmail);
     
     if (hasPending) {
       // Process mailbox requests
       await processUserMailbox(user.uid, normalizedEmail);
       
       // Refresh pending status
       hasPending = await hasMailboxRequests(normalizedEmail);
     }
     
     if (mounted) {
       setState(() {
         _hasPendingMailboxRequests = hasPending;
       });
     }
   }
   
   void _subscribeToMailbox() {
     final user = FirebaseAuth.instance.currentUser;
     if (user == null || user.email == null) return;
     
     final String normalizedEmail = normalizeEmailForPath(user.email!.toLowerCase());
     final DatabaseReference ref = FirebaseDatabase.instance.ref(
       'users_by_email/$normalizedEmail/requests',
     );
     
     _mailboxSub = ref.onValue.listen((DatabaseEvent event) {
       _checkMailbox();
     });
   }
   ```

4. **Update Friends button label:**
   ```dart
   // Current button label: 'Friends'
   // New: 'Friends (!)' when _hasPendingMailboxRequests == true
   
   String get _friendsButtonLabel {
     if (_hasPendingMailboxRequests) {
       return 'Friends (!)';
     }
     return AppStr.friends;
   }
   ```

5. **Clean up in dispose():**
   ```dart
   @override
   void dispose() {
     _mailboxSub?.cancel();
     super.dispose();
   }
   ```

6. **Optional: Re-check on screen resume**
   Add `didChangeDependencies()` or use `WidgetsBindingObserver` to check mailbox when user returns to top screen.

### 3. Update Friends Screen

**File:** `lib/friends_screen.dart`

**Changes Needed:**

1. **Add mailbox checking in initState():**
   ```dart
   @override
   void initState() {
     super.initState();
     _subscribeToFriends();
     _checkMailbox(); // NEW
   }
   ```

2. **Add mailbox checking method:**
   ```dart
   Future<void> _checkMailbox() async {
     final user = FirebaseAuth.instance.currentUser;
     if (user == null || user.email == null) return;
     
     final String normalizedEmail = normalizeEmailForPath(user.email!.toLowerCase());
     
     // Process any pending mailbox requests
     await processUserMailbox(user.uid, normalizedEmail);
     
     // The _subscribeToFriends() listener will automatically
     // pick up the updated friend stubs and refresh the UI
   }
   ```

**Note:** Friends Screen already has a real-time listener on `users/<uid>/friends`, so once mailbox processing updates friend stubs, the UI will automatically refresh. No additional subscription needed.

### 4. Update Sign-In Screen

**File:** `lib/signin_screen.dart`

**Changes Needed:**

1. **Replace local processing with service call:**
   ```dart
   // OLD (line 414):
   await _processPendingFriendRequests(uid, normalizedMailbox);
   
   // NEW:
   await processUserMailbox(uid, normalizedMailbox);
   ```

2. **Remove methods (now in mailbox_helper.dart):**
   - `_processPendingFriendRequests()` (lines 480-770)
   - `_resolveCanonicalProfile()` (lines 425-475)

3. **Add import:**
   ```dart
   import 'services/mailbox_helper.dart';
   ```

---

## Implementation Phases

### Phase 1: Extract Mailbox Logic (Foundation)
**Files:** New `lib/services/mailbox_helper.dart`

**Tasks:**
1. Create new mailbox_helper.dart file
2. Extract and refactor `_processPendingFriendRequests()` → `processUserMailbox()`
3. Extract and refactor `_resolveCanonicalProfile()` → `resolveCanonicalProfile()`
4. Create `hasMailboxRequests()` lightweight check function
5. Create `MailboxProcessResult` class
6. Add comprehensive error handling
7. Add logging for debugging

**Testing:**
- Unit tests for profile resolution
- Integration test: mailbox processing with mock Firebase data
- Verify all 6 statusCode paths work correctly

### Phase 2: Update Sign-In Screen
**Files:** `lib/signin_screen.dart`

**Tasks:**
1. Replace local methods with mailbox_helper calls
2. Remove old code
3. Test sign-in flow still works

**Testing:**
- Sign in with pending friend request
- Sign in with pending review request
- Sign in with no pending requests
- Verify backward compatibility

### Phase 3: Update Top Screen
**Files:** `lib/top_screen.dart`

**Tasks:**
1. Add state variables
2. Add _checkMailbox() method
3. Add _subscribeToMailbox() real-time listener
4. Update Friends button label logic
5. Add cleanup in dispose()

**Testing:**
- Navigate to top screen with pending mailbox → button shows (!)
- Navigate to top screen without pending mailbox → button normal
- Simulate incoming friend request while on top screen → button updates
- Verify mailbox is processed and friend stub created

### Phase 4: Update Friends Screen
**Files:** `lib/friends_screen.dart`

**Tasks:**
1. Add _checkMailbox() call in initState()
2. Test integration with existing real-time listener

**Testing:**
- Open friends screen with pending mailbox → request appears immediately
- Simulate incoming request while on friends screen → request appears
- Verify mailbox is processed and UI updates

### Phase 5: Polish & Optimization
**Tasks:**
1. Add rate limiting (don't check mailbox more than once per minute)
2. Add caching to avoid redundant checks
3. Performance testing with many pending requests
4. UI polish for pending indicator
5. Add analytics/logging for monitoring

---

## Data Flow Diagrams

### Current Flow (Sign-In Only)
```
User Signs In
    ↓
signin_screen.dart → _processPendingFriendRequests()
    ↓
Read users_by_email/<email>/requests
    ↓
Process each request (statusCode 0,1,3,5,6,8)
    ↓
Update users/<uid>/friends/<friendUid>
    ↓
Delete mailbox entry
    ↓
Navigate to Top Screen
```

### Proposed Flow (Multi-Screen)
```
┌─────────────────────────────────────────────┐
│   Sign-In Screen                            │
│   ↓                                         │
│   mailbox_helper.processUserMailbox()      │
└─────────────────────────────────────────────┘
                  ↓
        Navigate to Top Screen
                  ↓
┌─────────────────────────────────────────────┐
│   Top Screen (initState + onValue listener) │
│   ↓                                         │
│   mailbox_helper.hasMailboxRequests()      │
│   ↓                                         │
│   If has requests:                          │
│      mailbox_helper.processUserMailbox()   │
│      Update Friends button: "Friends (!)"  │
│   ↓                                         │
│   Real-time listener updates button        │
└─────────────────────────────────────────────┘
                  ↓
        User navigates to Friends Screen
                  ↓
┌─────────────────────────────────────────────┐
│   Friends Screen (initState)                │
│   ↓                                         │
│   mailbox_helper.processUserMailbox()      │
│   ↓                                         │
│   Existing onValue listener on friends/    │
│   automatically displays new friend stubs   │
└─────────────────────────────────────────────┘
```

### Friend Request Flow Example
```
User A sends friend request to User B
    ↓
Create mailbox record:
  users_by_email/<B_email>/requests/<reqId>
    statusCode: 0 (FR-ASKED)
    fromUid: A
    ↓
User B's Top Screen (real-time listener)
    ↓
Detects new request → calls processUserMailbox()
    ↓
Creates friend stub:
  users/<B_uid>/friends/<A_uid>
    statusCode: 2 (FR-WANTED)
    ↓
Updates Friends button: "Friends (!)"
    ↓
User B clicks Friends → navigates to Friends Screen
    ↓
UI shows User A's friend request with Accept/Decline
    ↓
User B clicks Accept
    ↓
buildAcceptUpdateMap() creates:
  - Update B's stub: statusCode=1 (accepted)
  - Delete B's mailbox entry
  - Create A's mailbox notification: statusCode=1
    ↓
User A's Top Screen (real-time listener)
    ↓
Detects new acceptance → calls processUserMailbox()
    ↓
Updates A's friend stub: statusCode=1 (accepted)
    ↓
Friends button shows (!) temporarily
    ↓
Both users now have accepted friend relationship
```

---

## Edge Cases & Considerations

### 1. Performance
**Issue:** Mailbox checking on every top screen visit could be expensive
**Solution:** 
- Use `hasMailboxRequests()` lightweight check first (only checks existence)
- Add rate limiting: max once per minute
- Cache last check timestamp in SessionCache

### 2. Race Conditions
**Issue:** Multiple simultaneous mailbox checks
**Solution:**
- Use mutex/lock pattern in mailbox_helper to prevent concurrent processing
- Idempotency checks already in place (clientRequestId matching)

### 3. Network Failures
**Issue:** Mailbox check fails due to network error
**Solution:**
- Silent failure with error logging
- Next screen visit or real-time trigger will retry
- Don't block UI on mailbox errors

### 4. Battery/Data Usage
**Issue:** Real-time listeners consume resources
**Solution:**
- Only subscribe on Top Screen (most frequently visited)
- Unsubscribe in dispose()
- Friends Screen uses one-time check (already has friend listener)

### 5. Notification Spam
**Issue:** Multiple rapid requests could spam user
**Solution:**
- Friends button shows generic (!) indicator
- Count is shown in Friends Screen
- User controls when to view/process

### 6. Backward Compatibility
**Issue:** Old clients still only check on sign-in
**Solution:**
- Mailbox records persist until processed
- New clients benefit from real-time updates
- Old clients still work (process on next sign-in)

### 7. Security
**Issue:** Mailbox reading permissions
**Solution:**
- Already enforced by Firebase rules
- Only user can read their own users_by_email/<email>/requests
- No changes needed to security model

### 8. Testing with Multiple Devices
**Issue:** Need to test real-time synchronization
**Solution:**
- Test with two devices/emulators
- User A sends request → User B sees (!) immediately
- Verify both mailbox and friend stub updates

---

## Alternative Approaches Considered

### Alternative 1: Push Notifications (FCM)
**Pros:** True real-time, works even when app closed
**Cons:** 
- Requires FCM setup and tokens
- Server-side Cloud Functions needed
- More complex infrastructure
- May be overkill for this use case

**Decision:** Not selected. Real-time database listeners are simpler and sufficient.

### Alternative 2: Polling Timer
**Pros:** Simple, predictable
**Cons:**
- Wastes battery checking even when inactive
- Fixed interval may miss immediate updates
- Less elegant than event-driven

**Decision:** Not selected. Real-time listeners are more efficient.

### Alternative 3: Only Check on Friends Screen
**Pros:** Simpler implementation
**Cons:**
- User has no way to know there's a pending request
- Requires user to randomly check Friends screen
- Defeats purpose of notification

**Decision:** Not selected. Top screen indicator is essential for discoverability.

---

## Migration Strategy

### No Data Migration Required
- Database schema unchanged
- All existing friend stubs remain valid
- Mailbox structure unchanged
- Only processing location changes

### Deployment Plan
1. Deploy new code version
2. Monitor error logs for 24 hours
3. Verify mailbox processing working on all screens
4. Gradual rollout if needed (feature flag)

### Rollback Plan
If issues arise:
1. Revert to previous version
2. Mailbox will accumulate requests
3. Users process on next sign-in (old behavior)
4. No data loss

---

## Success Metrics

### User Experience
- Time-to-notification: < 5 seconds after request sent
- Friends button accuracy: Shows (!) when requests pending
- UI responsiveness: No lag when checking mailbox

### Technical
- Error rate: < 1% of mailbox checks fail
- Processing time: < 2 seconds for typical mailbox (< 10 requests)
- Memory usage: Minimal impact from real-time listener

### Business
- Friend request acceptance rate increase
- Review request response time decrease
- User engagement with Friends feature increase

---

## Open Questions for Discussion

1. **Friends button label:** 
   - Option A: "Friends (!)" 
   - Option B: "Friends (2)" (show count)
   - Option C: Red dot indicator
   - **Recommendation:** Start with (!) for simplicity

2. **Check frequency:**
   - Top Screen: On every visit + real-time listener
   - Friends Screen: On open only (has friend listener)
   - **Question:** Should we also check when app resumes from background?

3. **Mailbox cleanup:**
   - Currently: Delete after processing
   - **Question:** Should we keep a processed history for audit/debugging?
   - **Recommendation:** Keep current deletion behavior, rely on audit tables if needed

4. **Error handling:**
   - Silent failures vs. user notification
   - **Recommendation:** Silent with logging, show generic "Try again" if critical

5. **Rate limiting:**
   - How often to allow mailbox checks?
   - **Recommendation:** Max once per minute per screen

6. **Caching:**
   - Should we cache "no pending requests" result?
   - **Recommendation:** Yes, cache for 30 seconds to reduce redundant checks

---

## Next Steps

1. **Review this design document together**
2. **Decide on open questions**
3. **Approve design or request changes**
4. **Begin Phase 1 implementation** (mailbox_helper.dart extraction)
5. **Incremental testing and review between phases**

---

## Appendix: Code Structure

### New Files
```
lib/services/mailbox_helper.dart (NEW)
  - processUserMailbox()
  - hasMailboxRequests()
  - resolveCanonicalProfile()
  - MailboxProcessResult class
```

### Modified Files
```
lib/signin_screen.dart
  - Remove _processPendingFriendRequests()
  - Remove _resolveCanonicalProfile()
  - Import and call mailbox_helper

lib/top_screen.dart
  - Add _hasPendingMailboxRequests state
  - Add _mailboxSub listener
  - Add _checkMailbox() method
  - Add _subscribeToMailbox() method
  - Update Friends button label
  - Update dispose()

lib/friends_screen.dart
  - Add _checkMailbox() call in initState()
```

### Unchanged Files (but related)
```
lib/services/db_utils.dart
  - buildAcceptUpdateMap() - creates mailbox notifications
  - buildRejectUpdateMap() - creates mailbox notifications
  
lib/sub_friends_screen/friend_actions.dart
  - UI components for Accept/Decline/Delete

lib/friend_request_screen.dart
  - Sends initial friend requests (creates mailbox records)

lib/review_request_screen.dart
  - Sends review requests (creates mailbox records)
```

---

## Estimated Implementation Time

- **Phase 1:** 4-6 hours (extraction + testing)
- **Phase 2:** 2 hours (sign-in update)
- **Phase 3:** 3-4 hours (top screen update)
- **Phase 4:** 2 hours (friends screen update)
- **Phase 5:** 3-4 hours (polish + optimization)

**Total:** 14-18 hours

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing sign-in flow | Low | High | Thorough testing Phase 2 |
| Race conditions on mailbox | Medium | Medium | Idempotency checks + locking |
| Performance degradation | Low | Medium | Rate limiting + caching |
| Real-time listener battery drain | Low | Low | Proper cleanup in dispose() |
| Network errors breaking UI | Medium | Low | Silent failures + retry |

**Overall Risk:** **Low-Medium** - Well-understood problem with clear solution path.

---

**Document Version:** 1.0  
**Date:** December 22, 2025  
**Author:** GitHub Copilot (AI Assistant)  
**Status:** Awaiting Review

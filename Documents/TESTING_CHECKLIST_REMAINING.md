# RestiView — Remaining Tests (open items only)

Generated: 2026-03-21  
Full checklist: [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md)  
Status key: `[ ]` not started · `[~]` in progress · `[x]` done

---

## 🟢 LOW — Deferred Code Issue

- [ ] **L-04** `preview_screen.dart` — `File.existsSync()` called synchronously in `build()` — blocking I/O in the render pipeline, can cause frame drops. *(deferred post-release)*

---

## Manual Test Scenarios

### Authentication
- [ ] Sign in with valid credentials
- [ ] Sign in with wrong password — verify friendly error (not raw Firebase code)
- [ ] Sign in with unregistered email
- [ ] Password reset flow — valid email
- [ ] Password reset — unregistered email
- [ ] Register new account — happy path
- [ ] Register — duplicate email
- [ ] Register — weak password
- [ ] Sign out and back in — session restored correctly

### Reviews
- [ ] Create a new review — save with photos
- [ ] Create a new review — save without photos
- [ ] Edit an existing review
- [ ] Delete a review
- [ ] Attempt to create duplicate review for same restaurant — duplicate warning shows
- [ ] View review list — sort and filter
- [ ] View review details / preview

### Friends — Request Lifecycle

**Send (pk3 = sender, pk1 = recipient)**
- [ ] pk3 sends friend request — pk3 stub becomes FR-ASKED (statusCode=0); pk1 stub becomes FR-WANTED (statusCode=2)
- [ ] pk3's Friends screen shows the FR-ASKED row; only Delete button is active
- [ ] pk1's Friends screen shows the FR-WANTED row; Accept and Decline buttons are active

**Accept path**
- [ ] pk1 accepts — both stubs become statusCode=1; pk3 receives statusCode=1 mailbox notification; on next sign-in pk3's stub updates to accepted
- [ ] After acceptance both pk3 and pk1 can view each other's permitted reviews

**Decline path (pk1 declines pk3's request)**
- [ ] pk1 declines — pk1 stub becomes statusCode=9; pk3 receives statusCode=8 mailbox notification; on next sign-in pk3's stub becomes statusCode=8 (declined)
- [ ] pk3 can then Delete the declined stub; row disappears
- [ ] pk1 can Delete their statusCode=9 stub

**Retraction path (pk3 retracts their own FR-ASKED)**
- [ ] pk3 selects their FR-ASKED row — Delete button is active; Decline button is NOT active
- [ ] pk3 taps Delete — confirmation dialog appears ("Retract this friend request?")
- [ ] pk3 confirms — pk3's stub is removed immediately; pk3's row disappears from UI
- [ ] pk1's mailbox receives statusCode=8 notification; on next sign-in pk1's FR-WANTED stub becomes statusCode=8 (declined); pk1 can only Delete it
- [ ] pk3 taps Delete then taps No in the dialog — nothing changes

**Timing race: pk3 retracts while pk1 simultaneously accepts**
- [ ] pk3's stub is deleted before pk1's acceptance notification arrives — acceptance notification is silently discarded (stub no longer exists); pk3 does NOT end up with an unwanted accepted-friend relationship
- [ ] pk1's stub receives the statusCode=8 retraction notification — overwrites the accepted stub to declined; pk1 can Delete the row

**Timing race: pk3 retracts while pk1 simultaneously declines**
- [ ] pk3's stub is deleted before pk1's decline notification arrives — decline notification is silently discarded (no stub to update)
- [ ] pk1's stub receives the statusCode=8 retraction — if already declined/deleted, no orphan stubs remain

**Delete established friend (statusCode=1)**
- [ ] pk3 declines an accepted friend — pk3 stub becomes statusCode=9; pk1 stub set to statusCode=8; pk1 receives statusCode=8 mailbox notification; on next sign-in pk1's stub shows declined
- [ ] Ghost-row check: after both users independently delete their own declined stubs, sign each back in — no phantom rows appear

**Decline established friend (statusCode=1)**
- [x] pk3 declines an established friend — pk3 stub becomes statusCode=9; pk1 stub directly set to statusCode=8; pk1 receives statusCode=8 mailbox notification
- [x] pk3 deletes their statusCode=9 stub — only pk3's stub is removed; pk1's statusCode=8 stub remains so pk1 can see they were declined
- [x] pk1 signs in after pk3 has deleted — pk1 still sees the declined (statusCode=8) stub
- [x] pk1 deletes their statusCode=8 stub — only pk1's stub is removed; no ghost rows on either side

**Stale notification guard**
- [ ] Sign pk3 out, have pk1 delete their stub, then sign pk3 back in — mailbox statusCode=9 notification arrives but pk3 stub is already gone — no ghost row created
- [ ] Re-send a friend request after deletion — fresh request works correctly; no stale mailbox entries interfere

**View friend's reviews**
- [ ] View an accepted friend's review list (where permitted)

### Review Requests
- [ ] Send a review request to a friend
- [ ] Receive a review request — view details screen (filter table, counts)
- [ ] Enter the review/exclude flow — exclude one review — return to details screen — counts refresh correctly
- [ ] Decline a review request
- [ ] Accept / complete a review request

### Settings
- [ ] Open Settings — verify all previously saved values load correctly
- [ ] Change sort order — save — reopen reviews list — confirm new sort applied
- [ ] Change default country — save — start new review — confirm country pre-filled correctly
- [ ] Toggle Allow Location on — save — confirm location prompt appears on Add Review
- [ ] Toggle Allow Location off — save — confirm location features are hidden on Add Review
- [ ] Change Search Radius slider — save — confirm new value retained on reopen
- [ ] Toggle Allow Photos off — save — confirm photo options hidden on review detail cards
- [ ] Toggle Allow Photos on — save — confirm photo options visible
- [ ] Toggle Allow Friends off — confirm blocking dialog when active friends exist
- [ ] Toggle Allow Friends off — when no active friends — confirm turns off
- [ ] Allow Auto Capture toggle is visible but disabled (coming soon state)
- [ ] Custom Values — add a custom cuisine — confirm it appears in Add Review dropdown
- [ ] Custom Values — edit a custom cuisine
- [ ] Custom Values — delete a custom cuisine
- [ ] Custom Values — add a custom occasion and country (same flow)
- [ ] Reset Settings — confirm all fields return to defaults
- [ ] Save Changes — close app — reopen — confirm settings persisted
- [ ] Delete Account — test with a disposable test account only

### App Lifecycle
- [ ] Put app in background and restore — no crash
- [ ] No network on launch — graceful degradation
- [ ] Lose network mid-session — no crash, appropriate error messages
- [ ] Regain network — app recovers

---

## Play Store Readiness

- [ ] App icon appears correctly at all densities
- [ ] `minSdkVersion` and `targetSdkVersion` set appropriately
- [ ] All permissions in `AndroidManifest.xml` are justified and minimal
- [ ] Privacy policy URL is live and referenced in Play Store listing
- [ ] Content rating questionnaire completed in Play Console
- [ ] App signing configured (upload key vs app signing key)
- [ ] `versionCode` and `versionName` set correctly in `build.gradle.kts`

---

## Static Analysis

- [ ] Run `flutter analyze` across the whole codebase — resolve all warnings and errors before release
- [ ] Confirm zero `print()` calls remain (should all be `appLog()`)
- [ ] Confirm no deprecated API usage flagged by analyzer

---

## Firebase Security Rules Audit

File: `database.rules.json`

- [ ] Verify no rule allows an authenticated user to read another user's reviews
- [ ] Verify no rule allows an authenticated user to write to another user's data
- [ ] Verify `users_by_email` paths are locked down — only the owner or explicit requester can write
- [ ] Verify `audit_info` is write-only for clients, not readable by arbitrary users
- [ ] Test rules using the Firebase Emulator or Rules Playground in the console

---

## Known Code Bug — `_onReview()` in `review_request_details_screen.dart`

- [ ] **Bug**: `_onReview()` builds a single `{country, city}` map from the legacy `_country`/`_city` fields and passes it to `ReviewReviewsScreen`. It should pass the full `_filters` list. For multi-filter requests the exclusion screen only sees the first (legacy) filter.
- [ ] Fix `_onReview()` to pass `_filters` to `ReviewReviewsScreen` and confirm `ReviewReviewsScreen` accepts a list.

---

## Unit Tests to Write

- [ ] `review_counter.dart` — `countMatchingReviews()`: empty filters, single filter match, multi-filter, excludeKeys respected, non-owner returns -1
- [ ] `mailbox_helper.dart` — push key null-safety guard (H-11 fix)
- [ ] `services/startup_tasks.dart` — graceful handling of non-Map Firebase snapshot values (H-09 fix)
- [ ] `services/ube_provider.dart` — empty email guard returns early rather than writing to push-key path (H-12 fix)

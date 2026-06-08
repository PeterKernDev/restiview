# RestiView — Pre-Release Testing & Bug Checklist (FULL)

Generated: 2026-03-20  
Updated: 2026-03-21 — v1.7.0+26 built and published to Internal Testing. appMode restored to test.  
See [TESTING_CHECKLIST_REMAINING.md](TESTING_CHECKLIST_REMAINING.md) for open items only.  
Status key: `[ ]` not started · `[~]` in progress · `[x]` done

---

## 🔴 HIGH — Must fix before Play Store release

- [x] **H-01** `constants/restiview_constants.dart` — Google Places API key is hardcoded in Dart source. Extractable from APK binary — move to a secure config or restrict key in Google Cloud Console.
- [x] **H-02** `constants/restiview_constants.dart` — `mailboxCheckIntervalSeconds = 30`. Comment says change to 600 for production. At 30s every active user fires 2 Firebase reads/min (battery drain + quota cost).
- [x] **H-03** `signin_screen.dart` — Three `catch` blocks pass raw `$e` / `${fe.message}` / `${fe.code}` into SnackBars visible to users. Replace with a generic user-facing message.
- [x] **H-04** `register_screen.dart` — Firebase DB write after Auth user creation has no `catch`. A DB failure leaves an orphaned Auth user with no recovery path and no error shown.
- [x] **H-05** `preview_screen.dart` — `saveReview()` and `updateReview()` use `try/finally` with no `catch`. Write failure gives zero user feedback and throws an unhandled exception.
- [x] **H-06** `preview_screen.dart` — `initState()` Firebase `.get().then(...)` has no `.catchError`. Network failure causes a permanent loading spinner with no error message.
- [x] **H-07** `preview_screen.dart` — `_checkForDuplicateReview()`: unsafe `as Map<dynamic, dynamic>` cast. Any non-Map snapshot value throws a `TypeError`.
- [x] **H-08** `settings_screen.dart` — `_confirmDeleteAccount()`: no `mounted` check after `await showDialog` before calling `ScaffoldMessenger.of(context)` — stale context crash risk.
- [x] **H-09** `services/startup_tasks.dart` — Two unsafe `as Map<dynamic,dynamic>?` casts at app startup. Corrupted or unexpected Firebase data throws `TypeError` during sign-in initialisation.
- [x] **H-10** `services/review_info_builder.dart` — Unsafe force cast on every review entry. One bad DB entry crashes the entire builder.
- [x] **H-11** `services/mailbox_helper.dart` — `push().key!` force-unwrap. In offline/degraded-connectivity mode the SDK can return `null`, crashing mailbox processing.
- [x] **H-12** `services/ube_provider.dart` — Empty `requesterEmail` fallback writes to a push-key path (`users_by_email/-Nxxxx/requests/...`). Request never reaches the recipient — silent data loss.

---

## 🟡 MEDIUM — Fix before release if possible

- [x] **M-01** `top_screen.dart` — Raw `$e` in error SnackBar. Replace with a generic message.
- [x] **M-02** `top_screen.dart` — `_collectAndClearNewReviewsFlags()`: silent failure on update leaves stale new-review indicator in UI with no user feedback.
- [x] **M-03** `settings_screen.dart` — `_saveSettings()` Firebase write has no try/catch. Failure propagates as an unhandled exception.
- [x] **M-04** `friend_request_screen.dart` — Raw Firebase errors (`${fe.message ?? fe.code}` / `$e`) in SnackBars.
- [x] **M-05** `friend_request_screen.dart` — `_checkRecipientPreview()`: no `mounted` check after multi-`await` sequence; `ScaffoldMessenger` captured before awaits used after them.
- [x] **M-06** `review_request_screen.dart` — Raw Firebase errors in SnackBars.
- [x] **M-07** `friends_screen.dart` — Raw `$e` in SnackBar for decline action.
- [x] **M-08** `services/accept_provided_reviews.dart` — Serial write loop with no rollback. Mid-loop failure leaves partially-written reviews in a permanently inconsistent state.
- [x] **M-09** `list_screen.dart` — Serial delete loop with no rollback. Mid-loop network failure leaves partial deletions with no user notification.
- [x] **M-10** `custom_values_screen.dart` — Multiple unsafe `as Map` casts on `customvals` data. Corrupted Firebase data crashes all custom-value operations.
- [x] **M-11** `general_screen.dart` — Two places expose raw `$e` in SnackBars (`_addInlineCustomCuisine`, `_autoFillRestaurantFromLocation`).

---

## 🟢 LOW — Can address post-release

- [x] **L-01** `goodfor_screen.dart` — `_goToNext()` and `_goToPreviewScreen()` are duplicate methods — dead code.
- [x] **L-02** `settings_screen.dart` — Hardcoded English strings in confirmation dialog (not using `AppStr`).
- [x] **L-03** `preview_screen.dart` — `removeScopedWillPopCallback` is deprecated; will break in a future Flutter stable release.
- [ ] **L-04** `preview_screen.dart` — `File.existsSync()` called synchronously in `build()` — blocking I/O in the render pipeline, can cause frame drops. *(deferred post-release)*
- [x] **L-05** `preview_screen.dart` — `'Back'` and `'Exclude'` button labels are hardcoded string literals, not `AppStr` constants.
- [x] **L-06** `services/location_restaurant_helper.dart` — Debug tools (`analyzeCuisineDetection`, `printCuisineAnalysisReport`, `getSampleRestaurantNames` with ~150 hardcoded names) left in production service file.
- [x] **L-07** `friends_screen.dart` — Hardcoded `'+Friend'`, `'RV-REQUEST'`, `'+Reviews'` button labels; hardcoded confirmation message string.
- [x] **L-08** `top_screen.dart` — `debugPrint('... \$e')` — `\$e` is escaped so the actual error value is never logged.
- [x] **L-09** `review_request_screen.dart` — `'REQUEST'` button label is a hardcoded string literal.
- [x] **L-10** `review_request_screen.dart` — `_loadReviewInfo()` catches error and only `debugPrint`s it; user sees an empty country tree with no explanation.

---

## Manual Test Scenarios

Work through these on-device after fixing the above.

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

### Friends
- [ ] Send a friend request
- [ ] Accept a friend request
- [ ] Decline a friend request
- [ ] Delete a friend
- [ ] View friend's review list (where permitted)

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

### Play Store Readiness
- [x] Release AAB builds without errors (`flutter build appbundle --release`) — v1.7.0+26 built 2026-03-21
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
- [ ] Confirm zero `print()` calls remain (should all be `debugPrint()`)
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

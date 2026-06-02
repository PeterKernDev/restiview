# DEV_NOTES — RestiView (working draft)

Generated: 2025-12-01

This document is a concise developer-oriented overview of the RestiView Flutter app. It was produced by reading the source files under `lib/` in batches. Sections flagged as "(TODO: expand)" indicate files or details pending full parsing.

---

## ⚠️ Developer rules / coding conventions (project-wide)

**CRITICAL:** These rules guide all development and code reviews. All contributors and automated checks must follow these conventions.

- **REMINDER: Don't change anything unless the owner has asked for it or we've explicitly agreed the change.**
- Statements in an `if` should be enclosed in a block (use `{ ... }`).
- All user-visible text strings should live in a centralized `strings.dart` (or similar) file. Example pattern:
  - class AppStr { static const String strName = "String name"; }
- Avoid deprecated `value` on form fields; use `initialValue` instead to set initial form field values (deprecated after v3.33.0-1.0.pre).
- Avoid `withOpacity`; prefer `.withValues()` to avoid precision loss when adjusting colors.
- We do not use any Cloud functions and we do not want to use them in the future, so do not propose or suggest any Cloud based solution.
- Always use braced blocks for bodies of `for`/`if`/`while`, and expand arrow or single-line callbacks into full blocks whenever the body performs more than one action or touches context/state.
  - Guard any async gaps with a `mounted` check before using `context`, `ScaffoldMessenger`, or `setState`.
- Do not use `MaterialStateProperty` (deprecated in this project). Use the recommended replacement patterns for button and style state handling.
- `addScopedWillPopCallback` and `removeScopedWillPopCallback` are deprecated; avoid using them.
- Put the file name and a brief description at the top of every `*.dart` file as a comment. Preserve any existing file header comments and add missing ones where appropriate.
- Do not use `return` inside a `finally` clause.
- Prefer `appLog()` for app-level debug logging; it is silent in `AppMode.production`.
- For nested RTDB reads such as `users/<uid>/friends/<friendUid>/review_request`, `value is Map` is not sufficient on its own. Verify expected keys and be prepared to unwrap the nested child if iOS returns the parent friends map.
- Release build command used by the project:
  - `flutter build appbundle --release`


## ⚠️ REMINDERS (owner supplied)

**AUTHORITATIVE:** The project owner supplied the following hard constraints and reminders. These must be followed for all subsequent edits unless the owner explicitly authorizes a change.

- Don't change anything unless I have asked you to change it, or we have agreed the change.
- Statements in an if should be enclosed in a block.
- Remember all text messages should be stored in `strings.dart`.
  - Example pattern: class AppStr { static const String strName = "String name"; }
- Remember - `value` is deprecated and shouldn't be used. Use `initialValue` instead to set the initial value for form fields (deprecated after v3.33.0-1.0.pre).
- Remember - `withOpacity` is deprecated and shouldn't be used. Use `.withValues()` to avoid precision loss. Try replacing deprecated members with the replacement.
- Remember - always use braced blocks for for/if/while bodies and expand arrow or single-line callbacks into full blocks whenever the body performs more than one action or touches context/state. Guard any async gaps with a `mounted` check before using `context`, `ScaffoldMessenger`, or `setState`.
- Remember not to use `MaterialStateProperty` — it is deprecated.
- Remember `addScopedWillPopCallback` and `removeScopedWillPopCallback` are deprecated.
- Remember we put the file name and a brief description in a comment at the top of every `*.dart` file. Preserve existing comments and add them if they are missing.
- Don't use `return` in a `finally` clause.
- Don't use `kDebugMode`; use `appLog()` for app logging.

NOTE: The code in `lib/review_request_details_screen.dart` contained three occurrences where `BuildContext` could be used across async gaps; these were corrected to guard with `mounted`. Follow the same pattern elsewhere when you find similar issues.

Include or reference this section in code reviews and the repository README so new contributors see the conventions.

---

## Table of contents

- Project summary
- App architecture
- Routes and screens
- Data model & Realtime Database (RTDB) nodes
- Important services and helpers
- Per-file concise summaries (collected batches)
- Security notes and remediation
- How to run / quick checks


## Project summary

RestiView is a Flutter mobile app that lets users create, request, and share restaurant reviews. It uses Firebase Authentication and Firebase Realtime Database (RTDB) for user accounts, public profiles, friend/request flows, and review storage.

Key libraries used (observed in code):
- firebase_auth, firebase_core, firebase_database
- flutter_secure_storage, image_picker, geolocator
- flutter_rating_bar, package_info_plus
- image (for resizing), uuid, intl


## Configuration & Credentials

### Google Cloud / Firebase Configuration

**Package Name:** `com.restiview.app`

**Google Maps / Places API Key:** `AIzaSyDphPAK5es8vB9XfT28T4JBtByXynFmq-4`
- This is the "Android key (auto created by Firebase)" from Google Cloud Console
- Configured for Android apps with package name `com.restiview.app`
- Has Places API enabled (required for nearby restaurant search)
- Located in code: `lib/constants/restiview_constants.dart`

**Android Signing Certificate Fingerprints:**
- **SHA-1:** `2D:62:8A:01:ED:94:E4:F4:1C:5B:7E:D6:20:40:9E:0C:C8:FF:4A:DB`
- **SHA-256:** `0D:41:53:85:EA:4A:DD:87:F1:45:35:CB:67:E7:98:3C:69:D8:04:D1:8C:F9:B5:21:AA:D0:28:FC:89:BE:6A:98`

**Important Notes:**
- The Android API key is restricted to the package name and SHA-1 fingerprint above
- Places API must be enabled in Google Cloud Console for restaurant search to work
- API changes can take up to 5 minutes to propagate


## App architecture

- UI screens are under `lib/` (top-level screens include `main.dart`, `landing_screen.dart`, `signin_screen.dart`, `register_screen.dart`, `top_screen.dart`, `list_screen.dart`, `preview_screen.dart`, etc.).
- Sub-screens and widgets live under `lib/` and `lib/sub_*` and `lib/widgets/`.
- Services (business logic and helpers) are in `lib/services/` (SessionCache, db_utils, request_audit, startup_tasks, user_setup, review_counter, location_restaurant_helper, etc.).
- Data flow:
  - Review creation: GeneralScreen → RatingsScreen → GoodForScreen → CommentsScreen → PreviewScreen → save to RTDB at `users/<uid>/reviews`.
  - Friend request flows and review request flows use atomic multi-path updates and a mailbox at `users_by_email/<normalized>/requests`.


## Routes and screens

Main routes (from `main.dart` and usage across code):
- `/` or landing: `LandingScreen`
- `/signin`: `SigninScreen`
- `/register`: `RegisterScreen`
- `/main` or `/top`: `TopScreen`
- `/list`: `ListScreen`
- `/preview`: `PreviewScreen`
- `/review-request`: `ReviewRequestScreen`
- `/friend-request`: `FriendRequestScreen`
- `/review-request-details`: `ReviewRequestDetailsScreen`
- `/review-reviews`: `ReviewReviewsScreen`
- `/settings` etc.

(See `lib/main.dart` for full route map.)


## Data model & RTDB nodes (observed patterns)

Common nodes and conventions:

- users/<uid>/reviews/<reviewKey>
  - Contains review payload (ratings, restname, reviewdate, details_..., photoPath(s), createdAt, updatedAt, etc.)

- users/<uid>/friends/<friendUid>
  - Friend/request stubs. Fields: statusCode, email, username, comment, clientRequestId, mailboxReqId, mailboxNormalized, review (optional nested map for review requests), rvCount, exCount, exKeys, updatedAt, accepted.
  - Canonical status codes (in `friends_screen.dart`):
    - 0: statusRequesterSent (friend requester)
    - 1: statusAccepted
    - 2: statusRequested (friend recipient)
    - 3: statusRvWants (recipient side of review request)
    - 4: statusRvAsked (requester side of review request)
    - 8: statusDeclined
    - 9: statusUnknown

- users_by_email/<normalized_email>/requests/<clientRequestId>
  - Mailbox entries for incoming friend/review requests. Each entry contains statusCode, fromUid, fromEmail, fromDisplayName, comment, review (for review requests), clientRequestId, createdAt, processedAt (optional), processedBy (optional), etc.

- public_profiles/<uid>
  - Lightweight public profile (displayName, email, sharedReviewsCount, acceptsFriends, ...). Used for lookups when `users_by_email` mapping doesn't have full fields.

- users/<uid>/customvals
  - Per-user custom lists (cuisine, occasion, country) stored as lists of `[name, usedFlag]` pairs. Clients update usedFlag to mark items used in saved reviews.

- request_audit
  - Audit records written by `writeRequestAudit()` for both friend and review requests (best-effort writes).

Notes:
- Atomic multi-path updates are used for consistent mailbox + friend stub writes; `_updateWithRetry` wrapper is used to retry transient DB errors with exponential backoff.
- Review requests prime `users/<recipient>/friends/<sender>/review` with `rvCount: -1` so clients will re-calculate matching review counts asynchronously.


## Important services and helpers (high-level)

- SessionCache
  - In-memory cached configuration (user email/name, default country/currency, custom lists, indexedMatrix used for city/cuisine filters). Persisted values read/written from secure storage.

- db_utils
  - Utilities such as `normalizeEmailForPath()`.

- request_audit
  - Writes audit entries for requests. Used as best-effort logging when requests are created.

- user_setup / startup_tasks
  - Helpers to ensure users_by_email mapping, public_profiles node, and initial customvals exist for new accounts.

- review_counter / countMatchingReviews
  - Helpers used by FriendsScreen to compute rvCount (matching review counts) when needed.

- location_restaurant_helper
  - Uses Google Places (Places API key in constants) and geolocation to suggest nearby restaurants. Contains defensive timeouts and permission checks.


## Per-file concise summaries (collected batches)

The following are concise file summaries gathered so far. Each summary lists the file purpose, key functions/UI flows, and any RTDB interactions or security notes.

- `lib/main.dart` — App entrypoint. Initializes Firebase, SessionCache, enforces portrait orientation, defines route map and `initialRoute`. Sets up top-level theme and handles deep linking.

- `lib/landing_screen.dart` — Simple landing view with app logo and navigation buttons to sign in/register/help.

- `lib/signin_screen.dart` — Handles sign-in with FirebaseAuth, processes incoming mailbox entries at `users_by_email/<normalized>/requests` (accepts friend/review request flows). Calls `ensureUserSetup` after sign-in and writes public profile mapping when needed. Creates friend stubs via atomic multi-path updates and uses a clientRequestId to avoid duplicate processing.

- `lib/register_screen.dart` — Registration form. Persists user record to `users/<uid>` including `userSettings7` (acceptsFriends) and calls `ensureUserSetup()` and `runStartupTasks()` to create auxiliary mappings and default values.

- `lib/top_screen.dart` — Dashboard-style top screen; displays counts and provides navigation to friend list, reviews list, and settings. Reads lightweight settings such as `userSettings7` to enable/disable friends features.

- `lib/list_screen.dart` — Shows user's reviews (reads `users/<uid>/reviews`). Supports filtering via SessionCache.indexedMatrix, sorting, and launching preview/edit flows.

- `lib/preview_screen.dart` — Preview/edit/save/delete review flows. Important responsibilities:
  - Converts formatted preview data back and forth via `review_formatter`/`review_transform` helpers.
  - Save: writes new review to `users/<uid>/reviews` (push) and updates `users/<uid>/customvals` (mark custom cuisine/occasion used) and SessionCache.indexedMatrix.
  - Update: updates existing `users/<uid>/reviews/<key>` and patches customvals/indexedMatrix (removes previous indexedMatrix entries, then re-adds from updated payload).
  - Delete: removes the review node and updates indexedMatrix.
  - Contains duplicate-safe normalization, detail card normalization, and defensive image handling.

- `lib/comments_screen.dart` — Comment & photo capture screen. Stores up to 3 photos (photoPath0..2) in the `ReviewContext.reviewMap`. Uses `compute()` to resize images in a background isolate and write temp files. Uses `Image.file(..., errorBuilder: ...)` and `Wrap` for thumbnails to avoid overflow.

- `lib/details_screen.dart` — Manages detailed items (cocktails, starters, wine, main, dessert, otherdrinks). Items store name, photoPath, timestamp; UI uses `Thumbnail` and `FullScreenImage` widgets. Saves back to `ReviewContext.reviewMap` as `details_<category>`.

- `lib/goodfor_screen.dart` and `lib/goodfor_filter_screen.dart` — Select tags describing what the restaurant is good for. Save selections into review map and return to the flow.

- `lib/general_screen.dart` — Primary review meta data: restaurant name, city, cuisine, occasion, date, diners, cost, and inline additions to custom values. Integrates with `location_restaurant_helper` to auto-fill restaurant info using geolocation and Google Places API (key in constants). Writes/reads `users/<uid>/customvals` for inline additions.

- `lib/ratings_screen.dart` — Collects ratings with a star UI using `flutter_rating_bar`. Stores per-rating scaled integers in the review map and computes total `restrating`.

- `lib/custom_values_screen.dart` — Manage custom cuisines, occasions, and countries. Reads and updates `users/<uid>/customvals`. Guards UI use after async gaps with `if (!mounted) return;` and uses helper `_withBusy` to prevent concurrent updates.

- `lib/friend_request_screen.dart` — Sends a friend request by writing mailbox entry and two friend stubs in a single atomic update. Uses `users_by_email/<normalized>/requests/<clientRequestId>` as mailbox and `users/<uid>/friends/<otherUid>` for stubs. Uses `_updateWithRetry` with exponential backoff. Checks existing friend stubs to avoid duplicate requests.

- `lib/friends_screen.dart` — Friend list and actions (accept/decline/delete). Subscribes to `users/<uid>/friends` onValue stream, normalizes friend entries into `FriendEntry` objects, fetches public_profiles when needed, and resolves missing `rvCount` for review requests using `countMatchingReviews`. BuildAccept/Reject/Change flows compose atomic updates via `buildAcceptUpdateMap`/`buildRejectUpdateMap` helpers.

- `lib/friend_request_screen.dart` — (See friend_request above). Also includes robust parsing for different shapes of stored status fields.

- `lib/review_request_screen.dart` — Creates review requests. Mailbox entry plus requester and recipient stubs; sets recipient nested review node `rvCount: -1` to force recipient re-computation. Writes request_audit if possible. Uses `_updateWithRetry`.

- `lib/review_request_details_screen.dart` — Provider-side screen showing an incoming review request's details: filters (country/cuisine/city), request comment, rvCount/exCount/exKeys, and a provider comment box. Allows navigating to `ReviewReviewsScreen` which lists matching reviews and lets provider exclude some before accepting.

- `lib/review_reviews_screen.dart` — Shows matching reviews for a review request, lets provider inspect, exclude/include reviews (updates `users/<myUid>/friends/<friendUid>/review` with `exCount` and `exKeys`), and preview selected reviews. Reads `users/<myUid>/reviews` and applies friend-request filters client-side when necessary.

- `lib/settings_screen.dart` — Manage user settings and persist to `users/<uid>` fields and SessionCache. Allows account deletion (removes `users/<uid>` and deletes auth user after confirmation). Ensure delete flows try to remove mailbox/friend stubs and report counts of removed nodes.

- `lib/help_screen.dart` — About/help view, shows package version via `package_info_plus` and launches website using `url_launcher`.

- `lib/widgets/*` — `thumbnail.dart`, `full_screen_image.dart`, `action_row.dart` and similar widgets provide reusable UI. Widgets use `Image.file(..., errorBuilder)` and constrained boxes to prevent layout overflow.


## Security notes and remediation

- Hard-coded Google Places API key found in `lib/constants/restiview_constants.dart` (field `googlePlacesApiKey` with literal value). Recommendation:
  - Replace the literal with a placeholder and load the real key from a platform environment variable or from a runtime config (e.g., `--dart-define` or native secret store).
  - Add `README.md` instructions: how to supply the key during local development and CI, and add the key to the platform-specific secret store for production builds.
  - Do NOT commit real API keys into source control. Consider rotating the key if it has been published.

- Other notes:
  - No other obvious secrets were found in the batch processed so far, but run a project-wide search for common secrets before publishing.


## How to run (quick)

From the workspace root (assumes Flutter SDK installed and device/emulator available):

```powershell
# Clean, fetch packages, and run (Windows PowerShell)
flutter clean
flutter pub get
flutter run
```

There's a workspace `task` labelled "Clean, Get, Run" in the VS Code tasks that runs the above.


## DBIC — Database Integrity Checker

A standalone Dart CLI tool (`tool/dbic.dart`) that scans the live Firebase Realtime Database via a service account and reports structural errors, orphan records, and data corruption.

**Full documentation:** [tool/DBIC_README.md](tool/DBIC_README.md)

### Usage

```powershell
.\DBIC check    # read-only — reports errors and warnings
.\DBIC fix      # same scan, then prompts y/n to apply auto-fixes
```

### Setup summary

- Requires a Firebase service account JSON in the project root (gitignored, matches `firebase-adminsdk*.json`).
- `googleapis_auth: ^2.0.0` is in `dev_dependencies` — run `dart pub get` after a fresh clone.
- `DBIC.bat` in the project root wraps the `dart run tool/dbic.dart` invocation (gitignored).

### Check sections

| Section | Nodes | Key checks |
|---|---|---|
| A | `users_by_email` | Load user registry |
| B | `public_profiles` | Orphan detection, required fields, UID/email consistency |
| C | `users_by_email/<n>/requests` | Status code validity, stale entries |
| D | `audit_info/request_events` | Required event fields |
| E | `audit_info/friend_*` | Required fields on 4 audit nodes |
| F | `users/<uid>/…` | Reviews (fields, ratings, dates, goodfor), friends, received reviews, customvals |

### Auto-fixable categories

`PUBLIC_PROFILES` (orphan delete), `REVIEWS` (rating/date field patches), `REVIEWS_CORRUPT` (delete review with missing required fields), `REVIEWS_REQUESTED` (strip cost/photo fields).

### Database state after 2026-04-09 run

- **0 errors** — 3 orphan public_profiles and 1 corrupt review deleted.
- **163 warnings** — all benign legacy data (reviews written before `createdAt`/`updatedAt` and before goodfor expanded from 16 → 18 tags). No action needed.

> Run `.\DBIC check` before every release to confirm 0 errors.


## Next steps and TODOs

- Finish reading the remaining lib Dart files (I will continue batched reads until all files are parsed).
- Expand the Per-file summaries list to include every file and fill in any TODO placeholders.
- Optionally remediate the Google Places API key: replace with placeholder and add README instructions.
- Optionally create `DEV_NOTES.md` commit or a PR (ask how you'd like the file saved/committed).


---

Notes: This is a working draft. I created this `DEV_NOTES.md` with the summaries collected so far and placeholder guidance for the remaining files. Tell me how you'd like me to proceed: continue reading the remaining files, immediately remediate the API key, or commit this file on a branch and open a PR.

## Friend / Friend-request flow (summary)

This section documents how friend requests and friend records are created, delivered, and handled in the app (read-only summary; no code changes were made).

- Mailbox (single source of incoming requests): `users_by_email/<normalized_email>/requests/<clientRequestId>`
  - Each mailbox entry contains at least: `statusCode`, `fromUid`, `fromEmail`, `fromDisplayName`, `clientRequestId`, `comment`, `createdAt` and optionally `review` for review-requests.
  - `clientRequestId` is generated client-side (UUID-like) and used to deduplicate requests and idempotently apply them.

- Friend stubs (per-user view): `users/<uid>/friends/<otherUid>`
  - The library creates two asymmetric stubs on request send:
    - Sender's stub (on the sender's `users/<senderUid>/friends/<recipientUid>`) with `statusCode: 0` (FR-ASKED) and metadata about the request (email, displayName, clientRequestId, mailboxNormalized, mailboxReqId).
    - Recipient's stub (on the recipient's `users/<recipientUid>/friends/<senderUid>`) with `statusCode: 2` (FR-WANTED) and the same metadata.
  - On acceptance, both stubs are updated to `statusCode: 1` (FR-ACCEPTED) and `accepted: true` (plus `updatedAt` and `processedAt` fields), and mailbox entry is either removed or marked processed depending on ownership/claim rules.
  - On decline/reject, stubs are updated to `statusCode: 8` (FR-DECLINED) and mailbox may be marked processed or removed.
  - On **retraction** (sender pk3 deletes their own FR-ASKED stub before recipient acts): pk3's stub is deleted, a statusCode=8 mailbox notification is sent to pk1 so pk1's FR-WANTED stub becomes declined. pk1 can then only Delete that stub. The retraction flow is implemented in `_handleDelete()` in `friends_screen.dart` (the `statusRequesterSent` branch).
  - On **declined-stub deletion** (statusCode=8 or 9): deleting a declined stub only removes the actor's own stub. The other user's stub is preserved so they can see the declined status and delete it themselves when ready. This prevents the relationship silently disappearing for one side. (For pending request retraction, statusCode=0, both stubs are still deleted atomically.)

- Atomic updates & mailbox removal
  - The client composes a single multi-path `.update()` map to create mailbox + both friend stubs atomically. This avoids partial state where a mailbox exists but stubs don't.
  - A helper `_addMailboxRemovalOrMark()` in `db_utils.dart` tries to remove the mailbox entry if the writing client is the mailbox owner, otherwise it marks the mailbox entry as `processedAt`/`processedBy` to avoid accidental deletion of another actor's mailbox.

- Auditing
  - `request_audit` entries are written as best-effort logs alongside request creation. These are not relied on for functional correctness but can assist debugging and manual reconciliation.

- Review requests
  - Review requests are a superset of friend requests and include a `review` object in the mailbox and in the recipient's friend stub (under `.review`) containing `rvCount: -1` to signal the recipient's client to recalculate matching review counts.

- Status codes (canonical meanings seen in code)
  - 0: requester-sent (FR-ASKED) — sender's stub while waiting for recipient to act
  - 1: accepted (FR-ACCEPTED)
  - 2: requested (FR-WANTED) — recipient's stub while waiting for them to act
  - 3: rv-wants (recipient side of review-request)
  - 4: rv-asked (requester side of review-request)
  - 5: rv-provided (requester's stub after provider publishes reviews)
  - 6: rv-declined (review request declined by provider)
  - 8: declined (FR-DECLINED) — recipient of a decline/retraction
  - 9: friend-deleted-instigator — the user who initiated the deletion/decline of an established friend

- Client responsibilities on receive
  - The recipient client listens to `users/<myUid>/friends` and will:
    - Use the `statusCode` to decide which UI actions to surface (Accept / Decline / Delete / Open request details).
    - For review-requests, recalculate `rvCount` by scanning local `users/<myUid>/reviews` (or via `review_counter`) and update the stub's `review.rvCount` atomically.
    - When accepting/declining, build an atomic accept/reject update map (helpers exist in `db_utils.dart`) to modify both user stubs and to mark/remove the mailbox entry.

- Mailbox handler guards (in `mailbox_helper.dart` → `processUserMailbox()`)
  - **statusCode=1 (accept notification)**: if the local stub no longer exists (retracted), discard notification and clean mailbox entry — do not recreate stub.
  - **statusCode=8 (decline notification)**: if the local stub no longer exists (retracted), discard notification. If local stub is statusCode=9 (instigator), skip (9 takes precedence).
  - **statusCode=9 (deletion notification)**: if the local stub no longer exists (already deleted), discard. If local stub has an active status (0, 1, or 2), skip as stale — the relationship moved on.
  - These guards prevent ghost rows and phantom relationships from out-of-order or delayed mailbox deliveries.

Notes and recommendations
- The current design relies on client-side atomic `.update()` maps to maintain mailbox + stub consistency. This is simple and efficient but relies on clients following rules. Consider server-side validation or Firebase Cloud Functions to enforce mailbox-stub invariants if you need stronger guarantees.
- Photo fields in friend stubs (if any) are local path references and are not synchronized to cloud storage — the stub should not be relied on to surface portable image assets.
- When deploying, audit mailbox removal rules carefully to avoid deleting someone else's mailbox entry; the existing helper marks processed by default when uncertain.

End of friend-request flow summary.

## Heavy-copy "Provide Reviews" design (provider → requester) — ACTUAL IMPLEMENTATION

Goals
- Allow a provider to accept a review request from a friend and publish up to 50 reviews into the requester's users_by_email mailbox, without copying photos/paths.
- Let the requester import the reviews into their personal requested_reviews area, or decline (delete them).
- Keep operations idempotent and traceable. Enforce a strict limit of 50 reviews maximum.
- Use client-side multi-path atomic updates.

IDs and defaults
- requestId: use a Firebase push key to create unique request IDs.
- Review limit: Maximum 50 reviews per transfer (strictly enforced, no chunking).
- Provenance fields added to each copied review: `providedByUid`, `providedAt` (ISO UTC).
- Status code for "RV-PROVIDED": 5 (requester's friend stub is set to 5, provider's stub set to 1).

Provider-side publish (actual storage location)
- Destination:
  - users_by_email/<requester_normalized_email>/requested_reviews/<requestId>/meta
  - users_by_email/<requester_normalized_email>/requested_reviews/<requestId>/reviews/<revKey>
- The `meta` node contains: { provider-message, rqCount, providerUid, providedAt }
- Each review under `reviews/` is a copy of the provider's review object with photo/photoPath fields removed plus the provenance fields (providedByUid, providedAt).

Friend pointer updates (atomic with publish)
- In the same multi-path update:
  - Requester's friend stub: users/<requesterUid>/friends/<providerUid>/statusCode = 5 (RV-PROVIDED)
  - Provider's friend stub: users/<providerUid>/friends/<requesterUid>/statusCode = 1 (FRIEND/accepted)
  - Both stubs get updatedAt timestamp

Requester import (accept) - TO BE IMPLEMENTED
- When requester accepts/imports the provided reviews, perform an atomic update that:
  - Copies reviews from users_by_email/<norm>/requested_reviews/<requestId>/reviews/* to users/<requesterUid>/requested_reviews/<importId>/reviews/*
  - Writes users/<requesterUid>/requested_reviews/<importId>/meta with provenance
  - Sets both friend stubs status back to 1 (accepted)
  - Deletes users_by_email/<norm>/requested_reviews/<requestId>
- Mark the imported transfer with provenance to make the import idempotent.

Requester decline - TO BE IMPLEMENTED
- If requester declines, delete the users_by_email transfer and reset friend statuses to accepted (status=1).

Current Implementation Status (as of 2025-12-13)
- Provider-side publish: IMPLEMENTED in lib/services/ube_provider.dart
  - buildProvideBatches() creates atomic update maps (note: function name uses "batches" but enforces 50-review limit)
  - performProvide() executes the update
  - Storage: users_by_email/<norm>/requested_reviews/<requestId>/
  - Friend stubs updated: requester=5, provider=1
- Requester-side accept/import: NOT YET IMPLEMENTED
  - Need to read from users_by_email/<norm>/requested_reviews/
  - Copy to users/<requesterUid>/requested_reviews/
  - Update friend stubs back to status=1
  - Delete users_by_email transfer
- Requester-side decline: NOT YET IMPLEMENTED
  - Delete users_by_email transfer
  - Reset friend stubs to status=1

Files changed so far
- `lib/friends_screen.dart` — provider publish flow added (statusCode=3 triggers provide flow)
- `lib/services/ube_provider.dart` — buildProvideBatches() and performProvide() implemented
- `lib/services/db_utils.dart` — stripPhotosFromReview() already existed

Files still needed for requester accept/decline
- `lib/friends_screen.dart` — add logic for when statusCode=5 (RV-PROVIDED) to accept/import reviews
- New service or helpers to build import/decline update maps

---

End of heavy-copy design notes (2025-12-13).

## Review Sharing Flow — Complete Implementation (2025-12-18)

This section documents the full end-to-end review sharing flow including provider publish, requester accept/decline, and the comment field consolidation.

### Overview

The review sharing system allows users to:
1. Request reviews from friends with specific filters (country, city, cuisine)
2. Providers can accept and share up to 50 matching reviews
3. Requesters can accept (import) or decline the shared reviews
4. Providers can decline review requests with an optional message
5. All state transitions are tracked via friend stub statusCode changes

### Status Code Flow

Complete status code lifecycle for review sharing:

**Normal Flow:**
- **statusCode=4** (RV-ASKED): Requester's stub after sending review request
- **statusCode=3** (RV-WANTS): Provider's stub after receiving review request
- **statusCode=5** (RV-PROVIDED): Requester's stub after provider shares reviews
- **statusCode=1** (FRIEND): Both stubs return to friends status after accept/decline

**Decline Flow:**
- **statusCode=6** (RV-DECLINED): Requester's stub when provider declines request
- **statusCode=1** (FRIEND): Provider's stub immediately after declining

### Comment Field Consolidation (2025-12-18)

Previously, three separate fields were used for different message types:
- `comment` - for friend/review request comments
- `providedMessageShort` - for provider messages when sharing reviews
- `declinedMessage` - for provider messages when declining requests

**Simplified Design:**
Now a single `comment` field handles all message types:
- Friend request comments (statusCode 0/2)
- Review request comments (statusCode 3/4)
- Provider messages when sharing reviews (statusCode 5)
- Provider decline messages (statusCode 6)
- **Automatically cleared** when statusCode transitions to 1 (FRIENDS)

**Benefits:**
- Single source of truth for display logic
- Consistent behavior across all request types
- Simplified data model (3 fields → 1 field)
- Clear lifecycle: comment exists during request flow, cleared when returning to friends

**Files Modified:**
- `lib/signin_screen.dart` - mailbox processing writes to `comment` field
- `lib/friends_screen.dart` - all state transitions use `comment` field, clear on accept
- `lib/sub_friends_screen/friend_entry.dart` - removed deprecated fields from model
- `lib/sub_friends_screen/friend_row.dart` - simplified display logic to always use `comment`
- `lib/services/db_utils.dart` - clear `comment` in buildAcceptUpdateMap
- `lib/services/accept_provided_reviews.dart` - clear `comment` when accepting reviews

### Provider Publish Flow (IMPLEMENTED)

**Entry Point:** `friends_screen.dart` _handleAccept() when statusCode=3

**Process:**
1. Count matching reviews using `review_counter.dart` with filters from review_request subnode
2. Enforce 50-review limit (show message if more, no action if zero)
3. Read optional provider comment from `review_request/providerComment` (set by ReviewRequestDetailsScreen)
4. Build atomic update via `ube_provider.dart` buildProvideUpdate():
   - Copy reviews to `users_by_email/<norm>/requests/<requestId>/reviews/*`
   - Strip photo fields from each review
   - Add provenance: `providedByUid`, `providedByEmail`, `providedAt`
   - Write meta node with provider message and count
   - Update requester stub: statusCode=5, comment=provider message
   - Update provider stub: statusCode=1, comment=null, clear review_request
5. Execute via performProvide() with retry logic

**Storage Location:**
```
users_by_email/<requester_normalized>/requests/<requestId>/
  ├─ meta: { provider-message, rqCount, providerUid, providedAt }
  └─ reviews/
      ├─ <reviewKey1>: { review data without photos + provenance }
      ├─ <reviewKey2>: { ... }
      └─ ...
```

### Requester Accept Flow (IMPLEMENTED)

**Entry Point:** `friends_screen.dart` _handleAccept() when statusCode=5

**Process:**
1. Call `accept_provided_reviews.dart` acceptProvidedReviews()
2. Read request metadata to get requestId
3. Atomic operation:
   - Copy reviews from `users_by_email/<norm>/requests/<requestId>/reviews/*`
   - Write to `users/<requesterUid>/requested_reviews/<reviewKey>` (flattened, not nested)
   - Add import timestamp and requester provenance
   - Update requester stub: statusCode=1, comment=null, clear provider metadata
   - Delete source `users_by_email/<norm>/requests/<requestId>`
4. Show success message with count of accepted reviews

**Key Design Decision:**
Reviews are stored flat at `users/<uid>/requested_reviews/<reviewKey>` rather than nested under a request folder. This allows:
- Easy querying and filtering
- Consistent structure with user's own reviews
- Simpler list screen implementation

### Requester Decline Flow (IMPLEMENTED)

**Entry Point:** `friends_screen.dart` _handleDecline() when statusCode=5

**Process:**
1. Atomic update:
   - Delete `users_by_email/<norm>/requests/<requestId>` (entire request)
   - Update requester stub: statusCode=1, comment=null, clear provider metadata
2. Show confirmation message

### Provider Decline Flow (IMPLEMENTED)

**Entry Point:** `friends_screen.dart` _handleDecline() when statusCode=3

**Process:**
1. Read optional provider message from `review_request/providerComment`
2. Create mailbox entry with statusCode=6 and meta containing decline message
3. Atomic update:
   - Write decline notification to `users_by_email/<requester_norm>/requests/<requestId>`
   - Update provider stub: statusCode=1, comment=null, clear review_request
4. Requester processes notification via signin_screen mailbox processing:
   - Sets requester stub: statusCode=6, comment=decline message

### Decline Acknowledgment Flow (IMPLEMENTED)

**Entry Point:** `friends_screen.dart` _handleAccept() when statusCode=6

**Process:**
1. Atomic update:
   - Update stub: statusCode=1, comment=null
2. Show "Decline acknowledged" message
3. Relationship returns to normal friends status

### Review Request Details Screen (IMPLEMENTED)

**File:** `lib/review_request_details_screen.dart`

**Purpose:** Provider views incoming review request details and can add optional comment

**Features:**
- Displays requester info and filter criteria (country, city, cuisine)
- Shows calculated matching review count
- Provider can add single-line comment (persisted to review_request/providerComment)
- Navigate to ReviewReviewsScreen to inspect/exclude specific reviews
- Comment is read by provide/decline flows

**Data Flow:**
- Read from: `users/<providerUid>/friends/<requesterUid>/review_request`
- Write to: `users/<providerUid>/friends/<requesterUid>/review_request/providerComment`
- Defensive note: on iOS, a read aimed at the `review_request` child may occasionally return the parent friends map. The screen now validates the map shape and unwraps `friends/<requesterUid>/review_request` before parsing.

### Review Exclusion System (IMPLEMENTED)

**File:** `lib/review_reviews_screen.dart`

**Purpose:** Provider can exclude specific reviews before sharing

**Features:**
- Lists all matching reviews based on request filters
- Toggle switches to exclude/include each review
- Exclusions saved to `review_request/exKeys` array
- Excluded reviews not counted in final share
- UI shows "To Provide: X reviews" with dynamic count

**Storage:**
```
users/<providerUid>/friends/<requesterUid>/review_request/
  ├─ exKeys: ["reviewKey1", "reviewKey3"]  // excluded review keys
  └─ exCount: 2                              // count of excluded
```

### Mailbox Processing (signin_screen.dart)

**Notification Types Processed:**

1. **statusCode=3** (Review Request):
   - Creates review_request structure with filters and calculated rvCount
   - Sets comment field with request message
   - Recipient stub → statusCode=3

2. **statusCode=5** (Provided Reviews):
   - Reads meta from mailbox
   - Sets providedRequestId, providedRqCount, providedAt
   - Sets comment field with provider message
   - Recipient stub → statusCode=5

3. **statusCode=6** (Declined Request):
   - Reads decline message from meta
   - Sets comment field with decline message
   - Recipient stub → statusCode=6
   - Deletes mailbox entry

### Data Consistency Rules

1. **Comment Lifecycle:**
   - Set during request creation
   - Updated during state transitions (provide/decline)
   - Cleared when returning to statusCode=1 (FRIENDS)

2. **Atomic Operations:**
   - All state transitions use multi-path updates
   - Friend stubs and mailbox always updated together
   - No partial states

3. **Idempotency:**
   - clientRequestId prevents duplicate processing
   - Request metadata includes timestamps for tracking
   - Import operations check for existing reviews

4. **50-Review Limit:**
   - Enforced in UI (friends_screen.dart)
   - Provider warned if more matches exist
   - Only first 50 reviews shared

### Files Involved

**Core Flow:**
- `lib/friends_screen.dart` - Main state machine for all accept/decline flows
- `lib/signin_screen.dart` - Mailbox processing for incoming notifications
- `lib/review_request_screen.dart` - Create review request
- `lib/review_request_details_screen.dart` - Provider views request details
- `lib/review_reviews_screen.dart` - Provider excludes specific reviews

**Services:**
- `lib/services/ube_provider.dart` - Build provider publish atomic update
- `lib/services/accept_provided_reviews.dart` - Requester accept/import logic
- `lib/services/review_counter.dart` - Count matching reviews with filters
- `lib/services/db_utils.dart` - Friend stub updates, strip photos

**Data Models:**
- `lib/sub_friends_screen/friend_entry.dart` - Friend stub data model
- `lib/sub_friends_screen/friend_row.dart` - Friend list item display

**UI Components:**
- `lib/sub_request_screen/filter_summary_panel.dart` - Display request filters
- `lib/sub_friends_screen/friend_actions.dart` - Action button rendering

### Future Enhancements

1. **Photo Handling:**
   - Currently photos are stripped during share
   - Future: consider cloud storage upload/share mechanism

2. **Review Limits:**
   - Current: 50 reviews hard limit
   - Future: consider pagination or configurable limits

3. **Analytics:**
   - Track share/accept rates
   - Most requested cuisines/countries
   - Provider response times

---

End of review sharing flow documentation (2025-12-18).

---

## Stage 6: Viewing & Filtering Requested Reviews (COMPLETED 2025-12-19)

### Overview
Implemented functionality allowing users to view, filter, and manage reviews they've requested from friends.

### Key Features Implemented

1. **Friend Reviews Screen (`review_reviews_screen.dart`):**
   - Accessible via "FRIEND REVIEWS" button on top_screen
   - Lists all reviews from `users/<uid>/requested_reviews`
   - Filtering options:
     - Filter by owner_email (provider who shared them)
     - Reset filters to show all requested reviews
   - Each review shows:
     - Restaurant name
     - Review date
     - Provider email
     - Preview summary
   - Tap review to view full details in preview mode

2. **Read-Only Preview Mode:**
   - Preview screen supports `mode: 'friend-review'` parameter
   - Disables edit/delete actions when viewing friend reviews
   - Shows full review details including ratings, comments, photos, detail items
   - Navigation back to review_reviews_screen

3. **Data Structure:**
   - Requested reviews stored at `users/<uid>/requested_reviews/<reviewKey>`
   - Each entry contains:
     - Full review payload (ratings, restaurant details, comments, etc.)
     - `owner_email`: email of the friend who provided the review
     - Metadata fields (createdAt, acceptedAt, etc.)

### Technical Implementation Details

**Review Context Enhancement:**
- Added `hasChanges` boolean flag to `ReviewContext` class
- Tracks when user makes modifications to a review (new or editing)
- Used to prevent accidental data loss

**Change Tracking System:**
- Monitors changes across all review input screens:
  - `general_screen.dart`: Text fields, dropdowns, date picker
  - `ratings_screen.dart`: All rating sliders, Michelin stars
  - `goodfor_screen.dart`: Tag selections
  - `comments_screen.dart`: Comments text, photo capture/removal
  - `details_screen.dart`: Detail items, photos, add/remove
- Text controllers have listeners attached to set `hasChanges = true`
- State changes in dropdowns, pickers, and tag selections also set flag
- Clear buttons reset `hasChanges = false` (intentional action)

**Discard Changes Warnings:**
- Warning dialog shown in three scenarios:
  1. Back button on general_screen when `hasChanges = true`
  2. List button on preview_screen when `reviewKey == null` (unsaved new review) OR `hasChanges = true`
  3. Any navigation attempt with unsaved changes
- Uses standard dialog from `AppStr.discardTitle` and `AppStr.discardMessage`
- User can choose to:
  - Cancel: stay on current screen
  - Yes: discard changes and navigate away

**BuildContext Async Safety:**
- Fixed async gaps in `preview_screen.dart`:
  - Added `mounted` checks after all `await showDialog()` calls
  - Prevents using `context`, `Navigator`, or `ScaffoldMessenger` after widget disposal
  - Pattern: check `mounted` before any context usage following async operations

**UI Overflow Fix:**
- Fixed 15-pixel overflow in `review_formatter.dart`
- Wrapped label text in `Flexible` widget in `reviewRow()` function
- Prevents overflow when displaying older reviews with longer field names
- Label can now compress if needed while value field takes remaining space

**Save/Update Behavior:**
- After successful save or update, `hasChanges` is reset to `false`
- Prevents false warnings after data is safely persisted
- Applied in both `saveReview()` and `updateReview()` methods

---

## CLI Tools — `tool/`

### `tool/dbic.dart` — DB Integrity Checker (DBIC)

Standalone Dart CLI that validates the live Firebase RTDB against the current app structure.

**Run:**
```
dart run tool/dbic.dart check <service-account.json>
```
Or use `DBIC.bat` in the project root:
```
DBIC check
```

**What it checks (6 sections):**
| Section | Node | What it validates |
|---|---|---|
| A | `users_by_email` | User registry — uid, email, displayName, updatedAt, statusCode |
| B | `public_profiles` | Display names match `users_by_email`; email back-reference present |
| C | `users_by_email/<id>/requests` (mailbox) | StatusCodes valid {0,1,3,5,6,8,9}; no stale entries |
| D | `audit_info/request_events` | Event log fields: eventType, actorUid/fromUid, targetUid/toUid, timestamp |
| E | `audit_info/deletions`, `/account_deletions`, `/other` | Deletion audit sub-nodes; required fields: timestamp, userId, type, target |
| F | `users/<uid>` tree | Reviews (field validity), friends (statusCodes {0-6,8-10,99}), custom values, received reviews |

**Valid status code sets (confirmed against lib/ code):**
- Friend statusCodes: `{0,1,2,3,4,5,6,8,9,10,99}` — code 10 is default/fallback in `settings_screen.dart`; 99 is legacy (WARN only)
- Mailbox statusCodes: `{0,1,3,5,6,8,9}` — code 2 only appears in friend stubs, not mailbox entries

**Session 2026-05-30 fixes:**
- Replaced 4 legacy Section E nodes (`friend_accept_audit` etc. — no longer written) with active `audit_info` sub-nodes
- Removed `pendingDeleteBy`/`pendingDeleteAt` field checks (fields absent from current code); statusCode=99 now emits WARN only
- Updated stats section in `_printReport` to show `auditDeletions`, `auditAccountDeletions`, `auditOtherEvents`
- `dart analyze` — **No issues found**

---

### `tool/report.dart` — Activity Reporter

Standalone Dart CLI that fetches user and activity data from Firebase RTDB and prints a formatted report. Always ends with a full DBIC run.

**Run:**
```
dart run tool/report.dart full   <service-account.json>
dart run tool/report.dart weekly <service-account.json>
```
Or use `REPORT.bat` in the project root:
```
REPORT full
REPORT weekly
```

**Modes:**
- `full` — All registered users sorted by registration date, with: Display Name, Email, Registered date, Home Country, Own Reviews count, Friend Reviews count, Last Activity timestamp
- `weekly` — Two tables: (1) new users registered in last 7 days; (2) existing users with review or audit activity in last 7 days

**Data sources per user:**
| Field | RTDB path |
|---|---|
| User list | `users_by_email` (single GET) |
| Own reviews | `users/<uid>/reviews` (per-user GET) |
| Friend reviews | `users/<uid>/reviews_requested` shallow (per-user GET) |
| Home country | `users/<uid>/baseCountry` (per-user GET) |
| Last activity / audit events | `audit_info/request_events` (single GET, scanned by actorUid) |

**File output:**
- Reports saved to `Reports/` folder (created if absent) as `report_{mode}_{YYYYMMDD}_{HHMMSS}.txt`
- All `print()` output is tee'd to both stdout and the file via `runZoned` + `ZoneSpecification`
- DBIC subprocess stdout is written explicitly to both

**Session 2026-05-30 changes:**
- Fixed doc comment angle-bracket paths (wrapped in backticks)
- Converted string concatenation (`+`) to adjacent string literals / interpolation
- Added timestamped file output to `Reports/` folder
- Added **Home Country** column to all three table layouts (full, weekly new-users, weekly active-users); reads `users/<uid>/baseCountry`
- `dart analyze` — **No issues found**

**Confirmed live run results (2026-05-30):**
- 22 users, 147 own reviews, 78 friend reviews, 114 audit events, 18/22 home countries populated
- DBIC: 0 errors, 165 warnings (all expected legacy data)

### Files Modified

**Core Changes:**
1. `lib/sub_preview_screen/review_context.dart` - Added `hasChanges` property
2. `lib/general_screen.dart` - Change tracking, conditional back warning
3. `lib/preview_screen.dart` - Change tracking, list button warning, async fixes
4. `lib/ratings_screen.dart` - Change tracking on ratings
5. `lib/goodfor_screen.dart` - Change tracking on tag selection
6. `lib/comments_screen.dart` - Change tracking on text/photos
7. `lib/details_screen.dart` - Change tracking on detail items
8. `lib/sub_preview_screen/review_formatter.dart` - Fixed layout overflow

### Benefits

1. **Data Loss Prevention:**
   - Users warned before accidentally losing unsaved work
   - Applies to both new reviews and edits to existing reviews
   - No false warnings when no changes made

2. **Better UX:**
   - Clear feedback about unsaved changes
   - Consistent warning dialogs across the app
   - Users maintain control over their data

3. **Code Quality:**
   - Proper async/await handling with mounted checks
   - Follows Flutter best practices for BuildContext usage
   - Flexible layouts handle edge cases (old data formats)

---

End of Stage 6 documentation (2025-12-19).

---

## Stage 7: Multi-Filter Review Requests (2025-12-20)

### Overview
Enhanced review request system to support multiple location filters with OR logic, allowing users to request reviews from multiple cities/countries in a single request.

### Database Structure Changes

**Multi-Filter Format:**
Review requests now use an array of location filters instead of single country/city values:
```javascript
{
  "filters": [
    {"country": "Argentina", "city": null},
    {"country": "Brazil", "city": "Bombinhas"},
    {"country": "Brazil", "city": "SP"},
    {"country": "United Kingdom", "city": "London"},
    {"country": "United Kingdom", "city": "Newmarket"}
  ]
}
```

**Mailbox Structure (`users_by_email/<normalized>/requests/<requestId>`):**
- Added `filters` array field
- Removed legacy single `country`/`city` fields (kept for backward compatibility reading)
- Each filter contains optional `country` and/or `city` fields

**Friend Stub Structure (`users/<uid>/friends/<friendUid>`):**
- Review request stub now includes `filters` array
- `rvCount` calculated across all filters using OR logic
- Excluded review keys (`exKeys`) apply across all filters

### Matching Logic (OR Semantics)

Reviews match a request if they match ANY filter in the array:
- Filter matches if both conditions true:
  1. Country matches (or filter country is null)
  2. City matches (or filter city is null)
- Empty/null filters array treated as "match all"

### Files Modified

**1. Review Counting (`lib/services/review_counter.dart`):**
- `countMatchingReviews()` signature changed to accept `List<Map<String, String?>> filters`
- Implements OR logic: review matches if it matches any filter in the list
- Handles null/empty filters array gracefully

**2. Mailbox Processing (`lib/signin_screen.dart`, lines 605-660):**
- Parse `filters` array from mailbox review requests
- Calculate `rvCount` across all filters using updated `countMatchingReviews()`
- Create friend stub with filters array
- Backward compatible: reads legacy `country`/`city` if `filters` missing

**3. Friend Management (`lib/friends_screen.dart`):**
- `_resolveOneRvCount()`: Read filters array from friend stub, recalculate matching count
- `_handleAccept()`: Use filters array for acceptance logic
- Removed all cuisine-related filtering logic (deprecated feature)
- Pass filters to `reviewReviewsScreen` for display

**4. Review Display for Provider (`lib/review_reviews_screen.dart`):**
- Load filters array from review_request
- Filter displayed reviews using OR logic across all location filters
- Show only reviews matching at least one filter
- Provider excludes unwanted reviews before accepting request

**5. Review Acceptance (`lib/services/accept_provided_reviews.dart`):**
- Added `duplicatesSkipped` field to `AcceptProvidedReviewsResult`
- Check for duplicate reviews before copying to `reviews_requested`
- Skip reviews already present in requester's collection
- Return count of duplicates for user feedback

**6. Friend Data Models:**
- `lib/widgets/friend_entry.dart`: Added `filters` field to `ReviewRequestData` class
- `lib/widgets/friend_row.dart`: Updated to work with filters array

### User Experience Improvements

**Duplicate Detection:**
- System checks if requester already has any provided review
- Skips duplicates during acceptance
- Shows contextual SnackBar messages:
  - "All N reviews already exist in your collection"
  - "Accepted N reviews (M duplicates skipped)"
  - Standard success message when no duplicates

**Review Counting:**
- Live count updates show total across all requested locations
- Provider sees only reviews matching their friend's filters
- Accurate counts prevent confusion about available reviews

### Testing Results

**End-to-End Flow (PK1 ↔ PK2):**
1. PK2 creates review request with 5 filters (Argentina, Bombinhas, SP, London, Newmarket)
2. System calculates 21 matching reviews from PK1's collection
3. PK1 sees review request notification
4. PK1 views 21 matching reviews, excludes 3 unwanted
5. PK1 provides 18 reviews to PK2
6. PK2 accepts 18 reviews into their collection
7. Duplicate detection working correctly

### City Extraction Debug Tools

**Purpose:**
Improve accuracy of city name extraction from Google Places formatted addresses.

**Implementation (`lib/services/location_restaurant_helper.dart`):**
- Added `debugAnalyzeCityExtraction(String uid)` function
- Loops through all user reviews
- Prints for each review:
  - Restaurant name
  - Country (from user's setting when review created)
  - Extracted city (from address parsing)
  - Full formatted address from Google Places
  - Re-extraction comparison

**UI Integration (`lib/settings_screen.dart`):**
- Added "Debug City Extraction" button
- Accessible in Settings screen
- Shows SnackBar confirmation when analysis starts
- Output appears in console/debug terminal

**Known Issues:**
- User's country setting may not match restaurant's actual country
- City extraction heuristics vary by country/address format
- TODO: Add country mismatch warning when capturing reviews

### Architecture Notes

**Backward Compatibility:**
- System reads legacy single country/city fields if filters array missing
- Allows gradual migration of existing review requests
- New requests always use filters array format

**Atomic Updates:**
- Multi-path updates ensure mailbox + friend stub consistency
- Uses `_updateWithRetry` for transient error handling
- Rollback on partial failures

**Performance:**
- OR logic efficiently implemented with early exit on match
- Review counting optimized with filter validation
- No N×M explosion for reasonable filter counts

### Future Enhancements

**Planned:**
1. Country mismatch warning when capturing reviews (user's country setting vs restaurant location)
2. Improved city extraction based on debug output analysis
3. Filter UI improvements for easier multi-location selection
4. Review request templates for common location combinations

**Considerations:**
- Maximum filter count limit (prevent abuse)
- UI scaling for many filters
- Performance monitoring for large review collections
- Analytics on filter usage patterns

---

End of Stage 7 documentation (2025-12-20).

---

## Stage 8: Pre-Release Stabilisation (2026-03-20)

Two-day code review and hardening session targeting Play Store release readiness.
All items from TESTING_CHECKLIST.md resolved (H-01→H-12, M-01→M-11, L-01→L-10 except L-04 which was deferred post-release).

### Key Changes By Category

**Crash Prevention (HIGH)**
- `preview_screen.dart`: catch blocks on `saveReview()`/`updateReview()`; `_loadFailed` state with `.catchError` on `initState` fetch; `is Map` guards replacing all unsafe casts
- `settings_screen.dart`: `mounted` check after `await showDialog` in `_confirmDeleteAccount()`; try/catch in `_saveSettings()`
- `startup_tasks.dart`: 4 unsafe `Map` casts → `is Map` guards
- `review_info_builder.dart`: 2 unsafe casts fixed; `debugPrint` → `appLog`
- `mailbox_helper.dart`: `push().key!` → null-safe with early return; all `debugPrint` → `appLog`
- `ube_provider.dart`: empty-email guard prevents silent data loss to push-key path

**User-Facing Error Messages (MEDIUM)**
- All raw `$e` / `${fe.message}` / `${fe.code}` removed from every `SnackBar` across: `top_screen`, `friend_request_screen`, `review_request_screen`, `friends_screen`, `general_screen`, `list_screen`
- All replaced with `AppStr` constants + `appLog()` for dev logging
- `top_screen`: stale `_hasNewReviewsDelivered` indicator cleared in catch block
- `friend_request_screen`: `mounted` checks added after both `await` calls in `_checkRecipientPreview()`

**Data Integrity (MEDIUM)**
- `accept_provided_reviews.dart`: serial per-review `set()` loop → single atomic `ref().update(updates)` call
- `list_screen.dart`: serial `.remove()` loop → single atomic multi-path `null` update
- `custom_values_screen.dart`: 7 unsafe `as Map` casts → `is Map` guards throughout

**Dead Code & Debug Cleanup (LOW)**
- `goodfor_screen.dart`: removed duplicate `_goToNext()` method (identical to `_goToPreviewScreen()`)
- `location_restaurant_helper.dart`: removed 3 debug analysis functions (`analyzeCuisineDetection`, `printCuisineAnalysisReport`, `getSampleRestaurantNames`) + `_isCommonWord` (~320 lines); all `debugPrint` → `appLog`
- `preview_screen.dart`: removed deprecated `_modalRoute`/`_onWillPop`/`addScopedWillPopCallback`/`removeScopedWillPopCallback` (back-press handled by `PopScope(canPop:false)`)
- All remaining `debugPrint` calls across the codebase → `appLog()`

**String Constants (LOW)**
- `settings_screen.dart`: `'OK'`/`'No'`/`'Yes'` → `AppStr.ok`/`AppStr.noLabel`/`AppStr.yes`
- `friends_screen.dart`: `'+Friend'`/`'RV-REQUEST'`/`'+Reviews'` → `AppStr` constants
- `review_request_screen.dart`: `'REQUEST'` → `AppStr.requestBtnLabel`
- `preview_screen.dart`: `'Back'`/`'Exclude'` → `AppStr.backButtonLabel`/`AppStr.exclude`
- New `AppStr` entries added: `reviewLoadError`, `rvRequestLabel`, `addReviewsLabel`, `deleteRelationshipFallback`, `requestBtnLabel`

### appLog() Convention

All debug logging now uses `appLog()` (defined in `restiview_constants.dart`) instead of `debugPrint()`.
`appLog()` is a no-op when `appMode == AppMode.production` — zero debug output in release builds.

### Release Readiness

1. Set `appMode = AppMode.production` in `lib/constants/restiview_constants.dart`
2. Bump version in `pubspec.yaml`
3. Run: `flutter build appbundle --release --dart-define=PLACES_API_KEY=AIzaSyDphPAK5es8vB9XfT28T4JBtByXynFmq-4`

---

End of Stage 8 documentation (2026-03-20).

---

## Release: v1.7.9+35 (2026-04-10)

- Built with `flutter build appbundle --release --dart-define=PLACES_API_KEY=...`
- Published to Play Store Internal Testing track on 2026-04-10
- `appMode` set to `AppMode.production` for build — **change back to `AppMode.test` before next dev session**
- Changes since v1.7.0+26: help screen expansion, connectivity checks, registration error handling, country label, save→list navigation, sign-out reliability, accept/decline dialog unification, GPS stale location fix, GPS timeout reduction, sort indicator, photo storage bug fix, general screen loading overlay, list screen false-toast fix, `mounted` guard, DBIC tool, cuisine cache fix, multi-select cuisine cache, custom values used-flag greying

## Release: v1.7.0+26 (2026-03-21)

- Built with `flutter build appbundle --release --dart-define=PLACES_API_KEY=...`
- Published to Play Store Internal Testing track on 2026-03-21
- Required fix: install Android SDK Command-line Tools (cmdline-tools/latest) — was missing, caused Flutter's post-build symbol-strip verification to fail
- `appMode` is currently set to `AppMode.production` — **change back to `AppMode.test` before next dev session**

---

## Release: v2.0.3+42 (2026-06-01)

- Built with `flutter build appbundle --release --dart-define=PLACES_API_KEY=...`
- Commit: `e23d63d` on branch `master`
- **Android nav bar overlap fix**: `MainActivity.kt` overrides `onCreate` to call
  `WindowCompat.setDecorFitsSystemWindows(window, true)` after `super.onCreate`.
  Flutter 3.22+ enables edge-to-edge by default, causing the 3-button navigation bar
  on older devices (e.g. Motorola G6) to draw over app content. This restores prior behaviour.
- CLI tools added to `tool/`: `dbic.dart` (DB integrity checker), `report.dart` (activity reporter)
- `REPORT.bat` wrapper added to project root
- `appMode` set to `AppMode.production` for build
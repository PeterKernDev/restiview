# DEV_NOTES — RestiView (working draft)

Generated: 2025-12-01

This document is a concise developer-oriented overview of the RestiView Flutter app. It was produced by reading the source files under `lib/` in batches. Sections flagged as "(TODO: expand)" indicate files or details pending full parsing.

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


## Next steps and TODOs

- Finish reading the remaining lib Dart files (I will continue batched reads until all files are parsed).
- Expand the Per-file summaries list to include every file and fill in any TODO placeholders.
- Optionally remediate the Google Places API key: replace with placeholder and add README instructions.
- Optionally create `DEV_NOTES.md` commit or a PR (ask how you'd like the file saved/committed).


---

Notes: This is a working draft. I created this `DEV_NOTES.md` with the summaries collected so far and placeholder guidance for the remaining files. Tell me how you'd like me to proceed: continue reading the remaining files, immediately remediate the API key, or commit this file on a branch and open a PR.

## Developer rules / coding conventions (project-wide)

Add these rules to guide development and code reviews. These are project conventions the team expects all contributors and automated checks to follow:

- REMINDER: Don’t change anything unless the owner has asked for it or we've explicitly agreed the change.
- Statements in an `if` should be enclosed in a block (use `{ ... }`).
- All user-visible text strings should live in a centralized `strings.dart` (or similar) file. Example pattern:
  - class AppStr { static const String strName = "String name"; }
- Avoid deprecated `value` on form fields; use `initialValue` instead to set initial form field values (deprecated after v3.33.0-1.0.pre).
- Avoid `withOpacity`; prefer `.withValues()` to avoid precision loss when adjusting colors.
- Always use braced blocks for bodies of `for`/`if`/`while`, and expand arrow or single-line callbacks into full blocks whenever the body performs more than one action or touches context/state.
  - Guard any async gaps with a `mounted` check before using `context`, `ScaffoldMessenger`, or `setState`.
- Do not use `MaterialStateProperty` (deprecated in this project). Use the recommended replacement patterns for button and style state handling.
- `addScopedWillPopCallback` and `removeScopedWillPopCallback` are deprecated; avoid using them.
- Put the file name and a brief description at the top of every `*.dart` file as a comment. Preserve any existing file header comments and add missing ones where appropriate.
- Do not use `return` inside a `finally` clause.
- Prefer `debugPrint` over `kDebugMode` checks for in-code debug messages.
- Release build command used by the project:
  - `flutter build appbundle --release`

Include or reference this section in code reviews and the repository README so new contributors see the conventions.

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

- Atomic updates & mailbox removal
  - The client composes a single multi-path `.update()` map to create mailbox + both friend stubs atomically. This avoids partial state where a mailbox exists but stubs don't.
  - A helper `_addMailboxRemovalOrMark()` in `db_utils.dart` tries to remove the mailbox entry if the writing client is the mailbox owner, otherwise it marks the mailbox entry as `processedAt`/`processedBy` to avoid accidental deletion of another actor's mailbox.

- Auditing
  - `request_audit` entries are written as best-effort logs alongside request creation. These are not relied on for functional correctness but can assist debugging and manual reconciliation.

- Review requests
  - Review requests are a superset of friend requests and include a `review` object in the mailbox and in the recipient's friend stub (under `.review`) containing `rvCount: -1` to signal the recipient's client to recalculate matching review counts.

- Status codes (canonical meanings seen in code)
  - 0: requester-sent (FR-ASKED)
  - 1: accepted (FR-ACCEPTED)
  - 2: requested (FR-WANTED)
  - 3: rv-wants (recipient side of review-request)
  - 4: rv-asked (requester side of review-request)
  - 8: declined (FR-DECLINED)
  - 9: unknown / placeholder

- Client responsibilities on receive
  - The recipient client listens to `users/<myUid>/friends` and will:
    - Use the `statusCode` to decide which UI actions to surface (Accept / Decline / Delete / Open request details).
    - For review-requests, recalculate `rvCount` by scanning local `users/<myUid>/reviews` (or via `review_counter`) and update the stub's `review.rvCount` atomically.
    - When accepting/declining, build an atomic accept/reject update map (helpers exist in `db_utils.dart`) to modify both user stubs and to mark/remove the mailbox entry.

Notes and recommendations
- The current design relies on client-side atomic `.update()` maps to maintain mailbox + stub consistency. This is simple and efficient but relies on clients following rules. Consider server-side validation or Firebase Cloud Functions to enforce mailbox-stub invariants if you need stronger guarantees.
- Photo fields in friend stubs (if any) are local path references and are not synchronized to cloud storage — the stub should not be relied on to surface portable image assets.
- When deploying, audit mailbox removal rules carefully to avoid deleting someone else's mailbox entry; the existing helper marks processed by default when uncertain.

End of friend-request flow summary.
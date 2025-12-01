# Friends Feature — README

Purpose
- Developer reference for the Friends feature: file locations, responsibilities, RTDB paths, and quick debugging notes.
- Place this file at: lib/sub_friends_screen/README.md

Project layout assumptions
- Main screens (e.g., `friends_screen.dart`, `preview_screen.dart`, other `*_screen.dart`) live directly under `lib/`.
- Complex screens that need supporting files use a sibling subfolder whose name is the screen prefixed with `sub_` (example: `lib/sub_friends_screen/` for `lib/friends_screen.dart`).
- Shared folders under `lib/`: `constants/`, `services/`, `widgets/`.

Table of contents
- Overview
- File map (exact paths)
- RTDB structure used
- Status codes and labels
- Key flows and where to look
- Dev helpers and testing checklist

## Overview
The Friends screen (main entry at `lib/friends_screen.dart`) displays the friends list, supports accept/decline flows, and patches friend metadata from canonical public profiles. Presentation components live in the subfolder `lib/sub_friends_screen/`; DB logic and subscriptions live in the main screen file.

## File map (exact paths)
- `lib/friends_screen.dart`  
  Main screen: subscribes to `users/{myUid}/friends`, manages selection state, performs accept/decline flows, and builds/executes RTDB update maps.

- `lib/sub_friends_screen/` (supporting files for `friends_screen.dart`)  
  - `friend_entry.dart` — `FriendEntry` model, `FriendStatus` enum, parsing helpers (e.g., `mapStringStatusToFsc`, `looksLikeUid`).  
  - `friend_row.dart` — Presentational widget that renders a single friend row (top/second line layout, selection highlight). Pure UI.  
  - `friend_actions.dart` — Presentational widget for the bottom action area (Accept / Decline and Back / +Friend). Pure UI.  
  - `README.md` — This file (keeps the subfolder self-describing).

- `lib/services/db_utils.dart`  
  DB helpers used by the screen: `buildAcceptUpdateMap`, `buildRejectUpdateMap`, audit-key helpers, and safe RTDB update map construction.

- `lib/constants/`  
  Shared constants used app-wide (e.g., `strings.dart`, `colors.dart`, `fonts.dart`).

- `lib/widgets/`  
  Reusable presentational widgets used across screens.

## RTDB structure used
- `users/{myUid}/friends/{friendUid}`  
  Stored as either an integer status code, a status string, or an object with optional fields:
  - `status` / `statusCode` / `state` (int|string)
  - `email`, `username`, `sharedReviewsCount`, `comment`, `mailboxReqId`, `mailboxNormalized`  
  Read via `ref('users/$myUid/friends')`. `lib/friends_screen.dart` patches this path when canonical profile data from `public_profiles/{uid}` is available.

- `public_profiles/{uid}`  
  Canonical public fields used to patch local friend entries: `email`, `displayName`, `sharedReviewsCount`.

- (Optional Stage 2) `reviewRequests/{requestId}`  
  Centralized request records: requester/recipient metadata, `country`, `cuisine`, `city`, `message`, `status`, `createdAt`.

## Status codes and labels
Numeric codes (mapping in `lib/sub_friends_screen/friend_entry.dart`):
- 0 — FR-ASKED
- 1 — ACCEPTED
- 2 — FR-WANTS
- 3 — RV-WANTS
- 4 — RV-ASKED
- 7 — TIMED-OUT
- 8 — REJECTED
- 9 — DECLINED

UI string constants live in `lib/constants/strings.dart` (e.g., `frAsked`, `frWants`, `rvAsked`, `rvWants`, `friendLabel`, `declined`, `timedOut`).

## Key flows and where to look when debugging
1. Subscription and rendering  
   - Inspect `lib/friends_screen.dart` for RTDB subscription issues, empty lists, or selection state bugs.

2. Profile patching  
   - `lib/friends_screen.dart` reads `public_profiles/{uid}` and patches `users/{myUid}/friends/{friendUid}`; check `lib/services/db_utils.dart` and RTDB shapes when patches are missing.

3. Accept / Decline  
   - Handlers are implemented in `lib/friends_screen.dart` and use helpers in `lib/services/db_utils.dart`; inspect the generated update map and resulting RTDB writes.

4. Presentation issues  
   - Fix UI in `lib/sub_friends_screen/friend_row.dart` and `lib/sub_friends_screen/friend_actions.dart` (pure UI files).

## Dev helpers
- Add a one-line header comment at the top of `lib/friends_screen.dart` pointing to `lib/sub_friends_screen/README.md` for quick reference in editors.
- Optional in-app dev helper: `DebugFilesMap` (gated by `kDebugMode`) that lists these files; place it in `lib/dev/` or inline while developing.
- Use relative imports in `lib/friends_screen.dart`:
  - import 'sub_friends_screen/friend_entry.dart';
  - import 'sub_friends_screen/friend_row.dart';
  - import 'sub_friends_screen/friend_actions.dart';

## Testing checklist
- Subscription & load: confirm `users/{myUid}/friends` items render as rows.
- Public profile patching: update `public_profiles/{uid}` and verify the patch appears at `users/{myUid}/friends/{friendUid}`.
- Accept / Decline: exercise both flows; verify DB writes, optimistic UI updates, and rollback/error handling.
- Parsing robustness: verify friend entries stored as int, string, and object shapes parse correctly.
- Selection behavior: ensure tapping rows toggles selection and action buttons enable/disable appropriately.

## Notes and recommendations
- Keep presentation widgets pure (no DB access) to simplify testing and reuse.
- Keep shared utilities in `lib/services/` and shared constants in `lib/constants/` to avoid duplication.
- Update this README in the same commit as code moves so docs stay synchronized.

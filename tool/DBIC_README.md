# DBIC — Database Integrity Checker

A standalone Dart CLI tool that reads the live RestiView Firebase Realtime Database via a service account and checks it for structural errors, orphan records, and data corruption. Run it any time before a release, after a major data migration, or whenever anomalies are suspected.

---

## Quick Start

```powershell
# From the project root:
.\DBIC check    # read-only scan — reports errors/warnings, changes nothing
.\DBIC fix      # same scan, then interactively offers to repair fixable issues
```

---

## One-Time Setup

### 1 — Service account file

1. Open [Firebase Console](https://console.firebase.google.com/) → **restiview-bb851** → gear icon → **Project settings**
2. Click the **Service accounts** tab
3. Click **Generate new private key** → **Generate key** — saves a JSON file to Downloads
4. Move it to the project root and name it to match the gitignore pattern:
   ```
   c:\dev\RestiView2\restiview\restiview-bb851-firebase-adminsdk-<hash>.json
   ```
   (The file is matched by `firebase-adminsdk*.json` in `.gitignore` — it will never be committed.)

### 2 — Dart dependency

`googleapis_auth` is already in `pubspec.yaml` under `dev_dependencies`. If you have freshly cloned the repo run:

```powershell
dart pub get
```

### 3 — DBIC.bat (already created, gitignored)

`DBIC.bat` in the project root contains:

```bat
@echo off
set SA_JSON=%~dp0restiview-bb851-firebase-adminsdk-3tfiq-e5c86eea59.json
if "%1"=="" ( echo Usage: DBIC check / DBIC fix & exit /b 1 )
cd /d "%~dp0"
dart run tool/dbic.dart %1 "%SA_JSON%"
```

If you regenerate the service account key, update the filename on the `set SA_JSON=` line.

---

## What It Checks

The tool runs 6 consecutive sections — progress is printed as `[A/6]...[F/6]`.

| Section | Node(s) checked | What is verified |
|---|---|---|
| **A** | `users_by_email` | Loads the user registry; builds UID / email cross-reference maps used by later sections. |
| **B** | `public_profiles` | Required fields present (`displayName`, `email`, `updatedAt`). Each profile UID exists in the user registry (orphan detection). Email ↔ UID consistency. |
| **C** | `users_by_email/<n>/requests` | Status code validity (`{0,1,3,5,6,8,9}`). Stale unprocessed entries (> 30 days old). |
| **D** | `audit_info/request_events` | Required fields present on every audit event (`action`, `actor`, `target`, `at`). |
| **E** | `audit_info/friend_accept` etc. | Same required-field check on the four friend-lifecycle audit trails. |
| **F** | `users/<uid>/…` | Deep scan of every account: user settings fields, all reviews (required fields, rating arithmetic, date formats, goodfor charset/length), friend entries (status codes, code-99 fields), received reviews (no leaked cost/photo fields), customvals structure. |

---

## Severity Levels

| Level | Meaning |
|---|---|
| **ERROR** | Data is wrong or missing in a way that could affect app behaviour. Must be resolved. |
| **WARN** | Data is incomplete but the cause is known (e.g., legacy reviews written before a field was added). Safe to ignore unless counts change unexpectedly. |

**Known benign warnings** (all legacy data, nothing to action):

| Warning message | Root cause |
|---|---|
| `Missing createdAt (legacy review)` | Reviews written before `createdAt` was added to the write path. |
| `Missing updatedAt (legacy review)` | Same — added at the same time as `createdAt`. |
| `Missing timestamp (legacy review)` | Same. |
| `goodfor length 16 ≠ 18 (legacy review, pre-tag-expansion)` | Written before the goodfor tag list was expanded from 16 → 18 entries. |

---

## Auto-Fixable Issues

When you run `.\DBIC fix` the tool groups fixable errors by category and prompts once per group:

```
Fix all 3 [PUBLIC_PROFILES] issue(s) (DELETE)? [y/n]:
Fix all 1 [REVIEWS_CORRUPT] issue(s) (DELETE)? [y/n]:
```

| Category | Condition | Fix applied |
|---|---|---|
| `PUBLIC_PROFILES` | Orphan profile — no matching `users_by_email` entry | DELETE `public_profiles/<uid>` |
| `REVIEWS` | `restrating` ≠ sum of 5 rating components | PATCH `restrating` with correct value |
| `REVIEWS` | `sortrr` string doesn't match rating | PATCH `sortrr` |
| `REVIEWS` | `sortdate` mismatches `reviewdate` | PATCH `sortdate` |
| `REVIEWS_CORRUPT` | One or more required fields missing | DELETE `users/<uid>/reviews/<key>` |
| `REVIEWS_REQUESTED` | `cost` field not empty (financial data leak) | PATCH empty string |
| `REVIEWS_REQUESTED` | Photo path field present (should be stripped) | DELETE field |

All other errors require manual investigation in the Firebase console.

---

## Reading the Report

```
════════════════════════════════════════════════════════
  RESULTS — CHECK mode
════════════════════════════════════════════════════════

  RECORD COUNTS
  ──────────────────────────────────────────
  Users (users_by_email)                       11
  ...

  ERRORS by category  (0 total)
  ──────────────────────────────────────────────────────
    None

  WARNINGS by category  (163 total)
  ──────────────────────────────────────────────────────
    [REVIEWS]  163 warning(s)
       55×  Missing createdAt (legacy review)
       51×  Missing updatedAt (legacy review)
       57×  goodfor length 16 ≠ 18 (legacy review, pre-tag-expansion)

  ✓  Clean — no errors found.
════════════════════════════════════════════════════════
```

- `★` prefix next to a category in fix mode means at least one issue in that group is auto-fixable.
- The fix log (applied changes, skipped items, failures) is printed at the end of a `fix` run.

---

## Source File

[tool/dbic.dart](dbic.dart)

The tool has no runtime dependency on the Flutter app — it is pure Dart and uses only:
- `dart:io`, `dart:convert`, `dart:async`
- `package:http`
- `package:googleapis_auth`

---

## Firebase Database URL

`https://restiview-bb851.firebaseio.com`

> Note: this is the legacy Firebase URL format (no `-default-rtdb` segment). Do not change it to the default-rtdb format — it will 404.

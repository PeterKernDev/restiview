# START HERE — RestiView Resume Guide

Read this first every time you restart. It tells you the current state of the project and what to read to get back up to speed.

---

## Current State (as of 2026-06-04)

**v2.0.5+44** | `appMode = AppMode.production` | Branch: `master`

### Platform status
- **Android**: v2.0.4+43 — awaiting Google Play approval for production.
- **iOS**: v2.0.3+42 — approved by Apple 2026-06-04; set to auto-release.
- **Next release**: v2.0.5+44 — built from this version. Includes platform (android/ios) capture at registration.

### ⚠️ iOS icon fix — CRITICAL Mac build step
v2.0.3 shipped with the Flutter icon on device despite `flutter_launcher_icons` having been run. Root cause: `git stash/pop` on Mac left the icon PNG files in a dirty state.

**For all future Mac builds, before building:**
```bash
git fetch origin
git reset --hard origin/master
flutter pub get
flutter build ipa --release --dart-define=PLACES_API_KEY=...
```
Use `git reset --hard` (not stash) to guarantee the icon files from the repo are used.

### Changes made 2026-06-04
| Area | Change |
|---|---|
| `pubspec.yaml` | Version bumped to `2.0.5+44` |

### Changes made 2026-06-03 (commit f98b22c)
| Area | Change |
|---|---|
| `lib/register_screen.dart` | Captures `platform` (android/ios) at registration, writes to `users/$uid/platform` in RTDB |
| `tool/report.dart` | Added Platform column to full and weekly report layouts; footer shows iOS/Android count |

### Changes made 2026-06-02
| Area | Change |
|---|---|
| `assets/` | RestiView launcher icons generated for Android + iOS via `flutter_launcher_icons` |
| `android/app/src/main/res/mipmap-*/ic_launcher.png` | Replaced default Flutter icon with RestiView icon (all densities) |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | Replaced default Flutter icon with RestiView icon (all sizes) |
| `pubspec.yaml` | Added `flutter_launcher_icons: ^0.14.3` dev dependency; added `flutter_launcher_icons:` config block |
| `pubspec.yaml` | Version bumped to `2.0.4+43` |
| Google Play | Production access application submitted — answered closed test questionnaire |

### Mac SSH config
Mac IP changed from `192.168.1.25` → `192.168.1.17`. SSH config updated on Windows.
If Mac IP changes again: `notepad $env:USERPROFILE\.ssh\config` → update `HostName`.

---

## ⚠️ Rule: Mac is build-only — never commit from the Mac

**Windows = development machine.** All code changes and commits happen here only.  
**Mac = build-only machine.** It only pulls and builds. Never `git commit` or `git push` from the Mac.

**Do NOT use `git stash/pop` on the Mac** — stash/pop can leave binary icon files in a dirty state, causing the wrong app icon to be embedded in the IPA (this caused the Flutter icon bug in v2.0.3).

Instead, always use:
```bash
git fetch origin
git reset --hard origin/master
flutter pub get
```

This guarantees a byte-for-byte clean copy of the repo before every build.

---

## Current State (as of 2026-05-28)

**Working toward v1.8.1+37. Not yet released.**  
`appMode` is currently `AppMode.test` ✅ correct for dev.  
Branch: `master` — all recent changes committed and pushed. Safe backup tag: `pre-review-request-hardening-20260527` (commit `de9a590`).

### Current focus: iOS testing on Mac simulator
App is being tested on the iOS simulator via SSH from a Windows Surface Pro 11.  
See the **How to Reconnect to the Mac** section below for the full reconnection workflow.

### Play Store closed testing status
- **12 testers** recruited and installed ✅ (needed 12 for 14-day qualification period)
- 14-day clock started **2026-05-18** → earliest production application date: **2026-06-01**
- Romania added as a distribution country ✅
- After 2026-06-01: go to Play Console → Testing → Closed testing → Apply for production access

### iOS bug fixed 2026-05-27 — Firebase nested snapshot shape (iOS vs Android)

**Root cause:** On iOS, `FirebaseDatabase.instance.ref('users/$myUid/friends/$friendUid/review_request').get()` was intermittently returning the parent friends map instead of the `review_request` child node. Android never exhibited this. The code was checking `value is Map` (which passed) but then parsing expected keys that did not exist at that depth, causing the review-request details screen, review list screen, and rvCount resolver to silently fail or show empty data on iOS.

**Fix:** Added `_extractReviewRequestMap()` to each affected screen/service. The method checks for expected keys first; if they are absent it attempts to unwrap one level down via `[friendUid]['review_request']` before returning the map. All three reading paths are now hardened:

| File | Path affected |
|---|---|
| `lib/review_request_details_screen.dart` | `_loadReviewSubnode()` |
| `lib/review_reviews_screen.dart` | `_loadMatchingReviews()` |
| `lib/friends_screen.dart` | `_resolveOneRvCount()` and provider-accept flow |

**Convention added:** See the **Nested RTDB reads** row in Key Conventions below. Also documented in [DEV_NOTES.md](DEV_NOTES.md).

**Rollback:** `git revert 6b0b0d0` or restore tag `pre-review-request-hardening-20260527`.

### All committed changes since v1.7.9+35

| Area | Change |
|---|---|
| `lib/constants/fonts.dart` | Replaced Gelica font with Literata. Renamed `gelica` → `systemFont`. Reduced font sizes 14 → 13. |
| `lib/main.dart` | Updated `fontFamily` to `'Literata'`. |
| `pubspec.yaml` | Replaced Gelica with full Literata family. Moved `fonts:` inside `flutter:` section. |
| `fonts/` folder | Added 8 Literata `.ttf` files. |
| `review_request_details_screen.dart` | iOS fix: `_extractReviewRequestMap()` added; `_onReview()` now passes `filtersList: _filters`. |
| `review_reviews_screen.dart` | iOS fix: `_extractReviewRequestMap()` added; added `filtersList` param and `_buildFallbackFilters()`. |
| `friends_screen.dart` | iOS fix: `_extractReviewRequestMap()` added to `_resolveOneRvCount()` and provider-accept flow. |
| `preview_screen.dart` | Added clipboard copy buttons next to address and telephone fields. |
| `constants/strings.dart` | Added `copiedToClipboard = 'Copied to clipboard'`. |
| `START_HERE.md` | Added Mac reconnection workflow section. Added iOS bug documentation. |
| `DEV_NOTES.md` | Updated logging convention; documented iOS nested RTDB snapshot behavior. |

### Still pending (before next release)

- [ ] Continue iOS simulator testing — work through [TESTING_CHECKLIST_REMAINING.md](TESTING_CHECKLIST_REMAINING.md)
- [ ] `flutter analyze` pass + audit for `print()` calls
- [ ] Firebase security rules audit (`database.rules.json`)
- [ ] 4 unit tests
- [ ] Full manual test run (49+ scenarios across Authentication, Reviews, Friends, Review Requests, Settings, App Lifecycle)
- [x] Play Store: privacy policy URL → https://www.restiview.com/Privacy.php ✅
- [ ] Play Store: content rating questionnaire (Play Console → Policy → App content → Ratings)
- [ ] Play Store: data safety form (Play Console → Policy → App content → Data safety)
- [ ] L-04: `File.existsSync()` sync I/O — deferred post-release

**⚠️ When building next release:**
- Change `appMode` → `AppMode.production` in `lib/constants/restiview_constants.dart`

---

## How to Run the App

```powershell
cd c:\dev\RestiView2\restiview
.\run_RV.bat
```

That bat file calls `flutter run` with the required `PLACES_API_KEY` dart-define.

---

## How to Reconnect to the Mac After a Windows Restart

Use this exact checklist if Windows has restarted and you need to get back onto the Mac to run the iOS simulator.

### 1. Open PowerShell on Windows

Open Windows Terminal or PowerShell as your normal user.

```powershell
whoami
```

You should see your normal Windows username.

### 2. Confirm the SSH key and config still exist

```powershell
Test-Path $env:USERPROFILE\.ssh\id_ed25519
Test-Path $env:USERPROFILE\.ssh\config
Get-Content $env:USERPROFILE\.ssh\config -ErrorAction SilentlyContinue
```

- If `id_ed25519` is missing, restore the private key from backup.
- If `config` is missing, recreate it exactly like this:

```powershell
New-Item -ItemType Directory -Path $env:USERPROFILE\.ssh -Force
@"
Host my-mac
  HostName 192.168.1.25
  User carol
  IdentityFile C:\Users\Denve\.ssh\id_ed25519
  ServerAliveInterval 60
"@ | Out-File -FilePath $env:USERPROFILE\.ssh\config -Encoding ascii
```

### 3. Start `ssh-agent` and load the key

```powershell
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
ssh-add -l
```

Expected result: `ssh-add -l` lists the key fingerprint.

### 4. Test the SSH alias

```powershell
ssh my-mac
```

Expected result: you land at the Mac prompt without a password prompt, for example:

```bash
MacBook-Air-3:~ carol$
```

If SSH asks for a password, run:

```powershell
ssh -v my-mac
```

and inspect the last 10-12 lines.

### 5. If passwordless SSH is not working

Try the following in order.

Force the identity file:

```powershell
ssh -i C:\Users\Denve\.ssh\id_ed25519 carol@192.168.1.25 -v
```

Reinstall the public key on the Mac one time if needed:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh carol@192.168.1.25 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

If VS Code keeps prompting for a password, confirm it is using the same SSH config file:

- `F1 -> Remote-SSH: Open Configuration File`
- choose `C:\Users\Denve\.ssh\config`
- verify the `IdentityFile` path is correct

### 6. Connect from VS Code with Remote-SSH

- Open VS Code on Windows.
- Make sure the Remote-SSH extension is installed.
- Run `F1 -> Remote-SSH: Connect to Host...`
- Choose `my-mac`.
- Allow VS Code to install the remote server if prompted.
- In the remote VS Code window, open the Mac project folder.

### 7. Start the iOS simulator and run RestiView on the Mac

In the Mac terminal or the VS Code remote terminal:

```bash
cd ~/restiview
git checkout master
git pull origin master
open -a Simulator
flutter devices
flutter pub get
flutter run
```

If you need to target a specific simulator device, use:

```bash
flutter run -d <device-id>
```

### 8. Useful simulator troubleshooting

If Flutter cannot see the simulator:

```bash
xcrun simctl list devices
open -a Simulator
flutter devices
```

If the build behaves strangely on the Mac, reset the Flutter build state:

```bash
cd ~/restiview
flutter clean
flutter pub get
flutter run
```

### 9. Clean disconnect

- In the SSH shell, run `exit` or press `Ctrl+D`.
- In VS Code, run `F1 -> Remote-SSH: Close Remote Connection`.

---

## How to Build a Release AAB

1. Open `lib/constants/restiview_constants.dart`
2. Change `AppMode.test` → `AppMode.production`
3. Run:

```powershell
flutter build appbundle --release --dart-define=PLACES_API_KEY=AIzaSyDphPAK5es8vB9XfT28T4JBtByXynFmq-4
```

4. Upload the `.aab` from `build/app/outputs/bundle/release/` to Play Console.

---

## Documents — What to Read and Why

| Document | Read when... |
|---|---|
| **START_HERE.md** (this file) | Every restart — orientation |
| [DEV_NOTES.md](DEV_NOTES.md) | You need the full development history and coding conventions. |
| [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md) | You want to see all manual test scenarios (49+). |
| [TESTING_CHECKLIST_REMAINING.md](TESTING_CHECKLIST_REMAINING.md) | Subset of checklist still to be completed. |
| [PRE_RELEASE_REVIEW.md](PRE_RELEASE_REVIEW.md) | Deployment checklist or code quality metrics summary. |
| [MAILBOX_REFACTOR_DESIGN.md](MAILBOX_REFACTOR_DESIGN.md) | Working on the mailbox / review-request delivery system. |
| [tool/DBIC_README.md](tool/DBIC_README.md) | The Database Integrity Checker — setup, all check sections, auto-fix catalogue, and report format. Run before every release. |
| **Share Predictor — VER7 (live)** | `C:\Users\Denve\PycharmProjects\HelloWorld\.venv\VER7_AI_S0_V1_All_Progs.py` — master orchestrator for the daily Golden Cross workflow. Runs Mon–Fri at 6 AM via Windows Task Scheduler ("Stock Analysis VER7 Weekday 6AM"). 4 steps: fetch history → clean/validate → mine GXs → predict & export to Excel. All stage programs are in `.venv\` alongside it. |
| **Share Predictor — VER10 design doc** | `C:\Users\Denve\PycharmProjects\HelloWorld\VER10\README.md` — full explanation of the trading strategy (GX, -15% stop, +12% engage, -8% trailing stop), the 19 features used, why V1 failed, and the V2 XGBoost pipeline. |
| **Share Predictor — VER11 design doc** | `C:\Users\Denve\PycharmProjects\HelloWorld\VER11\README.md` — in-progress version adding FINRA short interest data (3 new features). Hypothesis: high short interest at GX = short squeeze = more likely profitable. FINRA download was ~700/1848 files complete when last interrupted. |

---

## Key Conventions

| Convention | Detail |
|---|---|
| **`appLog()`** | Use instead of `debugPrint()` everywhere. Silent in `AppMode.production`. |
| **`AppMode`** | `test` for dev, `production` for release. Set in `lib/constants/restiview_constants.dart`. |
| **`AppStr`** constants | All user-visible strings live in `lib/constants/strings.dart`. Never put raw strings in SnackBars. |
| **`is Map` guards** | Never use `as Map` on a Firebase snapshot. Check `if (snapshot.value is! Map) return;` first. |
| **Nested RTDB reads** | For child reads like `.../review_request`, also verify expected keys. On iOS, a `Map` snapshot may sometimes be the parent friends map, so unwrap the nested child before parsing. |
| **Atomic writes** | Use `ref.update({multiPath: value, ...})` instead of serial `.set()` loops. |
| **`mounted` check** | After every `await`, add `if (!mounted) return;` before using `context`. |
| **No Cloud Functions** | Do not propose or use Firebase Cloud Functions. |
| **No `withOpacity`** | Use `.withValues()` instead. |
| **No `MaterialStateProperty`** | Deprecated — use replacement patterns. |

---

## Project Structure Quick Reference

```
lib/
  main.dart                  — app entry point, route map
  constants/
    restiview_constants.dart — AppMode, appLog(), app-wide config
    strings.dart             — AppStr (all user-visible strings)
  services/
    network_utils.dart       — hasInternetConnection() DNS check (NEW)
    mailbox_helper.dart      — review delivery / mailbox logic
    startup_tasks.dart       — runs on login to sync data
    session_cache.dart       — in-memory + persisted session state
    review_info_builder.dart — assembles review data structures
    accept_provided_reviews.dart — writes received reviews to DB
    location_restaurant_helper.dart — Places API / geocoding
  *_screen.dart              — one file per screen
  widgets/                   — shared UI components
```

### Key SessionCache fields relevant to list filtering

| Field | Meaning |
|---|---|
| `SessionCache.countryFilter` | Persisted country filter; `null` = use defaultCountry; `'ALL'` = show all |
| `SessionCache.cityFilter` | Persisted city filter; `null` = no filter |
| `SessionCache.cuisineFilter` | Persisted cuisine filter; `null` = no filter |
| `SessionCache.goodForFilter` | List of active good-for tags; empty = no filter |
| `SessionCache.defaultCountry` | User's home country from settings; `'Any'` means no default |
| `localCountryFilter` | List screen's local override; `'ALL'` = show all countries |

> On `saveReview()`, all four filters are reset: country → review's own country, city/cuisine → null, goodFor → cleared, sort → `date`. This ensures the new review is always visible at the top after saving.

---

## Git

- **Current branch:** `master`
- **Safe backup branch:** `backup-before-upgrades`
- To see what changed: `git diff backup-before-upgrades master`

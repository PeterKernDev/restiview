# RestiView — App Reference Sheet

This document is the single source of truth for critical app identifiers, credentials references, and release configuration. Keep it up to date.

> **Security note:** This file is in version control. Do NOT paste raw passwords or API keys here — reference where they are stored instead.

---

## Identity

| Field             | Value                        |
|-------------------|------------------------------|
| App name          | RestiView                    |
| Android package   | `com.restiview.app`          |
| iOS bundle ID     | TBD                          |
| Flutter project   | `restiview`                  |

---

## Current Version

| Field          | Value   |
|----------------|---------|
| versionName    | 1.7.9   |
| versionCode    | 35      |

> Set in `pubspec.yaml` → `version: 1.7.9+35`.  
> `flutter.versionCode` / `flutter.versionName` in `build.gradle.kts` picks this up automatically.

---

## Android Signing

| Field         | Value / Location                          |
|---------------|-------------------------------------------|
| Keystore file | `c:\dev\RestiView2\restiview\android\restiview.keystore` |
| Key alias     | `restiview`                               |
| Passwords     | Stored in `android/key.properties` (gitignored) |
| Config used by | `android/app/build.gradle.kts` via `signingConfigs.release` |

### SHA-1 Fingerprints

Run to obtain:
```
keytool -list -v -keystore c:\dev\RestiView2\restiview\android\restiview.keystore -alias restiview -storepass <password>
```

| Type                 | SHA-1 Fingerprint                                         |
|----------------------|-----------------------------------------------------------|
| Release (upload key) | `3F:B4:30:4C:FD:F4:2C:DF:80:F9:ED:61:85:B2:12:4D:F3:61:D6:38` |
| Debug                | `49:4E:77:30:51:80:37:C6:DB:CA:52:46:4A:AF:04:F7:D0:1F:D9:3E` |

**SHA-256 (for Firebase / Google Cloud):**  
`2A:DE:CC:64:F3:A5:CE:1E:61:E9:C4:13:47:B7:76:4D:F2:38:A9:38:9C:D8:A1:FD:A2:DB:6A:40:39:8C:5D:FC`

Cert owner: CN=Peter Kern, O=RestiView, L=Newmarket, ST=Suffolk, C=GB  
Valid until: 22 Feb 2053

> Add both fingerprints in Firebase Console → Project Settings → Android app, and in Google Cloud Console → API key restriction.

---

## Firebase

| Field               | Value / Location                          |
|---------------------|-------------------------------------------|
| Project             | See `.firebaserc`                         |
| Android config      | `android/app/google-services.json`        |
| Database rules      | `database.rules.json` + deployed via `firebase.json` |
| Console             | https://console.firebase.google.com       |

---

## Google Places API

| Field       | Value / Location                                         |
|-------------|----------------------------------------------------------|
| Key storage | Passed at build time via `--dart-define=PLACES_API_KEY=` |
| Dev (run)   | `run_RV.bat` and `.vscode/tasks.json`                    |
| Release     | `flutter build appbundle --dart-define=PLACES_API_KEY=<key>` |
| Restrict to | Google Cloud Console → Credentials → API restrictions → **Places API + Identity Toolkit API** (application restrictions: None) |
| Console     | https://console.cloud.google.com                         |

---

## Play Store (Android)

| Field                  | Value / Location                        |
|------------------------|-----------------------------------------|
| Developer account      | [TODO: fill in]                         |
| Play Console           | https://play.google.com/console         |
| App listing            | [TODO: add direct link once created]    |
| App signing (Play)     | Managed by Google Play (upload key above is the upload key, not the app signing key) |
| Privacy policy URL     | [TODO: fill in]                         |
| Target API level       | `flutter.targetSdkVersion` (via pubspec) |
| Min API level          | `flutter.minSdkVersion` (via pubspec)   |

---

## App Store (iOS) — Future

| Field               | Value / Location      |
|---------------------|-----------------------|
| Bundle ID           | [TODO: fill in]       |
| Apple Developer ID  | [TODO: fill in]       |
| App Store Connect   | https://appstoreconnect.apple.com |
| Provisioning profile | [TODO: fill in]      |
| iOS signing cert    | [TODO: fill in]       |

---

## Build Commands

### Development (Android)
```bat
run_RV.bat
```
or via VS Code task: **Clean, Get, Run**

### Release AAB (Play Store)
```bat
flutter build appbundle --release --dart-define=PLACES_API_KEY=<key>
```
**Before building release:** set `appMode = AppMode.production` in `lib/constants/restiview_constants.dart`  
**After release build:** revert to `AppMode.test` for continued development  
Output: `build/app/outputs/bundle/release/app-release.aab`

### Release APK (sideload / testing)
```bat
flutter build apk --release --dart-define=PLACES_API_KEY=<key>
```

---

## Key Files Reference

| File                          | Purpose                                           |
|-------------------------------|---------------------------------------------------|
| `pubspec.yaml`                | Version number, dependencies                      |
| `android/app/build.gradle.kts` | Android build config, signing, SDK versions      |
| `android/key.properties`      | Keystore passwords (gitignored)                   |
| `android/app/google-services.json` | Firebase Android config                      |
| `database.rules.json`         | Firebase RTDB security rules                      |
| `lib/constants/restiview_constants.dart` | Mailbox interval, system constants      |
| `run_RV.bat`                  | Dev run script (includes dart-define)             |
| `.vscode/tasks.json`          | VS Code build task (includes dart-define)         |

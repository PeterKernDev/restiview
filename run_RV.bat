@echo off
rem NOTE: If this repo is ever made public, move the key below to a gitignored local script.
rem Restrict this key in Google Cloud Console to your app package + SHA-1 fingerprint.
flutter clean
flutter pub get
flutter run --dart-define=PLACES_API_KEY=AIzaSyDphPAK5es8vB9XfT28T4JBtByXynFmq-4
pause
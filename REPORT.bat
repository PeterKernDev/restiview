@echo off
set SA_JSON=%~dp0restiview-bb851-firebase-adminsdk-3tfiq-e5c86eea59.json
if "%1"=="" ( echo Usage: REPORT full / REPORT weekly & exit /b 1 )
cd /d "%~dp0"
dart run tool/report.dart %1 "%SA_JSON%"

// session_cache.dart
// Centralized session state and secure storage for RestiView v1.2.2

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionCache {
  static final _storage = FlutterSecureStorage();

  // In-memory fallbacks (kept for quick access).
  static String userName = '';
  static String userEmail = '';
  static String sortOption = 'date'; // canonical values: 'date', 'name', 'rating'
  static String defaultCountry = 'Any';
  static String currency = '\$';
  static bool allowLocation = false;
  static bool allowPhotos = false;
  static int searchRadius = 50;
  static bool allowAutoCapture = false;

  // Device country code (used for registration defaults)
  static String deviceCountryCode = 'US';

  // Custom filters
  static List<String> goodForFilter = [];
  static bool get hasGoodForFilter => goodForFilter.isNotEmpty;

  static List<String> customCuisines = [];
  static List<String> customOccasions = [];
  static List<String> customCountries = [];
  static bool customValsLoaded = false;

  // Storage keys
  static const _keyStaySignedIn = 'staySignedIn';
  static const _keySavedEmail = 'savedEmail';
  static const _keySavedPassword = 'savedPassword';
  static const _keySortOption = 'sortOption';

  // Persist the Stay Signed In flag
  static Future<void> setStaySignedIn(bool value) async {
    await _storage.write(key: _keyStaySignedIn, value: value.toString());
  }

  static Future<bool> getStaySignedIn() async {
    final value = await _storage.read(key: _keyStaySignedIn);
    return value == 'true';
  }

  // Store credentials securely
  static Future<void> setCredentials(String email, String password) async {
    await _storage.write(key: _keySavedEmail, value: email);
    await _storage.write(key: _keySavedPassword, value: password);
  }

  // Clear stored credentials
  static Future<void> clearCredentials() async {
    await _storage.delete(key: _keySavedEmail);
    await _storage.delete(key: _keySavedPassword);
  }

  // Retrieve stored credentials
  static Future<String?> getSavedEmail() async {
    return await _storage.read(key: _keySavedEmail);
  }

  static Future<String?> getSavedPassword() async {
    return await _storage.read(key: _keySavedPassword);
  }

  // Persisted sort option API

  // Save the user's selected sort option persistently and update in-memory copy
  static Future<void> setSortOption(String option) async {
    final canonical = option.toLowerCase();
    sortOption = canonical;
    await _storage.write(key: _keySortOption, value: canonical);
  }

  // Read the persisted sort option; returns fallback in-memory value if none
  static Future<String> getSortOption() async {
    final stored = await _storage.read(key: _keySortOption);
    if (stored != null && stored.isNotEmpty) {
      sortOption = stored;
      return stored;
    }
    return sortOption;
  }

  // Warm in-memory values from storage at app bootstrap
  static Future<void> initializeFromStorage() async {
    final s = await _storage.read(key: _keySortOption);
    if (s != null && s.isNotEmpty) sortOption = s;
    // Add other stored keys here if you persist more later
  }
}
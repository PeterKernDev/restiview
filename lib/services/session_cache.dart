// services/session_cache.dart
// Centralized session state and secure storage for RestiView

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class SessionCache {
  static final _storage = FlutterSecureStorage();

  // In-memory session values
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

  // Filters
  static String? countryFilter;
  static String? cityFilter;
  static String? cuisineFilter;

  // GoodFor selection (single source of truth) and notifier for UI updates
  static List<String> goodForFilter = [];
  static final ValueNotifier<List<String>> goodForNotifier =
      ValueNotifier<List<String>>(List.from(goodForFilter));
  static bool get hasGoodForFilter => goodForFilter.isNotEmpty;

  // Helpers to keep notifier in sync
  static void setGoodForFilter(List<String> selected) {
    goodForFilter = List.from(selected);
    goodForNotifier.value = List.from(goodForFilter);
  }

  static void clearGoodForFilter() {
    goodForFilter.clear();
    goodForNotifier.value = List.from(goodForFilter);
  }

  static List<String> customCuisines = [];
  static List<String> customOccasions = [];
  static List<String> customCountries = [];
  static bool customValsLoaded = false;

  // Indexed Matrix for filtering: Country → City → Set<Cuisine>
  static Map<String, Map<String, Set<String>>> indexedMatrix = {};

  // Secure storage keys
  static const _keyStaySignedIn = 'staySignedIn';
  static const _keySavedEmail = 'savedEmail';
  static const _keySavedPassword = 'savedPassword';
  static const _keySortOption = 'sortOption';

  // Stay Signed In flag
  static Future<void> setStaySignedIn(bool value) async {
    await _storage.write(key: _keyStaySignedIn, value: value.toString());
  }

  static Future<bool> getStaySignedIn() async {
    final value = await _storage.read(key: _keyStaySignedIn);
    return value == 'true';
  }

  // Credentials
  static Future<void> setCredentials(String email, String password) async {
    await _storage.write(key: _keySavedEmail, value: email);
    await _storage.write(key: _keySavedPassword, value: password);
  }

  static Future<void> clearCredentials() async {
    await _storage.delete(key: _keySavedEmail);
    await _storage.delete(key: _keySavedPassword);
  }

  static Future<String?> getSavedEmail() async {
    return await _storage.read(key: _keySavedEmail);
  }

  static Future<String?> getSavedPassword() async {
    return await _storage.read(key: _keySavedPassword);
  }

  // Sort option
  static Future<void> setSortOption(String option) async {
    final canonical = option.toLowerCase();
    sortOption = canonical;
    await _storage.write(key: _keySortOption, value: canonical);
  }

  static Future<String> getSortOption() async {
    final stored = await _storage.read(key: _keySortOption);
    if (stored != null && stored.isNotEmpty) {
      sortOption = stored;
      return stored;
    }
    return sortOption;
  }

  // Initialize session from storage
  static Future<void> initializeFromStorage() async {
    final s = await _storage.read(key: _keySortOption);
    if (s != null && s.isNotEmpty) sortOption = s;
    // Add more keys here if needed
  }

  // Clear all filters
  static void clearFilters() {
    countryFilter = null;
    cityFilter = null;
    cuisineFilter = null;
    clearGoodForFilter();
  }

  // Reset entire session (e.g. on sign-out or account deletion)
  static Future<void> resetSession() async {
    userName = '';
    userEmail = '';
    sortOption = 'date';
    defaultCountry = 'Any';
    currency = '\$';
    allowLocation = false;
    allowPhotos = false;
    allowAutoCapture = false;
    searchRadius = 50;
    deviceCountryCode = 'US';

    countryFilter = null;
    clearGoodForFilter();
    customCuisines.clear();
    customOccasions.clear();
    customCountries.clear();
    customValsLoaded = false;
    indexedMatrix.clear();

    await clearCredentials();
    await setStaySignedIn(false);
  }
}

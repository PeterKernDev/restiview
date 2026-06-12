// services/session_cache.dart
// Centralized session state and secure storage for RestiView
// - Adds safe try/catch wrappers around secure storage I/O with debugPrints
// - Allows optional injection of a FlutterSecureStorage instance for unit testing
// - Exposes helpers used by RequestScreen: getSavedCountry and getCountryList

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class SessionCache {
  // Allow injection for tests. Default to a real FlutterSecureStorage instance.
  static FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Inject a storage instance (test-only). Non-breaking for existing callers.
  static void injectStorageForTesting(FlutterSecureStorage storage) {
    _storage = storage;
  }

  // In-memory session values
  static String userName = '';
  static String userEmail = '';
  static String sortOption =
      'date'; // canonical values: 'date', 'name', 'rating'
  static String defaultCountry = 'Any';
  static String currency = '\$';
  static bool allowLocation = false;
  static bool allowPhotos = false;
  static int searchRadius = 50;
  static bool allowAutoCapture = false;
  static bool reviewsAdded =
      false; // Track if new reviews added since last review_info update
  static String reviewInfoLastUpdateDate = ''; // Track last date review_info was updated (yyyy-MM-dd format)

  // Device country code (used for registration defaults)
  static String deviceCountryCode = 'US';

  // Filters
  static String? countryFilter;
  static String? cityFilter;
  static String? cuisineFilter;

  // Pending friend passed between screens (optional fallback)
  static String pendingFriendEmail = '';
  static String? pendingFriendUid;

  /// Set a pending friend to be consumed by request screens before navigation.
  static void setPendingFriend(String email, String? uid) {
    pendingFriendEmail = email.trim();
    pendingFriendUid = (uid != null && uid.isNotEmpty) ? uid : null;
  }

  /// Clear the pending friend fields after consumption.
  static void clearPendingFriend() {
    pendingFriendEmail = '';
    pendingFriendUid = null;
  }

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

  // Custom lists loaded at runtime
  static List<String> customCuisines = [];
  static List<String> customOccasions = [];
  static List<String> customCountries = [];
  static bool customValsLoaded = false;

  // Restaurant→cuisine cache: keyed by "country|restaurantname_lowercase"
  static Map<String, String> restaurantCuisineCache = {};
  static bool restaurantCuisineCacheLoaded = false;

  /// Reads the user's existing reviews and populates restaurantCuisineCache.
  /// Fire-and-forget: call without await. Silently no-ops on any error.
  static Future<void> warmUpRestaurantCuisineCache(String userId) async {
    if (restaurantCuisineCacheLoaded) return;
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('users/$userId/reviews')
          .get();
      if (!snapshot.exists || snapshot.value is! Map) {
        restaurantCuisineCacheLoaded = true;
        return;
      }
      final data = snapshot.value as Map;
      for (final entry in data.values) {
        if (entry is! Map) continue;
        final name = entry['restname']?.toString().trim() ?? '';
        final country = entry['restcountry']?.toString().trim() ?? '';
        final cuisine = entry['restcuisine']?.toString().trim() ?? '';
        if (name.isNotEmpty && country.isNotEmpty && cuisine.isNotEmpty) {
          // Only store the first cuisine seen — don't overwrite with later reviews
          // (a restaurant may have multiple reviews with different cuisines; first wins)
          final key = '$country|${name.toLowerCase()}';
          restaurantCuisineCache.putIfAbsent(key, () => cuisine);
        }
      }
      restaurantCuisineCacheLoaded = true;
    } catch (_) {
      // Silently fail — keyword fallback will be used instead
    }
  }

  // Indexed Matrix for filtering: Country → City → Set<Cuisine>
  static Map<String, Map<String, Set<String>>> indexedMatrix = {};

  // Secure storage keys
  static const _keySortOption = 'sortOption';
  static const _keySavedDisplayName = 'savedDisplayName';
  static const _keySavedCountry = 'savedCountry'; // new
  static const _keyReviewsAdded = 'reviewsAdded';
  static const _keyReviewInfoLastUpdate = 'reviewInfoLastUpdate';

  // Default system lists (fallbacks)
  static List<String> systemCuisinesFallback = <String>[
    'Italian',
    'Japanese',
    'Brazilian',
    'Mexican',
    'Indian',
    'Chinese',
    'French',
  ];

  static List<String> systemCountriesFallback = <String>[
    'US',
    'BR',
    'JP',
    'IN',
    'MX',
    'IT',
    'CN',
    'FR',
  ];

  // Display name helpers
  static Future<void> setSavedDisplayName(String displayName) async {
    try {
      await _storage.write(key: _keySavedDisplayName, value: displayName);
    } catch (e) {
      // Non-fatal: ignore storage write errors for display name.
    }
  }

  static Future<String?> getSavedDisplayName() async {
    try {
      final String? v = await _storage.read(key: _keySavedDisplayName);

      return v;
    } catch (e) {
      // Non-fatal: ignore read errors and return null.
      return null;
    }
  }

  static Future<void> clearSavedDisplayName() async {
    try {
      await _storage.delete(key: _keySavedDisplayName);
    } catch (e) {
      // Non-fatal: ignore errors while deleting saved display name.
    }
  }

  // Country helpers (new)
  static Future<void> setSavedCountry(String countryCode) async {
    try {
      await _storage.write(key: _keySavedCountry, value: countryCode);
    } catch (e) {
      // Non-fatal: ignore storage write errors for saved country.
    }
  }

  static Future<String?> getSavedCountry() async {
    try {
      final String? v = await _storage.read(key: _keySavedCountry);

      return v ?? (defaultCountry.isNotEmpty ? defaultCountry : null);
    } catch (e) {
      // Non-fatal: ignore read errors and return default country.
      return defaultCountry.isNotEmpty ? defaultCountry : null;
    }
  }

  // Return a country list for dropdowns. Prefers customCountries if loaded, falls back to a static list.
  static Future<List<String>> getCountryList() async {
    try {
      if (customValsLoaded && customCountries.isNotEmpty) {
        return List<String>.from(customCountries);
      }
      // Could be extended to read from storage or remote config
      return List<String>.from(systemCountriesFallback);
    } catch (e) {
      // Non-fatal: ignore read errors and return fallback country list.
      return List<String>.from(systemCountriesFallback);
    }
  }

  // Sort option
  static Future<void> setSortOption(String option) async {
    try {
      final String canonical = option.toLowerCase();
      sortOption = canonical;
      await _storage.write(key: _keySortOption, value: canonical);
    } catch (e) {
      // Non-fatal: ignore errors while setting sort option.
    }
  }

  static Future<String> getSortOption() async {
    try {
      final String? stored = await _storage.read(key: _keySortOption);
      if (stored != null && stored.isNotEmpty) {
        sortOption = stored;

        return stored;
      }

      return sortOption;
    } catch (e) {
      // Non-fatal: ignore read errors and return current sortOption.
      return sortOption;
    }
  }

  // Set/get reviewsAdded flag
  static Future<void> setReviewsAdded(bool value) async {
    reviewsAdded = value;
    try {
      await _storage.write(key: _keyReviewsAdded, value: value.toString());
    } catch (e) {
      debugPrint('Error writing reviewsAdded: $e');
    }
  }

  static Future<bool> getReviewsAdded() async {
    try {
      final String? stored = await _storage.read(key: _keyReviewsAdded);
      reviewsAdded = stored == 'true';
      return reviewsAdded;
    } catch (e) {
      debugPrint('Error reading reviewsAdded: $e');
      return false;
    }
  }

  // Set/get review info last update date
  static Future<void> setReviewInfoLastUpdate(String dateString) async {
    reviewInfoLastUpdateDate = dateString;
    try {
      await _storage.write(key: _keyReviewInfoLastUpdate, value: dateString);
    } catch (e) {
      debugPrint('Error writing reviewInfoLastUpdate: $e');
    }
  }

  static Future<String> getReviewInfoLastUpdate() async {
    try {
      final String? stored = await _storage.read(key: _keyReviewInfoLastUpdate);
      reviewInfoLastUpdateDate = stored ?? '';
      return reviewInfoLastUpdateDate;
    } catch (e) {
      debugPrint('Error reading reviewInfoLastUpdate: $e');
      return '';
    }
  }

  // Initialize session from storage
  static Future<void> initializeFromStorage() async {
    try {
      final String? s = await _storage.read(key: _keySortOption);
      if (s != null && s.isNotEmpty) {
        sortOption = s;
      }
      final String? c = await _storage.read(key: _keySavedCountry);
      if (c != null && c.isNotEmpty) {
        defaultCountry = c;
      }
      final String? r = await _storage.read(key: _keyReviewsAdded);
      reviewsAdded = r == 'true';

      // Add more keys here if needed
    } catch (e) {
      // Non-fatal: ignore initialization errors and continue.
      reviewsAdded = false;
    }
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

    try {
      // best-effort session cleanup
    } catch (e) {
      // Non-fatal: ignore errors during reset; best-effort only.
    }
  }
}

// services/session_cache.dart
// Centralized session state and secure storage for RestiView
// - Adds safe try/catch wrappers around secure storage I/O with debugPrints
// - Allows optional injection of a FlutterSecureStorage instance for unit testing
// - Exposes helpers used by RequestScreen: getSavedCountry and getCountryList

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class SessionCache {
  // Allow injection for tests. Default to a real FlutterSecureStorage instance.
  static FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Inject a storage instance (test-only). Non-breaking for existing callers.
  static void injectStorageForTesting(FlutterSecureStorage storage) {
    _storage = storage;
    if (kDebugMode) {
      debugPrint('[SessionCache] injected test storage instance');
    }
  }

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

    // Pending friend passed between screens (optional fallback)
  static String pendingFriendEmail = '';
  static String? pendingFriendUid;

  /// Set a pending friend to be consumed by request screens before navigation.
  static void setPendingFriend(String email, String? uid) {
    pendingFriendEmail = email.trim();
    pendingFriendUid = (uid != null && uid.isNotEmpty) ? uid : null;
    if (kDebugMode) debugPrint('[SessionCache] pending friend set: $pendingFriendEmail / $pendingFriendUid');
  }

  /// Clear the pending friend fields after consumption.
  static void clearPendingFriend() {
    pendingFriendEmail = '';
    pendingFriendUid = null;
    if (kDebugMode) debugPrint('[SessionCache] pending friend cleared');
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

  // Indexed Matrix for filtering: Country → City → Set<Cuisine>
  static Map<String, Map<String, Set<String>>> indexedMatrix = {};

  // Secure storage keys
  static const _keyStaySignedIn = 'staySignedIn';
  static const _keySavedEmail = 'savedEmail';
  static const _keySavedPassword = 'savedPassword';
  static const _keySortOption = 'sortOption';
  static const _keySavedDisplayName = 'savedDisplayName';
  static const _keySavedCountry = 'savedCountry'; // new

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

  // Stay Signed In flag
  static Future<void> setStaySignedIn(bool value) async {
    try {
      await _storage.write(key: _keyStaySignedIn, value: value.toString());
      if (kDebugMode) {
        debugPrint('[SessionCache] setStaySignedIn=$value');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] setStaySignedIn error: $e');
      }
    }
  }

  static Future<bool> getStaySignedIn() async {
    try {
      final String? value = await _storage.read(key: _keyStaySignedIn);
      if (kDebugMode) {
        debugPrint('[SessionCache] getStaySignedIn read="$value"');
      }
      return value == 'true';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] getStaySignedIn error: $e');
      }
      return false;
    }
  }

  // Credentials
  static Future<void> setCredentials(String email, String password) async {
    try {
      await _storage.write(key: _keySavedEmail, value: email);
      await _storage.write(key: _keySavedPassword, value: password);
      if (kDebugMode) {
        debugPrint('[SessionCache] credentials saved for email="$email"');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] setCredentials error: $e');
      }
    }
  }

  static Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _keySavedEmail);
      await _storage.delete(key: _keySavedPassword);
      await _storage.delete(key: _keySavedDisplayName);
      if (kDebugMode) {
        debugPrint('[SessionCache] credentials cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] clearCredentials error: $e');
      }
    }
  }

  static Future<String?> getSavedEmail() async {
    try {
      final String? v = await _storage.read(key: _keySavedEmail);
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedEmail read="${v ?? ''}"');
      }
      return v;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedEmail error: $e');
      }
      return null;
    }
  }

  static Future<String?> getSavedPassword() async {
    try {
      final String? v = await _storage.read(key: _keySavedPassword);
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedPassword read="${v != null ? '***' : ''}"');
      }
      return v;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedPassword error: $e');
      }
      return null;
    }
  }

  // Display name helpers
  static Future<void> setSavedDisplayName(String displayName) async {
    try {
      await _storage.write(key: _keySavedDisplayName, value: displayName);
      if (kDebugMode) {
        debugPrint('[SessionCache] setSavedDisplayName="$displayName"');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] setSavedDisplayName error: $e');
      }
    }
  }

  static Future<String?> getSavedDisplayName() async {
    try {
      final String? v = await _storage.read(key: _keySavedDisplayName);
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedDisplayName read="${v ?? ''}"');
      }
      return v;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedDisplayName error: $e');
      }
      return null;
    }
  }

  static Future<void> clearSavedDisplayName() async {
    try {
      await _storage.delete(key: _keySavedDisplayName);
      if (kDebugMode) {
        debugPrint('[SessionCache] clearSavedDisplayName');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] clearSavedDisplayName error: $e');
      }
    }
  }

  // Country helpers (new)
  static Future<void> setSavedCountry(String countryCode) async {
    try {
      await _storage.write(key: _keySavedCountry, value: countryCode);
      if (kDebugMode) {
        debugPrint('[SessionCache] setSavedCountry="$countryCode"');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] setSavedCountry error: $e');
      }
    }
  }

  static Future<String?> getSavedCountry() async {
    try {
      final String? v = await _storage.read(key: _keySavedCountry);
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedCountry read="${v ?? ''}"');
      }
      return v ?? (defaultCountry.isNotEmpty ? defaultCountry : null);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] getSavedCountry error: $e');
      }
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
      if (kDebugMode) {
        debugPrint('[SessionCache] getCountryList error: $e');
      }
      return List<String>.from(systemCountriesFallback);
    }
  }

  // Sort option
  static Future<void> setSortOption(String option) async {
    try {
      final String canonical = option.toLowerCase();
      sortOption = canonical;
      await _storage.write(key: _keySortOption, value: canonical);
      if (kDebugMode) {
        debugPrint('[SessionCache] setSortOption="$canonical"');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] setSortOption error: $e');
      }
    }
  }

  static Future<String> getSortOption() async {
    try {
      final String? stored = await _storage.read(key: _keySortOption);
      if (stored != null && stored.isNotEmpty) {
        sortOption = stored;
        if (kDebugMode) {
          debugPrint('[SessionCache] getSortOption read="$stored"');
        }
        return stored;
      }
      if (kDebugMode) {
        debugPrint('[SessionCache] getSortOption fallback="$sortOption"');
      }
      return sortOption;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] getSortOption error: $e');
      }
      return sortOption;
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
      if (kDebugMode) {
        debugPrint('[SessionCache] initializeFromStorage done (sortOption=$sortOption defaultCountry=$defaultCountry)');
      }
      // Add more keys here if needed
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] initializeFromStorage error: $e');
      }
    }
  }

  // Clear all filters
  static void clearFilters() {
    countryFilter = null;
    cityFilter = null;
    cuisineFilter = null;
    clearGoodForFilter();
    if (kDebugMode) {
      debugPrint('[SessionCache] clearFilters');
    }
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
      await clearCredentials();
      await setStaySignedIn(false);
      if (kDebugMode) {
        debugPrint('[SessionCache] resetSession complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SessionCache] resetSession error: $e');
      }
    }
  }
}

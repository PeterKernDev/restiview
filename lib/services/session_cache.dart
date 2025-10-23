// session_cache.dart
// Centralized session state and secure storage for RestiView v1.2.2

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionCache {
  static final _storage = FlutterSecureStorage();

  // 🔐 Secure session values
  static String userName = '';
  static String userEmail = '';
  static String sortOption = 'date';
  static String defaultCountry = 'Any';
  static String currency = '\$'; // 💰 Default fallback
  static bool allowLocation = false;
  static bool allowPhotos = false;
  static int searchRadius = 50;
  static bool allowAutoCapture = false;

  // 🌍 Device country code (used for registration defaults)
  static String deviceCountryCode = 'US'; // Default fallback, set dynamically at startup

  // 🔖 Custom filters
  static List<String> goodForFilter = [];
  static bool get hasGoodForFilter => goodForFilter.isNotEmpty;

  static List<String> customCuisines = [];
  static List<String> customOccasions = [];
  static List<String> customCountries = [];
  static bool customValsLoaded = false;

  // ✅ Persist the Stay Signed In flag
  static Future<void> setStaySignedIn(bool value) async {
    await _storage.write(key: 'staySignedIn', value: value.toString());
  }

  static Future<bool> getStaySignedIn() async {
    final value = await _storage.read(key: 'staySignedIn');
    return value == 'true';
  }

  // ✅ Store credentials securely
  static Future<void> setCredentials(String email, String password) async {
    await _storage.write(key: 'savedEmail', value: email);
    await _storage.write(key: 'savedPassword', value: password);
  }

  // ✅ Clear stored credentials
  static Future<void> clearCredentials() async {
    await _storage.delete(key: 'savedEmail');
    await _storage.delete(key: 'savedPassword');
  }

  // ✅ Retrieve stored credentials
  static Future<String?> getSavedEmail() async {
    return await _storage.read(key: 'savedEmail');
  }

  static Future<String?> getSavedPassword() async {
    return await _storage.read(key: 'savedPassword');
  }
}
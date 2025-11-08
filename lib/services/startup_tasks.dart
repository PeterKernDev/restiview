// services/startup_tasks.dart
//
import 'package:firebase_database/firebase_database.dart';
import 'session_cache.dart';
import '../constants/restiview_constants.dart';

Future<void> runStartupTasks({
  required String uid,
  required String userName,
  required String userEmail,
  required String homeCountry,
}) async {
  // 1. Set basic user identity
  SessionCache.userName = userName;
  SessionCache.userEmail = userEmail;
  SessionCache.defaultCountry = homeCountry;
  SessionCache.currency = getCurrencyForCountry(homeCountry);

  // 2. Load user settings
  final userSnapshot = await FirebaseDatabase.instance.ref('users/$uid').get();
  final userMap = userSnapshot.value as Map<dynamic, dynamic>? ?? {};

  SessionCache.sortOption = ((userMap['userSettings1'] as String?) ?? 'date').toLowerCase();
  SessionCache.allowLocation = (userMap['userSettings3'] as bool?) ?? false;
  SessionCache.allowPhotos = (userMap['userSettings4'] as bool?) ?? false;
  SessionCache.searchRadius = (userMap['userSettings5'] as int?) ?? 50;
  SessionCache.allowAutoCapture = (userMap['userSettings6'] as bool?) ?? false;

  // 3. Load reviews and build Indexed Matrix
  final reviewsRef = FirebaseDatabase.instance.ref('users/$uid/reviews');
  final reviewsSnapshot = await reviewsRef.get();
  final rawReviews = reviewsSnapshot.value as Map<dynamic, dynamic>? ?? {};

  final List<Map<String, dynamic>> reviews = rawReviews.entries.map((e) {
    final review = Map<String, dynamic>.from(e.value as Map);
    review['key'] = e.key;
    return review;
  }).toList();

  final Map<String, Map<String, Set<String>>> matrix = {};
  for (var review in reviews) {
    final ctRaw = review['restcountry'];
    final cyRaw = review['restcity'];
    final czRaw = review['restcuisine'];

    final ct = ctRaw is String ? ctRaw.trim() : (ctRaw?.toString().trim());
    final cy = cyRaw is String ? cyRaw.trim() : (cyRaw?.toString().trim());
    final cz = czRaw is String ? czRaw.trim() : (czRaw?.toString().trim());

    if (ct != null && ct.isNotEmpty && cy != null && cy.isNotEmpty && cz != null && cz.isNotEmpty) {
      matrix.putIfAbsent(ct, () => <String, Set<String>>{});
      matrix[ct]!.putIfAbsent(cy, () => <String>{});
      matrix[ct]![cy]!.add(cz);
    }
  }
  SessionCache.indexedMatrix = matrix;

  // 4. Load custom values
  final customSnap = await FirebaseDatabase.instance.ref('users/$uid/customvals').get();
  if (customSnap.exists) {
    final customData = customSnap.value as Map<dynamic, dynamic>;
    _appendCustomValuesFromFirebase(customData);
  } else {
    _initializeDefaultCustomValues();
  }
}

void _initializeDefaultCustomValues() {
  SessionCache.customValsLoaded = false;
  SessionCache.customCuisines = [...systemCuisines];
  SessionCache.customOccasions = [...systemOccasions];
  SessionCache.customCountries = [...getSystemCountryNames()];
}

void _appendCustomValuesFromFirebase(Map<dynamic, dynamic> customData) {
  final rawCuisines = <String>[];
  try {
    final raw = customData['cuisine'] ?? [];
    for (final item in List<dynamic>.from(raw)) {
      if (item is List && item.isNotEmpty) {
        final value = item[0];
        if (value is String && value.trim().isNotEmpty) rawCuisines.add(value.trim());
      } else if (item is String && item.trim().isNotEmpty) {
        rawCuisines.add(item.trim());
      }
    }
  } catch (_) {}

  final rawOccasions = <String>[];
  try {
    final raw = customData['occasion'] ?? [];
    for (final item in List<dynamic>.from(raw)) {
      if (item is List && item.isNotEmpty) {
        final value = item[0];
        if (value is String && value.trim().isNotEmpty) rawOccasions.add(value.trim());
      } else if (item is String && item.trim().isNotEmpty) {
        rawOccasions.add(item.trim());
      }
    }
  } catch (_) {}

  final rawCountries = <String>[];
  try {
    final raw = customData['country'] ?? [];
    for (final item in List<dynamic>.from(raw)) {
      if (item is String && item.trim().isNotEmpty) rawCountries.add(item.trim());
    }
  } catch (_) {}

  SessionCache.customValsLoaded = true;

  final cuisineSet = <String>{}
    ..addAll(systemCuisines)
    ..addAll(rawCuisines);
  SessionCache.customCuisines = cuisineSet.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final occasionSet = <String>{}
    ..addAll(systemOccasions)
    ..addAll(rawOccasions);
  SessionCache.customOccasions = occasionSet.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final countrySet = <String>{}
    ..addAll(getSystemCountryNames())
    ..addAll(rawCountries);
  SessionCache.customCountries = countrySet.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

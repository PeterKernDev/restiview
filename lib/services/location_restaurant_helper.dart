
// services/location_restaurant_helper.dart
//
// Defensive, timeout-aware helper to locate nearby restaurants and perform location-based utilities.
// Returns [] on any failure rather than throwing.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:diacritic/diacritic.dart';

import '../constants/cuisine_constants.dart';
import '../constants/restiview_constants.dart';
import '../services/session_cache.dart';

/// Normalizes geocoding country names to match app's country naming convention.
/// Maps common variations to the app's standard country names.
String normalizeCountryName(String? geocodedCountry) {
  if (geocodedCountry == null || geocodedCountry.isEmpty) {
    return '';
  }
  
  // Map common geocoding country names to app's country names
  const Map<String, String> countryNameMap = {
    'United States': 'USA',
    'United States of America': 'USA',
    'US': 'USA',
    'Great Britain': 'United Kingdom',
    'UK': 'United Kingdom',
    'South Korea': 'South Korea',
    'Korea': 'South Korea',
    'Republic of Korea': 'South Korea',
    // Add more mappings as needed
  };
  
  return countryNameMap[geocodedCountry] ?? geocodedCountry;
}

/// Returns the current country name using reverse geocoding.
/// Returns null if location or country cannot be determined.
/// The returned country name is normalized to match app's naming convention.
Future<String?> getCurrentCountrySafe({Duration timeout = const Duration(seconds: 10)}) async {
  final pos = await getCurrentLocationSafe(timeout: timeout);
  if (pos == null) {
    return null;
  }
  try {
    final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude)
        .timeout(timeout);
    if (placemarks.isNotEmpty) {
      final geocodedCountry = placemarks.first.country;
      return normalizeCountryName(geocodedCountry);
    }
    return null;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

String normalize(String input) => removeDiacritics(input.toLowerCase());

class NearbyRestaurant {
  final String name;
  final String address;
  final String? phone;
  final String city;
  final String cuisine;

  NearbyRestaurant({
    required this.name,
    required this.address,
    required this.city,
    required this.cuisine,
    this.phone,
  });
}

String cleanRestaurantName(String rawName) {
  final split = rawName.split(RegExp(r'[:\-]'));
  final cleaned = split.first.trim();
  return cleaned.length > 40 ? '${cleaned.substring(0, 40)}…' : cleaned;
}

/// Improved heuristic to extract city name from Google Places formatted address.
/// Handles various country-specific address formats.
/// Returns '' if no city can be determined.
String extractCityFromAddress(String address) {
  if (address.trim().isEmpty) {
    return '';
  }

  // Split by comma to get address components
  final List<String> parts = address.split(',').map((p) => p.trim()).toList();
  if (parts.isEmpty) {
    return '';
  }

  // Helper: Check if string looks like a ZIP/postal code
  bool looksLikeZip(String s) {
    return RegExp(r'^\d{5}(-\d{3,4})?$').hasMatch(s.trim()) || // US/Brazil ZIP
           RegExp(r'^\d{5}$').hasMatch(s.trim()) || // Spain/other
           RegExp(r'^[A-Z]\d[A-Z]\s?\d[A-Z]\d$').hasMatch(s.trim()); // Canada
  }

  // Helper: Check if string looks like a state/province abbreviation
  bool looksLikeState(String s) {
    final trimmed = s.trim();
    return RegExp(r'^[A-Z]{2}$').hasMatch(trimmed) || // US states: FL, CA
           RegExp(r'^[A-Z]{2,3}$').hasMatch(trimmed); // Other: SP, SC, UK
  }

  // Helper: Check if string starts with street number
  bool startsWithNumber(String s) {
    return RegExp(r'^\d+[\s\-]').hasMatch(s.trim());
  }

  // Helper: Extract city before hyphen in "City - State" format
  String extractBeforeStateHyphen(String s) {
    final segments = s.split('-').map((t) => t.trim()).toList();
    if (segments.length >= 2 && looksLikeState(segments.last)) {
      return segments.first; // Return "São Paulo" from "São Paulo - SP"
    }
    return s;
  }

  // Helper: Clean up postcode suffix (UK format: "London NW1 6JQ" -> "London")
  String stripPostcode(String s) {
    // Match UK postcodes: "London NW1 6JQ" or "London W1U 7BT"
    final ukPostcodePattern = RegExp(r'\s+[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}$');
    return s.replaceAll(ukPostcodePattern, '').trim();
  }

  // Strategy 1: Try to find known city from system cities list
  final String country = SessionCache.defaultCountry;
  final List<String> countryCities = systemCitiesByCountry[country] ?? [];
  final String normalizedAddress = normalize(address);
  
  for (final String city in countryCities) {
    if (normalizedAddress.contains(normalize(city))) {
      return city;
    }
  }

  // Strategy 2: Parse based on number of components and patterns
  
  // Single component - might be just city name
  if (parts.length == 1) {
    return parts[0];
  }

  // Two components: usually "City, Country"
  if (parts.length == 2) {
    return stripPostcode(parts[0]);
  }

  // Three components: could be "Street, City, Country" or "City, State, Country"
  if (parts.length == 3) {
    final candidate = stripPostcode(parts[1]);
    final cleaned = extractBeforeStateHyphen(candidate);
    if (!startsWithNumber(cleaned) && !looksLikeZip(cleaned)) {
      return cleaned;
    }
    // Fallback to first component if second doesn't look like city
    return stripPostcode(parts[0]);
  }

  // Four+ components - most common case
  // Formats:
  // - "Street, Number, ZIP City, Province, Country" (Spain: index 2 has "07810 Ibiza")
  // - "Number Street, City Postcode, Country" (UK: index 1 has "London NW1 6JQ")
  // - "Number Street, City, State ZIP, Country" (USA: index 1 has city)
  // - "Street, Number - Neighborhood, City - State, ZIP, Country" (Brazil: index 2 has "São Paulo - SP")

  if (parts.length >= 4) {
    // Check index 2 for "ZIP City" pattern (Spain style)
    final part2 = parts[2].trim();
    if (part2.contains(' ')) {
      final subParts = part2.split(' ');
      if (subParts.length >= 2 && looksLikeZip(subParts[0])) {
        // Found "07810 Ibiza" - return city after ZIP
        return subParts.sublist(1).join(' ').trim();
      }
    }

    // Check index 2 for "City - State" pattern (Brazil style)
    final cleaned2 = extractBeforeStateHyphen(part2);
    if (cleaned2 != part2 && !startsWithNumber(cleaned2)) {
      // Found "São Paulo - SP" pattern
      return cleaned2;
    }

    // Check index 1 for city (UK/USA style)
    final part1 = stripPostcode(parts[1].trim());
    final cleaned1 = extractBeforeStateHyphen(part1);
    if (!startsWithNumber(cleaned1) && !looksLikeZip(cleaned1) && !looksLikeState(cleaned1)) {
      return cleaned1;
    }
  }

  // Strategy 3: Scan middle components (skip first street and last country)
  for (int i = 1; i < parts.length - 1; i++) {
    final candidate = stripPostcode(parts[i].trim());
    final cleaned = extractBeforeStateHyphen(candidate);
    
    // Skip if looks like street number, ZIP, or state
    if (startsWithNumber(cleaned) || looksLikeZip(cleaned) || looksLikeState(cleaned)) {
      continue;
    }
    
    // Skip very short strings (likely abbreviations)
    if (cleaned.length < 3) {
      continue;
    }
    
    return cleaned;
  }

  // Last resort: use second-to-last component if it exists
  if (parts.length >= 3) {
    final fallback = stripPostcode(parts[parts.length - 2].trim());
    final cleaned = extractBeforeStateHyphen(fallback);
    if (!looksLikeZip(cleaned) && !looksLikeState(cleaned)) {
      return cleaned;
    }
  }

  return '';
}

String guessCuisineFromName(String name) {
  final lower = name.toLowerCase();
  for (final entry in cuisineKeywords.entries) {
    if (entry.value.any((keyword) => lower.contains(keyword))) {
      return entry.key;
    }
  }
  return 'Unknown';
}

/// Get current position with a timeout and safe handling.
/// Returns null on any failure or permission denial.
Future<Position?> getCurrentLocationSafe({Duration timeout = const Duration(seconds: 10)}) async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return last;
      }
    } catch (_) {}

    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(timeout);
      return pos;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  } catch (_) {
    return null;
  }
}

/// Defensive findNearbyRestaurants:
/// - returns empty list on any error
/// - uses short timeouts for network and details requests
/// - limits details requests and runs them concurrently
Future<List<NearbyRestaurant>> findNearbyRestaurants({
  Duration overallTimeout = const Duration(seconds: 14),
  Duration positionTimeout = const Duration(seconds: 10),
  Duration httpTimeout = const Duration(seconds: 6),
  int maxPlacesToProcess = 6,
}) {
  return _internalFind(positionTimeout, httpTimeout, maxPlacesToProcess)
      .timeout(overallTimeout, onTimeout: () => <NearbyRestaurant>[]);
}

Future<List<NearbyRestaurant>> _internalFind(
    Duration positionTimeout, Duration httpTimeout, int maxPlacesToProcess) async {
  if (!SessionCache.allowLocation) {
    debugPrint('🔍 Restaurant search: Location not allowed');
    return [];
  }

  if (googlePlacesApiKey.isEmpty) {
    debugPrint('🔍 Restaurant search: API key is empty');
    return [];
  }

  try {
    final pos = await getCurrentLocationSafe(timeout: positionTimeout);
    if (pos == null) {
      debugPrint('🔍 Restaurant search: Could not get location');
      return [];
    }
    final lat = pos.latitude;
    final lng = pos.longitude;
    final radius = SessionCache.searchRadius;
    
    debugPrint('🔍 Restaurant search: lat=$lat, lng=$lng, radius=$radius meters');

    final nearbyUrl =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radius&type=restaurant&key=$googlePlacesApiKey';

    late http.Response nearbyResponse;
    try {
      nearbyResponse = await http.get(Uri.parse(nearbyUrl)).timeout(httpTimeout);
    } on TimeoutException {
      debugPrint('🔍 Restaurant search: HTTP request timed out');
      return [];
    } catch (e) {
      debugPrint('🔍 Restaurant search: HTTP request failed: $e');
      return [];
    }

    if (nearbyResponse.statusCode != 200) {
      debugPrint('🔍 Restaurant search: HTTP status ${nearbyResponse.statusCode}');
      debugPrint('🔍 Response body: ${nearbyResponse.body}');
      return [];
    }

    final nearbyData = jsonDecode(nearbyResponse.body) as Map<String, dynamic>? ?? {};
    final status = nearbyData['status'] as String?;
    final errorMessage = nearbyData['error_message'] as String?;
    debugPrint('🔍 Restaurant search: API status=$status');
    if (errorMessage != null) {
      debugPrint('🔍 Restaurant search: Error message: $errorMessage');
    }
    
    final results = nearbyData['results'] as List<dynamic>? ?? [];
    debugPrint('🔍 Restaurant search: Found ${results.length} places');

    if (results.isEmpty) {
      return [];
    }

    final placesToProcess = results.take(maxPlacesToProcess).toList();

    final List<Future<NearbyRestaurant?>> detailFutures = [];
    for (final place in placesToProcess) {
      if (place is Map<String, dynamic>) {
        final placeId = place['place_id'] as String?;
        if (placeId == null) continue;

        detailFutures.add(_fetchPlaceDetails(placeId, httpTimeout));
      }
    }

    final details = await Future.wait(detailFutures);

    final restaurants = details.whereType<NearbyRestaurant>().toList();
    debugPrint('🔍 Restaurant search: Returning ${restaurants.length} restaurants');
    return restaurants;
  } catch (e, stackTrace) {
    debugPrint('🔍 Restaurant search: Exception: $e');
    debugPrint('🔍 Stack trace: $stackTrace');
    return [];
  }
}

/// Fetch place details for a single place_id; returns null on any failure.
Future<NearbyRestaurant?> _fetchPlaceDetails(String placeId, Duration timeout) async {
  if (googlePlacesApiKey.isEmpty) return null;

  final detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=name,formatted_address,formatted_phone_number&key=$googlePlacesApiKey';

  try {
    final resp = await http.get(Uri.parse(detailsUrl)).timeout(timeout);

    if (resp.statusCode != 200) {
      return null;
    }
    final Map<String, dynamic> detailsData = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = detailsData['result'] as Map<String, dynamic>?;

    if (result == null) return null;

    final nameRaw = result['name'] as String? ?? '';
    final cleanedName = nameRaw.isEmpty ? 'Unknown' : cleanRestaurantName(nameRaw);
    final address = result['formatted_address'] as String? ?? '';
    final city = extractCityFromAddress(address);
    final phone = result['formatted_phone_number'] as String?;
    final cuisine = guessCuisineFromName(cleanedName);

    return NearbyRestaurant(
      name: cleanedName,
      address: address,
      city: city,
      phone: phone,
      cuisine: cuisine,
    );
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}

/// Cuisine Analysis Tool
/// Analyzes a list of restaurant names and reports which ones don't match any cuisine.
/// Returns a map with analysis results for debugging and improving cuisine keywords.
Map<String, dynamic> analyzeCuisineDetection(List<String> restaurantNames) {
  final unmatched = <String>[];
  final matched = <String, List<String>>{};
  final suggestions = <String, Set<String>>{};

  for (final name in restaurantNames) {
    final cuisine = guessCuisineFromName(name);
    
    if (cuisine == 'Unknown') {
      unmatched.add(name);
      
      // Extract potential cuisine indicators from the name
      final lower = name.toLowerCase();
      final words = lower.split(RegExp(r'\s+'));
      
      for (final word in words) {
        // Skip common words that aren't cuisine indicators
        if (_isCommonWord(word)) continue;
        
        // Add to suggestions
        suggestions.putIfAbsent(word, () => {}).add(name);
      }
    } else {
      matched.putIfAbsent(cuisine, () => []).add(name);
    }
  }

  return {
    'total': restaurantNames.length,
    'matched': matched.length,
    'unmatched': unmatched.length,
    'unmatchedNames': unmatched,
    'matchedByCuisine': matched,
    'suggestions': suggestions,
    'matchRate': restaurantNames.isEmpty 
        ? 0.0 
        : (restaurantNames.length - unmatched.length) / restaurantNames.length,
  };
}

/// Helper to identify common words that aren't cuisine indicators
bool _isCommonWord(String word) {
  const commonWords = {
    'the', 'a', 'an', 'and', 'or', 'of', 'at', 'by', 'for', 'in', 'on', 'to',
    'restaurant', 'cafe', 'bar', 'house', 'kitchen', 'room', 'club', 'place',
    'new', 'old', 'grand', 'little', 'big', 'great', 'good', 'best', 'fine',
    'dining', 'eatery', 'bistro', 'inn', 'lodge', 'spot', 'gourmet',
    '&', '-', "'s", 'de', 'la', 'le', 'del', 'el', 'los', 'las',
  };
  return commonWords.contains(word.toLowerCase());
}

/// Prints a formatted analysis report to the console
void printCuisineAnalysisReport(Map<String, dynamic> analysis) {
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('📊 CUISINE DETECTION ANALYSIS REPORT');
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('');
  debugPrint('Total restaurants analyzed: ${analysis['total']}');
  debugPrint('Successfully matched: ${analysis['total'] - analysis['unmatched']}');
  debugPrint('Unmatched (Unknown): ${analysis['unmatched']}');
  debugPrint('Match rate: ${(analysis['matchRate'] * 100).toStringAsFixed(1)}%');
  debugPrint('');
  
  if (analysis['unmatched'] > 0) {
    debugPrint('❌ UNMATCHED RESTAURANTS:');
    final unmatchedNames = analysis['unmatchedNames'] as List<String>;
    for (var i = 0; i < unmatchedNames.length; i++) {
      debugPrint('   ${i + 1}. ${unmatchedNames[i]}');
    }
    debugPrint('');
    
    debugPrint('💡 SUGGESTED KEYWORDS TO ADD:');
    final suggestions = analysis['suggestions'] as Map<String, Set<String>>;
    final sortedSuggestions = suggestions.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    
    for (var i = 0; i < sortedSuggestions.length && i < 20; i++) {
      final entry = sortedSuggestions[i];
      debugPrint('   "${entry.key}" - appears in ${entry.value.length} restaurant(s):');
      for (final name in entry.value.take(3)) {
        debugPrint('      • $name');
      }
    }
    debugPrint('');
  }
  
  debugPrint('✅ MATCHED BY CUISINE TYPE:');
  final matchedByCuisine = analysis['matchedByCuisine'] as Map<String, List<String>>;
  final sortedCuisines = matchedByCuisine.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  
  for (final entry in sortedCuisines) {
    debugPrint('   ${entry.key}: ${entry.value.length} restaurant(s)');
    for (final name in entry.value.take(3)) {
      debugPrint('      • $name');
    }
    if (entry.value.length > 3) {
      debugPrint('      ... and ${entry.value.length - 3} more');
    }
  }
  
  debugPrint('');
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

/// Sample restaurant names for testing cuisine detection
/// Add real restaurant names you encounter to improve the system
List<String> getSampleRestaurantNames() {
  return [
    // Steakhouses / American Meat
    'Papi Steak House',
    'The Capital Grille',
    "Morton's The Steakhouse",
    'Texas Roadhouse',
    'Outback Steakhouse',
    "Ruth's Chris Steak House",
    'LongHorn Steakhouse',
    "Smith & Wollensky",
    "Del Frisco's Double Eagle",
    'Fleming\'s Prime Steakhouse',
    'The Palm',
    
    // Italian
    'Olive Garden',
    'Carrabba\'s Italian Grill',
    "Maggiano's Little Italy",
    'Buca di Beppo',
    'Romano\'s Macaroni Grill',
    'Bertucci\'s',
    'Il Fornaio',
    'Osteria',
    'Trattoria Italiana',
    
    // Mexican / Tex-Mex
    'Chipotle Mexican Grill',
    'Taco Bell',
    "Chili's Grill & Bar",
    'El Torito',
    "Chevys Fresh Mex",
    'Qdoba Mexican Eats',
    "Moe's Southwest Grill",
    'Cafe Rio',
    'On The Border',
    'Uncle Julio\'s',
    'Pappasito\'s Cantina',
    
    // Chinese
    'P.F. Chang\'s',
    'Panda Express',
    "Pick Up Stix",
    'Pei Wei Asian Diner',
    'China Bistro',
    'Mandarin House',
    'Golden Dragon',
    'Great Wall',
    
    // Japanese
    'Benihana',
    'Nobu',
    'Kona Grill',
    'RA Sushi',
    'Blue Fin',
    'Shogun',
    'Tokyo Joe\'s',
    'Sakura Japanese',
    'Sushi Palace',
    
    // Thai
    'Thai Basil',
    'Siam Garden',
    'Thai Kitchen',
    'Lemongrass Grill',
    'Royal Thai',
    
    // Korean
    'Gen Korean BBQ',
    'Bulgogi House',
    'Seoul Garden',
    'Kang Ho Dong Baekjeong',
    
    // Vietnamese
    'Pho 79',
    'Saigon Cafe',
    'Pho Hoa',
    'Banh Mi Saigon',
    
    // Indian
    'Bombay Palace',
    'Tandoor House',
    'India Palace',
    'Curry House',
    'Masala Indian Kitchen',
    
    // Mediterranean / Middle Eastern
    'The Kebab Shop',
    'Pita Jungle',
    'Cedars Restaurant',
    'Cafe Beirut',
    'Falafel King',
    
    // American Casual Dining
    'Applebee\'s',
    'TGI Fridays',
    'Red Robin',
    'The Cheesecake Factory',
    'BJ\'s Restaurant & Brewhouse',
    'Claim Jumper',
    "Chili's",
    "Denny's",
    'IHOP',
    "Coco's Bakery",
    'Cracker Barrel',
    
    // American Fast Casual
    'Panera Bread',
    'Corner Bakery Cafe',
    'Jason\'s Deli',
    'McAlister\'s Deli',
    'Potbelly Sandwich Shop',
    
    // Burgers
    'Five Guys',
    'Shake Shack',
    'In-N-Out Burger',
    'The Habit Burger Grill',
    'Smashburger',
    'Fatburger',
    "Carl's Jr.",
    "Wendy's",
    
    // Seafood
    'Red Lobster',
    'Joe\'s Crab Shack',
    'Bonefish Grill',
    'The Crab House',
    "Captain D's",
    "Long John Silver's",
    'Chart House',
    'McCormick & Schmick\'s',
    
    // BBQ / Smokehouse
    'Famous Dave\'s',
    'Dickey\'s Barbecue Pit',
    'Smokey Bones',
    "Sonny's BBQ",
    'Lucille\'s Smokehouse',
    'Jim \'N Nick\'s Bar-B-Q',
    'Dinosaur Bar-B-Que',
    
    // Brazilian
    'Fogo de Chão',
    'Texas de Brazil',
    'Tucanos Brazilian Grill',
    
    // French
    'La Madeleine',
    'Cafe Paris',
    'Chez Pierre',
    'Le Petit Bistro',
    
    // Spanish
    'Bulla Gastrobar',
    'Barcelona Wine Bar',
    'Ibiza Tapas',
    
    // Greek
    'Zoes Kitchen',
    'Daphne\'s Greek Cafe',
    'The Great Greek',
    
    // Fusion / Contemporary
    'The Melting Pot',
    'Yard House',
    'Buffalo Wild Wings',
    'Seasons 52',
    'California Pizza Kitchen',
    'Earls Kitchen + Bar',
    
    // Breakfast / Brunch
    'First Watch',
    'Snooze',
    'The Original Pancake House',
    'Waffle House',
    
    // Pizza
    'Pizza Hut',
    "Domino's",
    "Papa John's",
    "Round Table Pizza",
    "Blaze Pizza",
    "Pieology",
    
    // Sandwich / Deli
    'Subway',
    'Jersey Mike\'s',
    'Jimmy John\'s',
    'Firehouse Subs',
    
    // Wings
    'Wingstop',
    'Wing Zone',
    'Hooters',
    
    // Chicken
    'Raising Cane\'s',
    'Zaxby\'s',
    'Popeyes',
    'KFC',
    'Chick-fil-A',
  ];
}

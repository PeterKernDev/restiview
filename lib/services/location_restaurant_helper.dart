
// services/location_restaurant_helper.dart
//
// Defensive, timeout-aware helper to locate nearby restaurants and perform location-based utilities.
// Returns [] on any failure rather than throwing.

import 'dart:async';
import 'dart:convert';
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
    'Brasil': 'Brazil',
    'Brazil': 'Brazil',
    // Add more mappings as needed
  };
  
  return countryNameMap[geocodedCountry] ?? geocodedCountry;
}

/// Returns the current city name using reverse geocoding.
/// Tries locality first, then subAdministrativeArea, then administrativeArea.
/// Returns null if location or city cannot be determined.
Future<String?> getCurrentCitySafe({Duration timeout = const Duration(seconds: 10)}) async {
  final pos = await getCurrentLocationSafe(timeout: timeout);
  if (pos == null) {
    return null;
  }
  try {
    final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude)
        .timeout(timeout);
    if (placemarks.isNotEmpty) {
      final Placemark p = placemarks.first;
      final String? city = (p.locality != null && p.locality!.isNotEmpty)
          ? p.locality
          : (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty)
              ? p.subAdministrativeArea
              : p.administrativeArea;
      return (city != null && city.isNotEmpty) ? city : null;
    }
    return null;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
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
  return cleaned.length > 40 ? '${cleaned.substring(0, 40)}â€¦' : cleaned;
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
      return segments.first; // Return "SÃ£o Paulo" from "SÃ£o Paulo - SP"
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
  // - "Street, Number - Neighborhood, City - State, ZIP, Country" (Brazil: index 2 has "SÃ£o Paulo - SP")

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
      // Found "SÃ£o Paulo - SP" pattern
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
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(timeout);
      return pos;
    } on TimeoutException {
      // Fall back to last known position when getCurrentPosition times out
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return last;
        }
      } catch (_) {}
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
  Duration positionTimeout = const Duration(seconds: 5),
  Duration httpTimeout = const Duration(seconds: 6),
  int maxPlacesToProcess = 6,
}) {
  return _internalFind(positionTimeout, httpTimeout, maxPlacesToProcess)
      .timeout(overallTimeout, onTimeout: () => <NearbyRestaurant>[]);
}

Future<List<NearbyRestaurant>> _internalFind(
    Duration positionTimeout, Duration httpTimeout, int maxPlacesToProcess) async {
  if (!SessionCache.allowLocation) {
    appLog('Restaurant search: Location not allowed');
    return [];
  }

  if (googlePlacesApiKey.isEmpty) {
    appLog('Restaurant search: API key is empty');
    return [];
  }

  try {
    final pos = await getCurrentLocationSafe(timeout: positionTimeout);
    if (pos == null) {
      appLog('Restaurant search: Could not get location');
      return [];
    }
    final lat = pos.latitude;
    final lng = pos.longitude;
    final radius = SessionCache.searchRadius;
    
    appLog('Restaurant search: lat=$lat, lng=$lng, radius=$radius meters');

    final nearbyUrl =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radius&type=restaurant&key=$googlePlacesApiKey';

    late http.Response nearbyResponse;
    try {
      nearbyResponse = await http.get(Uri.parse(nearbyUrl)).timeout(httpTimeout);
    } on TimeoutException {
      appLog('Restaurant search: HTTP request timed out');
      return [];
    } catch (e) {
      appLog('Restaurant search: HTTP request failed: $e');
      return [];
    }

    if (nearbyResponse.statusCode != 200) {
      appLog('Restaurant search: HTTP status ${nearbyResponse.statusCode}');
      return [];
    }

    final nearbyData = jsonDecode(nearbyResponse.body) as Map<String, dynamic>? ?? {};
    final status = nearbyData['status'] as String?;
    final errorMessage = nearbyData['error_message'] as String?;
    appLog('Restaurant search: API status=$status');
    if (errorMessage != null) {
      appLog('Restaurant search: Error message: $errorMessage');
    }
    
    final results = nearbyData['results'] as List<dynamic>? ?? [];
    appLog('Restaurant search: Found ${results.length} places');

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
    appLog('Restaurant search: Returning ${restaurants.length} restaurants');
    return restaurants;
  } catch (e, stackTrace) {
    appLog('Restaurant search: Exception: $e, trace: $stackTrace');
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

/// Search for a restaurant by name using the Places Text Search API.
/// Optionally biases results toward the user's current location when
/// [SessionCache.allowLocation] is true.
/// Returns null on any failure or if no match is found — never throws.
Future<NearbyRestaurant?> searchRestaurantByName(
  String name, {
  Duration overallTimeout = const Duration(seconds: 12),
  Duration positionTimeout = const Duration(seconds: 5),
  Duration httpTimeout = const Duration(seconds: 8),
}) async {
  if (name.trim().isEmpty) {
    return null;
  }
  if (googlePlacesApiKey.isEmpty) {
    return null;
  }

  return _internalSearchByName(name.trim(), positionTimeout, httpTimeout)
      .timeout(overallTimeout, onTimeout: () => null);
}

Future<NearbyRestaurant?> _internalSearchByName(
  String name,
  Duration positionTimeout,
  Duration httpTimeout,
) async {
  try {
    // Build the text search URL; include a location bias when GPS is available.
    final StringBuffer urlBuffer = StringBuffer(
      'https://maps.googleapis.com/maps/api/place/textsearch/json'
      '?query=${Uri.encodeComponent(name)}'
      '&type=restaurant'
      '&key=$googlePlacesApiKey',
    );

    if (SessionCache.allowLocation) {
      final Position? pos = await getCurrentLocationSafe(timeout: positionTimeout);
      if (pos != null) {
        urlBuffer.write('&location=${pos.latitude},${pos.longitude}');
        urlBuffer.write('&radius=${SessionCache.searchRadius}');
      }
    }

    late http.Response response;
    try {
      response = await http.get(Uri.parse(urlBuffer.toString())).timeout(httpTimeout);
    } on TimeoutException {
      appLog('searchRestaurantByName: HTTP request timed out');
      return null;
    } catch (e) {
      appLog('searchRestaurantByName: HTTP request failed: $e');
      return null;
    }

    if (response.statusCode != 200) {
      appLog('searchRestaurantByName: HTTP status ${response.statusCode}');
      return null;
    }

    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>? ?? {};
    final String? status = body['status'] as String?;
    appLog('searchRestaurantByName: API status=$status');

    final List<dynamic> results = body['results'] as List<dynamic>? ?? [];
    if (results.isEmpty) {
      return null;
    }

    final dynamic topResult = results.first;
    if (topResult is! Map<String, dynamic>) {
      return null;
    }

    final String? placeId = topResult['place_id'] as String?;
    if (placeId == null || placeId.isEmpty) {
      return null;
    }

    return _fetchPlaceDetails(placeId, httpTimeout);
  } catch (e) {
    appLog('searchRestaurantByName: Exception: $e');
    return null;
  }
}

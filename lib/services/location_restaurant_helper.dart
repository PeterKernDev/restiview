// lib/services/location_restaurant_help.dart
//
// Defensive, timeout-aware helper to locate nearby restaurants.
// Returns [] on any failure rather than throwing.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:diacritic/diacritic.dart';

import '../constants/cuisine_constants.dart';
import '../constants/restiview_constants.dart';
import '../services/session_cache.dart';

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

String extractCityFromAddress(String address) {
  final country = SessionCache.defaultCountry;
  final countryCities = systemCitiesByCountry[country] ?? [];

  final normalizedAddress = normalize(address);
  for (final city in countryCities) {
    if (normalizedAddress.contains(normalize(city))) {
      return city;
    }
  }

  final parts = address.split(',');
  if (parts.length >= 3) {
    final fallback = parts[parts.length - 2].trim();
    final cleaned = fallback.replaceAll(RegExp(r'\d{5}-\d{3}'), '').trim();
    return cleaned.split('-').first.trim();
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
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
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
    return [];
  }

  if (googlePlacesApiKey.isEmpty) {
    return [];
  }

  try {
    final pos = await getCurrentLocationSafe(timeout: positionTimeout);
    if (pos == null) {
      return [];
    }
    final lat = pos.latitude;
    final lng = pos.longitude;
    final radius = SessionCache.searchRadius;

    final nearbyUrl =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radius&type=restaurant&key=$googlePlacesApiKey';

    late http.Response nearbyResponse;
    try {
      nearbyResponse = await http.get(Uri.parse(nearbyUrl)).timeout(httpTimeout);
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }

    if (nearbyResponse.statusCode != 200) {
      return [];
    }

    final nearbyData = jsonDecode(nearbyResponse.body) as Map<String, dynamic>? ?? {};
    final results = nearbyData['results'] as List<dynamic>? ?? [];

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
    return restaurants;
  } catch (_) {
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
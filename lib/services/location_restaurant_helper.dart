// location_restaurant_help.dart
//
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '/constants/cuisine_constants.dart';
import '/constants/restiview_constants.dart';
import '/services/session_cache.dart';
import 'package:diacritic/diacritic.dart';

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
      // debugPrint('Returning matched city name $city`');
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

Future<Position> getCurrentLocation() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services are disabled.');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions are denied.');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('Location permissions are permanently denied.');
  }

  return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
}

Future<List<NearbyRestaurant>> findNearbyRestaurants() async {
  if (!SessionCache.allowLocation) {
    debugPrint('📵 Location search skipped — allowLocation is false.');
    return [];
  }

  try {
    final position = await getCurrentLocation();
    final lat = position.latitude;
    final lng = position.longitude;
    final radius = SessionCache.searchRadius;

    // debugPrint('📍 Current location: lat=$lat, lng=$lng');
    // debugPrint('🌍 Country: ${SessionCache.defaultCountry}, 🔎 Radius: $radius meters');

    final apiKey = googlePlacesApiKey;
    final nearbyUrl =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radius&type=restaurant&key=$apiKey';

    final nearbyResponse = await http.get(Uri.parse(nearbyUrl)).timeout(const Duration(seconds: 5));
    final nearbyData = jsonDecode(nearbyResponse.body);

    // debugPrint('📡 Nearby search response: ${nearbyData.toString()}');

    if (nearbyData['results'] == null || nearbyData['results'].isEmpty) {
      // debugPrint('❌ No nearby restaurants found within $radius meters.');
      return [];
    }

    final List<NearbyRestaurant> restaurants = [];

    for (var place in nearbyData['results']) {
      final placeId = place['place_id'];
      if (placeId == null) continue;

      final detailsUrl =
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=name,formatted_address,formatted_phone_number&key=$apiKey';

      try {
        final detailsResponse = await http.get(Uri.parse(detailsUrl)).timeout(const Duration(seconds: 5));
        final detailsData = jsonDecode(detailsResponse.body);
        final result = detailsData['result'];

        if (result == null) continue;

        final cleanedName = cleanRestaurantName(result['name'] ?? 'Unknown');
        final address = result['formatted_address'] ?? '';
        final city = extractCityFromAddress(address);
        final phone = result['formatted_phone_number'];
        final cuisine = guessCuisineFromName(cleanedName);

        restaurants.add(NearbyRestaurant(
          name: cleanedName,
          address: address,
          city: city,
          phone: phone,
          cuisine: cuisine,
        ));
      } catch (e) {
        // debugPrint('⚠️ Failed to fetch details for place_id=$placeId: $e');
      }
    }

    return restaurants;
  } catch (e) {
    // debugPrint('⚠️ Error during multi-restaurant lookup: $e');
    return [];
  }
}
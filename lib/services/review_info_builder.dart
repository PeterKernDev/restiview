// services/review_info_builder.dart
// Builds and updates aggregated review information for user discovery

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Updates the review_info record in users_by_email mailbox
/// This provides aggregated stats about a user's reviews (countries, cities, counts)
/// for friend discovery purposes.
Future<void> updateReviewInfo(String uid, String normalizedEmail) async {
  try {
    // 1. Read all reviews for the user
    final reviewsRef = FirebaseDatabase.instance.ref('users/$uid/reviews');
    final snapshot = await reviewsRef.get();

    if (!snapshot.exists) {
      // No reviews - write minimal structure
      await _writeReviewInfo(normalizedEmail, 0, {});
      return;
    }

    // 2. Process reviews to build country → city → count structure
    final data = snapshot.value as Map<dynamic, dynamic>;
    final Map<String, Map<String, int>> countryData = {};
    int totalReviews = 0;

    for (final entry in data.entries) {
      // Skip metadata entries like _meta
      if (entry.key.toString().startsWith('_')) {
        continue;
      }

      final review = entry.value as Map<dynamic, dynamic>;
      String country = review['restcountry']?.toString().trim() ?? '';
      String city = review['restcity']?.toString().trim() ?? '';

      // Handle missing values
      if (country.isEmpty) {
        country = 'unknown';
      }
      if (city.isEmpty) {
        city = 'unknown';
      }

      // Initialize country if not exists
      if (!countryData.containsKey(country)) {
        countryData[country] = {};
      }

      // Increment city count
      countryData[country]![city] = (countryData[country]![city] ?? 0) + 1;
      totalReviews++;
    }

    // 3. Write the aggregated data
    await _writeReviewInfo(normalizedEmail, totalReviews, countryData);

    debugPrint(
      'Updated review_info for $normalizedEmail: $totalReviews reviews across ${countryData.length} countries',
    );
  } catch (e) {
    debugPrint('Error updating review_info: $e');
    // Non-fatal - don't throw, just log
  }
}

/// Write the review_info structure to the database
Future<void> _writeReviewInfo(
  String normalizedEmail,
  int totalReviews,
  Map<String, Map<String, int>> countryData,
) async {
  final infoRef = FirebaseDatabase.instance.ref(
    'users_by_email/$normalizedEmail/review_info',
  );

  // Build the payload
  final Map<String, dynamic> payload = {
    'totalReviews': totalReviews,
    'lastUpdated': DateTime.now().toIso8601String(),
  };

  // Add countries with their cities and totals
  if (countryData.isNotEmpty) {
    final Map<String, dynamic> countries = {};

    for (final countryEntry in countryData.entries) {
      final country = countryEntry.key;
      final cities = countryEntry.value;

      // Calculate total for this country
      final countryTotal = cities.values.fold<int>(
        0,
        (sum, count) => sum + count,
      );

      countries[country] = {'total': countryTotal, 'cities': cities};
    }

    payload['countries'] = countries;
  }

  await infoRef.set(payload);
}

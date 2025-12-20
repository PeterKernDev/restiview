// services/review_counter.dart
// Helper to count reviews for an ownerUid matching the provided filters.
// Client-side scan implementation: reads users/<ownerUid>/reviews once and counts matches.
// Supports multiple filters with OR logic - a review matches if it satisfies ANY filter.
// Behavior: never attempt to read another user's reviews from the client. On error or skip, returns -1.

// import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

String _norm(String? s) => s?.toString().trim().toLowerCase() ?? '';

Future<int> countMatchingReviews({
  required String ownerUid,
  required List<Map<String, String?>> filters,
  Set<String>? excludeKeys,
}) async {
  // Resolve owner UID: prefer provided ownerUid, fall back to current user.
  String resolvedOwner = ownerUid;
  if (resolvedOwner.isEmpty) {
    resolvedOwner = FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  if (resolvedOwner.isEmpty) {
    return -1;
  }

  // Do not attempt to read another user's reviews from the client.
  final String me = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (resolvedOwner != me) {
    return -1;
  }

  if (filters.isEmpty) {
    return 0;
  }

  final String path = 'users/$resolvedOwner/reviews';
  try {
    final DataSnapshot snap = await FirebaseDatabase.instance.ref(path).get();
    if (!snap.exists || snap.value == null) {
      return 0;
    }
    if (snap.value is! Map) {
      return 0;
    }

    final Map<dynamic, dynamic> map = Map<dynamic, dynamic>.from(
      snap.value as Map,
    );
    int count = 0;
    for (final MapEntry<dynamic, dynamic> entry in map.entries) {
      final String reviewKey = entry.key?.toString() ?? '';
      final dynamic val = entry.value;

      // Skip if this review key is in the exclusion set
      if (excludeKeys != null &&
          reviewKey.isNotEmpty &&
          excludeKeys.contains(reviewKey)) {
        continue;
      }

      if (val == null || val is! Map) {
        continue;
      }
      final Map<dynamic, dynamic> r = Map<dynamic, dynamic>.from(val);
      final String rCountry = _norm(r['restcountry']);
      final String rCity = _norm(r['restcity']);

      // Check if review matches ANY filter (OR logic)
      bool matchesAnyFilter = false;
      for (final Map<String, String?> filter in filters) {
        final String fCountry = _norm(filter['country']);
        final String fCity = _norm(filter['city']);

        // Country must match if specified in filter
        if (fCountry.isNotEmpty && rCountry != fCountry) {
          continue;
        }
        // City must match if specified in filter
        if (fCity.isNotEmpty && rCity != fCity) {
          continue;
        }
        // If we get here, this filter matches
        matchesAnyFilter = true;
        break;
      }

      if (matchesAnyFilter) {
        count++;
      }
    }
    return count;
  } catch (e) {
    // Permission denied or other database error — return -1 so caller knows it's unknown.
    return -1;
  }
}

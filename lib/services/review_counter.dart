// services/review_counter.dart
// Helper to count reviews for an ownerUid matching the provided filters.
// Client-side scan implementation: reads users/<ownerUid>/reviews once and counts matches.
// Behavior: never attempt to read another user's reviews from the client. On error or skip, returns -1.

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

String _norm(String? s) => s?.toString().trim().toLowerCase() ?? '';

Future<int> countMatchingReviews({
  required String ownerUid,
  String? country,
  String? cuisine,
  String? city,
  Set<String>? excludeKeys,
}) async {
  // Resolve owner UID: prefer provided ownerUid, fall back to current user.
  String resolvedOwner = ownerUid;
  if (resolvedOwner.isEmpty) {
    resolvedOwner = FirebaseAuth.instance.currentUser?.uid ?? '';
    debugPrint('[review_counter] ownerUid empty, falling back to currentUser.uid=$resolvedOwner');
  } else {
    debugPrint('[review_counter] ownerUid provided: $resolvedOwner');
  }

  if (resolvedOwner.isEmpty) {
    debugPrint('[review_counter] no ownerUid available, returning -1');
    return -1;
  }

  // Do not attempt to read another user's reviews from the client.
  final String me = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (resolvedOwner != me) {
    debugPrint('[review_counter] resolvedOwner ($resolvedOwner) != currentUser ($me); skipping remote read and returning -1');
    return -1;
  }

  final String cTry = _norm(country);
  final String cuTry = _norm(cuisine);
  final String ciTry = _norm(city);

  final String path = 'users/$resolvedOwner/reviews';
  try {
    debugPrint('[review_counter] querying $path for country="$cTry" cuisine="$cuTry" city="$ciTry"');
    final DataSnapshot snap = await FirebaseDatabase.instance.ref(path).get();
    if (!snap.exists || snap.value == null) {
      debugPrint('[review_counter] no reviews at $path');
      return 0;
    }
    if (snap.value is! Map) {
      debugPrint('[review_counter] unexpected value type at $path; expected Map');
      return 0;
    }

    final Map<dynamic, dynamic> map = Map<dynamic, dynamic>.from(snap.value as Map);
    int count = 0;
    for (final MapEntry<dynamic, dynamic> entry in map.entries) {
      final String reviewKey = entry.key?.toString() ?? '';
      final dynamic val = entry.value;
      
      // Skip if this review key is in the exclusion set
      if (excludeKeys != null && reviewKey.isNotEmpty && excludeKeys.contains(reviewKey)) {
        continue;
      }
      
      if (val == null || val is! Map) {
        continue;
      }
      final Map<dynamic, dynamic> r = Map<dynamic, dynamic>.from(val);
      final String rCountry = _norm(r['restcountry']);
      final String rCuisine = _norm(r['restcuisine']);
      final String rCity = _norm(r['restcity']);

      if (cTry.isNotEmpty && rCountry != cTry) {
        continue;
      }
      if (cuTry.isNotEmpty && rCuisine != cuTry) {
        continue;
      }
      if (ciTry.isNotEmpty && rCity != ciTry) {
        continue;
      }
      count++;
    }
    debugPrint('[review_counter] matched $count reviews for $path');
    return count;
  } catch (e) {
    // Permission denied or other database error — log and return -1 so caller knows it's unknown.
    debugPrint('[review_counter] error reading $path: $e');
    return -1;
  }
}

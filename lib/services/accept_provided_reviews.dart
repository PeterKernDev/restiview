// lib/services/accept_provided_reviews.dart
// Service to handle accepting provided reviews (statusCode=5) from friends.
// Relocates reviews from users_by_email/<normalized>/requests/<requestId>
// to users/<uid>/reviews_requested/ in a flat structure.
// Preserves owner_email field for filtering by provider.

import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/foundation.dart';
import 'db_utils.dart';

/// Result of accepting provided reviews operation
class AcceptProvidedReviewsResult {
  final bool success;
  final int reviewsAccepted;
  final int duplicatesSkipped;
  final String? errorMessage;

  AcceptProvidedReviewsResult({
    required this.success,
    this.reviewsAccepted = 0,
    this.duplicatesSkipped = 0,
    this.errorMessage,
  });
}

/// Scan for friends with statusCode=5 and fetch their metadata
/// Returns map of providerUid -> {requestId, providerMessage, rqCount}
Future<Map<String, Map<String, dynamic>>> loadProvidedReviewsMetadata({
  required String myUid,
  required String myEmail,
}) async {
  final Map<String, Map<String, dynamic>> result =
      <String, Map<String, dynamic>>{};

  try {
    // Get all friends with statusCode = 5
    final DatabaseReference friendsRef = FirebaseDatabase.instance.ref(
      'users/$myUid/friends',
    );
    final DataSnapshot friendsSnap = await friendsRef.get();

    if (!friendsSnap.exists || friendsSnap.value == null) {
      return result;
    }

    final Map<dynamic, dynamic> friends = Map<dynamic, dynamic>.from(
      friendsSnap.value as Map,
    );
    final String normalizedEmail = normalizeEmailForPath(myEmail);

    // Find friends with statusCode = 5
    for (final MapEntry<dynamic, dynamic> entry in friends.entries) {
      final String providerUid = entry.key.toString();
      final dynamic friendData = entry.value;

      if (friendData is! Map) continue;

      final Map<dynamic, dynamic> friendMap = Map<dynamic, dynamic>.from(
        friendData,
      );
      final int statusCode = (friendMap['statusCode'] is int)
          ? friendMap['statusCode'] as int
          : int.tryParse(friendMap['statusCode']?.toString() ?? '') ?? -1;

      if (statusCode != 5) continue;

      // Find corresponding request in users_by_email
      final DatabaseReference requestsRef = FirebaseDatabase.instance.ref(
        'users_by_email/$normalizedEmail/requests',
      );
      final DataSnapshot requestsSnap = await requestsRef.get();

      if (!requestsSnap.exists || requestsSnap.value == null) continue;

      final Map<dynamic, dynamic> requests = Map<dynamic, dynamic>.from(
        requestsSnap.value as Map,
      );

      // Find request where meta.providerUid matches
      for (final MapEntry<dynamic, dynamic> requestEntry in requests.entries) {
        final String requestId = requestEntry.key.toString();
        final dynamic requestData = requestEntry.value;

        if (requestData is! Map) continue;

        final Map<dynamic, dynamic> requestMap = Map<dynamic, dynamic>.from(
          requestData,
        );
        final dynamic metaData = requestMap['meta'];

        if (metaData is! Map) continue;

        final Map<dynamic, dynamic> meta = Map<dynamic, dynamic>.from(metaData);
        final String metaProviderUid = meta['providerUid']?.toString() ?? '';

        if (metaProviderUid == providerUid) {
          result[providerUid] = <String, dynamic>{
            'requestId': requestId,
            'providerMessage': meta['comment']?.toString() ?? '',
            'rqCount': (meta['count'] is int)
                ? meta['count'] as int
                : int.tryParse(meta['count']?.toString() ?? '') ?? 0,
          };
          break;
        }
      }
    }
  } catch (e) {
    // Return partial results on error
  }

  return result;
}

// Accept provided reviews from a friend (statusCode=5 -> statusCode=1)
// Relocates reviews from users_by_email to users/<uid>/requested_reviews
Future<AcceptProvidedReviewsResult> acceptProvidedReviews({
  required String myUid,
  required String myEmail,
  required String providerUid,
  required String requestId,
}) async {
  try {
    final String normalizedEmail = normalizeEmailForPath(myEmail);
    final String sourceBasePath =
        'users_by_email/$normalizedEmail/requests/$requestId';

    // 1. Read all reviews from source
    final DatabaseReference reviewsRef = FirebaseDatabase.instance.ref(
      '$sourceBasePath/reviews_requested',
    );
    final DataSnapshot reviewsSnap = await reviewsRef.get();

    if (!reviewsSnap.exists || reviewsSnap.value == null) {
      return AcceptProvidedReviewsResult(
        success: false,
        errorMessage: 'No reviews found to accept',
      );
    }

    final Map<dynamic, dynamic> reviews = Map<dynamic, dynamic>.from(
      reviewsSnap.value as Map,
    );

    // 2. Get provider's email to use as owner_email
    String providerEmail = '';
    try {
      final DataSnapshot providerEmailSnap = await FirebaseDatabase.instance
          .ref('public_profiles/$providerUid/email')
          .get();
      if (providerEmailSnap.exists && providerEmailSnap.value is String) {
        providerEmail = (providerEmailSnap.value as String).trim();
      }
    } catch (_) {}

    // 3. Prepare destination writes (flat structure under reviews_requested)
    final String destBasePath = 'users/$myUid/reviews_requested';

    final Map<String, dynamic> updates = <String, dynamic>{};
    int reviewsAccepted = 0;
    int duplicatesSkipped = 0;

    for (final MapEntry<dynamic, dynamic> entry in reviews.entries) {
      final String reviewKey = entry.key.toString();
      final dynamic reviewData = entry.value;

      if (reviewData is! Map) {
        continue;
      }

      // Check for existing review with same key (avoid duplicates)
      final DatabaseReference existingRef = FirebaseDatabase.instance.ref(
        '$destBasePath/$reviewKey',
      );
      final DataSnapshot existingSnap = await existingRef.get();

      if (!existingSnap.exists) {
        // Ensure owner_email field is present for filtering
        final Map<String, dynamic> reviewMap = Map<String, dynamic>.from(
          reviewData,
        );
        if (providerEmail.isNotEmpty && !reviewMap.containsKey('owner_email')) {
          reviewMap['owner_email'] = providerEmail;
        }
        // Remove financial information: set cost to empty/blank
        reviewMap['cost'] = '';
        // Add to updates map
        updates['$destBasePath/$reviewKey'] = reviewMap;
        reviewsAccepted++;
      } else {
        // Review already exists - count as duplicate
        duplicatesSkipped++;
      }
    }

    // 4. Write reviews individually (avoid permission issues with atomic update)
    for (final MapEntry<String, dynamic> entry in updates.entries) {
      final String path = entry.key;
      final dynamic value = entry.value;
      await FirebaseDatabase.instance.ref(path).set(value);
    }

    // 5. Update friend record back to FRIEND status (statusCode=1)
    final String nowIso = DateTime.now().toUtc().toIso8601String();
    final Map<String, dynamic> friendUpdates = <String, dynamic>{
      'users/$myUid/friends/$providerUid/statusCode': 1,
      'users/$myUid/friends/$providerUid/updatedAt': nowIso,
      'users/$myUid/friends/$providerUid/providedRequestId': null,
      'users/$myUid/friends/$providerUid/providedRqCount': null,
      'users/$myUid/friends/$providerUid/comment': null,
      'users/$myUid/friends/$providerUid/providedAt': null,
    };
    await FirebaseDatabase.instance.ref().update(friendUpdates);

    // 6. Cleanup - delete source request record from mailbox
    await FirebaseDatabase.instance.ref(sourceBasePath).remove();

    // Note: The original request from provider's mailbox was already deleted
    // when the provider accepted the request and provided the reviews

    return AcceptProvidedReviewsResult(
      success: true,
      reviewsAccepted: reviewsAccepted,
      duplicatesSkipped: duplicatesSkipped,
    );
  } catch (e) {
    return AcceptProvidedReviewsResult(
      success: false,
      errorMessage: e.toString(),
    );
  }
}

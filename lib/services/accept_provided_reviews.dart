// lib/services/accept_provided_reviews.dart
// Service to handle accepting provided reviews (statusCode=5) from friends.
// Relocates reviews from users_by_email/<normalized>/requested_reviews/<requestId>
// to users/<uid>/requested_reviews/ in a flat structure.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'db_utils.dart';

/// Result of accepting provided reviews operation
class AcceptProvidedReviewsResult {
  final bool success;
  final int reviewsAccepted;
  final String? errorMessage;

  AcceptProvidedReviewsResult({
    required this.success,
    this.reviewsAccepted = 0,
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
        'users_by_email/$normalizedEmail/requested_reviews',
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
            'providerMessage': meta['provider-message']?.toString() ?? '',
            'rqCount': (meta['rqCount'] is int)
                ? meta['rqCount'] as int
                : int.tryParse(meta['rqCount']?.toString() ?? '') ?? 0,
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
        'users_by_email/$normalizedEmail/requested_reviews/$requestId';
    
    debugPrint('[acceptProvidedReviews] Starting for myUid=$myUid, providerUid=$providerUid, requestId=$requestId');
    debugPrint('[acceptProvidedReviews] Source path: $sourceBasePath');

    // 1. Read all reviews from source
    final DatabaseReference reviewsRef = FirebaseDatabase.instance.ref(
      '$sourceBasePath/reviews',
    );
    final DataSnapshot reviewsSnap = await reviewsRef.get();

    if (!reviewsSnap.exists || reviewsSnap.value == null) {
      debugPrint('[acceptProvidedReviews] No reviews found at source path');
      return AcceptProvidedReviewsResult(
        success: false,
        errorMessage: 'No reviews found to accept',
      );
    }

    final Map<dynamic, dynamic> reviews = Map<dynamic, dynamic>.from(
      reviewsSnap.value as Map,
    );
    
    debugPrint('[acceptProvidedReviews] Found ${reviews.length} reviews at source');

    // 2. Prepare destination writes (flat structure)
    final String destBasePath = 'users/$myUid/requested_reviews';
    debugPrint('[acceptProvidedReviews] Destination path: $destBasePath');
    
    final Map<String, dynamic> updates = <String, dynamic>{};
    int reviewsAccepted = 0;

    for (final MapEntry<dynamic, dynamic> entry in reviews.entries) {
      final String reviewKey = entry.key.toString();
      final dynamic reviewData = entry.value;

      if (reviewData is! Map) {
        debugPrint('[acceptProvidedReviews] Skipping non-map review: $reviewKey');
        continue;
      }

      // Check for existing review with same key (avoid duplicates)
      final DatabaseReference existingRef = FirebaseDatabase.instance.ref(
        '$destBasePath/$reviewKey',
      );
      final DataSnapshot existingSnap = await existingRef.get();

      if (!existingSnap.exists) {
        // Add to updates map
        updates['$destBasePath/$reviewKey'] = reviewData;
        reviewsAccepted++;
        debugPrint('[acceptProvidedReviews] Queued review for move: $reviewKey');
      } else {
        debugPrint('[acceptProvidedReviews] Skipping duplicate review: $reviewKey');
      }
    }

    debugPrint('[acceptProvidedReviews] Prepared $reviewsAccepted reviews for relocation');

    // 3. Write reviews individually (avoid permission issues with atomic update)
    debugPrint('[acceptProvidedReviews] Writing reviews to destination');
    for (final MapEntry<String, dynamic> entry in updates.entries) {
      final String path = entry.key;
      final dynamic value = entry.value;
      await FirebaseDatabase.instance.ref(path).set(value);
      debugPrint('[acceptProvidedReviews] Wrote: $path');
    }
    debugPrint('[acceptProvidedReviews] All reviews written successfully');

    // 4. Update friend record back to FRIEND status
    final String nowIso = DateTime.now().toUtc().toIso8601String();
    await FirebaseDatabase.instance.ref('users/$myUid/friends/$providerUid/statusCode').set(1);
    await FirebaseDatabase.instance.ref('users/$myUid/friends/$providerUid/updatedAt').set(nowIso);
    debugPrint('[acceptProvidedReviews] Friend stub updated to statusCode=1');

    // 6. Cleanup - delete source requested_reviews
    debugPrint('[acceptProvidedReviews] Deleting source at: $sourceBasePath');
    await FirebaseDatabase.instance.ref(sourceBasePath).remove();
    debugPrint('[acceptProvidedReviews] Source cleanup complete');

    // Note: The original request from provider's mailbox was already deleted
    // when the provider accepted the request and provided the reviews

    return AcceptProvidedReviewsResult(
      success: true,
      reviewsAccepted: reviewsAccepted,
    );
  } catch (e) {
    return AcceptProvidedReviewsResult(
      success: false,
      errorMessage: e.toString(),
    );
  }
}

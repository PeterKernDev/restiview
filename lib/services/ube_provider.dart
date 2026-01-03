// lib/services/ube_provider.dart
// Helper service to build and perform provider-side "heavy copy" (UBE).
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
// import 'package:flutter/rendering.dart';
import 'db_utils.dart';

/// Maximum number of reviews to include in a single provide operation (strictly enforced).
const int kProvideMaxReviews = 50;

/// Build a multi-path update map for providing up to 50 [reviews]
/// from [providerUid] to [requesterUid]. The returned Map is suitable
/// to pass to `rootRef.update(...)` to perform an atomic update.
///
/// If more than 50 reviews are provided, only the first 50 are used.
/// Reviews must be a list of Maps; each item may include a 'key' entry
/// that identifies the source review's key. If no 'key' is provided a
/// destination push-key will be generated.
Future<Map<String, dynamic>> buildProvideUpdate({
  required DatabaseReference rootRef,
  required String providerUid,
  required String requesterUid,
  required List<Map<dynamic, dynamic>> reviews,
}) async {
  if (reviews.isEmpty) {
    return <String, dynamic>{};
  }

  // Enforce strict limit of 50 reviews
  final List<Map<dynamic, dynamic>> reviewsToProvide =
      reviews.length > kProvideMaxReviews
      ? reviews.sublist(0, kProvideMaxReviews)
      : reviews;

  final String nowIso = DateTime.now().toUtc().toIso8601String();
  // Determine requester's normalized email so we can write under users_by_email/<norm>/requests
  String requesterEmail = '';
  try {
    final DataSnapshot pubEmailSnap = await rootRef
        .child('public_profiles/$requesterUid/email')
        .get();
    if (pubEmailSnap.exists &&
        pubEmailSnap.value is String &&
        (pubEmailSnap.value as String).trim().isNotEmpty) {
      requesterEmail = (pubEmailSnap.value as String).trim();
    }
  } catch (_) {}
  if (requesterEmail.isEmpty) {
    try {
      final DataSnapshot userEmailSnap = await rootRef
          .child('users/$requesterUid/email')
          .get();
      if (userEmailSnap.exists &&
          userEmailSnap.value is String &&
          (userEmailSnap.value as String).trim().isNotEmpty) {
        requesterEmail = (userEmailSnap.value as String).trim();
      }
    } catch (_) {}
  }

  String norm = '';
  if (requesterEmail.isNotEmpty) {
    norm = normalizeEmailForPath(requesterEmail);
  } else {
    // Fallback: use safeKey of the uid when email not available (not ideal but prevents crash)
    norm = safePushKey(rootRef.child('users_by_email')).toString();
  }

  // Use a client request ID based on timestamp for the requests collection
  final String clientRequestId = DateTime.now().millisecondsSinceEpoch
      .toString();
  final String requestId = clientRequestId;

  final Map<String, dynamic> updates = <String, dynamic>{};

  // Write reviews to mailbox - PK4 will auto-process them to reviews_requested
  final String requestBasePath = 'users_by_email/$norm/requests/$requestId';
  final String destBasePath = '$requestBasePath/reviews_requested';

  // Get provider's email to set as owner_email for filtering
  String providerEmail = '';
  try {
    final DataSnapshot providerEmailSnap = await rootRef
        .child('public_profiles/$providerUid/email')
        .get();
    if (providerEmailSnap.exists && providerEmailSnap.value is String) {
      providerEmail = (providerEmailSnap.value as String).trim();
    }
  } catch (_) {}

  debugPrint(
    'DEBUG buildProvideUpdate: providerUid=$providerUid, providerEmail=$providerEmail, requesterUid=$requesterUid',
  );

  // Copy each review (strip photos) to mailbox
  for (final Map<dynamic, dynamic> r in reviewsToProvide) {
    String destKey = '';
    try {
      if (r.containsKey('key') &&
          r['key'] != null &&
          r['key'].toString().isNotEmpty) {
        destKey = r['key'].toString();
      }
    } catch (_) {
      destKey = '';
    }
    if (destKey.isEmpty) {
      destKey = safePushKey(
        rootRef.child('users').child(requesterUid).child('reviews_requested'),
      );
    }

    final Map<String, dynamic> clean = stripPhotosFromReview(
      Map<String, dynamic>.from(r),
    );
    clean.remove('key');
    // Ensure owner_email field is present for filtering
    if (providerEmail.isNotEmpty && !clean.containsKey('owner_email')) {
      clean['owner_email'] = providerEmail;
    }
    debugPrint(
      'DEBUG: Review $destKey has owner_email: ${clean.containsKey('owner_email')}, value: ${clean['owner_email']}',
    );
    // Remove financial information: set cost to empty/blank
    clean['cost'] = '';

    updates['$destBasePath/$destKey'] = clean;
  }

  // Create mailbox notification (statusCode=5) - reviews will be auto-processed
  updates['$requestBasePath/fromUid'] = providerUid;
  updates['$requestBasePath/statusCode'] = 5; // RV-PROVIDED (auto-process)
  updates['$requestBasePath/createdAt'] = nowIso;
  updates['$requestBasePath/clientRequestId'] = clientRequestId;
  updates['$requestBasePath/type'] = 'review_provided';

  // Store metadata in mailbox notification
  updates['$requestBasePath/meta'] = <String, dynamic>{
    'rqCount': reviewsToProvide.length,
    'providerUid': providerUid,
    'deliveredAt': nowIso,
  };

  // Update provider's friend stub back to accepted (statusCode=1)
  // Provider goes back to FRIEND status immediately after delivering reviews
  final String providerFriendPathBase =
      'users/$providerUid/friends/$requesterUid';
  updates['$providerFriendPathBase/statusCode'] = 1;
  updates['$providerFriendPathBase/updatedAt'] = nowIso;

  return updates;
}

/// Execute a prepared multi-path update map against [rootRef].
/// Throws any exception returned by the underlying update call.
Future<void> performProvide({
  required DatabaseReference rootRef,
  required Map<String, dynamic> updates,
}) async {
  if (updates.isEmpty) {
    return;
  }
  await rootRef.update(updates);
}

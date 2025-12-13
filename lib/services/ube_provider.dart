// lib/services/ube_provider.dart
// Helper service to build and perform provider-side "heavy copy" (UBE).
import 'package:firebase_database/firebase_database.dart';
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
  required String providerCommentShort,
}) async {
  if (reviews.isEmpty) {
    return <String, dynamic>{};
  }

  // Enforce strict limit of 50 reviews
  final List<Map<dynamic, dynamic>> reviewsToProvide = reviews.length > kProvideMaxReviews
      ? reviews.sublist(0, kProvideMaxReviews)
      : reviews;

  final String nowIso = DateTime.now().toUtc().toIso8601String();
  // Determine requester's normalized email so we can write under users_by_email/<norm>/requested_reviews
  String requesterEmail = '';
  try {
    final DataSnapshot pubEmailSnap = await rootRef.child('public_profiles/$requesterUid/email').get();
    if (pubEmailSnap.exists && pubEmailSnap.value is String && (pubEmailSnap.value as String).trim().isNotEmpty) {
      requesterEmail = (pubEmailSnap.value as String).trim();
    }
  } catch (_) {}
  if (requesterEmail.isEmpty) {
    try {
      final DataSnapshot userEmailSnap = await rootRef.child('users/$requesterUid/email').get();
      if (userEmailSnap.exists && userEmailSnap.value is String && (userEmailSnap.value as String).trim().isNotEmpty) {
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

  // Use a push key under the users_by_email/<norm>/requested_reviews
  final String requestId = safePushKey(rootRef.child('users_by_email').child(norm).child('requested_reviews'));

  final String metaPath = 'users_by_email/$norm/requested_reviews/$requestId/meta';
  final String reviewsBase = 'users_by_email/$norm/requested_reviews/$requestId/reviews';

  final Map<String, dynamic> updates = <String, dynamic>{};

  // Meta: minimal fields as requested
  updates[metaPath] = <String, dynamic>{
    'provider-message': (providerCommentShort.isNotEmpty) ? providerCommentShort : '',
    'rqCount': reviewsToProvide.length,
    'providerUid': providerUid,
    'providedAt': nowIso,
  };

  // Copy each review (strip photos) into the requested_reviews collection
  for (final Map<dynamic, dynamic> r in reviewsToProvide) {
      String destKey = '';
      try {
        if (r.containsKey('key') && r['key'] != null && r['key'].toString().isNotEmpty) {
          destKey = r['key'].toString();
        }
      } catch (_) {
        destKey = '';
      }
      if (destKey.isEmpty) {
        destKey = safePushKey(rootRef.child('users_by_email').child(norm).child('requested_reviews').child(requestId).child('reviews'));
      }

  final Map<String, dynamic> clean = stripPhotosFromReview(Map<String, dynamic>.from(r));
  clean.remove('key');
  // Add provenance fields so security rules can validate the provider identity and time
  clean['providedByUid'] = providerUid;
  clean['providedAt'] = nowIso;

  updates['$reviewsBase/$destKey'] = clean;
  }

  // Friend stub updates: set requester-side friend stub to RV-PROVIDED (5)
  // and set provider-side friend stub to accepted (1)
  final String requesterFriendPathBase = 'users/$requesterUid/friends/$providerUid';
  updates['$requesterFriendPathBase/statusCode'] = 5; // RV-PROVIDED
  updates['$requesterFriendPathBase/updatedAt'] = nowIso;

  final String providerFriendPathBase = 'users/$providerUid/friends/$requesterUid';
  updates['$providerFriendPathBase/statusCode'] = 1; // FRIEND / accepted
  updates['$providerFriendPathBase/updatedAt'] = nowIso;

  return updates;
}

/// Execute a prepared multi-path update map against [rootRef].
/// Throws any exception returned by the underlying update call.
Future<void> performProvide({required DatabaseReference rootRef, required Map<String, dynamic> updates}) async {
  if (updates.isEmpty) {
    return;
  }
  await rootRef.update(updates);
}

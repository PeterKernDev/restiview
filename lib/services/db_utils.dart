// lib/services/db_utils.dart
//
// Database helper utilities for RTDB path construction, safe keys, and
// multi-path update map builders used by friends_screen.dart.
// This version re-enables audit writes (previously disabled for testing)
// and keeps mailbox removal helper behavior as before.

import 'package:firebase_database/firebase_database.dart';

String safeKey(String s) {
  return s.replaceAll(RegExp(r'[.$#[\]/]'), '_');
}

String normalizeEmailForPath(String email) {
  if (email.isEmpty) {
    return '';
  }
  return safeKey(email.trim().toLowerCase());
}

/// Public safe push key helper. Returns a unique key for the given ref or a
/// timestamp-based fallback when the push key is null.
String safePushKey(DatabaseReference ref) => ref.push().key ?? DateTime.now().millisecondsSinceEpoch.toString();

/// Return a shallow copy of the review map with known photo/photo-path keys
/// removed so that objects copied into other users' trees do not include
/// local file paths or large binary blobs. This intentionally strips keys like
/// `photos`, `photoPath0..N`, `photoPaths` and any key that begins with
/// `photo`. Also recursively strips photo paths from nested structures like
/// detail items (details_cocktails, details_starters, etc.).
Map<String, dynamic> stripPhotosFromReview(Map<dynamic, dynamic> review) {
  final Map<String, dynamic> out = <String, dynamic>{};
  try {
    review.forEach((dynamic k, dynamic v) {
      final String key = k?.toString() ?? '';
      if (key.isEmpty) {
        return;
      }
      final String lower = key.toLowerCase();
      if (lower == 'photos' || lower == 'photopaths' || lower == 'photopath' || lower.startsWith('photopath') || lower.startsWith('photo')) {
        // skip photo-related keys at top level
        return;
      }
      
      // Recursively process nested structures (e.g., details_cocktails, details_starters)
      if (v is List) {
        final List<dynamic> cleanedList = [];
        for (final item in v) {
          if (item is Map) {
            // Strip photoPath from each detail item
            final Map<String, dynamic> cleanedItem = {};
            item.forEach((dynamic itemKey, dynamic itemValue) {
              final String itemKeyStr = itemKey?.toString() ?? '';
              final String itemKeyLower = itemKeyStr.toLowerCase();
              // Skip any photo-related keys in detail items
              if (itemKeyLower != 'photopath' && !itemKeyLower.startsWith('photo')) {
                cleanedItem[itemKeyStr] = itemValue;
              }
            });
            if (cleanedItem.isNotEmpty) {
              cleanedList.add(cleanedItem);
            }
          } else {
            cleanedList.add(item);
          }
        }
        out[key] = cleanedList;
      } else {
        out[key] = v;
      }
    });
  } catch (_) {
    // on unexpected structure, return an empty map rather than crash
    return <String, dynamic>{};
  }
  return out;
}

// Helper that attempts to remove a mailbox request only when actor (auth.uid) is allowed to.
// If deletion is not allowed, only set processedBy/processedAt when rules permit:
//   - actor is mailbox owner (root.users_by_email/$norm/uid == actorUid), OR
//   - request id looks like an autogen id (endsWith '_autogen')
Future<void> _addMailboxRemovalOrMark(Map<String, dynamic> updates, {
  required DatabaseReference rootRef,
  required String actorUid,
  String? mailboxReqId,
  String? mailboxNormalized,
}) async {
  if (mailboxReqId == null || mailboxReqId.isEmpty) {
    return;
  }

  final bool isAutogen = mailboxReqId.endsWith('_autogen');

  if (mailboxNormalized != null && mailboxNormalized.isNotEmpty) {
    final String safeNorm = safeKey(mailboxNormalized);
    final String safeReq = safeKey(mailboxReqId);
    try {
      final DataSnapshot mapping = await rootRef.child('users_by_email/$safeNorm/uid').get();
      final String ownerUid = (mapping.exists && mapping.value != null) ? mapping.value.toString() : '';

      if (ownerUid.isNotEmpty && ownerUid == actorUid) {
        // Actor owns the mailbox mapping; safe to delete the request entry.
        updates['users_by_email/$safeNorm/requests/$safeReq'] = null;
        return;
      }

      if (isAutogen) {
        updates['users_by_email/$safeNorm/requests/$safeReq/processedBy'] = actorUid;
        updates['users_by_email/$safeNorm/requests/$safeReq/processedAt'] = DateTime.now().toUtc().toIso8601String();
        return;
      }

      return;
    } catch (e) {
      if (isAutogen) {
        final String safeReq = safeKey(mailboxReqId);
        updates['users_by_email/$safeNorm/requests/$safeReq/processedBy'] = actorUid;
        updates['users_by_email/$safeNorm/requests/$safeReq/processedAt'] = DateTime.now().toUtc().toIso8601String();
        return;
      }
      final String myNorm = normalizeEmailForPath(actorUid);
      if (myNorm.isNotEmpty) {
        final String safeMyNorm = safeKey(myNorm);
        final String safeReq = safeKey(mailboxReqId);
        updates['users_by_email/$safeMyNorm/requests/$safeReq/processedBy'] = actorUid;
        updates['users_by_email/$safeMyNorm/requests/$safeReq/processedAt'] = DateTime.now().toUtc().toIso8601String();
      }
      return;
    }
  } else {
    if (isAutogen) {
      return;
    }
    final String myNorm = normalizeEmailForPath(actorUid);
    if (myNorm.isNotEmpty) {
      final String safeMyNorm = safeKey(myNorm);
      final String safeReq = safeKey(mailboxReqId);
      updates['users_by_email/$safeMyNorm/requests/$safeReq/processedBy'] = actorUid;
      updates['users_by_email/$safeMyNorm/requests/$safeReq/processedAt'] = DateTime.now().toUtc().toIso8601String();
    }
    return;
  }
}

// Existing helper: friend stub updates (unchanged)
Map<String, dynamic> makeFriendStubUpdates({
  required String actorUid,
  required String friendUid,
  required String actorDisplayName,
  required String actorEmail,
  required String friendDisplayName,
  required String friendEmail,
  required int statusCode,
  bool? acceptedFlag,
}) {
  final String sActor = safeKey(actorUid);
  final String sFriend = safeKey(friendUid);
  final Map<String, dynamic> updates = <String, dynamic>{};
  final String now = DateTime.now().toUtc().toIso8601String();

  // Only update the actor's own friend stub, not the friend's stub
  updates['users/$sActor/friends/$sFriend/statusCode'] = statusCode;
  updates['users/$sActor/friends/$sFriend/username'] = friendDisplayName;
  updates['users/$sActor/friends/$sFriend/email'] = friendEmail;
  if (acceptedFlag != null) {
    updates['users/$sActor/friends/$sFriend/accepted'] = acceptedFlag;
  }
  updates['users/$sActor/friends/$sFriend/updatedAt'] = now;

  return updates;
}

// Accept builder
Future<Map<String, dynamic>> buildAcceptUpdateMap({
  required DatabaseReference rootRef,
  required String actorUid,
  required String friendUid,
  required String actorEmail,
  String? mailboxReqId,
  String? mailboxNormalized,
  required String actorDisplayName,
  required String actorPublicEmail,
  required String friendDisplayName,
  required String friendPublicEmail,
}) async {
  final Map<String, dynamic> updates = <String, dynamic>{};

  await _addMailboxRemovalOrMark(
    updates,
    rootRef: rootRef,
    actorUid: actorUid,
    mailboxReqId: mailboxReqId,
    mailboxNormalized: mailboxNormalized,
  );

  // Update only the actor's own friend stub
  updates.addAll(makeFriendStubUpdates(
    actorUid: actorUid,
    friendUid: friendUid,
    actorDisplayName: actorDisplayName,
    actorEmail: actorPublicEmail,
    friendDisplayName: friendDisplayName,
    friendEmail: friendPublicEmail,
    statusCode: 1,
    acceptedFlag: true,
  ));
  
  // Clear comment field when transitioning to accepted status
  updates['users/$actorUid/friends/$friendUid/comment'] = null;

  // Create a mailbox entry for the friend to notify them of acceptance
  // The friend will update their own stub when they sign in
  final String friendEmailNormalized = normalizeEmailForPath(friendPublicEmail.toLowerCase());
  final String acceptClientRequestId = DateTime.now().millisecondsSinceEpoch.toString();
  final String friendMailboxPath = 'users_by_email/$friendEmailNormalized/requests/$acceptClientRequestId';
  
  updates[friendMailboxPath] = <String, dynamic>{
    'statusCode': 1, // 1 = accepted
    'fromUid': actorUid,
    'fromEmail': actorPublicEmail,
    'fromDisplayName': actorDisplayName,
    'clientRequestId': acceptClientRequestId,
    'createdAt': DateTime.now().toIso8601String(),
    'type': 'friend_accept',
  };

  return updates;
}

// Reject builder
Future<Map<String, dynamic>> buildRejectUpdateMap({
  required DatabaseReference rootRef,
  required String actorUid,
  required String friendUid,
  required String actorEmail,
  String? mailboxReqId,
  String? mailboxNormalized,
  required String friendDisplayName,
  required String friendPublicEmail,
  required String actorDisplayName,
  required String actorPublicEmail,
}) async {
  final Map<String, dynamic> updates = <String, dynamic>{};

  await _addMailboxRemovalOrMark(
    updates,
    rootRef: rootRef,
    actorUid: actorUid,
    mailboxReqId: mailboxReqId,
    mailboxNormalized: mailboxNormalized,
  );

  // Update only the actor's (PK1's) own friend stub to statusCode=9 (unknown/not interested)
  updates.addAll(makeFriendStubUpdates(
    actorUid: actorUid,
    friendUid: friendUid,
    actorDisplayName: '',
    actorEmail: '',
    friendDisplayName: friendDisplayName,
    friendEmail: friendPublicEmail,
    statusCode: 9,
    acceptedFlag: false,
  ));

  // Create a mailbox entry for the friend to notify them of rejection
  // The friend will update their own stub when they sign in
  final String friendEmailNormalized = normalizeEmailForPath(friendPublicEmail.toLowerCase());
  final String declineClientRequestId = DateTime.now().millisecondsSinceEpoch.toString();
  final String friendMailboxPath = 'users_by_email/$friendEmailNormalized/requests/$declineClientRequestId';
  
  updates[friendMailboxPath] = <String, dynamic>{
    'statusCode': 8, // 8 = declined
    'fromUid': actorUid,
    'fromEmail': actorPublicEmail,
    'fromDisplayName': actorDisplayName,
    'clientRequestId': declineClientRequestId,
    'createdAt': DateTime.now().toIso8601String(),
    'type': 'friend_decline',
  };

  return updates;
}

// Mark pending delete builder (uses mailbox helper above)
Future<Map<String, dynamic>> buildMarkPendingDeleteUpdateMap({
  required DatabaseReference rootRef,
  required String actorUid,
  required String friendUid,
  String? mailboxReqId,
  String? mailboxNormalized,
}) async {
  final Map<String, dynamic> updates = <String, dynamic>{};
  final String sMe = safeKey(actorUid);
  final String sFriend = safeKey(friendUid);
  final String now = DateTime.now().toUtc().toIso8601String();

  updates['users/$sMe/friends/$sFriend'] = null;

  updates['users/$sFriend/friends/$sMe/statusCode'] = 99;
  updates['users/$sFriend/friends/$sMe/pendingDeleteBy'] = actorUid;
  updates['users/$sFriend/friends/$sMe/pendingDeleteAt'] = now;
  updates['users/$sFriend/friends/$sMe/updatedAt'] = now;

  await _addMailboxRemovalOrMark(
    updates,
    rootRef: rootRef,
    actorUid: actorUid,
    mailboxReqId: mailboxReqId,
    mailboxNormalized: mailboxNormalized,
  );

  return updates;
}

// Finalize pending delete builder
Future<Map<String, dynamic>> buildFinalizePendingDeleteUpdateMap({
  required DatabaseReference rootRef,
  required String actorUid,
  required String friendUid,
  String? mailboxReqId,
  String? mailboxNormalized,
}) async {
  final Map<String, dynamic> updates = <String, dynamic>{};
  final String sActor = safeKey(actorUid);
  final String sFriend = safeKey(friendUid);

  updates['users/$sActor/friends/$sFriend'] = null;
  updates['users/$sFriend/friends/$sActor'] = null;

  await _addMailboxRemovalOrMark(
    updates,
    rootRef: rootRef,
    actorUid: actorUid,
    mailboxReqId: mailboxReqId,
    mailboxNormalized: mailboxNormalized,
  );

  updates['users/$sActor/friends/$sFriend/review'] = null;
  updates['users/$sFriend/friends/$sActor/review'] = null;
  updates['users/$sActor/friends/$sFriend/clientRequestId'] = null;
  updates['users/$sFriend/friends/$sActor/clientRequestId'] = null;
  updates['users/$sActor/friends/$sFriend/mailboxReqId'] = null;
  updates['users/$sFriend/friends/$sActor/mailboxReqId'] = null;
  updates['users/$sActor/friends/$sFriend/mailboxNormalized'] = null;
  updates['users/$sFriend/friends/$sActor/mailboxNormalized'] = null;

  return updates;
}

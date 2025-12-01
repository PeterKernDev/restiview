// friends_delete.dart
// Helper functions to perform a single-update finalize+delete (Option B).
// Drop this file into your project and call performFinalizeAndDelete(...) from your UI or service layer.
//
// Requires: firebase_database package.

import 'package:firebase_database/firebase_database.dart';

class FriendsDelete {
  final DatabaseReference rootRef = FirebaseDatabase.instance.ref();

  // Perform one atomic update that deletes both friend parents and writes a finalize audit.
  // meUid: actor performing the finalize/delete
  // friendUid: target friend
  // Returns true on success, throws on failure.
  Future<bool> performFinalizeAndDelete({
    required String meUid,
    required String friendUid,
    int retryAttempts = 3,
  }) async {
    final String pairKey = '${meUid}_$friendUid';
    final String pushId = rootRef.child('friend_finalize_pending_delete_audit').push().key!;
    final String nowIso = DateTime.now().toUtc().toIso8601String();

    // Build update map: parent deletions only, plus audit entry (audit is not a descendant of deleted parents)
    final Map<String, dynamic> updates = {
      'users/$meUid/friends/$friendUid': null,
      'users/$friendUid/friends/$meUid': null,
      'friend_finalize_pending_delete_audit/$pairKey/$pushId': {
        'action': 'finalize_pending_delete',
        'actor': meUid,
        'target': friendUid,
        'at': nowIso,
      },
    };

    // Try with simple retry/backoff for transient failures (not for validation/permission errors)
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        await rootRef.update(updates);
        return true;
      } catch (e) {
        // If permission denied or validation error, rethrow immediately
        final String msg = e.toString();
        if (msg.contains('permission-denied') || msg.contains('Permission denied') || msg.contains('Validation') || msg.contains('ancestor')) {
          rethrow;
        }
        if (attempt >= retryAttempts) rethrow;
        // simple exponential backoff
        await Future.delayed(Duration(milliseconds: 200 * (1 << (attempt - 1))));
      }
    }
  }

  // Safe local reconciliation helper (call this after a successful finalize/delete)
  // Pass in your local friends map and the friendUid to remove; this avoids null-check crashes.
  void reconcileLocalAfterDelete(Map<String, dynamic> localFriendsMap, String friendUid) {
    // Remove any local entry for the friend; removal is idempotent
    localFriendsMap.remove(friendUid);
  }
}

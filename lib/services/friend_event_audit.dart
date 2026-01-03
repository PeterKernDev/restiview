// lib/services/friend_event_audit.dart
// Audit logging for friend and review request lifecycle events.
// All friend-related actions write to audit_info/request_events/ for tracking.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Write a friend/review event to the audit log.
/// 
/// Event types:
/// - 'friend_request_accepted': Friend request accepted
/// - 'friend_request_declined': Friend request declined
/// - 'friend_request_auto_declined': Friend request auto-declined (statusCode=9 blocking)
/// - 'review_request_accepted': Review request accepted
/// - 'review_request_declined': Review request declined
/// - 'established_friend_declined': Established friend (statusCode=1) declined
/// - 'friend_deleted_by_instigator': Friend stub deleted by instigator (statusCode=9)
/// - 'friend_deleted_by_recipient': Friend stub deleted by recipient (statusCode=8)
///
/// Parameters:
/// - [eventType]: One of the 8 event types listed above
/// - [actorUid]: UID of the user performing the action
/// - [targetUid]: UID of the user affected by the action
/// - [metadata]: Optional map of additional event data (e.g., decline message, review count)
Future<void> writeFriendEvent({
  required String eventType,
  required String actorUid,
  required String targetUid,
  Map<String, dynamic>? metadata,
}) async {
  try {
    final DatabaseReference auditRef =
        FirebaseDatabase.instance.ref('audit_info/request_events');
    final String pushKey = auditRef.push().key ?? '';
    
    if (pushKey.isEmpty) {
      debugPrint('ERROR: Failed to generate audit push key');
      return;
    }

    final String nowIso = DateTime.now().toUtc().toIso8601String();

    final Map<String, dynamic> auditRecord = <String, dynamic>{
      'eventType': eventType,
      'actorUid': actorUid,
      'targetUid': targetUid,
      'timestamp': nowIso,
    };

    // Add optional metadata fields directly to root level
    if (metadata != null && metadata.isNotEmpty) {
      auditRecord.addAll(metadata);
    }

    await auditRef.child(pushKey).set(auditRecord);
    debugPrint('AUDIT: Logged $eventType: actor=$actorUid, target=$targetUid');
  } catch (e) {
    debugPrint('ERROR: Failed to write audit event: $e');
  }
}

/// Write an auto-decline event when a friend request is automatically declined
/// due to a statusCode=9 blocking stub.
///
/// Parameters:
/// - [blockedUid]: UID of the user who has the blocking statusCode=9 stub
/// - [requesterUid]: UID of the user whose request was auto-declined
/// - [reason]: Explanation string (e.g., 'recipient_has_declined_stub')
Future<void> writeAutoDeclineEvent({
  required String blockedUid,
  required String requesterUid,
  required String reason,
}) async {
  await writeFriendEvent(
    eventType: 'friend_request_auto_declined',
    actorUid: blockedUid, // The user with the blocking stub
    targetUid: requesterUid, // The user whose request was blocked
    metadata: <String, dynamic>{
      'reason': reason,
      'autoDeclined': true,
    },
  );
}

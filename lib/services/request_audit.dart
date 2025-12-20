// lib/services/request_audit.dart
//
// Helper to write a single request audit record to the Realtime Database under
// the root node "request_audit".
//
// Field set written:
// - typeCode       : int  (request type code; see codes below)
// - fromUid        : String
// - toUid          : String
// - fromEmail      : String
// - toEmail        : String
// - clientRequestId: String (client-supplied request id, if any)
// - statusCode     : int  (status code; see codes below)
// - createdAt      : ISO8601 timestamp (server-local)
//
// Returns the generated audit key on success, or null on failure.
//
// Supported codes (current):
// Request type codes:
//   1 = friend_request
//   2 = review_request
//   3 = delete_friend
//
// Status codes:
//   0 = created
//   1 = accepted
//   2 = declined
//   3 = deleted

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

Future<String?> writeRequestAudit({
  required int typeCode,
  required String fromUid,
  required String toUid,
  String fromEmail = '',
  String toEmail = '',
  String clientReqId = '',
  int statusCode = 0,
  String? auditId, // optional: if provided, use this id instead of push()
}) async {
  if (typeCode <= 0) {
    return null;
  }
  if ((fromUid.isEmpty) && (toUid.isEmpty)) {
    return null;
  }

  try {
    final DatabaseReference root = FirebaseDatabase.instance.ref();
    final DatabaseReference auditRoot = root.child('request_audit');

    final String key;
    if (auditId != null && auditId.isNotEmpty) {
      key = auditId;
    } else {
      key = auditRoot.push().key ?? '';
      if (key.isEmpty) {
        debugPrint('writeRequestAudit: failed to generate push key');
        return null;
      }
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'typeCode': typeCode,
      'fromUid': fromUid,
      'toUid': toUid,
      'fromEmail': fromEmail,
      'toEmail': toEmail,
      'clientRequestId': clientReqId,
      'statusCode': statusCode,
      'createdAt': DateTime.now().toIso8601String(),
    };

    final DatabaseReference targetRef = auditRoot.child(key);
    await targetRef.set(payload);
    debugPrint(
        'writeRequestAudit: wrote audit record key=$key typeCode=$typeCode from=$fromUid to=$toUid statusCode=$statusCode');
    return key;
  } catch (e, st) {
    debugPrint('writeRequestAudit: failed to write audit record: $e\n$st');
    return null;
  }
}

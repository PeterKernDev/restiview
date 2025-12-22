// lib/services/audit_info.dart
//
// Helper to write a generic audit record to the Realtime Database under
// the root node "audit_info".
//
// Fields:
// - timestamp   : int (UTC ms since epoch)
// - userId      : String (UID of the user)
// - userEmail   : String (email of the user)
// - type        : String ("delete", "account_delete", etc)
// - target      : String (what was affected)
// - details     : Map<String, dynamic> (optional, only if exceptional or for account deletion reason)
//
// Returns the generated audit key on success, or null on failure.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

Future<String?> writeAuditInfo({
  required String userId,
  required String userEmail,
  required String type,
  required String target,
  Map<String, dynamic>? details,
}) async {
  try {
    final DatabaseReference root = FirebaseDatabase.instance.ref();
    // Determine subfolder based on type
    String subfolder;
    if (type == 'review_delete' || type == 'requested_review_delete') {
      subfolder = 'deletions';
    } else if (type == 'account_delete') {
      subfolder = 'account_deletions';
    } else {
      subfolder = 'other';
    }
    final DatabaseReference auditRoot = root.child('audit_info').child(subfolder);
    final String key = auditRoot.push().key ?? '';
    if (key.isEmpty) {
      debugPrint('writeAuditInfo: failed to generate push key');
      return null;
    }
    final int timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final Map<String, dynamic> record = {
      'timestamp': timestamp,
      'userId': userId,
      'userEmail': userEmail,
      'type': type,
      'target': target,
    };
    if (details != null && details.isNotEmpty) {
      record['details'] = details;
    }
    await auditRoot.child(key).set(record);
    return key;
  } catch (e) {
    debugPrint('writeAuditInfo: $e');
    return null;
  }
}

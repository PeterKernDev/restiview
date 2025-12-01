// lib/services/user_setup.dart
//
// Ensures minimal records for a new user:
// - users_by_email/<normalized> mapping (includes acceptsFriends flag)
// - public_profiles/<uid> with displayName/email
// - users/<uid>/userSettings7 ensured (created as true if missing)
// The mapping write uses a small exponential backoff with a hard-coded max of 3 attempts.
// Calls are best-effort and non-blocking for callers (errors are logged).

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '/services/db_utils.dart';

Future<void> ensureUserSetup({
  required String uid,
  required String email,
  required String displayName,
  required bool acceptsFriends,
}) async {
  if (uid.isEmpty) {
    debugPrint('ensureUserSetup: empty uid, skipping');
    return;
  }

  final String mailboxEmail = email.trim().toLowerCase();
  final String normalized = normalizeEmailForPath(mailboxEmail);

  final DatabaseReference root = FirebaseDatabase.instance.ref();
  final DatabaseReference emailMapRef = root.child('users_by_email/$normalized');
  final DatabaseReference publicProfileRef = root.child('public_profiles/$uid');
  final DatabaseReference userSettings7Ref = root.child('users/$uid/userSettings7');

  // 1) Ensure users_by_email mapping exists and points to this uid (and include acceptsFriends)
  try {
    final DataSnapshot snap = await emailMapRef.get();
    bool shouldWrite = false;

    if (!snap.exists) {
      shouldWrite = true;
      debugPrint('ensureUserSetup: mapping missing for $normalized (will write)');
    } else {
      final Object? v = snap.value;
      if (v is String) {
        if (v != uid) {
          shouldWrite = true;
          debugPrint('ensureUserSetup: legacy mapping string differs ($v != $uid), will overwrite');
        }
      } else if (v is Map) {
        final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(v);
        final Object? existingUid = m['uid'];
        if (existingUid == null || existingUid.toString().isEmpty || existingUid.toString() != uid) {
          shouldWrite = true;
          debugPrint('ensureUserSetup: mapping uid mismatch existing=$existingUid -> will overwrite');
        } else {
          debugPrint('ensureUserSetup: mapping already correct for $normalized -> $uid');
        }
      } else {
        shouldWrite = true;
        debugPrint('ensureUserSetup: mapping present but unexpected type -> will overwrite');
      }
    }

    if (shouldWrite) {
      final Map<String, dynamic> mapping = <String, dynamic>{
        'uid': uid,
        'email': mailboxEmail,
        'displayName': displayName,
        'userName': displayName,
        'acceptsFriends': acceptsFriends,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      const int maxAttempts = 3;
      int attempt = 0;
      while (true) {
        attempt++;
        try {
          debugPrint('ensureUserSetup: writing mapping attempt $attempt -> users_by_email/$normalized');
          await emailMapRef.set(mapping);
          debugPrint('ensureUserSetup: mapping written for $normalized');
          break;
        } catch (e, st) {
          debugPrint('ensureUserSetup: mapping write failed attempt $attempt: $e\n$st');
          if (attempt >= maxAttempts) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 200 * (1 << (attempt - 1))));
        }
      }
    }
  } catch (e, st) {
    debugPrint('ensureUserSetup: error ensuring mapping for $normalized: $e\n$st');
  }

  // 2) Ensure public_profiles/<uid> exists/updated (best-effort)
  try {
    final Map<String, dynamic> pub = <String, dynamic>{
      'displayName': displayName,
      'email': mailboxEmail,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await publicProfileRef.set(pub);
    debugPrint('ensureUserSetup: public_profiles/$uid written/updated');
  } catch (e, st) {
    debugPrint('ensureUserSetup: failed to write public_profiles/$uid: $e\n$st');
  }

  // 3) Ensure users/$uid/userSettings7 exists (set true if missing)
  try {
    final DataSnapshot s = await userSettings7Ref.get();
    if (!s.exists) {
      await userSettings7Ref.set(true);
      debugPrint('ensureUserSetup: userSettings7 created for uid=$uid');
    } else {
      debugPrint('ensureUserSetup: userSettings7 already present for uid=$uid');
    }
  } catch (e, st) {
    debugPrint('ensureUserSetup: failed to ensure userSettings7 for uid=$uid: $e\n$st');
  }
}

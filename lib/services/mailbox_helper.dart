// mailbox_helper.dart
// Centralized mailbox processing service
// Processes friend and review requests from users_by_email/<email>/requests
//

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'review_counter.dart'; // For countMatchingReviews

/// Result of mailbox processing operation
class MailboxProcessResult {
  final bool hasRequests;
  final int friendRequestsProcessed;
  final int reviewRequestsProcessed;
  final int notificationsProcessed;
  final List<String> errors;

  MailboxProcessResult({
    required this.hasRequests,
    required this.friendRequestsProcessed,
    required this.reviewRequestsProcessed,
    required this.notificationsProcessed,
    required this.errors,
  });

  int get totalProcessed =>
      friendRequestsProcessed +
      reviewRequestsProcessed +
      notificationsProcessed;
}

/// Lightweight check for pending mailbox requests
/// Returns true if mailbox has any pending requests
Future<bool> hasMailboxRequests(String normalizedMailbox) async {
  try {
    final DatabaseReference ref = FirebaseDatabase.instance.ref(
      'users_by_email/$normalizedMailbox/requests',
    );
    final DataSnapshot snap = await ref.get();
    return snap.exists && snap.value != null;
  } catch (e) {
    debugPrint('Error checking mailbox requests: $e');
    return false;
  }
}

/// Resolves canonical profile information for a user
/// Prefers mailbox mapping data, falls back to public_profiles
// Never reads private /users/<uid> for security
Future<Map<String, String>> resolveCanonicalProfile(
  String uid,
  Map<dynamic, dynamic>? mapping,
) async {
  String email = '';
  String username = '';

  if (mapping != null) {
    if (mapping['email'] is String && (mapping['email'] as String).isNotEmpty) {
      email = mapping['email'] as String;
    }
    if (mapping['userEmail'] is String &&
        (mapping['userEmail'] as String).isNotEmpty) {
      email = mapping['userEmail'] as String;
    }
    if (mapping['displayName'] is String &&
        (mapping['displayName'] as String).isNotEmpty) {
      username = mapping['displayName'] as String;
    }
    if (mapping['userName'] is String &&
        (mapping['userName'] as String).isNotEmpty) {
      username = mapping['userName'] as String;
    }
  }

  // Prefer mapping, then public_profiles; do NOT attempt to read private /users
  if (username.isEmpty || email.isEmpty) {
    try {
      final DataSnapshot pub = await FirebaseDatabase.instance
          .ref('public_profiles/$uid')
          .get();
      if (pub.exists && pub.value != null && pub.value is Map) {
        final Map<dynamic, dynamic> pm = Map<dynamic, dynamic>.from(
          pub.value as Map,
        );
        if ((pm['displayName'] is String) &&
            (pm['displayName'] as String).isNotEmpty) {
          username = pm['displayName'] as String;
        }
        if ((pm['email'] is String) && (pm['email'] as String).isNotEmpty) {
          email = pm['email'] as String;
        }
      }
    } catch (e) {
      // Non-fatal, continue
      debugPrint('Error reading public_profiles: $e');
    }
  }

  if (email.isEmpty) email = uid;
  if (username.isEmpty) username = email;
  return {'email': email, 'username': username};
}

/// Writes audit record for request processing event
Future<void> _writeRequestAuditEvent({
  required String eventType,
  required String fromUid,
  required String toUid,
  String? details,
}) async {
  try {
    final String eventId = FirebaseDatabase.instance
        .ref('audit_info/request_events')
        .push()
        .key!;

    final Map<String, dynamic> auditData = <String, dynamic>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'eventType': eventType,
      'fromUid': fromUid,
      'toUid': toUid,
    };

    if (details != null && details.isNotEmpty) {
      auditData['details'] = details;
    }

    await FirebaseDatabase.instance
        .ref('audit_info/request_events/$eventId')
        .set(auditData);
  } catch (e) {
    // Best-effort audit logging, don't fail on audit errors
    debugPrint('Error writing audit event: $e');
  }
}

// Main mailbox processing function
// Processes all pending requests in users_by_email/<normalizedMailbox>/requests
// Handles all 6 status codes: 0,1,3,5,6,8
Future<MailboxProcessResult> processUserMailbox(
  String myUid,
  String normalizedMailbox,
) async {
  int friendRequestsProcessed = 0;
  int reviewRequestsProcessed = 0;
  int notificationsProcessed = 0;
  final List<String> errors = <String>[];

  final DatabaseReference ref = FirebaseDatabase.instance.ref(
    'users_by_email/$normalizedMailbox/requests',
  );

  DataSnapshot snap;
  try {
    snap = await ref.get();
  } catch (e) {
    errors.add('Failed to read mailbox: $e');
    return MailboxProcessResult(
      hasRequests: false,
      friendRequestsProcessed: 0,
      reviewRequestsProcessed: 0,
      notificationsProcessed: 0,
      errors: errors,
    );
  }

  if (!snap.exists || snap.value == null) {
    return MailboxProcessResult(
      hasRequests: false,
      friendRequestsProcessed: 0,
      reviewRequestsProcessed: 0,
      notificationsProcessed: 0,
      errors: errors,
    );
  }

  final Object? raw = snap.value;
  if (raw is! Map) {
    return MailboxProcessResult(
      hasRequests: false,
      friendRequestsProcessed: 0,
      reviewRequestsProcessed: 0,
      notificationsProcessed: 0,
      errors: errors,
    );
  }

  final Map<String, dynamic> entries = Map<String, dynamic>.from(raw);

  for (final MapEntry<String, dynamic> entry in entries.entries) {
    final String reqId = entry.key;
    final Object? requestData = entry.value;

    if (requestData is! Map) {
      continue;
    }

    final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(requestData);

    int statusCode = -1;
    if (m['statusCode'] is int) {
      statusCode = m['statusCode'] as int;
    } else if (m['statusCode'] is String) {
      statusCode = int.tryParse(m['statusCode'] as String) ?? -1;
    } else if (m['status'] is String) {
      final String s = (m['status'] as String).toUpperCase();
      if (s.contains('FR-ASKED') || s.contains('FR_ASKED')) {
        statusCode = 0;
      } else if (s.contains('FR-WANTED') ||
          s.contains('FR_WANTS') ||
          s.contains('FR-WANTS')) {
        statusCode = 2;
      } else {
        statusCode = -1;
      }
    }

    final String fromUid = m['fromUid']?.toString() ?? '';
    final String clientRequestId = m['clientRequestId']?.toString() ?? '';
    final String comment = m['comment']?.toString() ?? '';

    if (statusCode < 0) {
      continue;
    }
    if (fromUid.isEmpty) {
      continue;
    }

    try {
      Map<dynamic, dynamic>? mapping;
      if (m.isNotEmpty) {
        mapping = Map<dynamic, dynamic>.from(m);
      }
      final Map<String, String> canonical = await resolveCanonicalProfile(
        fromUid,
        mapping,
      );
      final String fromEmail = canonical['email']!;
      final String fromDisplayName = canonical['username']!;

      // Idempotency check: skip if friend stub already has same clientRequestId
      final DatabaseReference friendRef = FirebaseDatabase.instance.ref(
        'users/$myUid/friends/$fromUid',
      );
      final DataSnapshot friendSnap = await friendRef.get();

      bool shouldWriteFriend = true;
      if (friendSnap.exists &&
          friendSnap.value != null &&
          friendSnap.value is Map) {
        final Map<dynamic, dynamic> f = Map<dynamic, dynamic>.from(
          friendSnap.value as Map,
        );
        if (clientRequestId.isNotEmpty &&
            f['clientRequestId'] != null &&
            f['clientRequestId'].toString() == clientRequestId) {
          shouldWriteFriend = false;
        }
      }

      if (shouldWriteFriend) {
        // Handle different statusCode values:
        // - statusCode=0: incoming friend request
        // - statusCode=1: friend acceptance notification
        // - statusCode=8: friend decline notification
        // - statusCode=3: review request
        // - statusCode=5: reviews provided notification
        // - statusCode=6: review request declined notification

        if (statusCode == 1) {
          // This is a friend acceptance notification
          // Update my existing friend stub to accepted status
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid/statusCode': 1,
            'users/$myUid/friends/$fromUid/accepted': true,
            'users/$myUid/friends/$fromUid/updatedAt': DateTime.now()
                .toIso8601String(),
            'users_by_email/$normalizedMailbox/requests/$reqId': null,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

          // Write audit event
          await _writeRequestAuditEvent(
            eventType: 'Friend request accepted',
            fromUid: fromUid,
            toUid: myUid,
          );

          notificationsProcessed++;
        } else if (statusCode == 8) {
          // This is a friend decline notification
          // Update my existing friend stub to declined status
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid/statusCode': 8,
            'users/$myUid/friends/$fromUid/accepted': false,
            'users/$myUid/friends/$fromUid/updatedAt': DateTime.now()
                .toIso8601String(),
            'users_by_email/$normalizedMailbox/requests/$reqId': null,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

          // Write audit event
          await _writeRequestAuditEvent(
            eventType: 'Friend request declined',
            fromUid: fromUid,
            toUid: myUid,
          );

          notificationsProcessed++;
        } else if (statusCode == 9) {
          // This is a friend deletion notification
          // The other user deleted their friend stub, so update mine to declined
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid/statusCode': 8,
            'users/$myUid/friends/$fromUid/accepted': false,
            'users/$myUid/friends/$fromUid/updatedAt': DateTime.now()
                .toIso8601String(),
            'users_by_email/$normalizedMailbox/requests/$reqId': null,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

          // Write audit event
          await _writeRequestAuditEvent(
            eventType: 'Friend deleted by other user',
            fromUid: fromUid,
            toUid: myUid,
          );

          notificationsProcessed++;
        } else if (statusCode == 3) {
          // This is a review request notification
          // Update the friend stub to add review_request structure

          // Parse filters array from mailbox request
          final List<Map<String, String?>> filters = <Map<String, String?>>[];
          try {
            if (m['filters'] is List) {
              final List<dynamic> filtersList = m['filters'] as List;
              for (final dynamic filterItem in filtersList) {
                if (filterItem is Map) {
                  final Map<dynamic, dynamic> filterMap =
                      Map<dynamic, dynamic>.from(filterItem);
                  final String? country = filterMap['country']?.toString();
                  final String? city = filterMap['city']?.toString();
                  if (country != null && country.isNotEmpty) {
                    filters.add(<String, String?>{
                      'country': country,
                      'city': (city == null || city.isEmpty || city == 'none')
                          ? null
                          : city,
                    });
                  }
                }
              }
            }
          } catch (e) {
            errors.add('Error parsing filters: $e');
          }

          // Calculate review count for this request (sum across all filters)
          int rvCount = 0;
          if (filters.isNotEmpty) {
            try {
              rvCount = await countMatchingReviews(
                ownerUid: myUid,
                filters: filters,
                excludeKeys: null, // No exclusions for initial request
              );
            } catch (e) {
              rvCount = -1; // -1 indicates calculation failed
              errors.add('Error calculating rvCount: $e');
            }
          }

          final String nowIso = DateTime.now().toUtc().toIso8601String();

          // Create review_request structure with filters array
          final Map<String, dynamic> reviewRequestData = <String, dynamic>{
            'requestComment': comment,
            'filters': filters,
            'rvCount': rvCount,
            'rvCountLastCheckedAt': nowIso,
            'exCount': 0,
            'fromEmail': fromEmail,
            'fromDisplayName': fromDisplayName,
            'exKeys': <String>[],
          };

          // Atomic multi-path update: update statusCode, add review_request, and delete mailbox entry
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid/statusCode': 3,
            'users/$myUid/friends/$fromUid/comment': comment,
            'users/$myUid/friends/$fromUid/review_request': reviewRequestData,
            'users/$myUid/friends/$fromUid/rvCount': rvCount,
            'users/$myUid/friends/$fromUid/rvCountLastCheckedAt': nowIso,
            'users/$myUid/friends/$fromUid/updatedAt': nowIso,
            'users_by_email/$normalizedMailbox/requests/$reqId': null,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

          // Write audit event
          await _writeRequestAuditEvent(
            eventType: 'Review request received',
            fromUid: fromUid,
            toUid: myUid,
            details: 'rvCount: $rvCount',
          );

          reviewRequestsProcessed++;
        } else if (statusCode == 5) {
          // This is a provided reviews notification (RV-PROVIDED)
          // Extract metadata from mailbox record and store on friend stub
          int rqCount = 0;
          String providerMessage = '';
          String providedAt = '';

          try {
            if (m['meta'] is Map) {
              final Map<dynamic, dynamic> meta = Map<dynamic, dynamic>.from(
                m['meta'] as Map,
              );
              rqCount = (meta['rqCount'] is int)
                  ? meta['rqCount'] as int
                  : int.tryParse(meta['rqCount']?.toString() ?? '') ?? 0;
              providerMessage = meta['provider-message']?.toString() ?? '';
              providedAt = meta['providedAt']?.toString() ?? '';
            }
          } catch (e) {
            errors.add('Error parsing RV-PROVIDED metadata: $e');
          }

          // Update friend stub to statusCode=5 with metadata from mailbox
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid/statusCode': 5,
            'users/$myUid/friends/$fromUid/updatedAt': DateTime.now()
                .toIso8601String(),
            'users/$myUid/friends/$fromUid/mailboxReqId': reqId,
            'users/$myUid/friends/$fromUid/mailboxNormalized':
                normalizedMailbox,
            'users/$myUid/friends/$fromUid/providedRequestId': reqId,
            'users/$myUid/friends/$fromUid/providedRqCount': rqCount,
            'users/$myUid/friends/$fromUid/comment': providerMessage,
            'users/$myUid/friends/$fromUid/providedAt': providedAt,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

          // Write audit event
          await _writeRequestAuditEvent(
            eventType: 'Review request accepted',
            fromUid: fromUid,
            toUid: myUid,
            details: '$rqCount reviews shared',
          );

          notificationsProcessed++;
        } else if (statusCode == 6) {
          // This is a declined review request notification (RV-DECLINED)
          // Extract metadata from mailbox record and store on friend stub
          String providerMessage = '';

          try {
            if (m['meta'] is Map) {
              final Map<dynamic, dynamic> meta = Map<dynamic, dynamic>.from(
                m['meta'] as Map,
              );
              providerMessage = meta['provider-message']?.toString() ?? '';
            }
          } catch (e) {
            errors.add('Error parsing RV-DECLINED metadata: $e');
          }

          // Update friend stub to statusCode=6 with declined message
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid/statusCode': 6,
            'users/$myUid/friends/$fromUid/comment': providerMessage,
            'users/$myUid/friends/$fromUid/updatedAt': DateTime.now()
                .toIso8601String(),
            'users_by_email/$normalizedMailbox/requests/$reqId': null,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

          // Write audit event
          await _writeRequestAuditEvent(
            eventType: 'Review request declined',
            fromUid: fromUid,
            toUid: myUid,
          );

          notificationsProcessed++;
        } else if (statusCode == 0) {
          // This is an incoming friend request
          // Create the recipient's own friend stub (my stub).
          final Map<String, dynamic> recipientStub = <String, dynamic>{
            'statusCode': 2, // FR-WANTED
            'email': fromEmail,
            'username': fromDisplayName,
            'comment': comment,
            'clientRequestId': clientRequestId,
            'mailboxReqId': clientRequestId,
            'mailboxNormalized': normalizedMailbox,
            'updatedAt': DateTime.now().toIso8601String(),
          };

          // Atomic multi-path update: create recipient's friend stub and delete mailbox entry
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid': recipientStub,
            'users_by_email/$normalizedMailbox/requests/$reqId': null,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

          // Write audit event
          await _writeRequestAuditEvent(
            eventType: 'Friend request received',
            fromUid: fromUid,
            toUid: myUid,
          );

          friendRequestsProcessed++;
        }
      } else {
        // Request already processed (idempotency check)
        // Mark as processed but don't modify friend stub
        final Map<String, dynamic> processedMark = <String, dynamic>{
          'processedAt': DateTime.now().toIso8601String(),
          'processedBy': myUid,
        };
        await FirebaseDatabase.instance
            .ref('users_by_email/$normalizedMailbox/requests/$reqId')
            .update(processedMark);
      }
    } catch (e) {
      errors.add('Error processing request $reqId: $e');
    }
  }

  return MailboxProcessResult(
    hasRequests: false, // Will be checked after processing
    friendRequestsProcessed: friendRequestsProcessed,
    reviewRequestsProcessed: reviewRequestsProcessed,
    notificationsProcessed: notificationsProcessed,
    errors: errors,
  );
}

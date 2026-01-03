// mailbox_helper.dart
// Centralized mailbox processing service
// Processes friend and review requests from users_by_email/<email>/requests
//

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'review_counter.dart'; // For countMatchingReviews
import 'friend_event_audit.dart'; // For audit logging
import 'db_utils.dart'; // For normalizeEmailForPath

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
// Handles all 7 status codes: 0,1,3,5,6,7,8
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
        // - statusCode=3: review request notification
        // - statusCode=5: reviews provided notification (auto-copy to reviews_requested)
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

          notificationsProcessed++;
        } else if (statusCode == 8) {
          // This is a friend decline notification
          // Check if I already have statusCode=9 for this friend (I was the instigator)
          // If so, skip processing this mailbox - statusCode=9 takes precedence
          final DataSnapshot existingStub = await FirebaseDatabase.instance
              .ref('users/$myUid/friends/$fromUid/statusCode')
              .get();
          
          if (existingStub.exists && existingStub.value == 9) {
            // I was the instigator of decline, don't overwrite with statusCode=8
            debugPrint('SKIP: Ignoring statusCode=8 mailbox - I have statusCode=9 (instigator)');
            await FirebaseDatabase.instance
                .ref('users_by_email/$normalizedMailbox/requests/$reqId')
                .remove();
            notificationsProcessed++;
            continue;
          }
          
          // Update my existing friend stub to declined status (I was the recipient)
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
          
          // Check if there's already a friend stub - if it exists and has a different
          // status (e.g., a newer friend request), skip processing this stale deletion
          bool shouldProcess = true;
          try {
            final DataSnapshot existingStub = await FirebaseDatabase.instance
                .ref('users/$myUid/friends/$fromUid/statusCode')
                .get();
            if (existingStub.exists) {
              final int existingStatus = existingStub.value is int
                  ? existingStub.value as int
                  : int.tryParse(existingStub.value?.toString() ?? '') ?? -1;
              // If there's already a friend request (status 0 or 2) or accepted (1),
              // don't overwrite it with this stale deletion notification
              if (existingStatus == 0 ||
                  existingStatus == 1 ||
                  existingStatus == 2) {
                shouldProcess = false;
                debugPrint(
                  'Skipping stale deletion notification - newer friend stub exists (status=$existingStatus)',
                );
              }
            }
          } catch (e) {
            debugPrint('Error checking existing friend stub: $e');
          }

          if (shouldProcess) {
            // Extract auditEventId if present
            String? auditEventId;
            try {
              if (m['auditEventId'] is String) {
                auditEventId = m['auditEventId'] as String;
              }
            } catch (e) {
              debugPrint('Error extracting auditEventId: $e');
            }

            final Map<String, dynamic> atomic = <String, dynamic>{
              'users/$myUid/friends/$fromUid/statusCode': 8,
              'users/$myUid/friends/$fromUid/accepted': false,
              'users/$myUid/friends/$fromUid/updatedAt': DateTime.now()
                  .toIso8601String(),
              'users_by_email/$normalizedMailbox/requests/$reqId': null,
            };

            // Store auditEventId on friend stub if present
            if (auditEventId != null && auditEventId.isNotEmpty) {
              atomic['users/$myUid/friends/$fromUid/auditEventId'] =
                  auditEventId;
            }

            await FirebaseDatabase.instance.ref().update(atomic);
          } else {
            // Just delete the stale mailbox entry
            await FirebaseDatabase.instance
                .ref('users_by_email/$normalizedMailbox/requests/$reqId')
                .remove();
          }

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

          reviewRequestsProcessed++;
        } else if (statusCode == 5) {
          // This is a provided reviews notification (RV-PROVIDED)
          // Auto-copy reviews from mailbox to reviews_requested
          String deliveredAt = '';

          try {
            if (m['meta'] is Map) {
              final Map<dynamic, dynamic> meta = Map<dynamic, dynamic>.from(
                m['meta'] as Map,
              );
              deliveredAt = meta['deliveredAt']?.toString() ?? '';
            }
          } catch (e) {
            errors.add('Error parsing RV-PROVIDED metadata: $e');
          }

          // Read reviews from mailbox and copy to reviews_requested
          int copiedCount = 0;
          int skippedCount = 0;
          try {
            final String reviewsPath =
                'users_by_email/$normalizedMailbox/requests/$reqId/reviews_requested';
            final DataSnapshot reviewsSnap = await FirebaseDatabase.instance
                .ref(reviewsPath)
                .get();

            if (reviewsSnap.exists && reviewsSnap.value is Map) {
              final Map<dynamic, dynamic> reviews = Map<dynamic, dynamic>.from(
                reviewsSnap.value as Map,
              );

              // First, read existing reviews_requested to check for duplicates
              final DataSnapshot existingSnap = await FirebaseDatabase.instance
                  .ref('users/$myUid/reviews_requested')
                  .get();

              final Set<String> existingKeys = <String>{};
              if (existingSnap.exists && existingSnap.value is Map) {
                final Map<dynamic, dynamic> existing =
                    Map<dynamic, dynamic>.from(existingSnap.value as Map);
                existingKeys.addAll(
                  existing.keys.map((dynamic k) => k.toString()),
                );
              }

              // Copy each review to user's reviews_requested (skip duplicates)
              for (final MapEntry<dynamic, dynamic> entry in reviews.entries) {
                final String reviewKey = entry.key.toString();
                final dynamic reviewData = entry.value;

                if (reviewData is Map) {
                  // Skip if review already exists
                  if (existingKeys.contains(reviewKey)) {
                    skippedCount++;
                    debugPrint(
                      'Skipping duplicate review: $reviewKey (already in reviews_requested)',
                    );
                    continue;
                  }

                  // Prepare review map with required modifications
                  final Map<String, dynamic> reviewMap =
                      Map<String, dynamic>.from(reviewData);

                  // Ensure owner_email field is present for filtering by provider
                  if (fromEmail.isNotEmpty &&
                      !reviewMap.containsKey('owner_email')) {
                    reviewMap['owner_email'] = fromEmail;
                  }

                  // Remove financial information: set cost to empty/blank
                  reviewMap['cost'] = '';

                  final String destPath =
                      'users/$myUid/reviews_requested/$reviewKey';
                  await FirebaseDatabase.instance
                      .ref(destPath)
                      .set(reviewMap);
                  copiedCount++;
                }
              }
            }
          } catch (e) {
            errors.add('Error copying reviews from mailbox: $e');
          }

          // Update friend stub back to FRIEND status (statusCode=1)
          // Set hasNewReviews flag to show (!) indicator
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid/statusCode': 1,
            'users/$myUid/friends/$fromUid/updatedAt': DateTime.now()
                .toIso8601String(),
            'users/$myUid/friends/$fromUid/review_request': null,
            'users/$myUid/friends/$fromUid/comment': null,
            'users/$myUid/friends/$fromUid/hasNewReviews': true,
            'users/$myUid/friends/$fromUid/newReviewsCount': copiedCount,
            'users/$myUid/friends/$fromUid/duplicatesSkipped': skippedCount,
            'users/$myUid/friends/$fromUid/newReviewsAt': deliveredAt,
            'users_by_email/$normalizedMailbox/requests/$reqId': null,
          };
          await FirebaseDatabase.instance.ref().update(atomic);

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
          // This is an incoming friend request (FR-ASKED)
          
          // PHASE 2: Check if recipient has a statusCode=9 stub for sender (auto-decline protection)
          final DataSnapshot recipientStubSnap = await FirebaseDatabase.instance
              .ref('users/$myUid/friends/$fromUid')
              .get();
          
          if (recipientStubSnap.exists && recipientStubSnap.value != null) {
            final Map<dynamic, dynamic> existingStub = 
                Map<dynamic, dynamic>.from(recipientStubSnap.value as Map);
            final int existingStatusCode = existingStub['statusCode'] as int? ?? -1;
            
            if (existingStatusCode == 9) {
              // Recipient has declined this user previously (statusCode=9)
              // Auto-decline: create statusCode=8 mailbox entry for sender, delete incoming request
              debugPrint('AUTO-DECLINE: Recipient $myUid has statusCode=9 for sender $fromUid');
              
              final String nowIso = DateTime.now().toUtc().toIso8601String();
              final String autoDeclineReqId = DateTime.now().millisecondsSinceEpoch.toString();
              
              // Create statusCode=8 mailbox entry for sender (auto-declined notification)
              final String senderNormalizedMailbox = normalizeEmailForPath(fromEmail);
              final Map<String, dynamic> atomic = <String, dynamic>{
                'users_by_email/$senderNormalizedMailbox/requests/$autoDeclineReqId/fromUid': myUid,
                'users_by_email/$senderNormalizedMailbox/requests/$autoDeclineReqId/statusCode': 8,
                'users_by_email/$senderNormalizedMailbox/requests/$autoDeclineReqId/createdAt': nowIso,
                'users_by_email/$senderNormalizedMailbox/requests/$autoDeclineReqId/clientRequestId': autoDeclineReqId,
                'users_by_email/$senderNormalizedMailbox/requests/$autoDeclineReqId/type': 'friend_request_auto_declined',
                'users_by_email/$senderNormalizedMailbox/requests/$autoDeclineReqId/meta': <String, dynamic>{
                  'reason': 'recipient_has_declined_stub',
                  'autoDeclined': true,
                },
                // Delete the incoming friend request from recipient's mailbox
                'users_by_email/$normalizedMailbox/requests/$reqId': null,
              };
              
              await FirebaseDatabase.instance.ref().update(atomic);
              
              // Write audit event
              await writeAutoDeclineEvent(
                blockedUid: myUid,
                requesterUid: fromUid,
                reason: 'recipient_has_declined_stub',
              );
              
              notificationsProcessed++;
              continue; // Skip normal friend request processing
            }
            
            // If any other friend stub exists (not statusCode=9), just delete the mailbox entry
            // and don't overwrite the existing stub
            debugPrint('SKIP: Friend stub already exists with statusCode=$existingStatusCode for $fromUid');
            await FirebaseDatabase.instance
                .ref('users_by_email/$normalizedMailbox/requests/$reqId')
                .remove();
            notificationsProcessed++;
            continue;
          }
          
          // Normal friend request processing - no friend stub exists at all
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

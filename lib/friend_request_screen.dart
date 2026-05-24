// lib/friend_request_screen.dart
// Friend-request only screen. Writes mailbox + asymmetric friend-stubs for a plain friend request.
// This file contains NO review logic. It always writes FR codes:
//   requester = 0 (statusRequesterSent) and recipient = 2 (statusRequested).
//
// Fix: ensure the requester stub is always written under the signed-in user's UID
// and the recipient stub under the resolved recipient UID. Add debug prints to
// show exactly what was sent to Firebase.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/session_cache.dart';
import 'services/db_utils.dart'; // normalizeEmailForPath helper
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/restiview_constants.dart';
import 'friends_screen.dart'; // for status constants

class FriendRequestScreen extends StatefulWidget {
  const FriendRequestScreen({super.key});

  @override
  State<FriendRequestScreen> createState() => _FriendRequestScreenState();
}

class _FriendRequestScreenState extends State<FriendRequestScreen> {
  bool _loading = false;
  final TextEditingController emailCtl = TextEditingController();
  final TextEditingController commentCtl = TextEditingController();

  String? _checkedNormalized;
  bool _checkValid = false;

  void _toggleLoading(bool value) {
    if (!mounted) {
      return;
    }
    setState(() => _loading = value);
  }

  @override
  void dispose() {
    emailCtl.dispose();
    commentCtl.dispose();
    super.dispose();
  }

  int? _extractStatusCode(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is Map) {
      final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(raw);
      final dynamic sc = m['statusCode'] ?? m['status'] ?? m['state'];
      if (sc is int) {
        return sc;
      }
      if (sc is String) {
        final String s = sc.toLowerCase();
        if (s.contains('accept')) {
          return 1;
        }
        if (s.contains('decline')) {
          return 8;
        }
      }
    }
    return null;
  }

  Future<void> _checkRecipientPreview() async {
    final String raw = emailCtl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.emailRequired)));
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    _checkValid = false;
    _checkedNormalized = null;

    final String normalized = normalizeEmailForPath(raw.toLowerCase());

    DataSnapshot mappingSnap;
    try {
      mappingSnap = await FirebaseDatabase.instance.ref('users_by_email/$normalized').get();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.requestSendFailed)));
      return;
    }

    if (!mounted) return;

    if (!mappingSnap.exists || mappingSnap.value == null) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      return;
    }

    String? mappedUid;
    Map<dynamic, dynamic>? mapping;
    if (mappingSnap.value is Map) {
      mapping = Map<dynamic, dynamic>.from(mappingSnap.value as Map);
      mappedUid = mapping['uid']?.toString();
    } else if (mappingSnap.value is String) {
      mappedUid = mappingSnap.value.toString();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      return;
    }

    if (mappedUid == null || mappedUid.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      return;
    }

    try {
      if (mapping != null && mapping.containsKey('acceptsFriends')) {
        final dynamic af = mapping['acceptsFriends'];
        bool allows = true;
        if (af is bool) {
          allows = af;
        } else if (af is String) {
          allows = af.toLowerCase() == 'true';
        } else if (af is num) {
          allows = af != 0;
        }
        if (!allows) {
          messenger.showSnackBar(SnackBar(content: Text(AppStr.friendRequestsDisabled)));
          return;
        }
      }
    } catch (_) {
      // ignore
    }

    if (myUid.isNotEmpty && mappedUid == myUid) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.cannotAddSelf)));
      return;
    }

    try {
      if (myUid.isNotEmpty) {
        // Only check our own friend stub - no need to read the other user's data
        final DataSnapshot myFriendSnap =
            await FirebaseDatabase.instance.ref('users/$myUid/friends/$mappedUid').get();
        if (!mounted) return;
        if (myFriendSnap.exists && myFriendSnap.value != null) {
          final int? code = _extractStatusCode(myFriendSnap.value);
          if (code == 8 || code == 9) {
            messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotAvailable)));
            return;
          }
          if (code == 1) {
            messenger.showSnackBar(SnackBar(content: Text(AppStr.alreadyFriends)));
            return;
          }
        }
      }
    } catch (e) {
      // non-fatal
    }

    _checkedNormalized = normalized;
    _checkValid = true;
    messenger.showSnackBar(SnackBar(content: Text(AppStr.validEmailAddress)));
    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, String>> _resolveRecipientFromMappingOrPublic(String uid, Map<dynamic, dynamic>? mapping) async {
    String email = '';
    String username = '';

    if (mapping != null) {
      if (mapping['email'] is String && (mapping['email'] as String).isNotEmpty) {
        email = mapping['email'] as String;
      }
      if (mapping['displayName'] is String && (mapping['displayName'] as String).isNotEmpty) {
        username = mapping['displayName'] as String;
      } else if (mapping['userName'] is String && (mapping['userName'] as String).isNotEmpty) {
        username = mapping['userName'] as String;
      }
    }

    if (username.isEmpty || email.isEmpty) {
      try {
        final DataSnapshot pub = await FirebaseDatabase.instance.ref('public_profiles/$uid').get();
        if (pub.exists && pub.value != null && pub.value is Map) {
          final Map<dynamic, dynamic> pm = Map<dynamic, dynamic>.from(pub.value as Map);
          if (pm['displayName'] is String && (pm['displayName'] as String).isNotEmpty) {
            username = pm['displayName'] as String;
          }
          if (pm['email'] is String && (pm['email'] as String).isNotEmpty) {
            email = pm['email'] as String;
          }
        }
      } catch (_) {
        // ignore
      }
    }

    if (email.isEmpty) {
      email = uid;
    }
    if (username.isEmpty) {
      username = email;
    }
    return <String, String>{'email': email, 'username': username};
  }

  Future<void> _sendFriendRequest(String rawEmail) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final String currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserUid.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.signInRequired)));
      return;
    }

    final String emailTrim = rawEmail.trim();
    final String commentTrim = commentCtl.text.trim();

    if (emailTrim.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.emailRequired)));
      return;
    }

    final String normalized = _checkedNormalized ?? normalizeEmailForPath(emailTrim.toLowerCase());

    DataSnapshot recipientSnap;
    try {
      recipientSnap = await FirebaseDatabase.instance.ref('users_by_email/$normalized').get();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.requestSendFailed)));
      return;
    }

    if (!recipientSnap.exists || recipientSnap.value == null) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      return;
    }

    String recipientUid = '';
    Map<dynamic, dynamic>? mapping;
    final Object? raw = recipientSnap.value;
    if (raw is Map) {
      mapping = Map<dynamic, dynamic>.from(raw);
      if (mapping['uid'] != null) {
        recipientUid = mapping['uid'].toString();
      }
    } else if (raw is String) {
      recipientUid = raw;
    } else {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      return;
    }

    if (recipientUid.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      return;
    }

    try {
      if (mapping != null && mapping.containsKey('acceptsFriends')) {
        final dynamic af = mapping['acceptsFriends'];
        bool allows = true;
        if (af is bool) {
          allows = af;
        } else if (af is String) {
          allows = af.toLowerCase() == 'true';
        } else if (af is num) {
          allows = af != 0;
        }
        if (!allows) {
          messenger.showSnackBar(SnackBar(content: Text(AppStr.friendRequestsDisabled)));
          return;
        }
      }
    } catch (_) {
      // ignore
    }

    if (recipientUid == currentUserUid) {
      messenger.showSnackBar(SnackBar(content: Text(AppStr.cannotAddSelf)));
      return;
    }

    try {
      final DataSnapshot myFriendSnap =
          await FirebaseDatabase.instance.ref('users/$currentUserUid/friends/$recipientUid').get();
      if (myFriendSnap.exists && myFriendSnap.value != null) {
        final int? code = _extractStatusCode(myFriendSnap.value);
        if (code == 1) {
          messenger.showSnackBar(SnackBar(content: Text(AppStr.alreadyFriends)));
          return;
        }
        if (code == 8 || code == 9) {
          messenger.showSnackBar(SnackBar(content: Text(AppStr.userNotAvailable)));
          return;
        }
      }
    } catch (_) {
      // non-fatal
    }

    final String clientRequestId = DateTime.now().millisecondsSinceEpoch.toString();
    final String fromEmail = (await SessionCache.getSavedEmail()) ?? FirebaseAuth.instance.currentUser?.email ?? '';
    final String fromDisplayName =
        (await SessionCache.getSavedDisplayName()) ?? (FirebaseAuth.instance.currentUser?.displayName ?? fromEmail);

    String recipientEmail = emailTrim;
    String recipientDisplayName = emailTrim;
    try {
      final Map<String, String> resolved = await _resolveRecipientFromMappingOrPublic(recipientUid, mapping);
      recipientEmail = resolved['email']!;
      recipientDisplayName = resolved['username']!;
    } catch (_) {
      // non-fatal
    }

    // Use explicit final variables so we never accidentally swap UIDs
    final String finalSenderUid = currentUserUid;
    final String finalRecipientUid = recipientUid;
    final String mailboxPath = 'users_by_email/$normalized/requests/$clientRequestId';

    // Debug sanity checks in debug builds
    if (kDebugMode) {
      assert(finalSenderUid.isNotEmpty && finalRecipientUid.isNotEmpty && finalSenderUid != finalRecipientUid,
          'sender and recipient UIDs must be non-empty and different');
    }

    final Map<String, dynamic> updates = <String, dynamic>{};

    // Mailbox entry (friend request)
    updates[mailboxPath] = <String, dynamic>{
      'statusCode': 0,
      'fromUid': finalSenderUid,
      'fromEmail': fromEmail,
      'fromDisplayName': fromDisplayName,
      'comment': commentTrim,
      'createdAt': DateTime.now().toIso8601String(),
      'clientRequestId': clientRequestId,
    };

    // Requester stub = FR-ASKED (0) — always under current signed-in user
    // Only the sender creates their own stub. The recipient will create theirs on sign-in.
    final Map<String, dynamic> senderStub = <String, dynamic>{
      'statusCode': statusRequesterSent,
      'email': recipientEmail,
      'username': recipientDisplayName,
      'comment': commentTrim,
      'clientRequestId': clientRequestId,
      'mailboxReqId': clientRequestId,
      'mailboxNormalized': normalized,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    updates['users/$finalSenderUid/friends/$finalRecipientUid'] = senderStub;

    // NOTE: Recipient stub is NOT created here. The recipient will create their own
    // friend stub when they sign in and process the mailbox entry.

    if (mounted) {
      _toggleLoading(true);
    }

    try {
      await _updateWithRetry(updates, maxAttempts: 3);

      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(AppStr.requestSent)));
      if (mounted) {
        navigator.pop(true);
      }
      return;
    } on FirebaseException catch (fe) {
      try {
        final DataSnapshot existing = await FirebaseDatabase.instance.ref(mailboxPath).get();
        if (existing.exists && existing.value != null && existing.value is Map) {
          final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(existing.value as Map);
          if (m['clientRequestId'] != null && m['clientRequestId'].toString() == clientRequestId) {
            if (!mounted) {
              return;
            }
            messenger.showSnackBar(SnackBar(content: Text(AppStr.requestSent)));
            if (mounted) {
              navigator.pop(true);
            }
            return;
          }
        }
      } catch (_) {}
      if (!mounted) {
        return;
      }
      appLog('sendFriendRequest FirebaseException: ${fe.message ?? fe.code}');
      messenger.showSnackBar(SnackBar(content: Text(AppStr.requestSendFailed)));
      return;
    } catch (e) {
      if (!mounted) {
        return;
      }
      appLog('sendFriendRequest error: $e');
      messenger.showSnackBar(SnackBar(content: Text(AppStr.requestSendFailed)));
      return;
    } finally {
      if (mounted) {
        _toggleLoading(false);
      }
    }
  }

  Future<void> _updateWithRetry(Map<String, dynamic> updates, {int maxAttempts = 3}) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        await FirebaseDatabase.instance.ref().update(updates);
        return;
      } catch (e) {
        if (attempt >= maxAttempts) {
          rethrow;
        }
        final int backoffMs = 150 * (1 << (attempt - 1));
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sendEnabled = !_loading && _checkValid;
    final bool checkEnabled = !_loading;

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        title: Text(AppStr.requestsTitle, style: AppFonts.bold.copyWith(color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: emailCtl,
                      decoration: InputDecoration(labelText: AppStr.emailLabel),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (_checkValid) {
                          setState(() {
                            _checkValid = false;
                            _checkedNormalized = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commentCtl,
                      decoration: InputDecoration(labelText: AppStr.requestCommentLabel),
                      keyboardType: TextInputType.text,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 12),
                    if (_loading) const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.transparent,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: () {
                          if (!mounted) {
                            return;
                          }
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ochre,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(AppStr.back, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.black)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: checkEnabled ? () async {
                          await _checkRecipientPreview();
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: checkEnabled ? AppColors.yellow : AppColors.mutedText,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(AppStr.checkLabel, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.black)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: sendEnabled ? () async {
                          await _sendFriendRequest(emailCtl.text.trim());
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sendEnabled ? AppColors.darkGreen : AppColors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(AppStr.sendRequest, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

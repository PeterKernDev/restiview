// lib/review_request_screen.dart
// Dedicated screen for creating a review request targeted at a selected friend.
// Requester stub = 4 (RV-ASKED), Recipient stub = 3 (RV-WANTED).
// MailboxNormalized points to the recipient normalized path (the mailbox we write).
// Recipient stub is primed with rvCount = -1 in the nested review node so the recipient's client will resolve counts.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/session_cache.dart';
import 'services/db_utils.dart';
import 'services/request_audit.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/restiview_constants.dart';
import 'friends_screen.dart'; // reuse status constants

class ReviewRequestScreen extends StatefulWidget {
  const ReviewRequestScreen({super.key});

  @override
  State<ReviewRequestScreen> createState() => _ReviewRequestScreenState();
}

class _ReviewRequestScreenState extends State<ReviewRequestScreen> {
  bool _loading = false;
  final TextEditingController emailCtl = TextEditingController();
  final TextEditingController commentCtl = TextEditingController();
  final TextEditingController cityCtl = TextEditingController();

  String? _reviewFriendUid;
  String? _checkedNormalized;

  List<String> _countryList = <String>[];
  String? _selectedCountry;
  String? _selectedCuisine;

  bool _didInitArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitArgs) {
      return;
    }

    final Object? args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final String? friendEmail = args['friendEmail'] as String?;
      final String? friendUid = args['friendUid'] as String?;
      if (friendEmail != null && friendEmail.isNotEmpty) {
        emailCtl.text = friendEmail;
        _checkedNormalized = normalizeEmailForPath(friendEmail.toLowerCase());
        _reviewFriendUid = (friendUid != null && friendUid.isNotEmpty) ? friendUid : null;
      }
    }

    if (emailCtl.text.isEmpty) {
      final String pending = SessionCache.pendingFriendEmail.trim();
      if (pending.isNotEmpty) {
        emailCtl.text = pending;
        _checkedNormalized = normalizeEmailForPath(pending.toLowerCase());
        _reviewFriendUid = SessionCache.pendingFriendUid;
      }
    }

    try {
      final List<String> raw = List<String>.from(SessionCache.customCountries);
      final List<String> cleaned = raw.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
      cleaned.sort();
      if (cleaned.isNotEmpty) {
        _countryList = cleaned;
      }
    } catch (_) {
      // fallback below
    }

    if (_countryList.isEmpty) {
      SessionCache.getCountryList().then((list) {
        if (!mounted) {
          return;
        }
        final List<String> cleaned = list.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
        cleaned.sort();
        if (!mounted) {
          return;
        }
        setState(() {
          _countryList = cleaned;
        });
      }).catchError((_) {});
    }

    final String candidate = SessionCache.defaultCountry.trim();
    if (candidate.isNotEmpty && _countryList.contains(candidate)) {
      _selectedCountry = candidate;
    } else if (_countryList.isNotEmpty) {
      _selectedCountry ??= _countryList.first;
    } else {
      SessionCache.getCountryList().then((list) {
        if (!mounted) {
          return;
        }
        final List<String> cleaned = list.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
        cleaned.sort();
        if (!mounted) {
          return;
        }
        setState(() {
          _countryList = cleaned;
          final String cand = SessionCache.defaultCountry.trim();
          if (cand.isNotEmpty && _countryList.contains(cand)) {
            _selectedCountry = cand;
          } else if (_selectedCountry == null && _countryList.isNotEmpty) {
            _selectedCountry = _countryList.first;
          }
        });
      }).catchError((_) {});
    }

    _selectedCuisine = null;
    _didInitArgs = true;
  }

  @override
  void dispose() {
    emailCtl.dispose();
    commentCtl.dispose();
    cityCtl.dispose();
    super.dispose();
  }

  void _toggleLoading(bool v) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = v;
    });
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

  Future<void> _sendReviewRequest() async {
    final String senderUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (senderUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.signInRequired)));
      }
      return;
    }

    final String toEmail = emailCtl.text.trim();
    final String comment = commentCtl.text.trim();
    final String city = cityCtl.text.trim();

    assert(toEmail.isNotEmpty, 'ReviewRequestScreen: recipient email must be present');

    if (toEmail.isEmpty) {
      return;
    }

    if (_selectedCountry == null || _selectedCountry!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.countryRequired)));
      }
      return;
    }

    final String normalized = _checkedNormalized ?? normalizeEmailForPath(toEmail.toLowerCase());
    String recipientUid = '';
    Map<dynamic, dynamic>? mapping;

    if (_reviewFriendUid != null && _reviewFriendUid!.isNotEmpty) {
      recipientUid = _reviewFriendUid!;
      try {
        final DataSnapshot pub = await FirebaseDatabase.instance.ref('public_profiles/$recipientUid').get();
        if (pub.exists && pub.value != null && pub.value is Map) {
          mapping = Map<dynamic, dynamic>.from(pub.value as Map);
        }
      } catch (_) {}
    } else {
      DataSnapshot snap;
      try {
        snap = await FirebaseDatabase.instance.ref('users_by_email/$normalized').get();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.requestSendFailed)));
        }
        return;
      }
      if (!snap.exists || snap.value == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
        }
        return;
      }
      final Object? raw = snap.value;
      if (raw is Map) {
        mapping = Map<dynamic, dynamic>.from(raw);
        if (mapping['uid'] != null) {
          recipientUid = mapping['uid'].toString();
        }
      } else if (raw is String) {
        recipientUid = raw;
      }
    }

    if (recipientUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      }
      return;
    }

    if (recipientUid == senderUid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.cannotAddSelf)));
      }
      return;
    }

    // If mapping says recipient doesn't accept friends/requests, block
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.friendRequestsDisabled)));
          }
          return;
        }
      }
    } catch (_) {
      // ignore parsing issues (best-effort)
    }

    String recipientEmail = toEmail;
    String recipientDisplayName = toEmail;
    try {
      final Map<String, String> resolved = await _resolveRecipientFromMappingOrPublic(recipientUid, mapping);
      recipientEmail = resolved['email']!;
      recipientDisplayName = resolved['username']!;
    } catch (_) {}

    final String clientRequestId = DateTime.now().millisecondsSinceEpoch.toString();
    final String fromEmail = (await SessionCache.getSavedEmail()) ?? FirebaseAuth.instance.currentUser?.email ?? '';
    final String fromDisplayName = (await SessionCache.getSavedDisplayName()) ?? (FirebaseAuth.instance.currentUser?.displayName ?? fromEmail);

    final Map<String, dynamic> updates = <String, dynamic>{};
    final String mailboxPath = 'users_by_email/$normalized/requests/$clientRequestId';

    final Map<String, dynamic> reviewPayload = <String, dynamic>{
      'country': _selectedCountry,
      if (_selectedCuisine != null && _selectedCuisine!.isNotEmpty) 'cuisine': _selectedCuisine,
      if (city.isNotEmpty) 'city': city,
      'comment': comment,
    };

    updates[mailboxPath] = <String, dynamic>{
      'statusCode': 0,
      'type': 'review_request',
      'fromUid': senderUid,
      'fromEmail': fromEmail,
      'fromDisplayName': fromDisplayName,
      'comment': comment,
      'review': reviewPayload,
      'createdAt': DateTime.now().toIso8601String(),
      'clientRequestId': clientRequestId,
    };

    // Correct RV mapping:
    // requester stub = RV-ASKED (4) - keep review payload at nested 'review'
    updates['users/$senderUid/friends/$recipientUid'] = <String, dynamic>{
      'statusCode': statusRvAsked, // 4
      'email': recipientEmail,
      'username': recipientDisplayName,
      'comment': comment,
      'clientRequestId': clientRequestId,
      'mailboxReqId': clientRequestId,
      'mailboxNormalized': normalized, // recipient mailbox normalized
      'review': <String, dynamic>{
        ...reviewPayload,
      },
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // recipient stub = RV-WANTED (3)
    // place review details under the nested review subnode and prime rvCount = -1 there
    updates['users/$recipientUid/friends/$senderUid'] = <String, dynamic>{
      'statusCode': statusRvWants, // 3
      'email': fromEmail,
      'username': fromDisplayName,
      'comment': comment,
      'clientRequestId': clientRequestId,
      'mailboxReqId': clientRequestId,
      'mailboxNormalized': normalized, // recipient mailbox normalized
      'review': <String, dynamic>{
        ...reviewPayload,
        'rvCount': -1,
        'exCount': 0,
        'exKeys': <String, bool>{},
      },
      'updatedAt': DateTime.now().toIso8601String(),
    };

    _toggleLoading(true);
    try {
      await _updateWithRetry(updates, maxAttempts: 3);

      // On success, write request_audit separately (best-effort)
      try {
        await writeRequestAudit(
          typeCode: 2, // review_request
          fromUid: senderUid,
          toUid: recipientUid,
          fromEmail: fromEmail,
          toEmail: recipientEmail,
          clientReqId: clientRequestId,
          statusCode: 0,
          auditId: null,
        );
      } catch (auditErr) {
        if (kDebugMode) {
          debugPrint('[ReviewRequestScreen] writeRequestAudit failed: $auditErr');
        }
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.requestSent)));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      return;
    } on FirebaseException catch (fe) {
      // idempotency check: maybe mailbox entry already exists
      try {
        final DataSnapshot existing = await FirebaseDatabase.instance.ref(mailboxPath).get();
        if (existing.exists && existing.value != null && existing.value is Map) {
          final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(existing.value as Map);
          if (m['clientRequestId'] != null && m['clientRequestId'].toString() == clientRequestId) {
            try {
              await writeRequestAudit(
                typeCode: 2,
                fromUid: senderUid,
                toUid: recipientUid,
                fromEmail: fromEmail,
                toEmail: recipientEmail,
                clientReqId: clientRequestId,
                statusCode: 0,
              );
            } catch (_) {
              // ignore audit write failures here
            }

            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.requestSent)));
            if (!mounted) {
              return;
            }
            Navigator.of(context).pop(true);
            return;
          }
        }
      } catch (_) {
        // ignore
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.requestSendFailed}: ${fe.message ?? fe.code}')));
      return;
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.requestSendFailed}: $e')));
      return;
    } finally {
      _toggleLoading(false);
    }
  }

  Future<void> _updateWithRetry(Map<String, dynamic> updates, {int maxAttempts = 3}) async {
    int attempt = 0;
    while (true) {
      attempt += 1;
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
    final bool sendEnabled = !_loading && _selectedCountry != null && _selectedCountry!.isNotEmpty;

    final List<DropdownMenuItem<String>> countryItems = _countryList.map((String v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList();
    final String? countryInitial = (_selectedCountry != null && _countryList.contains(_selectedCountry)) ? _selectedCountry : null;
    final String? cuisineInitial = (_selectedCuisine != null && systemCuisines.contains(_selectedCuisine)) ? _selectedCuisine : null;

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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  TextField(
                    controller: emailCtl,
                    decoration: const InputDecoration(labelText: 'To:'),
                    keyboardType: TextInputType.emailAddress,
                    readOnly: true,
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: commentCtl,
                    decoration: InputDecoration(labelText: AppStr.requestCommentLabel),
                    keyboardType: TextInputType.text,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Country'),
                    items: countryItems,
                    initialValue: countryInitial,
                    onChanged: !_loading
                        ? (String? v) {
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _selectedCountry = v;
                            });
                          }
                        : null,
                    hint: const Text('Select country'),
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Cuisine (optional)'),
                    items: systemCuisines.map((String c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList(),
                    initialValue: cuisineInitial,
                    onChanged: !_loading
                        ? (String? v) {
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _selectedCuisine = v;
                            });
                          }
                        : null,
                    hint: const Text('Select cuisine'),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: cityCtl,
                    decoration: const InputDecoration(labelText: 'City (optional)'),
                    keyboardType: TextInputType.text,
                  ),
                  const SizedBox(height: 12),

                  if (_loading) const Center(child: CircularProgressIndicator()),
                ]),
              ),
            ),

            // Bottom action buttons: Back (ochre), Accept (green), Reject (red), Review (orange)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.transparent,
              child: Row(
                children: <Widget>[
                  // Back - ochre
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
                        child: Text(
                          AppStr.backLabel,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                          style: AppFonts.bold,
                        ),
                      ),
                    ),
                  ),

                  // Accept - green (sends request)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: sendEnabled
                            ? () async {
                                await _sendReviewRequest();
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sendEnabled ? AppColors.darkGreen : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(
                          AppStr.acceptLabel,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                          style: AppFonts.bold.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                  // Reject - red (cancel)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: () {
                          if (!mounted) {
                            return;
                          }
                          Navigator.pop(context, false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(
                          AppStr.declineLabel,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                          style: AppFonts.bold.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                  // Review - orange (disabled placeholder to match requested color)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(
                          AppStr.reviewLabel,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                          style: AppFonts.bold.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

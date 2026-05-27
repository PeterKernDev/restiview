// lib/friends_screen.dart
// FriendsScreen — friend / review status handling and rvCount resolver.
// Lint-safe: all flow-control statements use braces and types are explicit.

import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/strings.dart';
import 'constants/restiview_constants.dart';
import 'top_screen.dart';
import 'services/session_cache.dart';
import 'services/mailbox_helper.dart';
import 'sub_friends_screen/friend_entry.dart';
import 'sub_friends_screen/friend_row.dart';
import 'sub_friends_screen/friend_actions.dart';
import 'services/db_utils.dart';
import 'services/review_counter.dart';
import 'services/ube_provider.dart';
import 'services/friend_event_audit.dart';

// Canonical status codes
const int statusRequesterSent = 0; // FR-ASKED (requester)
const int statusAccepted = 1;
const int statusRequested = 2; // FR-WANTED (recipient)
const int statusRvWants = 3; // RV-WANTED (recipient)
const int statusRvAsked = 4; // RV-ASKED (requester)
const int statusProvided =
    5; // RV-PROVIDED - reviews delivered and auto-copied
const int statusRvDeclined =
    6; // provider declined review request (recipient marker)
const int statusDeclined = 8;
const int statusFriendDeleted =
    9; // friend deleted relationship (notification to other user)
const int statusUnknown = 10;
const int statusPendingDelete = 99;

// TTL for re-checking rvCount (seconds)
const int rvCountTtlSeconds = 86400;

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.allowFriendRequests = true});
  final bool allowFriendRequests;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final List<FriendEntry> _friends = <FriendEntry>[];
  final Map<String, FriendEntry> _friendByUid = <String, FriendEntry>{};
  final Map<String, bool> _loadingProfileFor = <String, bool>{};
  StreamSubscription<DatabaseEvent>? _sub;
  bool _loading = true;
  Timer? _loadTimeout;

  String? _selectedUid;
  bool _accepting = false;
  bool _declining = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _checkMailbox(); // Check mailbox for pending requests
    _subscribeToFriends();
    // Safety net: if Firebase onValue is slow or unavailable, clear the spinner
    _loadTimeout = Timer(const Duration(seconds: 10), () {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _checkMailbox() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      return;
    }

    final String normalizedEmail = normalizeEmailForPath(
      user.email!.toLowerCase(),
    );

    try {
      // Process any pending mailbox requests
      await processUserMailbox(user.uid, normalizedEmail);
      // The _subscribeToFriends() listener will automatically
      // pick up the updated friend stubs and refresh the UI
    } catch (e) {
      // Silent failure with logging
      appLog('Error processing mailbox in friends screen: $e');
    }
  }

  Future<void> _subscribeToFriends() async {
    final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (myUid.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    final DatabaseReference ref = FirebaseDatabase.instance.ref(
      'users/$myUid/friends',
    );
    _sub = ref.onValue.listen(
      (DatabaseEvent event) async {
        final DataSnapshot snap = event.snapshot;
        final Map<String, FriendEntry> nextMap = <String, FriendEntry>{};
        final Map<String, Map<dynamic, dynamic>> rawFriendVmaps =
            <String, Map<dynamic, dynamic>>{};

        if (snap.exists && snap.value != null && snap.value is Map) {
          final Map<dynamic, dynamic> rawMap = Map<dynamic, dynamic>.from(
            snap.value as Map,
          );
          rawMap.forEach((dynamic key, dynamic val) {
            final String friendUid = key?.toString() ?? '';
            if (friendUid.isEmpty) {
              return;
            }

            int fsc = statusUnknown;
            String email = friendUid;
            String username = friendUid;
            int sharedCount = 0;
            String? comment;
            String? reqId;
            String? normalized;
            bool? acceptedFlag;
            int? rvCount;
            String? rvCountLastCheckedAt;
            ReviewData? reviewData;
            ReviewRequestData? reviewRequestData;
            String? providedRequestId;
            int? providedRqCount;
            String? providedAt;

            try {
              if (val is int) {
                fsc = val;
              } else if (val is String) {
                fsc = FriendEntry.mapStringStatusToFsc(val);
              } else if (val is Map) {
                final Map<dynamic, dynamic> vmap = Map<dynamic, dynamic>.from(
                  val,
                );
                rawFriendVmaps[friendUid] = vmap;
                final dynamic statusField =
                    vmap['status'] ?? vmap['statusCode'] ?? vmap['state'];
                if (statusField is int) {
                  fsc = statusField;
                  appLog('LISTENER DEBUG: Friend $friendUid has statusCode=$fsc');
                } else if (statusField is String) {
                  fsc = FriendEntry.mapStringStatusToFsc(statusField);
                  appLog('LISTENER DEBUG: Friend $friendUid has string status=$statusField mapped to fsc=$fsc');
                }

                if (vmap['email'] is String &&
                    (vmap['email'] as String).isNotEmpty) {
                  email = vmap['email'] as String;
                }
                if (vmap['username'] is String &&
                    (vmap['username'] as String).isNotEmpty) {
                  username = vmap['username'] as String;
                }
                if (vmap['sharedReviewsCount'] is int) {
                  sharedCount = vmap['sharedReviewsCount'] as int;
                }
                if (vmap['comment'] is String &&
                    (vmap['comment'] as String).isNotEmpty) {
                  comment = vmap['comment'] as String;
                }
                if (vmap['mailboxReqId'] is String &&
                    (vmap['mailboxReqId'] as String).isNotEmpty) {
                  reqId = vmap['mailboxReqId'] as String;
                }
                if (vmap['mailboxNormalized'] is String &&
                    (vmap['mailboxNormalized'] as String).isNotEmpty) {
                  normalized = vmap['mailboxNormalized'] as String;
                }
                if (vmap['accepted'] is bool) {
                  acceptedFlag = vmap['accepted'] as bool;
                } else if (vmap['accepted'] is int) {
                  acceptedFlag = (vmap['accepted'] as int) == 1;
                }
                // Read rvCount - prioritize review_request subnode over top-level field
                if (vmap['review_request'] is Map) {
                  final Map<dynamic, dynamic> rrMapTemp =
                      Map<dynamic, dynamic>.from(vmap['review_request'] as Map);
                  if (rrMapTemp['rvCount'] is int) {
                    rvCount = rrMapTemp['rvCount'] as int;
                  }
                  if (rrMapTemp['rvCountLastCheckedAt'] is String &&
                      (rrMapTemp['rvCountLastCheckedAt'] as String)
                          .isNotEmpty) {
                    rvCountLastCheckedAt =
                        rrMapTemp['rvCountLastCheckedAt'] as String;
                  }
                }
                // Fallback to top-level rvCount if not in review_request
                if (rvCount == null && vmap['rvCount'] is int) {
                  rvCount = vmap['rvCount'] as int;
                }
                if (rvCountLastCheckedAt == null &&
                    vmap['rvCountLastCheckedAt'] is String &&
                    (vmap['rvCountLastCheckedAt'] as String).isNotEmpty) {
                  rvCountLastCheckedAt = vmap['rvCountLastCheckedAt'] as String;
                }

                // Parse provider metadata (for RV-PROVIDED status)
                if (vmap['providedRequestId'] is String &&
                    (vmap['providedRequestId'] as String).isNotEmpty) {
                  providedRequestId = vmap['providedRequestId'] as String;
                }
                if (vmap['providedRqCount'] is int) {
                  providedRqCount = vmap['providedRqCount'] as int;
                }
                if (vmap['providedAt'] is String &&
                    (vmap['providedAt'] as String).isNotEmpty) {
                  providedAt = vmap['providedAt'] as String;
                }

                try {
                  if (vmap['review_request'] is Map) {
                    final Map<dynamic, dynamic> rrMap =
                        Map<dynamic, dynamic>.from(
                          vmap['review_request'] as Map,
                        );

                    final List<String> exKeys = <String>[];
                    if (rrMap['exKeys'] is List) {
                      for (final dynamic item in rrMap['exKeys'] as List) {
                        if (item is String) {
                          exKeys.add(item);
                        }
                      }
                    }

                    // Parse filters array
                    final List<Map<String, String?>> filters =
                        <Map<String, String?>>[];
                    if (rrMap['filters'] is List) {
                      for (final dynamic filterItem
                          in rrMap['filters'] as List) {
                        if (filterItem is Map) {
                          final Map<dynamic, dynamic> filterMap =
                              Map<dynamic, dynamic>.from(filterItem);
                          filters.add(<String, String?>{
                            'country': filterMap['country']?.toString(),
                            'city': filterMap['city']?.toString(),
                          });
                        }
                      }
                    }

                    reviewRequestData = ReviewRequestData(
                      requestComment: (rrMap['requestComment'] is String)
                          ? rrMap['requestComment'] as String
                          : null,
                      filterCountry: (rrMap['filterCountry'] is String)
                          ? rrMap['filterCountry'] as String
                          : null,
                      filterCity: (rrMap['filterCity'] is String)
                          ? rrMap['filterCity'] as String
                          : null,
                      filters: filters.isNotEmpty ? filters : null,
                      exCount: (rrMap['exCount'] is int)
                          ? rrMap['exCount'] as int
                          : 0,
                      fromEmail: (rrMap['fromEmail'] is String)
                          ? rrMap['fromEmail'] as String
                          : null,
                      fromDisplayName: (rrMap['fromDisplayName'] is String)
                          ? rrMap['fromDisplayName'] as String
                          : null,
                      exKeys: exKeys.isNotEmpty ? exKeys : null,
                    );
                  }
                } catch (_) {
                  // ignore review_request parse errors
                }

                try {
                  if (vmap['review'] is Map) {
                    final Map<dynamic, dynamic> rvMap =
                        Map<dynamic, dynamic>.from(vmap['review'] as Map);

                    final Map<String, String> filters = <String, String>{};
                    final dynamic f = rvMap['filters'];
                    if (f is Map) {
                      f.forEach((dynamic k, dynamic v2) {
                        if (k != null && v2 is String && v2.isNotEmpty) {
                          filters[k.toString()] = v2;
                        }
                      });
                    } else {
                      if (rvMap['country'] is String &&
                          (rvMap['country'] as String).isNotEmpty) {
                        filters['country'] = rvMap['country'] as String;
                      }
                      if (rvMap['cuisine'] is String &&
                          (rvMap['cuisine'] as String).isNotEmpty) {
                        filters['cuisine'] = rvMap['cuisine'] as String;
                      }
                      if (rvMap['city'] is String &&
                          (rvMap['city'] as String).isNotEmpty) {
                        filters['city'] = rvMap['city'] as String;
                      }
                    }

                    final Map<String, bool>? exKeys = (rvMap['exKeys'] is Map)
                        ? Map<String, bool>.from(
                            rvMap['exKeys'] as Map,
                          ).map((k, v2) => MapEntry(k.toString(), v2 == true))
                        : null;

                    final int? parsedRvCount = (rvMap['rvCount'] is int)
                        ? rvMap['rvCount'] as int
                        : (rvMap['rvCount'] is String
                              ? int.tryParse(rvMap['rvCount'])
                              : null);
                    final int? parsedExCount = (rvMap['exCount'] is int)
                        ? rvMap['exCount'] as int
                        : null;

                    reviewData = ReviewData(
                      filters: filters,
                      comment:
                          (rvMap['comment'] is String &&
                              (rvMap['comment'] as String).isNotEmpty)
                          ? rvMap['comment'] as String
                          : null,
                      rvCount: parsedRvCount,
                      exCount: parsedExCount,
                      exKeys: exKeys,
                      createdAt: (rvMap['createdAt'] is String)
                          ? rvMap['createdAt'] as String
                          : null,
                      updatedAt: (rvMap['updatedAt'] is String)
                          ? rvMap['updatedAt'] as String
                          : null,
                    );
                  }
                } catch (_) {
                  // ignore review parse errors
                }
              }
              nextMap[friendUid] = FriendEntry(
                uid: friendUid,
                email: email,
                username: username,
                fsc: fsc,
                sharedReviewsCount: sharedCount,
                comment: comment,
                mailboxReqId: reqId,
                mailboxNormalized: normalized,
                accepted: acceptedFlag,
                rvCount: rvCount,
                rvCountLastCheckedAt: rvCountLastCheckedAt,
                reviewRequest: reviewRequestData,
                review: reviewData,
                providedRequestId: providedRequestId,
                providedRqCount: providedRqCount,
                providedAt: providedAt,
              );
            } catch (_) {
              // ignore parsing errors
            }
          });
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _friendByUid
            ..clear()
            ..addAll(nextMap);
          _friends
            ..clear()
            ..addAll(_friendByUid.values);
          _loading = false;
          if (_selectedUid != null && !_friendByUid.containsKey(_selectedUid)) {
            _selectedUid = null;
          }
        });

        for (final FriendEntry fe in _friendByUid.values) {
          if (FriendEntry.looksLikeUid(fe.email) &&
              FriendEntry.looksLikeUid(fe.username)) {
            _fetchAndPatchProfile(fe.uid);
          }
        }

        _resolveMissingRvCounts(myUid, rawFriendVmaps);
        // Note: _loadProvidedReviewsMetadata removed - no longer needed with new direct delivery flow
      },
      onError: (Object err, StackTrace? st) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
        });
      },
    );
  }

  void _resolveMissingRvCounts(
    String myUid,
    Map<String, Map<dynamic, dynamic>> rawFriendVmaps,
  ) {
    const int maxConcurrent = 3;
    final List<String> queue = <String>[];

    for (final MapEntry<String, FriendEntry> e in _friendByUid.entries) {
      final String friendUid = e.key;
      final FriendEntry fe = e.value;

      // Only attempt to resolve when the local stub is recipient-side RV-WANTS.
      // Do NOT attempt when the status is requester-side RV-ASKED.
      if (fe.fsc != statusRvWants) {
        continue;
      }

      final int? cur = fe.review?.rvCount ?? fe.rvCount;
      final String? lastChecked =
          fe.rvCountLastCheckedAt ?? fe.review?.updatedAt;

      bool needs = false;
      if (cur == null) {
        needs = true;
      } else if (cur == -1) {
        needs = true;
      } else if (lastChecked != null) {
        try {
          final DateTime then = DateTime.parse(lastChecked).toUtc();
          final DateTime now = DateTime.now().toUtc();
          final int ageSec = now.difference(then).inSeconds;
          if (ageSec >= rvCountTtlSeconds) {
            needs = true;
          }
        } catch (_) {
          needs = true;
        }
      } else {
        needs = true;
      }

      if (needs) {
        queue.add(friendUid);
      }
    }

    if (queue.isEmpty) {
      return;
    }

    int inFlight = 0;
    int idx = 0;

    void scheduleNext() {
      if (idx >= queue.length) {
        return;
      }
      if (inFlight >= maxConcurrent) {
        return;
      }
      final String friendUid = queue[idx];
      idx += 1;
      inFlight += 1;
      _resolveOneRvCount(
        myUid,
        friendUid,
        rawFriendVmaps[friendUid],
      ).whenComplete(() {
        inFlight -= 1;
        scheduleNext();
      });
      scheduleNext();
    }

    scheduleNext();
  }

  Map<dynamic, dynamic>? _extractReviewRequestMap(
    dynamic rawValue,
    String friendUid,
  ) {
    if (rawValue is! Map) {
      return null;
    }

    final Map<dynamic, dynamic> asMap = Map<dynamic, dynamic>.from(rawValue);

    if (asMap.containsKey('filters') ||
        asMap.containsKey('filterCountry') ||
        asMap.containsKey('requestComment') ||
        asMap.containsKey('rvCount')) {
      return asMap;
    }

    final dynamic nestedFriend = asMap[friendUid];
    if (nestedFriend is Map) {
      final Map<dynamic, dynamic> friendMap = Map<dynamic, dynamic>.from(
        nestedFriend,
      );
      final dynamic nestedRequest = friendMap['review_request'];
      if (nestedRequest is Map) {
        return Map<dynamic, dynamic>.from(nestedRequest);
      }
    }

    return asMap;
  }

  Future<void> _resolveOneRvCount(
    String myUid,
    String friendUid,
    Map<dynamic, dynamic>? vmap,
  ) async {
    if (vmap == null) {
      return;
    }

    try {
      // Read review criteria from review_request structure in friend stub
      final DatabaseReference reviewRequestRef = FirebaseDatabase.instance.ref(
        'users/$myUid/friends/$friendUid/review_request',
      );
      final DataSnapshot reviewRequestSnap = await reviewRequestRef.get();

      if (!reviewRequestSnap.exists || reviewRequestSnap.value is! Map) {
        return;
      }

      final Map<dynamic, dynamic>? requestData = _extractReviewRequestMap(
        reviewRequestSnap.value,
        friendUid,
      );

      if (requestData == null) {
        return;
      }

      // Read filters array from review_request structure
      final List<Map<String, String?>> filters = <Map<String, String?>>[];
      try {
        if (requestData['filters'] is List) {
          final List<dynamic> filtersList = requestData['filters'] as List;
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
        // Error parsing filters
      }

      if (filters.isEmpty) {
        return;
      }

      // Read exKeys BEFORE counting so we can exclude already-provided reviews
      final Set<String> exKeysSet = <String>{};
      if (requestData['exKeys'] is List) {
        for (final dynamic item in requestData['exKeys'] as List) {
          if (item is String) {
            exKeysSet.add(item);
          }
        }
      }

      final String myUidNow = FirebaseAuth.instance.currentUser?.uid ?? '';

      final int found = await countMatchingReviews(
        ownerUid: myUidNow,
        filters: filters,
        excludeKeys: exKeysSet.isNotEmpty ? exKeysSet : null,
      );

      if (found < 0) {
        return;
      }

      // exKeys already read above, just get exCount
      final int exCount = (requestData['exCount'] is int)
          ? requestData['exCount'] as int
          : 0;

      final String nowIso = DateTime.now().toUtc().toIso8601String();

      // Write rvCount back to review_request structure
      final Map<String, dynamic> reviewRequestPatch = <String, dynamic>{
        'users/$myUid/friends/$friendUid/review_request/rvCount': found,
        'users/$myUid/friends/$friendUid/review_request/updatedAt': nowIso,
        'users/$myUid/friends/$friendUid/rvCount': found,
        'users/$myUid/friends/$friendUid/rvCountLastCheckedAt': nowIso,
      };

      try {
        await FirebaseDatabase.instance.ref().update(reviewRequestPatch);
      } catch (_) {}

      if (!mounted) {
        return;
      }
      final FriendEntry? local = _friendByUid[friendUid];
      if (local == null) {
        return;
      }

      // Update local state with count for display
      local.rvCount = found;
      local.rvCountLastCheckedAt = nowIso;

      // Update reviewRequest if present
      if (local.reviewRequest != null) {
        // Create new ReviewRequestData with updated values (immutable pattern)
        local.reviewRequest = ReviewRequestData(
          requestComment: local.reviewRequest!.requestComment,
          filterCountry: local.reviewRequest!.filterCountry,
          filterCity: local.reviewRequest!.filterCity,
          filters: local.reviewRequest!.filters,
          exCount: exCount,
          fromEmail: local.reviewRequest!.fromEmail,
          fromDisplayName: local.reviewRequest!.fromDisplayName,
          exKeys: exKeysSet.isNotEmpty ? exKeysSet.toList() : null,
        );
      }

      if (mounted) {
        setState(() {
          _friends
            ..clear()
            ..addAll(_friendByUid.values);
        });
      }
    } catch (_) {
      // ignore
    }
  }

  int _acceptedCount() {
    int n = 0;
    for (final FriendEntry f in _friends) {
      if ((f.accepted ?? false) ||
          f.fsc == statusAccepted ||
          f.status == FriendStatus.accepted) {
        n += 1;
      }
    }
    return n;
  }

  void _toggleSelect(String uid) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedUid = (_selectedUid == uid) ? null : uid;
    });
  }

  // Accept button logic: active for incoming requests only (NOT statusCode=1)
  bool _selectedIsAcceptable() {
    if (_selectedUid == null) {
      return false;
    }
    final FriendEntry? f = _friendByUid[_selectedUid];
    if (f == null) {
      return false;
    }

    // Accept is only for incoming friend/review requests
    // statusCode=2 (FR-WANTED), statusCode=3 (RV-WANTS), statusCode=6 (RV-DECLINED acknowledgment)
    return f.fsc == statusRequested || f.fsc == statusRvWants || f.fsc == statusRvDeclined;
  }

  // Decline button logic: active for incoming requests AND established friends (statusCode=1)
  // NOT for statusCode=0 (FR-ASKED retraction) or statusCode=4 (RV-ASKED retraction) — those use Delete
  bool _selectedIsDeclinable() {
    if (_selectedUid == null) {
      return false;
    }
    final FriendEntry? f = _friendByUid[_selectedUid];
    if (f == null) {
      return false;
    }

    // Decline active for:
    // - Incoming friend requests: statusCode=2 (FR-WANTED)
    // - Incoming review requests: statusCode=3 (RV-WANTS)
    // - Established friends: statusCode=1 (FRIEND)
    // - Outgoing review request placeholder: statusCode=4 (RV-ASKED)
    // NOT for statusCode=0 (FR-ASKED) — that is a retraction, handled by Delete
    // NOT for statusCode=6 (RV-DECLINED) - no concept of declining a decline
    return f.fsc == statusRequested ||
           f.fsc == statusRvWants ||
           f.fsc == statusAccepted ||
           f.fsc == statusRvAsked;
  }

  bool get _selectedIsDeletable {
    if (_selectedUid == null) {
      return false;
    }
    final FriendEntry? f = _friendByUid[_selectedUid];
    if (f == null) {
      return false;
    }
    // Delete button active for declined friend stubs (statusCode 8 or 9)
    // and for outgoing friend requests (statusCode=0, FR-ASKED) — retraction
    return f.fsc == statusDeclined || f.fsc == statusFriendDeleted || f.fsc == statusRequesterSent;
  }

  Future<void> _fetchAndPatchProfile(String friendUid) async {
    if (_loadingProfileFor[friendUid] == true) {
      return;
    }
    _loadingProfileFor[friendUid] = true;

    try {
      final DataSnapshot pubSnap = await FirebaseDatabase.instance
          .ref('public_profiles/$friendUid')
          .get();
      if (!pubSnap.exists || pubSnap.value == null) {
        return;
      }
      if (pubSnap.value is! Map) {
        return;
      }
      final Map<dynamic, dynamic> vmap = Map<dynamic, dynamic>.from(
        pubSnap.value as Map,
      );

      final String? email =
          (vmap['email'] is String && (vmap['email'] as String).isNotEmpty)
          ? vmap['email'] as String
          : null;
      final String? username =
          (vmap['displayName'] is String &&
              (vmap['displayName'] as String).isNotEmpty)
          ? vmap['displayName'] as String
          : null;
      final int? shared = (vmap['sharedReviewsCount'] is int)
          ? vmap['sharedReviewsCount'] as int
          : null;

      if (!mounted) {
        return;
      }
      final FriendEntry? current = _friendByUid[friendUid];
      if (current == null) {
        return;
      }

      bool localChanged = false;
      if (username != null &&
          username.isNotEmpty &&
          username != current.username) {
        current.username = username;
        localChanged = true;
      }
      if (email != null && email.isNotEmpty && email != current.email) {
        current.email = email;
        localChanged = true;
      }
      if (shared != null && shared != current.sharedReviewsCount) {
        current.sharedReviewsCount = shared;
        localChanged = true;
      }

      if (localChanged && mounted) {
        setState(() {
          _friends
            ..clear()
            ..addAll(_friendByUid.values);
        });
      }

      bool changed = false;
      final Map<String, dynamic> patch = <String, dynamic>{};
      final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (email != null && email.isNotEmpty && email != current.email) {
        if (myUid.isNotEmpty) {
          patch['users/$myUid/friends/$friendUid/email'] = email;
        }
        changed = true;
      }
      if (username != null &&
          username.isNotEmpty &&
          username != current.username) {
        if (myUid.isNotEmpty) {
          patch['users/$myUid/friends/$friendUid/username'] = username;
        }
        changed = true;
      }
      if (shared != null && shared != current.sharedReviewsCount) {
        if (myUid.isNotEmpty) {
          patch['users/$myUid/friends/$friendUid/sharedReviewsCount'] = shared;
        }
        changed = true;
      }

      if (changed && patch.isNotEmpty) {
        try {
          await FirebaseDatabase.instance.ref().update(patch);
        } catch (_) {
          // ignore write failure
        }
      }
    } catch (_) {
      // ignore fetch errors
    } finally {
      _loadingProfileFor.remove(friendUid);
    }
  }

  Future<void> _handleAccept() async {
    if (_selectedUid == null) {
      return;
    }
    final FriendEntry? selected = _friendByUid[_selectedUid];
    if (selected == null) {
      return;
    }
    if (!selected.isActionableByMe) {
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String me = currentUser?.uid ?? '';
    if (me.isEmpty) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    // If this is accepting a declined review request notification (statusCode=6), reset to FRIEND
    if (selected.fsc == statusRvDeclined) {
      try {
        final String nowIso = DateTime.now().toUtc().toIso8601String();
        final Map<String, dynamic> updates = <String, dynamic>{
          'users/$me/friends/${selected.uid}/statusCode': 1,
          'users/$me/friends/${selected.uid}/comment': null,
          'users/$me/friends/${selected.uid}/updatedAt': nowIso,
        };

        await FirebaseDatabase.instance.ref().update(updates);

        if (!mounted) return;

        setState(() {
          selected.fsc = statusAccepted;
          selected.accepted = true;
          selected.comment = null;
          _selectedUid = null;
          _accepting = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.declineAcknowledged)));
      } catch (e) {
        if (mounted) {
          setState(() {
            _accepting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStr.requestSendFailed)),
          );
        }
      }
      return;
    }

    // If this is a review request (recipient wants reviews), run the provider flow
    if (selected.fsc == statusRvWants) {
      // Gather matching reviews first, enforce 0/50 limits and then collect provider comment.
      final String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final List<Map<dynamic, dynamic>> toProvide = <Map<dynamic, dynamic>>[];
      int totalMatches = 0;
      try {
        // Read review criteria from friend stub's review_request subnode
        final String reviewRequestPath =
            'users/$myUid/friends/${selected.uid}/review_request';
        final DataSnapshot reviewRequestSnap = await FirebaseDatabase.instance
            .ref(reviewRequestPath)
            .get();

        if (!reviewRequestSnap.exists || reviewRequestSnap.value is! Map) {
          throw Exception('Review request data not found');
        }

        final Map<dynamic, dynamic>? requestData = _extractReviewRequestMap(
          reviewRequestSnap.value,
          selected.uid,
        );

        if (requestData == null) {
          throw Exception('Review request data not found');
        }

        // Read filters array from review_request structure
        final List<Map<String, String?>> filters = <Map<String, String?>>[];
        try {
          if (requestData['filters'] is List) {
            final List<dynamic> filtersList = requestData['filters'] as List;
            for (final dynamic filterItem in filtersList) {
              if (filterItem is Map) {
                final Map<dynamic, dynamic> filterMap =
                    Map<dynamic, dynamic>.from(filterItem);
                final String? country = filterMap['country']?.toString();
                final String? city = filterMap['city']?.toString();
                if (country != null && country.isNotEmpty) {
                  filters.add(<String, String?>{
                    'country': country.trim(),
                    'city': (city == null || city.isEmpty || city == 'none')
                        ? null
                        : city.trim(),
                  });
                }
              }
            }
          }
        } catch (e) {
        appLog('Error parsing filters: $e');
      }

        if (filters.isEmpty) {
          throw Exception('No valid filters found in review request');
        }

        final Set<String> excludedKeys = <String>{};
        // Parse exclusions if present (can be Map or List)
        try {
          final dynamic exRaw = requestData['exKeys'];
          if (exRaw is Map) {
            for (final dynamic k in exRaw.keys) {
              if (k != null) excludedKeys.add(k.toString());
            }
          } else if (exRaw is List) {
            for (final dynamic v in exRaw) {
              if (v != null) excludedKeys.add(v.toString());
            }
          }
        } catch (_) {}

        // Read my reviews and filter client-side against all filters (OR logic)
        final DatabaseReference myReviewsRef = FirebaseDatabase.instance.ref(
          'users/$myUid/reviews',
        );
        final DataSnapshot myRvSnap = await myReviewsRef.get();
        if (myRvSnap.exists &&
            myRvSnap.value != null &&
            myRvSnap.value is Map) {
          final Map<dynamic, dynamic> all = Map<dynamic, dynamic>.from(
            myRvSnap.value as Map,
          );
          for (final dynamic k in all.keys) {
            final dynamic v = all[k];
            if (v is! Map) continue;
            final Map<dynamic, dynamic> rv = Map<dynamic, dynamic>.from(v);

            String rvCountry = '';
            String rvCity = '';
            try {
              if (rv['country'] is String) {
                rvCountry = (rv['country'] as String).trim().toLowerCase();
              }
              if (rv['restcountry'] is String && rvCountry.isEmpty) {
                rvCountry = (rv['restcountry'] as String).trim().toLowerCase();
              }
            } catch (_) {}
            try {
              if (rv['city'] is String) {
                rvCity = (rv['city'] as String).trim().toLowerCase();
              }
              if (rv['restcity'] is String && rvCity.isEmpty) {
                rvCity = (rv['restcity'] as String).trim().toLowerCase();
              }
            } catch (_) {}

            final String keyStr = k.toString();
            // Skip excluded keys configured in ReviewReviewsScreen
            if (excludedKeys.contains(keyStr)) {
              continue;
            }

            // Check if review matches ANY filter (OR logic)
            bool matchesAnyFilter = false;
            for (final Map<String, String?> filter in filters) {
              final String fCountry = (filter['country'] ?? '')
                  .trim()
                  .toLowerCase();
              final String fCity = (filter['city'] ?? '').trim().toLowerCase();

              // Country must match if specified
              if (fCountry.isNotEmpty && rvCountry != fCountry) {
                continue;
              }
              // City must match if specified
              if (fCity.isNotEmpty && rvCity != fCity) {
                continue;
              }
              // If we get here, this filter matches
              matchesAnyFilter = true;
              break;
            }

            if (matchesAnyFilter) {
              totalMatches += 1;
              if (toProvide.length < 50) {
                final Map<dynamic, dynamic> item = Map<dynamic, dynamic>.from(
                  rv,
                );
                item['key'] = keyStr;
                toProvide.add(item);
              }
            }
          }
        }
      } catch (e) {
        appLog('Error gathering reviews to provide: $e');
        if (mounted) {
          setState(() {
            _accepting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStr.errorGatheringReviews)),
          );
        }
        return;
      }

      // If zero matches, cannot accept — inform user and abort
      if (totalMatches == 0) {
        if (mounted) {
          setState(() {
            _accepting = false;
          });
          showDialog<void>(
            context: context,
            builder: (BuildContext ctx) {
              return AlertDialog(
                title: const Text(AppStr.reviewReviewsTitle),
                content: const Text(
                  'No matching reviews found; cannot accept this request.',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(AppStr.ok),
                  ),
                ],
              );
            },
          );
        }
        return;
      }

      // If there are more than 50 matches, the toProvide list contains the first 50.
      // Show a combined dialog to collect provider comment and confirm sending.
      // First, check if a provider comment was already saved on the
      // review-details screen at users/<me>/friends/<friendUid>/review_request/providerComment.
      // If found, prefer that value and skip prompting the user again.
      String? dialogResult;
      try {
        final String pcPath =
            'users/$myUid/friends/${selected.uid}/review_request/providerComment';
        final DataSnapshot pcSnap = await FirebaseDatabase.instance
            .ref(pcPath)
            .get();
        if (pcSnap.exists &&
            pcSnap.value is String &&
            (pcSnap.value as String).trim().isNotEmpty) {
          dialogResult = (pcSnap.value as String).trim();
          // Enforce 40 char limit (trim if necessary)
          if (dialogResult.length > 40) {
            dialogResult = dialogResult.substring(0, 40);
          }
        }
      } catch (e) {
        // ignore read errors and fall back to empty
        dialogResult = null;
      }

      // If no stored comment is present, use an empty provider comment
      // (do not prompt the user here — the review-request-details screen is the place to edit it).
      dialogResult ??= '';

      // Confirm sending with user
      if (mounted) {
        final bool? confirmSend = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: Text(AppStr.accept),
              content: Text(AppStr.sendNReviews(toProvide.length)),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text(AppStr.noLabel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(AppStr.yes),
                ),
              ],
            );
          },
        );
        if (confirmSend != true) {
          setState(() {
            _accepting = false;
          });
          return;
        }
      }

      // Build and perform update
      try {
        final DatabaseReference rootRef = FirebaseDatabase.instance.ref();
        final Map<String, dynamic> updates = await buildProvideUpdate(
          rootRef: rootRef,
          providerUid: me,
          requesterUid: selected.uid,
          reviews: toProvide,
        );

        await performProvide(rootRef: rootRef, updates: updates);

        // PHASE 5: Write audit event for review request acceptance
        await writeFriendEvent(
          eventType: 'review_request_accepted',
          actorUid: me,
          targetUid: selected.uid,
          metadata: <String, dynamic>{
            'reviewCount': toProvide.length,
          },
        );

        // Post-write confirmation: read the exact meta node and extract rqCount
        int providedCount = 0;
        try {
          String? metaKeyPath;
          for (final String k in updates.keys) {
            if (k.endsWith('/meta')) {
              metaKeyPath = k; // this is the full DB path to the meta node
              break;
            }
          }
          if (metaKeyPath != null) {
            final DataSnapshot metaSnap = await rootRef
                .child(metaKeyPath)
                .get();
            if (metaSnap.exists && metaSnap.value != null) {
              try {
                final Map<dynamic, dynamic> metaMap =
                    Map<dynamic, dynamic>.from(metaSnap.value as Map);
                // prefer 'rqCount' then legacy 'count'
                providedCount = (metaMap['rqCount'] is int)
                    ? metaMap['rqCount'] as int
                    : ((metaMap['count'] is int) ? metaMap['count'] as int : 0);
              } catch (e) {
                // Silently handle error
              }
            }
          }
        } catch (e) {
          // Silently handle error
        }

        if (mounted) {
          setState(() {
            selected.fsc =
                statusAccepted; // Provider goes back to FRIEND status immediately
            selected.accepted = true;
            selected.review = null;
            selected.reviewRequest = null;
            selected.comment = dialogResult;
            _selectedUid = null;
            _accepting = false;
          });
          // Reviews have been delivered directly to requester's reviews_requested
          // Mailbox notification with statusCode=5 has been sent to requester
          if (!mounted) return;
          final String infoMsg =
              'Request accepted - $providedCount reviews provided';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(infoMsg)));
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            _accepting = false;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(AppStr.requestSendFailed)));
        }
        return;
      }
    }
    bool success = false;
    String snackbarMsg = AppStr.requestSendFailed;

    try {
      final DatabaseReference rootRef = FirebaseDatabase.instance.ref();

      final String actorEmail = currentUser?.email ?? '';
      final String actorDisplayName = currentUser?.displayName ?? '';
      final String actorPublicEmail = currentUser?.email ?? '';

      final String friendDisplayName = selected.username;
      final String friendPublicEmail = selected.email;

      final Map<String, dynamic> updates = await buildAcceptUpdateMap(
        rootRef: rootRef,
        actorUid: me,
        friendUid: selected.uid,
        actorEmail: actorEmail,
        mailboxReqId: selected.mailboxReqId,
        mailboxNormalized: selected.mailboxNormalized,
        actorDisplayName: actorDisplayName,
        actorPublicEmail: actorPublicEmail,
        friendDisplayName: friendDisplayName,
        friendPublicEmail: friendPublicEmail,
      );

      // PHASE 5: Write audit event for friend request acceptance
      await writeFriendEvent(
        eventType: 'friend_request_accepted',
        actorUid: me,
        targetUid: selected.uid,
      );

      // Remove the review_request subnode after acceptance
      updates['users/$me/friends/${selected.uid}/review_request'] = null;

      await rootRef.update(updates);

      success = true;
      snackbarMsg = AppStr.accept;
    } catch (_) {
      snackbarMsg = AppStr.requestSendFailed;
    }

    if (!mounted) {
      return;
    }

    if (success) {
      final String? sel = _selectedUid;
      if (sel != null) {
        final FriendEntry? reloaded = _friendByUid[sel];
        if (reloaded != null) {
          setState(() {
            reloaded.fsc = statusAccepted;
            reloaded.accepted = true;
            reloaded.review = null;
            reloaded.reviewRequest = null;
            _selectedUid = null;
          });
          await _fetchAndPatchProfile(sel);
        }
      }
    }

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text(snackbarMsg)));
      setState(() {
        _accepting = false;
      });
    }
  }

  Future<void> _handleDecline() async {
    if (_selectedUid == null) {
      return;
    }
    final FriendEntry? selected = _friendByUid[_selectedUid];
    if (selected == null) {
      return;
    }
    if (!selected.isActionableByMe) {
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String me = currentUser?.uid ?? '';
    if (me.isEmpty) {
      return;
    }

    // PHASE 0: Retraction placeholder for statusCode 0 (FR-ASKED) and 4 (RV-ASKED)
    if (selected.fsc == statusRequesterSent || selected.fsc == statusRvAsked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.featureNotAvailable)),
        );
      }
      return;
    }

    setState(() {
      _declining = true;
    });

    // If this is a review request (recipient wants reviews), decline it
    if (selected.fsc == statusRvWants) {
      appLog('DEBUG: Declining review request from ${selected.uid}');

      if (!mounted) {
        setState(() {
          _declining = false;
        });
        return;
      }

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text(AppStr.declineReviewRequestTitle),
            content: const Text('Decline review request?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(AppStr.noLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(AppStr.yes),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        setState(() {
          _declining = false;
        });
        return;
      }

      bool success = false;
      String snackbarMsg = AppStr.requestSendFailed;

      try {
        // Get requester's email for the mailbox
        String requesterEmail = selected.email;
        if (requesterEmail.isEmpty) {
          throw Exception('Requester email not available');
        }

        // Normalize the requester's email for mailbox path
        final String normalizedMailbox = normalizeEmailForPath(requesterEmail);

        // Generate a request ID
        final String requestId = DateTime.now().millisecondsSinceEpoch
            .toString();
        final String nowIso = DateTime.now().toUtc().toIso8601String();

        final String providerMessage = '';

        // Build atomic update
        final Map<String, dynamic> updates = <String, dynamic>{};

        // Create request record in requester's users_by_email mailbox with status code 6
        final String requestBasePath =
            'users_by_email/$normalizedMailbox/requests/$requestId';
        updates['$requestBasePath/fromUid'] = me;
        updates['$requestBasePath/statusCode'] = 6;
        updates['$requestBasePath/createdAt'] = nowIso;
        updates['$requestBasePath/clientRequestId'] = requestId;
        updates['$requestBasePath/type'] = 'review_declined';
        updates['$requestBasePath/meta'] = <String, dynamic>{
          'provider-message': providerMessage,
          'providerUid': me,
          'declinedAt': nowIso,
        };

        // Reset provider's (my) friend stub to status code 1 (FRIEND)
        updates['users/$me/friends/${selected.uid}/statusCode'] = 1;
        updates['users/$me/friends/${selected.uid}/review_request'] = null;
        updates['users/$me/friends/${selected.uid}/comment'] = null;
        updates['users/$me/friends/${selected.uid}/updatedAt'] = nowIso;

        await FirebaseDatabase.instance.ref().update(updates);
        
        // PHASE 5: Write audit event for review request decline
        await writeFriendEvent(
          eventType: 'review_request_declined',
          actorUid: me,
          targetUid: selected.uid,
          metadata: <String, dynamic>{
            'providerMessage': providerMessage,
          },
        );
        
        appLog('DEBUG: Review request declined successfully');
        success = true;
        snackbarMsg = AppStr.reviewRequestDeclined;
      } catch (e) {
        appLog('Error declining review request: $e');
        snackbarMsg = AppStr.requestSendFailed;
      }

      if (!mounted) {
        return;
      }

      if (success) {
        final FriendEntry? reloaded = _friendByUid[_selectedUid];
        if (reloaded != null) {
          setState(() {
            reloaded.fsc = statusAccepted;
            reloaded.reviewRequest = null;
            _selectedUid = null;
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(snackbarMsg)));
        setState(() {
          _declining = false;
        });
      }
      return;
    }

    // PHASE 4: Handle decline for established friends (statusCode=1)
    if (selected.fsc == statusAccepted) {
      appLog('DEBUG: Declining established friend ${selected.uid}');

      // Show confirmation dialog for established friend decline
      if (mounted) {
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: Text(AppStr.declineEstablishedFriendTitle),
              content: Text(
                AppStr.declineEstablishedFriendMessage,
                style: AppFonts.standard,
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(AppStr.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(AppStr.decline),
                ),
              ],
            );
          },
        );

        if (confirmed != true) {
          setState(() {
            _declining = false;
          });
          return;
        }
      }

      bool success = false;
      String snackbarMsg = AppStr.requestSendFailed;

      try {
        final String nowIso = DateTime.now().toUtc().toIso8601String();
        final String friendEmail = selected.email;
        
        // Normalize friend's email for mailbox
        final String normalizedMailbox = normalizeEmailForPath(friendEmail);
        final String requestId = DateTime.now().millisecondsSinceEpoch.toString();
        
        appLog('DECLINE DEBUG: Instigator=$me declining friend=${selected.uid}');
        
        // Build atomic update
        final Map<String, dynamic> updates = <String, dynamic>{};
        
        // Update my friend stub to statusCode=9 (instigator of decline)
        updates['users/$me/friends/${selected.uid}/statusCode'] = 9;
        updates['users/$me/friends/${selected.uid}/updatedAt'] = nowIso;
        
        // Directly update the friend's stub to statusCode=8 so they see it immediately
        // (Firebase rules allow this: auth.uid === $friendUid for their entry)
        updates['users/${selected.uid}/friends/$me/statusCode'] = 8;
        updates['users/${selected.uid}/friends/$me/accepted'] = false;
        updates['users/${selected.uid}/friends/$me/updatedAt'] = nowIso;
        
        appLog('DECLINE DEBUG: Setting users/$me/friends/${selected.uid}/statusCode = 9');
        
        // Create statusCode=8 mailbox entry for friend (recipient of decline)
        final String requestBasePath = 'users_by_email/$normalizedMailbox/requests/$requestId';
        updates['$requestBasePath/fromUid'] = me;
        updates['$requestBasePath/statusCode'] = 8;
        updates['$requestBasePath/createdAt'] = nowIso;
        updates['$requestBasePath/clientRequestId'] = requestId;
        updates['$requestBasePath/type'] = 'established_friend_declined';
        
        appLog('DECLINE DEBUG: Creating statusCode=8 mailbox for friend at $normalizedMailbox');
        
        await FirebaseDatabase.instance.ref().update(updates);
        
        appLog('DECLINE DEBUG: Database update completed successfully');
        
        // Write audit event
        await writeFriendEvent(
          eventType: 'established_friend_declined',
          actorUid: me,
          targetUid: selected.uid,
        );
        
        success = true;
        snackbarMsg = AppStr.friendDeclined;
      } catch (e) {
        appLog('Error declining established friend: $e');
        snackbarMsg = AppStr.requestSendFailed;
      }

      if (!mounted) {
        return;
      }

      if (success) {
        final FriendEntry? reloaded = _friendByUid[_selectedUid];
        if (reloaded != null) {
          setState(() {
            reloaded.fsc = statusFriendDeleted; // statusCode=9
            _selectedUid = null;
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(snackbarMsg)),
        );
        setState(() {
          _declining = false;
        });
      }
      return;
    }

    // Handle regular friend request decline (statusCode=2)
    bool success = false;
    String snackbarMsg = AppStr.requestSendFailed;

    try {
      final DatabaseReference rootRef = FirebaseDatabase.instance.ref();
      final String actorEmail = currentUser?.email ?? '';
      final String actorDisplayName = currentUser?.displayName ?? '';
      final String actorPublicEmail = currentUser?.email ?? '';

      final String friendDisplayName = selected.username;
      final String friendPublicEmail = selected.email;

      final Map<String, dynamic> updates = await buildRejectUpdateMap(
        rootRef: rootRef,
        actorUid: me,
        friendUid: selected.uid,
        actorEmail: actorEmail,
        mailboxReqId: selected.mailboxReqId,
        mailboxNormalized: selected.mailboxNormalized,
        friendDisplayName: friendDisplayName,
        friendPublicEmail: friendPublicEmail,
        actorDisplayName: actorDisplayName,
        actorPublicEmail: actorPublicEmail,
      );

      updates['users/$me/friends/${selected.uid}/review'] = null;

      if (selected.mailboxNormalized != null &&
          selected.mailboxNormalized!.isNotEmpty &&
          selected.mailboxReqId != null &&
          selected.mailboxReqId!.isNotEmpty) {
        final String mailboxPath =
            'users_by_email/${selected.mailboxNormalized}/requests/${selected.mailboxReqId}';
        updates[mailboxPath] = null;
      }

      await rootRef.update(updates);
      
      // PHASE 5: Write audit event for friend request decline
      await writeFriendEvent(
        eventType: 'friend_request_declined',
        actorUid: me,
        targetUid: selected.uid,
      );
      
      success = true;
      snackbarMsg = AppStr.declinedLabel;
    } catch (_) {
      snackbarMsg = AppStr.requestSendFailed;
    }

    if (!mounted) {
      return;
    }
    if (success) {
      final FriendEntry? reloaded = _friendByUid[_selectedUid];
      if (reloaded != null) {
        setState(() {
          reloaded.fsc = statusFriendDeleted; // Actor declines: they are the instigator (statusCode=9)
          reloaded.review = null;
          _selectedUid = null;
        });
      }
    }
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text(snackbarMsg)));
      setState(() {
        _declining = false;
      });
    }
  }

  Future<void> _handleDelete() async {
    if (_selectedUid == null) {
      return;
    }
    final FriendEntry? selected = _friendByUid[_selectedUid];
    if (selected == null) {
      return;
    }

    // RETRACTION: pk3 deletes their own outgoing FR-ASKED (statusCode=0)
    // Sends statusCode=8 to pk1's mailbox so pk1's stub becomes "declined"
    if (selected.fsc == statusRequesterSent) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(AppStr.deleteFriendTitle, style: AppFonts.bold),
            content: Text(AppStr.retractFriendRequest, style: AppFonts.standard),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
child: Text(AppStr.noLabel, style: AppFonts.standard),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStr.yes, style: AppFonts.standard),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;

      final User? currentUser = FirebaseAuth.instance.currentUser;
      final String me = currentUser?.uid ?? '';
      if (me.isEmpty) return;

      setState(() { _deleting = true; });

      final String friendUid = selected.uid;
      try {
        final String nowIso = DateTime.now().toUtc().toIso8601String();
        final String? friendNormalized = selected.email.isNotEmpty
            ? normalizeEmailForPath(selected.email.toLowerCase())
            : null;

        // Delete own stub
        await FirebaseDatabase.instance.ref('users/$me/friends/$friendUid').remove();

        // Clean any mailbox entries we sent to the friend (the original FR)
        // MUST happen BEFORE pushing the statusCode=8 notification — otherwise
        // the cleanup loop would delete the retraction notification it just wrote.
        String? myNormalized;
        final String? myEmail2 = currentUser?.email;
        if (myEmail2 != null && myEmail2.isNotEmpty) {
          myNormalized = normalizeEmailForPath(myEmail2.toLowerCase());
        }
        if (friendNormalized != null && friendNormalized.isNotEmpty) {
          // Remove entries from friend's mailbox that came from us
          final DataSnapshot mbSnap = await FirebaseDatabase.instance
              .ref('users_by_email/$friendNormalized/requests')
              .get();
          if (mbSnap.exists && mbSnap.value is Map) {
            final Map<dynamic, dynamic> mbMap =
                Map<dynamic, dynamic>.from(mbSnap.value as Map);
            for (final dynamic key in mbMap.keys) {
              final dynamic val = mbMap[key];
              if (val is Map) {
                final Map<dynamic, dynamic> v =
                    Map<dynamic, dynamic>.from(val);
                if (v['fromUid']?.toString() == me) {
                  await FirebaseDatabase.instance
                      .ref('users_by_email/$friendNormalized/requests/$key')
                      .remove();
                }
              }
            }
          }
        }

        // Now send statusCode=8 to pk1's mailbox so their FR-WANTED becomes "declined"
        if (friendNormalized != null && friendNormalized.isNotEmpty) {
          final String myEmail = currentUser?.email ?? me;
          final DatabaseReference notificationRef = FirebaseDatabase.instance
              .ref('users_by_email/$friendNormalized/requests')
              .push();
          await notificationRef.set(<String, dynamic>{
            'statusCode': 8,
            'fromUid': me,
            'type': 'friend_request_retracted',
            'email': myEmail,
            'createdAt': nowIso,
            'clientRequestId': notificationRef.key ?? nowIso,
          });
        }
        if (myNormalized != null && myNormalized.isNotEmpty) {
          // Remove entries in our own mailbox that came from the friend
          final DataSnapshot myMbSnap = await FirebaseDatabase.instance
              .ref('users_by_email/$myNormalized/requests')
              .get();
          if (myMbSnap.exists && myMbSnap.value is Map) {
            final Map<dynamic, dynamic> myMbMap =
                Map<dynamic, dynamic>.from(myMbSnap.value as Map);
            for (final dynamic key in myMbMap.keys) {
              final dynamic val = myMbMap[key];
              if (val is Map) {
                final Map<dynamic, dynamic> v =
                    Map<dynamic, dynamic>.from(val);
                if (v['fromUid']?.toString() == friendUid) {
                  await FirebaseDatabase.instance
                      .ref('users_by_email/$myNormalized/requests/$key')
                      .remove();
                }
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _friendByUid.remove(friendUid);
            _friends
              ..clear()
              ..addAll(_friendByUid.values);
            _selectedUid = null;
            _deleting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStr.deleteSuccessPending)),
          );
        } else {
          _deleting = false;
        }
      } catch (e) {
        appLog('Error retracting friend request: $e');
        if (mounted) {
          setState(() { _deleting = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStr.deleteFailed)),
          );
        } else {
          _deleting = false;
        }
      }
      return;
    }

    // PHASE 3: Different confirmation messages for instigator (statusCode=9) vs recipient (statusCode=8)
    appLog('DELETE DEBUG: selected.fsc=${selected.fsc}, statusFriendDeleted=$statusFriendDeleted, statusDeclined=$statusDeclined');
    String confirmationMessage;
    if (selected.fsc == statusFriendDeleted) {
      // statusCode=9: Instigator of decline (you declined this friend)
      appLog('DELETE DEBUG: Matched statusCode=9 (instigator)');
      confirmationMessage = AppStr.deleteDeclinedFriendInstigator;
    } else if (selected.fsc == statusDeclined) {
      // statusCode=8: Recipient of decline (the friend declined your request)
      appLog('DELETE DEBUG: Matched statusCode=8 (recipient)');
      confirmationMessage = AppStr.deleteDeclinedFriendRecipient;
    } else {
      // Fallback (should not reach here due to button logic)
      appLog('DELETE DEBUG: Matched fallback condition');
      confirmationMessage = AppStr.deleteRelationshipFallback;
    }
    appLog('DELETE DEBUG: Using message: $confirmationMessage');

    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppStr.deleteFriendTitle, style: AppFonts.bold),
          content: Text(
            confirmationMessage,
            style: AppFonts.standard,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(AppStr.noLabel, style: AppFonts.standard),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(AppStr.yes, style: AppFonts.standard),
            ),
          ],
        );
      },
    );

    // If user didn't confirm, return without deleting
    if (confirmed != true) {
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String me = currentUser?.uid ?? '';

    setState(() {
      _deleting = true;
    });

    final String friendUid = selected.uid;

    final DatabaseReference rootRef = FirebaseDatabase.instance.ref();

    final Set<String> mailboxPaths = <String>{};
    bool parentAExists = false;
    bool parentBExists = false;

    try {
      try {
        final DataSnapshot aSnap = await rootRef
            .child('users/$me/friends/$friendUid')
            .get();
        if (aSnap.exists) {
          parentAExists = true;
        }
      } catch (_) {}
      try {
        final DataSnapshot bSnap = await rootRef
            .child('users/$friendUid/friends/$me')
            .get();
        if (bSnap.exists) {
          parentBExists = true;
        }
      } catch (_) {}

      String? friendNormalized;
      final String friendEmail = selected.email;
      if (friendEmail.isNotEmpty) {
        try {
          friendNormalized = normalizeEmailForPath(friendEmail.toLowerCase());
        } catch (_) {
          friendNormalized = null;
        }
      }

      String? myNormalized;
      String? myEmail = currentUser?.email;
      if (myEmail != null && myEmail.isNotEmpty) {
        try {
          myNormalized = normalizeEmailForPath(myEmail.toLowerCase());
        } catch (_) {
          myNormalized = null;
        }
      }

      Future<void> scanMailboxForFromUid(
        String normalized,
        String fromUid,
      ) async {
        try {
          final String mailboxRoot = 'users_by_email/$normalized/requests';
          final DataSnapshot mailboxSnap = await rootRef
              .child(mailboxRoot)
              .get();
          if (!mailboxSnap.exists ||
              mailboxSnap.value == null ||
              mailboxSnap.value is! Map) {
            return;
          }
          final Map<dynamic, dynamic> mailboxMap = Map<dynamic, dynamic>.from(
            mailboxSnap.value as Map,
          );
          for (final dynamic key in mailboxMap.keys) {
            final dynamic val = mailboxMap[key];
            if (val is Map) {
              final Map<dynamic, dynamic> v = Map<dynamic, dynamic>.from(val);
              final String? from = v['fromUid']?.toString();
              if (from != null && from == fromUid) {
                final String fullPath = '$mailboxRoot/$key';
                mailboxPaths.add(fullPath);
              }
            }
          }
        } catch (_) {}
      }

      if (friendNormalized != null &&
          friendNormalized.isNotEmpty &&
          me.isNotEmpty) {
        await scanMailboxForFromUid(friendNormalized, me);
      }
      if (myNormalized != null &&
          myNormalized.isNotEmpty &&
          friendUid.isNotEmpty) {
        await scanMailboxForFromUid(myNormalized, friendUid);
      }

      bool parentDeleteSucceeded = false;
      try {
        if (me.isNotEmpty && friendUid.isNotEmpty) {
          // Check if friend stub has auditEventId (for completing deletion audit)
          String? auditEventId;
          try {
            final DataSnapshot friendSnap = await FirebaseDatabase.instance
                .ref('users/$me/friends/$friendUid/auditEventId')
                .get();
            if (friendSnap.exists && friendSnap.value is String) {
              auditEventId = friendSnap.value as String;
            }
          } catch (e) {
            appLog('Error reading auditEventId: $e');
          }

          // If auditEventId exists, update the audit record to mark completion
          if (auditEventId != null && auditEventId.isNotEmpty) {
            try {
              final String nowIso = DateTime.now().toUtc().toIso8601String();
              await FirebaseDatabase.instance
                  .ref('audit_info/request_events/$auditEventId')
                  .update({
                'completedAt': nowIso,
                'completedBy': me,
                'status': 'completed',
              });
            } catch (e) {
              appLog('Warning: Could not update audit record: $e');
            }
          }

          // Delete both stubs atomically so the friend's list updates immediately.
          // Firebase rules allow the actor to delete their counterpart's entry
          // because auth.uid === $friendUid for the friend's path.
          await FirebaseDatabase.instance.ref().update(<String, dynamic>{
            'users/$me/friends/$friendUid': null,
            'users/$friendUid/friends/$me': null,
          });
          parentDeleteSucceeded = true;

          // PHASE 3: Write audit event using new audit system
          final String eventType = (selected.fsc == statusFriendDeleted)
              ? 'friend_deleted_by_instigator'  // statusCode=9: You declined this friend
              : 'friend_deleted_by_recipient';   // statusCode=8: Friend declined you
          
          await writeFriendEvent(
            eventType: eventType,
            actorUid: me,
            targetUid: friendUid,
            metadata: <String, dynamic>{
              'deletedStatusCode': selected.fsc,
            },
          );

          // Send status code 9 notification to the other user via their mailbox
          // ONLY if you're deleting statusCode=9 (you were the instigator of decline)
          // Don't send if you're deleting statusCode=8 (they declined you - they already know)
          if (selected.fsc == statusFriendDeleted && friendNormalized != null && friendNormalized.isNotEmpty) {
            try {
              final String nowIso = DateTime.now().toUtc().toIso8601String();
              final String myDisplayName =
                  currentUser?.displayName ?? myEmail ?? me;

              // Use push() to generate a unique key instead of potentially conflicting timestamp
              final DatabaseReference notificationRef = FirebaseDatabase
                  .instance
                  .ref('users_by_email/$friendNormalized/requests')
                  .push();

              await notificationRef.set({
                'statusCode': 9,
                'fromUid': me,
                'type': 'friend_deleted',
                'displayName': myDisplayName,
                'email': myEmail ?? me,
                'createdAt': nowIso,
                'clientRequestId': notificationRef.key ?? nowIso,
              });
            } catch (e) {
              // Non-fatal, continue with deletion
              appLog('Warning: Could not send deletion notification: $e');
            }
          }
        }
      } catch (_) {
        parentDeleteSucceeded = false;
      }

      int mailboxDeleted = 0;
      if (mailboxPaths.isNotEmpty) {
        // Delete mailbox entries individually instead of multi-path update
        for (final String p in mailboxPaths) {
          try {
            await FirebaseDatabase.instance.ref(p).remove();
            mailboxDeleted += 1;
          } catch (_) {
            // Continue even if one fails
          }
        }
      }

      int foundCount = 0;
      if (parentAExists) {
        foundCount += 1;
      }
      if (parentBExists) {
        foundCount += 1;
      }
      foundCount += mailboxPaths.length;

      int deletedParents = 0;
      if (parentDeleteSucceeded) {
        deletedParents = (parentAExists || parentBExists)
            ? (parentAExists && parentBExists ? 2 : 1)
            : 0;
      } else {
        try {
          final DataSnapshot a = await rootRef
              .child('users/$me/friends/$friendUid')
              .get();
          if (!a.exists) {
            deletedParents += 1;
          }
        } catch (_) {}
        try {
          final DataSnapshot b = await rootRef
              .child('users/$friendUid/friends/$me')
              .get();
          if (!b.exists) {
            deletedParents += 1;
          }
        } catch (_) {}
      }

      final int deletedCount = deletedParents + mailboxDeleted;

      if (mounted) {
        setState(() {
          _friendByUid.remove(friendUid);
          _friends
            ..clear()
            ..addAll(_friendByUid.values);
          _selectedUid = null;
          _deleting = false;
        });

        final String msg;
        if (foundCount == 0) {
          msg = AppStr.deleteSuccessPending;
        } else {
          msg = '${AppStr.deleteSuccessPending} $deletedCount of $foundCount';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        _deleting = false;
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.deleteFailed)));
      } else {
        _deleting = false;
      }
      return;
    }
  }

  void _onAddFriendPressed() {
    if (!widget.allowFriendRequests) {
      return;
    }

    if (_selectedUid == null) {
      Navigator.pushNamed(context, '/friend-request');
      return;
    }

    final FriendEntry? selected = _friendByUid[_selectedUid];
    if (selected == null) {
      Navigator.pushNamed(context, '/friend-request');
      return;
    }

    // If the selected friend is a recipient-side RV-WANTS request,
    // show the review request details screen instead of the normal flow.
    if (selected.fsc == statusRvWants) {
      // Pass the FriendEntry to the details screen. The details screen can fetch additional raw data if required.
      Navigator.pushNamed(
        context,
        '/review-request-details',
        arguments: <String, dynamic>{'friendEntry': selected},
      );
      return;
    }

    // Only allow statusCode=1 (FRIEND - accepted friends)
    if (selected.fsc != statusAccepted) {
      appLog('DEBUG: Early return - selected.fsc (${selected.fsc}) != statusAccepted (1)');
      return;
    }

    // For accepted friends, allow new review requests
    SessionCache.setPendingFriend(selected.email, selected.uid);

    Navigator.pushNamed(
      context,
      '/review-request',
      arguments: <String, dynamic>{
        'friendEmail': selected.email,
        'friendUid': selected.uid,
      },
    ).then((Object? res) async {
      if (res == true) {
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedUid = null;
        });
        try {
          await _fetchAndPatchProfile(selected.uid);
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final int accepted = _acceptedCount();
    final bool acceptEnabled =
        _selectedIsAcceptable() &&
        !_accepting &&
        !_declining &&
        !_deleting;

    // Decline button active for incoming requests, established friends, and retraction placeholders
    final bool declineEnabled =
        _selectedIsDeclinable() &&
        !_accepting &&
        !_declining &&
        !_deleting;

    final bool deleteEnabled =
        _selectedIsDeletable && !_deleting && !_accepting && !_declining;

    String addButtonLabel;
    if (_selectedUid == null) {
      addButtonLabel = AppStr.addFriend;
    } else {
      final FriendEntry? sel = _friendByUid[_selectedUid];
      if (sel != null && sel.fsc == statusRvWants) {
        addButtonLabel = AppStr.rvRequestLabel;
      } else {
        addButtonLabel = AppStr.addReviewsLabel;
      }
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: AppColors.darkGreen,
        title: Text(
          '${AppStr.friendsTitle}: ($accepted)',
          style: AppFonts.title.copyWith(color: AppColors.white),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _friends.isEmpty
                ? Center(
                    child: Text(
                      AppStr.noFriends,
                      style: AppFonts.standard.copyWith(
                        color: AppColors.mutedText,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _friends.length,
                    itemBuilder: (BuildContext context, int index) {
                      final FriendEntry f = _friends[index];
                      return GestureDetector(
                        onTap: () {
                          _toggleSelect(f.uid);
                        },
                        child: FriendRow(
                          entry: f,
                          selected: _selectedUid == f.uid,
                          onTap: () {
                            _toggleSelect(f.uid);
                          },
                        ),
                      );
                    },
                  ),
          ),

          FriendActions(
            acceptEnabled: acceptEnabled,
            declineEnabled: declineEnabled,
            deleteEnabled: deleteEnabled,
            accepting: _accepting,
            declining: _declining,
            deleting: _deleting,
            onAccept: _handleAccept,
            onDecline: _handleDecline,
            onDelete: _handleDelete,
            onBack: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const TopScreen()),
                (route) => false,
              );
            },
            onAddFriend: _onAddFriendPressed,
            addFriendLabel: addButtonLabel,
          ),
        ],
      ),
    );
  }
}

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
import 'top_screen.dart';
import 'services/session_cache.dart';
import 'sub_friends_screen/friend_entry.dart';
import 'sub_friends_screen/friend_row.dart';
import 'sub_friends_screen/friend_actions.dart';
import 'services/db_utils.dart';
import 'services/review_counter.dart';
import 'services/ube_provider.dart';
import 'services/accept_provided_reviews.dart';
import '/sub_friends_screen/friends_delete.dart';

// Canonical status codes
const int statusRequesterSent = 0; // FR-ASKED (requester)
const int statusAccepted = 1;
const int statusRequested = 2; // FR-WANTED (recipient)
const int statusRvWants = 3; // RV-WANTED (recipient)
const int statusRvAsked = 4; // RV-ASKED (requester)
const int statusProvided = 5; // provider has shared reviews (local marker)
const int statusRvDeclined =
    6; // provider declined review request (recipient marker)
const int statusDeclined = 8;
const int statusUnknown = 9;
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

  String? _selectedUid;
  bool _accepting = false;
  bool _declining = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _subscribeToFriends();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
                } else if (statusField is String) {
                  fsc = FriendEntry.mapStringStatusToFsc(statusField);
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
                    final List<Map<String, String?>> filters = <Map<String, String?>>[];
                    if (rrMap['filters'] is List) {
                      for (final dynamic filterItem in rrMap['filters'] as List) {
                        if (filterItem is Map) {
                          final Map<dynamic, dynamic> filterMap = Map<dynamic, dynamic>.from(filterItem);
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
            } catch (_) {
              // ignore parsing errors
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
        _loadProvidedReviewsMetadata(myUid);
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

      final Map<dynamic, dynamic> requestData = Map<dynamic, dynamic>.from(
        reviewRequestSnap.value as Map,
      );

      // Read filters array from review_request structure
      final List<Map<String, String?>> filters = <Map<String, String?>>[];
      try {
        if (requestData['filters'] is List) {
          final List<dynamic> filtersList = requestData['filters'] as List;
          for (final dynamic filterItem in filtersList) {
            if (filterItem is Map) {
              final Map<dynamic, dynamic> filterMap = Map<dynamic, dynamic>.from(filterItem);
              final String? country = filterMap['country']?.toString();
              final String? city = filterMap['city']?.toString();
              if (country != null && country.isNotEmpty) {
                filters.add(<String, String?>{
                  'country': country,
                  'city': (city == null || city.isEmpty || city == 'none') ? null : city,
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

  Future<void> _loadProvidedReviewsMetadata(String myUid) async {
    try {
      final String myEmail = FirebaseAuth.instance.currentUser?.email ?? '';
      if (myEmail.isEmpty) {
        return;
      }

      final Map<String, Map<String, dynamic>> metadata =
          await loadProvidedReviewsMetadata(myUid: myUid, myEmail: myEmail);

      if (!mounted) {
        return;
      }

      // Update friend entries with metadata
      bool updated = false;
      for (final MapEntry<String, Map<String, dynamic>> entry
          in metadata.entries) {
        final String providerUid = entry.key;
        final Map<String, dynamic> data = entry.value;

        final FriendEntry? friend = _friendByUid[providerUid];
        if (friend != null) {
          friend.providedRequestId = data['requestId'] as String?;
          friend.providedRqCount = data['rqCount'] as int?;
          friend.comment = data['providerMessage'] as String?;
          updated = true;
        }
      }

      if (updated && mounted) {
        setState(() {
          _friends
            ..clear()
            ..addAll(_friendByUid.values);
        });
      }
    } catch (e) {
      // Silently handle error
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

  bool _selectedIsActionableByStatus() {
    if (_selectedUid == null) {
      return false;
    }
    final FriendEntry? f = _friendByUid[_selectedUid];
    if (f == null) {
      return false;
    }

    // Check if status code is actionable
    final bool isActionableStatus =
        f.fsc == statusRequested ||
        f.fsc == statusRequesterSent ||
        f.fsc == statusRvAsked ||
        f.fsc == statusRvWants ||
        f.fsc == statusProvided ||
        f.fsc == statusRvDeclined;

    // If status code is 1 (accepted with no pending request), not actionable
    if (f.fsc == statusAccepted) {
      return false;
    }

    return isActionableStatus;
  }

  bool get _selectedIsDeletable {
    return (_selectedUid != null);
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
            SnackBar(content: Text('${AppStr.requestSendFailed}: $e')),
          );
        }
      }
      return;
    }

    // If this is accepting provided reviews (statusCode=5), relocate reviews and reset status
    if (selected.fsc == statusProvided) {
      try {
        final String myEmail = currentUser?.email ?? '';
        if (myEmail.isEmpty) {
          throw Exception('User email not available');
        }

        final String? requestId = selected.providedRequestId;
        if (requestId == null || requestId.isEmpty) {
          throw Exception('Request ID not found');
        }

        final AcceptProvidedReviewsResult result = await acceptProvidedReviews(
          myUid: me,
          myEmail: myEmail,
          providerUid: selected.uid,
          requestId: requestId,
        );

        if (!mounted) return;

        if (result.success) {
          setState(() {
            selected.fsc = statusAccepted;
            selected.accepted = true;
            selected.providedRequestId = null;
            selected.providedRqCount = null;
            selected.comment = null;
            selected.providedAt = null;
            _selectedUid = null;
            _accepting = false;
          });

          String message;
          if (result.reviewsAccepted > 0 && result.duplicatesSkipped > 0) {
            message = '${AppStr.accept} — accepted ${result.reviewsAccepted} review(s), ${result.duplicatesSkipped} duplicate(s) skipped';
          } else if (result.reviewsAccepted > 0) {
            message = '${AppStr.accept} — accepted ${result.reviewsAccepted} review(s)';
          } else if (result.duplicatesSkipped > 0) {
            message = '${AppStr.accept} — all ${result.duplicatesSkipped} review(s) already received';
          } else {
            message = '${AppStr.accept} — no reviews to accept';
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        } else {
          setState(() {
            _accepting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${AppStr.requestSendFailed}: ${result.errorMessage ?? "Unknown error"}',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _accepting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${AppStr.requestSendFailed}: $e')),
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

        final Map<dynamic, dynamic> requestData = Map<dynamic, dynamic>.from(
          reviewRequestSnap.value as Map,
        );

        // Read filters array from review_request structure
        final List<Map<String, String?>> filters = <Map<String, String?>>[];
        try {
          if (requestData['filters'] is List) {
            final List<dynamic> filtersList = requestData['filters'] as List;
            for (final dynamic filterItem in filtersList) {
              if (filterItem is Map) {
                final Map<dynamic, dynamic> filterMap = Map<dynamic, dynamic>.from(filterItem);
                final String? country = filterMap['country']?.toString();
                final String? city = filterMap['city']?.toString();
                if (country != null && country.isNotEmpty) {
                  filters.add(<String, String?>{
                    'country': country.trim(),
                    'city': (city == null || city.isEmpty || city == 'none') ? null : city.trim(),
                  });
                }
              }
            }
          }
        } catch (e) {
          // Error parsing filters
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
              final String fCountry = (filter['country'] ?? '').trim().toLowerCase();
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
                final Map<dynamic, dynamic> item = Map<dynamic, dynamic>.from(rv);
                item['key'] = keyStr;
                toProvide.add(item);
              }
            }
          }
        }
      } catch (e) {
        // Silently handle error
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
      // Build and perform update
      try {
        final DatabaseReference rootRef = FirebaseDatabase.instance.ref();
        final Map<String, dynamic> updates = await buildProvideUpdate(
          rootRef: rootRef,
          providerUid: me,
          requesterUid: selected.uid,
          reviews: toProvide,
          providerCommentShort: dialogResult,
        );

        await performProvide(rootRef: rootRef, updates: updates);

        // Post-write confirmation: read the exact meta node and extract rqCount/requestId
        String? requestId;
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
                // extract requestId from the metaKeyPath
                final List<String> parts = metaKeyPath.split('/');
                final int idx = parts.indexOf('requests');
                if (idx >= 0 && parts.length > idx + 1) {
                  requestId = parts[idx + 1];
                }
              } catch (e) {
                // Silently handle error
              }
            }
          }
        } catch (e) {
          // Silently handle error
        }

        final String nowIso = DateTime.now().toUtc().toIso8601String();
        if (mounted) {
          setState(() {
            selected.fsc = statusProvided;
            selected.accepted = true;
            selected.review = null;
            selected.providedRequestId = requestId;
            selected.providedRqCount = providedCount;
            selected.comment = dialogResult;
            selected.providedAt = nowIso;
            _selectedUid = null;
            _accepting = false;
          });
          // Note: The provider cannot delete the requester's mailbox entry due to permission rules.
          // The requester will handle their own mailbox cleanup when they accept the provided reviews.
          if (!mounted) return;
          final String infoMsg =
              '${AppStr.accept} — provided $providedCount review(s) (reqId=${requestId ?? 'unknown'})';
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

    setState(() {
      _declining = true;
    });

    // If this is declining provided reviews (statusCode=5), warn and delete
    if (selected.fsc == statusProvided) {
      // Show confirmation dialog
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: Text(AppStr.declineProvidedReviewsTitle),
            content: const Text(
              'This will permanently delete the provided reviews. This action cannot be undone.\n\nDo you want to decline these reviews?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(false);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(true);
                },
                child: const Text(
                  'Decline',
                  style: TextStyle(color: AppColors.red),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        // User cancelled
        setState(() {
          _declining = false;
        });
        return;
      }

      // User confirmed decline - proceed with deletion
      bool success = false;
      String snackbarMsg = AppStr.requestSendFailed;

      try {
        final String myEmail = currentUser?.email ?? '';
        if (myEmail.isEmpty) {
          throw Exception('User email not available');
        }

        // Get the mailbox request ID
        final String? requestId = selected.providedRequestId;
        if (requestId == null || requestId.isEmpty) {
          throw Exception('Request ID not available');
        }

        // Normalize my email for mailbox path
        final String normalizedMailbox = normalizeEmailForPath(myEmail);

        final String nowIso = DateTime.now().toUtc().toIso8601String();
        final Map<String, dynamic> updates = <String, dynamic>{};

        // Delete the request record in my mailbox (includes meta and reviews subnodes)
        final String mailboxRequestPath =
            'users_by_email/$normalizedMailbox/requests/$requestId';
        updates[mailboxRequestPath] = null;

        // Reset my friend stub to status code 1 (FRIEND)
        updates['users/$me/friends/${selected.uid}/statusCode'] = 1;
        updates['users/$me/friends/${selected.uid}/updatedAt'] = nowIso;

        await FirebaseDatabase.instance.ref().update(updates);
        success = true;
        snackbarMsg = 'Provided reviews declined';
      } catch (e) {
        snackbarMsg = '${AppStr.requestSendFailed}: $e';
      }

      if (!mounted) {
        return;
      }

      if (success) {
        final FriendEntry? reloaded = _friendByUid[_selectedUid];
        if (reloaded != null) {
          setState(() {
            reloaded.fsc = statusAccepted;
            reloaded.accepted = true;
            reloaded.providedRequestId = null;
            reloaded.providedRqCount = null;
            reloaded.comment = null;
            reloaded.providedAt = null;
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

    // If this is a review request (recipient wants reviews), decline it
    if (selected.fsc == statusRvWants) {
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

        // Read provider comment from friend stub (set on review_request_details_screen)
        String providerMessage = '';
        try {
          final String pcPath =
              'users/$me/friends/${selected.uid}/review_request/providerComment';
          final DataSnapshot pcSnap = await FirebaseDatabase.instance
              .ref(pcPath)
              .get();
          if (pcSnap.exists &&
              pcSnap.value is String &&
              (pcSnap.value as String).trim().isNotEmpty) {
            providerMessage = (pcSnap.value as String).trim();
          }
        } catch (_) {
          // If can't read, use empty string
        }

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
        success = true;
        snackbarMsg = 'Review request declined';
      } catch (e) {
        snackbarMsg = '${AppStr.requestSendFailed}: $e';
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
          reloaded.fsc =
              statusUnknown; // 9 - actor declines, sets to unknown/not interested
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

    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppStr.deleteFriendTitle, style: AppFonts.bold),
          content: Text(
            'Are you sure you want to delete this friend relationship?',
            style: AppFonts.standard,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text('No', style: AppFonts.standard),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text('Yes', style: AppFonts.standard),
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

      final FriendsDelete fd = FriendsDelete();
      bool parentDeleteSucceeded = false;
      try {
        if (me.isNotEmpty) {
          await fd.performFinalizeAndDelete(meUid: me, friendUid: friendUid);
          parentDeleteSucceeded = true;
        } else {
          final Map<String, dynamic> parentPatch = <String, dynamic>{
            'users/$me/friends/$friendUid': null,
            'users/$friendUid/friends/$me': null,
          };
          try {
            await rootRef.update(parentPatch);
            parentDeleteSucceeded = true;
          } catch (_) {
            parentDeleteSucceeded = false;
          }
        }
      } catch (_) {
        parentDeleteSucceeded = false;
      }

      int mailboxDeleted = 0;
      if (mailboxPaths.isNotEmpty) {
        final Map<String, dynamic> mailboxPatch = <String, dynamic>{};
        for (final String p in mailboxPaths) {
          mailboxPatch[p] = null;
        }
        try {
          await rootRef.update(mailboxPatch);
          for (final String p in mailboxPaths) {
            try {
              final DataSnapshot snap = await rootRef.child(p).get();
              if (!snap.exists) {
                mailboxDeleted += 1;
              }
            } catch (_) {}
          }
        } catch (_) {
          mailboxDeleted = 0;
          for (final String p in mailboxPaths) {
            try {
              await rootRef.child(p).remove();
              try {
                final DataSnapshot snap = await rootRef.child(p).get();
                if (!snap.exists) {
                  mailboxDeleted += 1;
                }
              } catch (_) {}
            } catch (_) {}
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
        _selectedIsActionableByStatus() &&
        !_accepting &&
        !_declining &&
        !_deleting;

    // Decline button should not be active for RV-DECLINED status (no concept of declining a decline)
    bool declineEnabled =
        _selectedIsActionableByStatus() &&
        !_accepting &&
        !_declining &&
        !_deleting;
    if (_selectedUid != null) {
      final FriendEntry? selected = _friendByUid[_selectedUid];
      if (selected != null && selected.fsc == statusRvDeclined) {
        declineEnabled = false;
      }
    }

    final bool deleteEnabled =
        _selectedIsDeletable && !_deleting && !_accepting && !_declining;

    String addButtonLabel;
    if (_selectedUid == null) {
      addButtonLabel = '+Friend';
    } else {
      final FriendEntry? sel = _friendByUid[_selectedUid];
      if (sel != null && sel.fsc == statusRvWants) {
        addButtonLabel = 'RV-REQUEST';
      } else {
        addButtonLabel = '+Reviews';
      }
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: AppColors.darkGreen,
        title: Text(
          '${AppStr.friendsTitle}: ($accepted)',
          style: AppFonts.title.copyWith(color: Colors.white),
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

// lib/friends_screen.dart
// FriendsScreen — friend / review status handling and rvCount resolver.
// Lint-safe: all flow-control statements use braces and types are explicit.

import 'dart:async';
import 'package:flutter/material.dart';
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
import '/sub_friends_screen/friends_delete.dart';

// Canonical status codes
const int statusRequesterSent = 0; // FR-ASKED (requester)
const int statusAccepted = 1;
const int statusRequested = 2; // FR-WANTED (recipient)
const int statusRvWants = 3; // RV-WANTED (recipient)
const int statusRvAsked = 4; // RV-ASKED (requester)
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

    final DatabaseReference ref = FirebaseDatabase.instance.ref('users/$myUid/friends');
    _sub = ref.onValue.listen((DatabaseEvent event) async {
      final DataSnapshot snap = event.snapshot;
      final Map<String, FriendEntry> nextMap = <String, FriendEntry>{};
      final Map<String, Map<dynamic, dynamic>> rawFriendVmaps = <String, Map<dynamic, dynamic>>{};

      if (snap.exists && snap.value != null && snap.value is Map) {
        final Map<dynamic, dynamic> rawMap = Map<dynamic, dynamic>.from(snap.value as Map);
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

          try {
            if (val is int) {
              fsc = val;
            } else if (val is String) {
              fsc = FriendEntry.mapStringStatusToFsc(val);
            } else if (val is Map) {
              final Map<dynamic, dynamic> vmap = Map<dynamic, dynamic>.from(val);
              rawFriendVmaps[friendUid] = vmap;
              final dynamic statusField = vmap['status'] ?? vmap['statusCode'] ?? vmap['state'];
              if (statusField is int) {
                fsc = statusField;
              } else if (statusField is String) {
                fsc = FriendEntry.mapStringStatusToFsc(statusField);
              }

              if (vmap['email'] is String && (vmap['email'] as String).isNotEmpty) {
                email = vmap['email'] as String;
              }
              if (vmap['username'] is String && (vmap['username'] as String).isNotEmpty) {
                username = vmap['username'] as String;
              }
              if (vmap['sharedReviewsCount'] is int) {
                sharedCount = vmap['sharedReviewsCount'] as int;
              }
              if (vmap['comment'] is String && (vmap['comment'] as String).isNotEmpty) {
                comment = vmap['comment'] as String;
              }
              if (vmap['mailboxReqId'] is String && (vmap['mailboxReqId'] as String).isNotEmpty) {
                reqId = vmap['mailboxReqId'] as String;
              }
              if (vmap['mailboxNormalized'] is String && (vmap['mailboxNormalized'] as String).isNotEmpty) {
                normalized = vmap['mailboxNormalized'] as String;
              }
              if (vmap['accepted'] is bool) {
                acceptedFlag = vmap['accepted'] as bool;
              } else if (vmap['accepted'] is int) {
                acceptedFlag = (vmap['accepted'] as int) == 1;
              }
              if (vmap['rvCount'] is int) {
                rvCount = vmap['rvCount'] as int;
              }
              if (vmap['rvCountLastCheckedAt'] is String && (vmap['rvCountLastCheckedAt'] as String).isNotEmpty) {
                rvCountLastCheckedAt = vmap['rvCountLastCheckedAt'] as String;
              }

              try {
                if (vmap['review'] is Map) {
                  final Map<dynamic, dynamic> rvMap = Map<dynamic, dynamic>.from(vmap['review'] as Map);

                  final Map<String, String> filters = <String, String>{};
                  final dynamic f = rvMap['filters'];
                  if (f is Map) {
                    f.forEach((dynamic k, dynamic v2) {
                      if (k != null && v2 is String && v2.isNotEmpty) {
                        filters[k.toString()] = v2;
                      }
                    });
                  } else {
                    if (rvMap['country'] is String && (rvMap['country'] as String).isNotEmpty) {
                      filters['country'] = rvMap['country'] as String;
                    }
                    if (rvMap['cuisine'] is String && (rvMap['cuisine'] as String).isNotEmpty) {
                      filters['cuisine'] = rvMap['cuisine'] as String;
                    }
                    if (rvMap['city'] is String && (rvMap['city'] as String).isNotEmpty) {
                      filters['city'] = rvMap['city'] as String;
                    }
                  }

                  final Map<String, bool>? exKeys = (rvMap['exKeys'] is Map)
                      ? Map<String, bool>.from(rvMap['exKeys'] as Map).map((k, v2) => MapEntry(k.toString(), v2 == true))
                      : null;

                  final int? parsedRvCount =
                      (rvMap['rvCount'] is int) ? rvMap['rvCount'] as int : (rvMap['rvCount'] is String ? int.tryParse(rvMap['rvCount']) : null);
                  final int? parsedExCount = (rvMap['exCount'] is int) ? rvMap['exCount'] as int : null;

                  reviewData = ReviewData(
                    filters: filters,
                    comment: (rvMap['comment'] is String && (rvMap['comment'] as String).isNotEmpty) ? rvMap['comment'] as String : null,
                    rvCount: parsedRvCount,
                    exCount: parsedExCount,
                    exKeys: exKeys,
                    createdAt: (rvMap['createdAt'] is String) ? rvMap['createdAt'] as String : null,
                    updatedAt: (rvMap['updatedAt'] is String) ? rvMap['updatedAt'] as String : null,
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
            review: reviewData,
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
        if (FriendEntry.looksLikeUid(fe.email) && FriendEntry.looksLikeUid(fe.username)) {
          _fetchAndPatchProfile(fe.uid);
        }
      }

      _resolveMissingRvCounts(myUid, rawFriendVmaps);
    }, onError: (Object err, StackTrace? st) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
    });
  }

  void _resolveMissingRvCounts(String myUid, Map<String, Map<dynamic, dynamic>> rawFriendVmaps) {
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
      final String? lastChecked = fe.rvCountLastCheckedAt ?? fe.review?.updatedAt;
      bool needs = false;
      if (cur == null) {
        needs = true;
      } else if (cur == -1) {
        needs = true;
      } else if (lastChecked != null) {
        try {
          final DateTime then = DateTime.parse(lastChecked).toUtc();
          final DateTime now = DateTime.now().toUtc();
          if (now.difference(then).inSeconds >= rvCountTtlSeconds) {
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
      _resolveOneRvCount(myUid, friendUid, rawFriendVmaps[friendUid]).whenComplete(() {
        inFlight -= 1;
        scheduleNext();
      });
      scheduleNext();
    }

    scheduleNext();
  }

  Future<void> _resolveOneRvCount(String myUid, String friendUid, Map<dynamic, dynamic>? vmap) async {
    if (vmap == null) {
      return;
    }

    try {
      final dynamic reviewObj = vmap['review'];
      if (reviewObj == null || reviewObj is! Map) {
        return;
      }

      final Map<dynamic, dynamic> r = Map<dynamic, dynamic>.from(reviewObj);
      final Map<dynamic, dynamic> filtersMap = (r['filters'] is Map) ? Map<dynamic, dynamic>.from(r['filters'] as Map) : <dynamic, dynamic>{};

      String? country = (filtersMap['country'] is String) ? filtersMap['country'] as String : null;
      String? cuisine = (filtersMap['cuisine'] is String) ? filtersMap['cuisine'] as String : null;
      String? city = (filtersMap['city'] is String) ? filtersMap['city'] as String : null;

      country ??= (r['country'] is String) ? r['country'] as String : null;
      cuisine ??= (r['cuisine'] is String) ? r['cuisine'] as String : null;
      city ??= (r['city'] is String) ? r['city'] as String : null;

      if (country == null || country.trim().isEmpty) {
        return;
      }

      final String myUidNow = FirebaseAuth.instance.currentUser?.uid ?? '';
      final int found = await countMatchingReviews(ownerUid: myUidNow, country: country, cuisine: cuisine, city: city);

      if (found < 0) {
        return;
      }

      final int exCount = 0;
      final Map<String, bool> exKeysMap = <String, bool>{};

      final String nowIso = DateTime.now().toUtc().toIso8601String();

      final String reviewPath = 'users/$myUid/friends/$friendUid/review';
      final Map<String, dynamic> reviewPatch = <String, dynamic>{
        '$reviewPath/rvCount': found,
        '$reviewPath/exCount': exCount,
        '$reviewPath/exKeys': exKeysMap,
        '$reviewPath/updatedAt': nowIso,
      };

      try {
        await FirebaseDatabase.instance.ref().update(reviewPatch);
      } catch (_) {}

      if (!mounted) {
        return;
      }
      final FriendEntry? local = _friendByUid[friendUid];
      if (local == null) {
        return;
      }

      local.review ??= ReviewData(filters: <String, String>{});

      local.review!.rvCount = found;
      local.review!.exCount = exCount;
      local.review!.exKeys = exKeysMap;
      local.review!.updatedAt = nowIso;
      local.rvCount = found;
      local.rvCountLastCheckedAt = nowIso;

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
      if ((f.accepted ?? false) || f.fsc == statusAccepted || f.status == FriendStatus.accepted) {
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
    if (f.accepted == true || f.fsc == statusAccepted) {
      return false;
    }
    return f.fsc == statusRequested || f.fsc == statusRequesterSent || f.fsc == statusRvAsked || f.fsc == statusRvWants;
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
      final DataSnapshot pubSnap = await FirebaseDatabase.instance.ref('public_profiles/$friendUid').get();
      if (!pubSnap.exists || pubSnap.value == null) {
        return;
      }
      if (pubSnap.value is! Map) {
        return;
      }
      final Map<dynamic, dynamic> vmap = Map<dynamic, dynamic>.from(pubSnap.value as Map);

      final String? email = (vmap['email'] is String && (vmap['email'] as String).isNotEmpty) ? vmap['email'] as String : null;
      final String? username = (vmap['displayName'] is String && (vmap['displayName'] as String).isNotEmpty) ? vmap['displayName'] as String : null;
      final int? shared = (vmap['sharedReviewsCount'] is int) ? vmap['sharedReviewsCount'] as int : null;

      if (!mounted) {
        return;
      }
      final FriendEntry? current = _friendByUid[friendUid];
      if (current == null) {
        return;
      }

      bool localChanged = false;
      if (username != null && username.isNotEmpty && username != current.username) {
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
      if (username != null && username.isNotEmpty && username != current.username) {
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

      updates['users/$me/friends/${selected.uid}/review'] = null;

      if (selected.mailboxNormalized != null && selected.mailboxNormalized!.isNotEmpty && selected.mailboxReqId != null && selected.mailboxReqId!.isNotEmpty) {
        final String mailboxPath = 'users_by_email/${selected.mailboxNormalized}/requests/${selected.mailboxReqId}';
        updates[mailboxPath] = null;
      }

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

    bool success = false;
    String snackbarMsg = AppStr.requestSendFailed;

    try {
      final DatabaseReference rootRef = FirebaseDatabase.instance.ref();
      final String actorEmail = currentUser?.email ?? '';

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
      );

      updates['users/$me/friends/${selected.uid}/review'] = null;

      if (selected.mailboxNormalized != null && selected.mailboxNormalized!.isNotEmpty && selected.mailboxReqId != null && selected.mailboxReqId!.isNotEmpty) {
        final String mailboxPath = 'users_by_email/${selected.mailboxNormalized}/requests/${selected.mailboxReqId}';
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
          reloaded.fsc = statusDeclined;
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
        final DataSnapshot aSnap = await rootRef.child('users/$me/friends/$friendUid').get();
        if (aSnap.exists) {
          parentAExists = true;
        }
      } catch (_) {}
      try {
        final DataSnapshot bSnap = await rootRef.child('users/$friendUid/friends/$me').get();
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

      Future<void> scanMailboxForFromUid(String normalized, String fromUid) async {
        try {
          final String mailboxRoot = 'users_by_email/$normalized/requests';
          final DataSnapshot mailboxSnap = await rootRef.child(mailboxRoot).get();
          if (!mailboxSnap.exists || mailboxSnap.value == null || mailboxSnap.value is! Map) {
            return;
          }
          final Map<dynamic, dynamic> mailboxMap = Map<dynamic, dynamic>.from(mailboxSnap.value as Map);
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

      if (friendNormalized != null && friendNormalized.isNotEmpty && me.isNotEmpty) {
        await scanMailboxForFromUid(friendNormalized, me);
      }
      if (myNormalized != null && myNormalized.isNotEmpty && friendUid.isNotEmpty) {
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
        deletedParents = (parentAExists || parentBExists) ? (parentAExists && parentBExists ? 2 : 1) : 0;
      } else {
        try {
          final DataSnapshot a = await rootRef.child('users/$me/friends/$friendUid').get();
          if (!a.exists) {
            deletedParents += 1;
          }
        } catch (_) {}
        try {
          final DataSnapshot b = await rootRef.child('users/$friendUid/friends/$me').get();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        _deleting = false;
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.deleteFailed)));
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
        arguments: <String, dynamic>{
          'friendEntry': selected,
        },
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
    final bool acceptEnabled = _selectedIsActionableByStatus() && !_accepting && !_declining && !_deleting;
    final bool declineEnabled = _selectedIsActionableByStatus() && !_accepting && !_declining && !_deleting;
    final bool deleteEnabled = _selectedIsDeletable && !_deleting && !_accepting && !_declining;

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
        title: Text('${AppStr.friendsTitle}: ($accepted)', style: AppFonts.title.copyWith(color: Colors.white)),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _friends.isEmpty
                    ? Center(child: Text(AppStr.noFriends, style: AppFonts.standard.copyWith(color: AppColors.mutedText)))
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
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const TopScreen()), (route) => false);
            },
            onAddFriend: _onAddFriendPressed,
            addFriendLabel: addButtonLabel,
          ),
        ],
      ),
    );
  }
}

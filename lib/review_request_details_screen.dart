// lib/review_request_details_screen.dart
// ReviewRequestDetailsScreen — provider view of a received review request.
// Reads from users_by_email/<mailboxNormalized>/requests/<mailboxReqId> for filters, comment, rvCount and exCount/exKeys.
// Displays requester email/username (from FriendEntry) and allows provider to add a short single-line
// message. Action buttons pinned to the bottom. All user-facing text comes from AppStr.
// Pressing Review navigates to ReviewReviewsScreen to let the provider inspect and exclude reviews.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/strings.dart';
import 'constants/restiview_constants.dart';
import 'sub_friends_screen/friend_entry.dart';
import 'review_reviews_screen.dart';
import 'services/review_counter.dart';
import 'services/ube_provider.dart';
import 'services/friend_event_audit.dart';
import 'services/db_utils.dart';

class ReviewRequestDetailsScreen extends StatefulWidget {
  const ReviewRequestDetailsScreen({
    super.key,
    required this.friendEntry,
    this.friendVmap,
  });

  final FriendEntry friendEntry;
  final Map<dynamic, dynamic>? friendVmap;

  @override
  State<ReviewRequestDetailsScreen> createState() =>
      _ReviewRequestDetailsScreenState();
}

class _ReviewRequestDetailsScreenState
    extends State<ReviewRequestDetailsScreen> {
  bool _loading = false;
  bool _accepting = false;
  bool _declining = false;

  late final String _requesterEmail;
  late final String _requesterUsername;

  String? _requestComment;
  String? _country;
  String? _city;
  int? _rvCount;
  int? _exCount;
  List<String>? _exKeys;
  bool _includePhotos = false;
  List<Map<String, String?>> _filters = <Map<String, String?>>[];
  List<int> _filterCounts = <int>[];

  String get myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get friendUid => widget.friendEntry.uid;

  void _logCurrentState(String stage) {
    appLog(
      'DEBUG: ReviewRequestDetails[$stage] '
      'friendUid=$friendUid requesterEmail=$_requesterEmail '
      'rvCount=$_rvCount exCount=$_exCount includePhotos=$_includePhotos '
      'country=$_country city=$_city filters=$_filters exKeys=$_exKeys '
      'comment=$_requestComment filterCounts=$_filterCounts',
    );
  }

  @override
  void initState() {
    super.initState();
    _requesterEmail = widget.friendEntry.email;
    _requesterUsername = widget.friendEntry.username;
    appLog(
      'DEBUG: ReviewRequestDetails init friendEntry uid=$friendUid '
      'rvCount=${widget.friendEntry.rvCount} '
      'reviewRequest=${widget.friendEntry.reviewRequest != null}',
    );
    _applyFriendEntryFallback();
    _logCurrentState('after-fallback-init');
    _loadReviewSubnode();
  }

  @override
  void dispose() {
    super.dispose();
  }

  int? _parseIntValue(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  List<String> _parseStringCollection(dynamic value) {
    if (value is List) {
      return List<dynamic>.from(value)
          .map((dynamic e) => e?.toString() ?? '')
          .where((String s) => s.isNotEmpty)
          .toList();
    }
    if (value is Map) {
      final Map<dynamic, dynamic> mapValue = Map<dynamic, dynamic>.from(value);
      return mapValue.entries
          .map((MapEntry<dynamic, dynamic> entry) {
            final dynamic collectionValue = entry.value;
            if (collectionValue == null) {
              return entry.key?.toString() ?? '';
            }
            if (collectionValue is bool) {
              return collectionValue ? (entry.key?.toString() ?? '') : '';
            }
            final String text = collectionValue.toString();
            return text;
          })
          .where((String s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  List<Map<String, String?>> _parseFilters(dynamic rawFilters) {
    final List<Map<String, String?>> parsedFilters = <Map<String, String?>>[];

    Iterable<dynamic> items = const <dynamic>[];
    if (rawFilters is List) {
      items = rawFilters;
    } else if (rawFilters is Map) {
      final Map<dynamic, dynamic> mapFilters = Map<dynamic, dynamic>.from(rawFilters);
      items = mapFilters.values;
    }

    for (final dynamic filterItem in items) {
      if (filterItem is! Map) {
        continue;
      }

      final Map<dynamic, dynamic> fm = Map<dynamic, dynamic>.from(filterItem);
      final String? fc =
          (fm['country'] is String && (fm['country'] as String).trim().isNotEmpty)
          ? (fm['country'] as String).trim()
          : null;
      final String? fci =
          (fm['city'] is String && (fm['city'] as String).trim().isNotEmpty)
          ? (fm['city'] as String).trim()
          : null;

      if (fc != null || fci != null) {
        parsedFilters.add(<String, String?>{'country': fc, 'city': fci});
      }
    }

    return parsedFilters;
  }

  Map<dynamic, dynamic>? _extractReviewRequestMap(dynamic rawValue) {
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
      final Map<dynamic, dynamic> friendMap = Map<dynamic, dynamic>.from(nestedFriend);
      final dynamic nestedRequest = friendMap['review_request'];
      if (nestedRequest is Map) {
        appLog('DEBUG: review_request snapshot was parent friends map; unwrapping nested review_request for $friendUid');
        return Map<dynamic, dynamic>.from(nestedRequest);
      }
    }

    return asMap;
  }

  void _applyFriendEntryFallback() {
    final ReviewRequestData? fallback = widget.friendEntry.reviewRequest;
    if (fallback == null) {
      appLog('DEBUG: ReviewRequestDetails fallback missing on friendEntry');
      return;
    }

    appLog(
      'DEBUG: Applying friendEntry fallback '
      'rvCount=${widget.friendEntry.rvCount} '
      'comment=${fallback.requestComment} '
      'filters=${fallback.filters} '
      'legacyCountry=${fallback.filterCountry} '
      'legacyCity=${fallback.filterCity} '
      'exCount=${fallback.exCount} '
      'exKeys=${fallback.exKeys}',
    );

    _requestComment ??= fallback.requestComment;
    _country ??= fallback.filterCountry;
    _city ??= fallback.filterCity;
    _exCount ??= fallback.exCount ?? 0;
    _exKeys ??= fallback.exKeys != null
        ? List<String>.from(fallback.exKeys!)
        : <String>[];

    if (_filters.isEmpty && fallback.filters != null && fallback.filters!.isNotEmpty) {
      _filters = List<Map<String, String?>>.from(fallback.filters!);
    }

    _rvCount ??= widget.friendEntry.rvCount;
  }

  Future<void> _loadReviewSubnode() async {
    if (myUid.isEmpty) {
      appLog('DEBUG: ReviewRequestDetails load aborted because myUid is empty');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
    });

    Map<dynamic, dynamic>? reviewMap;
    try {
      // Read from friend stub's review_request subnode
      final DatabaseReference ref = FirebaseDatabase.instance.ref(
        'users/$myUid/friends/$friendUid/review_request',
      );
      final DataSnapshot snap = await ref.get();
      appLog(
        'DEBUG: review_request snapshot exists=${snap.exists} '
        'type=${snap.value.runtimeType} value=${snap.value}',
      );
      if (snap.exists && snap.value is Map) {
        reviewMap = _extractReviewRequestMap(snap.value);
        appLog('DEBUG: review_request map keys=${reviewMap?.keys.toList()}');
      }

      if (reviewMap != null) {
        // Read filter criteria from review_request structure
        final String? liveCountry = (reviewMap['filterCountry'] is String)
            ? reviewMap['filterCountry'] as String
            : null;
        final String? liveCity = (reviewMap['filterCity'] is String)
            ? reviewMap['filterCity'] as String
            : null;

        _country = liveCountry ?? _country;
        _city = liveCity ?? _city;

        // Convert 'none' to null for display
        if (_city == 'none') _city = null;

        final String? liveRequestComment =
            (reviewMap['requestComment'] is String &&
                (reviewMap['requestComment'] as String).isNotEmpty)
            ? reviewMap['requestComment'] as String
            : null;
        _requestComment = liveRequestComment ?? _requestComment;

        _rvCount = _parseIntValue(reviewMap['rvCount']) ?? _rvCount;
        _exCount = _parseIntValue(reviewMap['exCount']) ?? _exCount ?? 0;

        final List<String> parsedExKeys = _parseStringCollection(reviewMap['exKeys']);
        if (parsedExKeys.isNotEmpty) {
          _exKeys = parsedExKeys;
        } else {
          _exKeys ??= <String>[];
        }

        _includePhotos = reviewMap['includePhotos'] == true;

        // Parse filters array for per-filter count display
        final List<Map<String, String?>> parsedFilters = <Map<String, String?>>[];
        try {
          parsedFilters.addAll(_parseFilters(reviewMap['filters']));
        } catch (_) {
          // parsing error — keep parsedFilters empty
        }
        appLog(
          'DEBUG: Parsed review_request filters raw=${reviewMap['filters']} '
          'parsed=$parsedFilters',
        );
        // Legacy fallback: if no filters array, build from single country/city fields
        if (parsedFilters.isEmpty && (_country != null || _city != null)) {
          parsedFilters.add(<String, String?>{'country': _country, 'city': _city});
        }
        if (parsedFilters.isNotEmpty) {
          _filters = parsedFilters;
        }

        // Compute per-filter review counts
        final List<int> counts = <int>[];
        for (final Map<String, String?> f in _filters) {
          if (!mounted) {
            break;
          }
          final int c = await countMatchingReviews(
            ownerUid: myUid,
            filters: <Map<String, String?>>[f],
            excludeKeys: _exKeys?.toSet(),
          );
          counts.add(c);
        }
        _filterCounts = counts;
        _logCurrentState('after-live-read');
      } else {
        appLog('DEBUG: review_request live read returned null map; using friendEntry fallback');
        _applyFriendEntryFallback();
        _logCurrentState('after-null-live-read');
      }
    } catch (e) {
      appLog('DEBUG: review_request live read threw error: $e');
      _applyFriendEntryFallback();
      _logCurrentState('after-live-read-error');
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _onAccept() async {
    if (_loading || _accepting || _declining) return;

    final int exCount = _exCount ?? 0;
    final int approvedCount =
        (_rvCount != null && _rvCount! >= 0) ? (_rvCount! - exCount) : 0;

    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(AppStr.accept),
          content: Text(AppStr.sendNReviews(approvedCount)),
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

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _accepting = true;
    });

    final List<Map<dynamic, dynamic>> toProvide = <Map<dynamic, dynamic>>[];
    int totalMatches = 0;

    try {
      final Set<String> excludedKeys = <String>{};
      if (_exKeys != null) {
        excludedKeys.addAll(_exKeys!);
      }

      final DatabaseReference myReviewsRef =
          FirebaseDatabase.instance.ref('users/$myUid/reviews');
      final DataSnapshot myRvSnap = await myReviewsRef.get();

      if (myRvSnap.exists && myRvSnap.value != null && myRvSnap.value is Map) {
        final Map<dynamic, dynamic> all =
            Map<dynamic, dynamic>.from(myRvSnap.value as Map);
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
          if (excludedKeys.contains(keyStr)) continue;

          bool matchesAnyFilter = false;
          for (final Map<String, String?> filter in _filters) {
            final String fCountry =
                (filter['country'] ?? '').trim().toLowerCase();
            final String fCity = (filter['city'] ?? '').trim().toLowerCase();
            if (fCountry.isNotEmpty && rvCountry != fCountry) continue;
            if (fCity.isNotEmpty && rvCity != fCity) continue;
            matchesAnyFilter = true;
            break;
          }

          if (matchesAnyFilter) {
            totalMatches += 1;
            if (toProvide.length < 50) {
              final Map<dynamic, dynamic> item =
                  Map<dynamic, dynamic>.from(rv);
              item['key'] = keyStr;
              toProvide.add(item);
            }
          }
        }
      }
    } catch (e) {
      appLog('Error gathering reviews to accept: $e');
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
              content: const Text(AppStr.noMatchingReviewsCannotAccept),
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

    try {
      final DatabaseReference rootRef = FirebaseDatabase.instance.ref();
      final Map<String, dynamic> updates = await buildProvideUpdate(
        rootRef: rootRef,
        providerUid: myUid,
        requesterUid: friendUid,
        reviews: toProvide,
      );

      await performProvide(rootRef: rootRef, updates: updates);

      await writeFriendEvent(
        eventType: 'review_request_accepted',
        actorUid: myUid,
        targetUid: friendUid,
        metadata: <String, dynamic>{'reviewCount': toProvide.length},
      );

      final String nowIso = DateTime.now().toUtc().toIso8601String();
      await FirebaseDatabase.instance.ref().update(<String, dynamic>{
        'users/$myUid/friends/$friendUid/statusCode': 1,
        'users/$myUid/friends/$friendUid/review_request': null,
        'users/$myUid/friends/$friendUid/updatedAt': nowIso,
      });

      if (!mounted) return;
      final String infoMsg =
          'Request accepted - ${toProvide.length} reviews provided';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(infoMsg)));
      Navigator.of(context).pop();
    } catch (e) {
      appLog('Error performing accept: $e');
      if (mounted) {
        setState(() {
          _accepting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.requestSendFailed)),
        );
      }
    }
  }

  Future<void> _onDecline() async {
    if (_loading || _accepting || _declining) return;

    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(AppStr.declineReviewRequestTitle),
          content: const Text(AppStr.declineReviewRequestConfirm),
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

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _declining = true;
    });

    try {
      final String normalizedMailbox =
          normalizeEmailForPath(_requesterEmail.toLowerCase());
      final String requestId =
          DateTime.now().millisecondsSinceEpoch.toString();
      final String nowIso = DateTime.now().toUtc().toIso8601String();

      final Map<String, dynamic> updates = <String, dynamic>{};

      final String requestBasePath =
          'users_by_email/$normalizedMailbox/requests/$requestId';
      updates['$requestBasePath/fromUid'] = myUid;
      updates['$requestBasePath/statusCode'] = 6;
      updates['$requestBasePath/createdAt'] = nowIso;
      updates['$requestBasePath/clientRequestId'] = requestId;
      updates['$requestBasePath/type'] = 'review_declined';
      updates['$requestBasePath/meta'] = <String, dynamic>{
        'provider-message': '',
        'providerUid': myUid,
        'declinedAt': nowIso,
      };

      updates['users/$myUid/friends/$friendUid/statusCode'] = 1;
      updates['users/$myUid/friends/$friendUid/review_request'] = null;
      updates['users/$myUid/friends/$friendUid/comment'] = null;
      updates['users/$myUid/friends/$friendUid/updatedAt'] = nowIso;

      await FirebaseDatabase.instance.ref().update(updates);

      await writeFriendEvent(
        eventType: 'review_request_declined',
        actorUid: myUid,
        targetUid: friendUid,
        metadata: <String, dynamic>{'providerMessage': ''},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.reviewRequestDeclined)),
      );
      Navigator.of(context).pop();
    } catch (e) {
      appLog('Error declining review request: $e');
      if (mounted) {
        setState(() {
          _declining = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.requestSendFailed)),
        );
      }
    }
  }

  Future<void> _onBack() async {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
  // the following two actions were removed along with their buttons

  // FIX: await the pushed route result and reload the review subnode when returning
  Future<void> _onReview() async {
    if (!mounted) {
      return;
    }

    final Object? result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => ReviewReviewsScreen(
          friendUid: friendUid,
          friendEntryUid: friendUid,
          filters: <String, String?>{'country': _country, 'city': _city},
          filtersList: _filters,
          initialExKeys: _exKeys,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    // Accept/decline was performed — also pop the details screen to return to friends
    if (result == 'done') {
      Navigator.of(context).pop();
      return;
    }
    // Exclusion changes were saved — reload the review subnode and stay
    if (result == true) {
      await _loadReviewSubnode();
    }
  }

  Widget _buildFilterTable() {
    if (_filters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Text(AppStr.none, style: AppFonts.standard),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 4,
                child: Text(
                  AppStr.countryLabel,
                  style: AppFonts.smallHint.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  AppStr.cityLabel,
                  style: AppFonts.smallHint.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  AppStr.filterColReviews,
                  style: AppFonts.smallHint.copyWith(
                    color: AppColors.mutedText,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        for (int i = 0; i < _filters.length; i++)
          _buildFilterRow(
            _filters[i],
            i < _filterCounts.length ? _filterCounts[i] : null,
          ),
      ],
    );
  }

  Widget _buildFilterRow(Map<String, String?> filter, int? count) {
    final String country = (filter['country'] ?? '').trim();
    final String? city = filter['city'];
    final bool hasCity = city != null && city.trim().isNotEmpty;
    final String cityDisplay =
        hasCity ? city.trim() : AppStr.filterAllCities;
    final String countDisplay =
        (count == null || count < 0) ? AppStr.unknownCount : count.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              country.isEmpty ? AppStr.none : country,
              style: AppFonts.standard,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              cityDisplay,
              style: hasCity
                  ? AppFonts.standard
                  : AppFonts.standard.copyWith(color: AppColors.mutedText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              countDisplay,
              style: AppFonts.standard,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // Renders a summary row whose value column is right-aligned to match the
  // Reviews column in _buildFilterTable (flex 7 label + flex 2 value).
  Widget _buildTotalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 7,
            child: Text(
              label,
              style: AppFonts.smallHint.copyWith(color: AppColors.mutedText),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: AppFonts.standard,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String? value) {
    final String display = (value ?? '').trim().isEmpty ? AppStr.none : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: AppFonts.smallHint.copyWith(color: AppColors.mutedText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              display,
              style: AppFonts.standard,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String email = _requesterEmail;
    final String username = _requesterUsername;
    final String comment = _requestComment ?? '';
    final String rvCountText = (_rvCount != null && _rvCount! >= 0)
        ? _rvCount.toString()
        : AppStr.unknownCount;
    final int exCount = _exCount ?? 0;
    final String exCountText = exCount > 0 ? exCount.toString() : '0';
    final int approvedCount =
        (_rvCount != null && _rvCount! >= 0) ? (_rvCount! - exCount) : -1;
    final String approvedText =
        approvedCount >= 0 ? approvedCount.toString() : AppStr.unknownCount;

    // Match RatingsScreen shared button style so labels truncate the same way
    final ButtonStyle actionBtnBase = ElevatedButton.styleFrom(
      textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      minimumSize: const Size(0, 44),
    );

    final EdgeInsets horizontalBtnPadding = const EdgeInsets.symmetric(
      horizontal: 6.0,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStr.reviewRequestDetailsTitle,
          style: AppFonts.title.copyWith(color: AppColors.white),
        ),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 152.0),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildReadOnlyRow(AppStr.requestingEmail, email),
                    _buildReadOnlyRow(AppStr.requestingUsername, username),
                    _buildReadOnlyRow(AppStr.requestingComment, comment),
                    const SizedBox(height: 12.0),
                    Text(
                      AppStr.filtersLabel,
                      style: AppFonts.smallHint.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    _buildFilterTable(),
                    const SizedBox(height: 12.0),
                    _buildTotalRow(
                      AppStr.reviewMatchingCountLabel,
                      rvCountText,
                    ),
                    _buildTotalRow(
                      AppStr.reviewsApprovedLabel,
                      approvedText,
                    ),
                    _buildTotalRow(
                      AppStr.reviewsExcludedLabel,
                      exCountText,
                    ),
                    const SizedBox(height: 12.0),
                    Row(
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: Text(
                            AppStr.includePhotosLabel,
                            style: AppFonts.smallHint.copyWith(
                              color: AppColors.mutedText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 7,
                          child: Switch(value: _includePhotos, onChanged: null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24.0),
                  ],
                ),
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Container(
                  color: AppColors.beige,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Top row: Accept | Decline
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Padding(
                              padding: horizontalBtnPadding,
                              child: ElevatedButton(
                                onPressed: (_accepting || _declining)
                                    ? null
                                    : _onAccept,
                                style: actionBtnBase.copyWith(
                                  backgroundColor: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.green,
                                  ).backgroundColor,
                                  foregroundColor: ElevatedButton.styleFrom(
                                    foregroundColor: AppColors.white,
                                  ).foregroundColor,
                                ),
                                child: Text(
                                  AppStr.accept,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: horizontalBtnPadding,
                              child: ElevatedButton(
                                onPressed: (_accepting || _declining)
                                    ? null
                                    : _onDecline,
                                style: actionBtnBase.copyWith(
                                  backgroundColor: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.red,
                                  ).backgroundColor,
                                  foregroundColor: ElevatedButton.styleFrom(
                                    foregroundColor: AppColors.white,
                                  ).foregroundColor,
                                ),
                                child: Text(
                                  AppStr.declineLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      // Bottom row: Back | Review
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Padding(
                              padding: horizontalBtnPadding,
                              child: ElevatedButton(
                                onPressed: _onBack,
                                style: actionBtnBase.copyWith(
                                  backgroundColor: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.ochre,
                                  ).backgroundColor,
                                  foregroundColor: ElevatedButton.styleFrom(
                                    foregroundColor: AppColors.black,
                                  ).foregroundColor,
                                ),
                                child: Text(
                                  AppStr.backButtonLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
                              ),
                            ),
                          ),
                          // Accept/Reject buttons removed — they were stubs and non-functional
                          Expanded(
                            child: Padding(
                              padding: horizontalBtnPadding,
                              child: ElevatedButton(
                                onPressed: _onReview,
                                style: actionBtnBase.copyWith(
                                  backgroundColor: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.orange,
                                  ).backgroundColor,
                                  foregroundColor: ElevatedButton.styleFrom(
                                    foregroundColor: AppColors.white,
                                  ).foregroundColor,
                                ),
                                child: Text(
                                  AppStr.reviewButtonLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_loading || _accepting || _declining)
              Container(
                color: AppColors.overlayDefault,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

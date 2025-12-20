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
import 'sub_friends_screen/friend_entry.dart';
import 'review_reviews_screen.dart';

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
  final TextEditingController _providerCommentController =
      TextEditingController();

  bool _loading = false;

  late final String _requesterEmail;
  late final String _requesterUsername;

  String? _requestComment;
  String? _country;
  String? _city;
  int? _rvCount;
  int? _exCount;
  List<String>? _exKeys;
  bool _includePhotos = false;

  String get myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get friendUid => widget.friendEntry.uid;

  @override
  void initState() {
    super.initState();
    _requesterEmail = widget.friendEntry.email;
    _requesterUsername = widget.friendEntry.username;
    _loadReviewSubnode();
  }

  @override
  void dispose() {
    _providerCommentController.dispose();
    super.dispose();
  }

  Future<void> _loadReviewSubnode() async {
    if (myUid.isEmpty) {
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
      if (snap.exists && snap.value is Map) {
        reviewMap = Map<dynamic, dynamic>.from(snap.value as Map);
      }

      if (reviewMap != null) {
        // Read filter criteria from review_request structure
        _country = (reviewMap['filterCountry'] is String)
            ? reviewMap['filterCountry'] as String
            : null;
        _city = (reviewMap['filterCity'] is String)
            ? reviewMap['filterCity'] as String
            : null;

        // Convert 'none' to null for display
        if (_city == 'none') _city = null;

        _requestComment =
            (reviewMap['requestComment'] is String &&
                (reviewMap['requestComment'] as String).isNotEmpty)
            ? reviewMap['requestComment'] as String
            : null;

        if (reviewMap['rvCount'] is int) {
          _rvCount = reviewMap['rvCount'] as int;
        } else if (reviewMap['rvCount'] is String) {
          _rvCount = int.tryParse(reviewMap['rvCount'] as String);
        }

        if (reviewMap['exCount'] is int) {
          _exCount = reviewMap['exCount'] as int;
        } else if (reviewMap['exCount'] is String) {
          _exCount = int.tryParse(reviewMap['exCount'] as String);
        } else {
          _exCount = 0;
        }

        if (reviewMap['exKeys'] is List) {
          try {
            _exKeys = List<dynamic>.from(reviewMap['exKeys'] as List)
                .map((e) => e?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toList();
          } catch (_) {
            _exKeys = <String>[];
          }
        } else if (reviewMap['exKeys'] is Map) {
          final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(
            reviewMap['exKeys'] as Map,
          );
          _exKeys = <String>[];
          m.forEach((dynamic k, dynamic v) {
            if (k != null) {
              final String ks = k.toString();
              if (ks.isNotEmpty) {
                _exKeys!.add(ks);
              }
            }
          });
        } else {
          _exKeys = <String>[];
        }

        _includePhotos = reviewMap['includePhotos'] == true;
        // populate provider comment if present
        if (reviewMap['providerComment'] is String &&
            (reviewMap['providerComment'] as String).isNotEmpty) {
          _providerCommentController.text =
              reviewMap['providerComment'] as String;
        }
      } else {
        _country = null;
        _city = null;
        _requestComment = null;
        _rvCount = null;
        _exCount = 0;
        _exKeys = <String>[];
        _includePhotos = false;
      }
    } catch (_) {
      // keep defaults
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _onBack() async {
    // persist provider comment (trimmed) to the review_request subnode
    final String trimmed = _providerCommentController.text.trim();
    if (myUid.isNotEmpty) {
      final DatabaseReference ref = FirebaseDatabase.instance.ref();
      try {
        if (trimmed.isEmpty) {
          // remove the field by setting it to null
          await ref
              .child(
                'users/$myUid/friends/$friendUid/review_request/providerComment',
              )
              .set(null);
        } else {
          await ref
              .child(
                'users/$myUid/friends/$friendUid/review_request/providerComment',
              )
              .set(trimmed);
        }
      } catch (_) {
        // ignore write failure
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
  // the following two actions were removed along with their buttons

  // FIX: await the pushed route result and reload the review subnode when returning
  Future<void> _onReview() async {
    final Map<String, String?> filters = <String, String?>{
      'country': _country,
      'city': _city,
    };

    if (!mounted) {
      return;
    }

    // persist provider comment before navigating so it's available to the review screen
    final String trimmed = _providerCommentController.text.trim();
    if (myUid.isNotEmpty) {
      final DatabaseReference ref = FirebaseDatabase.instance.ref(
        'users/$myUid/friends/$friendUid/review_request/providerComment',
      );
      try {
        if (trimmed.isEmpty) {
          await ref.set(null);
        } else {
          await ref.set(trimmed);
        }
      } catch (_) {
        // ignore; navigation should still proceed
      }
    }

    if (!mounted) {
      return;
    }

    final bool? result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReviewReviewsScreen(
          friendUid: friendUid,
          friendEntryUid: friendUid,
          filters: filters,
          initialExKeys: _exKeys,
        ),
      ),
    );

    // Only reload the review subnode if the pushed screen indicated changes (true)
    if (!mounted) {
      return;
    }
    if (result == true) {
      await _loadReviewSubnode();
    }
  }

  String _displayOrNone(String? value) {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return AppStr.none;
    }
    return trimmed;
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
    final String country = _displayOrNone(_country);
    final String city = _displayOrNone(_city);
    final String rvCountText = (_rvCount != null && _rvCount! >= 0)
        ? _rvCount.toString()
        : AppStr.unknownCount;
    final String exCountText = (_exCount != null && _exCount! > 0)
        ? _exCount.toString()
        : '0';

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
              padding: const EdgeInsets.only(bottom: 96.0),
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
                    _buildReadOnlyRow(AppStr.countryLabel, country),
                    _buildReadOnlyRow(AppStr.cityLabel, city),
                    const SizedBox(height: 12.0),
                    _buildReadOnlyRow(
                      AppStr.reviewMatchingCountLabel,
                      rvCountText,
                    ),
                    const SizedBox(height: 6.0),
                    _buildReadOnlyRow(AppStr.excludedLabel, exCountText),
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
                    const SizedBox(height: 12.0),
                    Text(
                      AppStr.providerCommentLabel,
                      style: AppFonts.smallHint.copyWith(
                        color: AppColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    TextField(
                      controller: _providerCommentController,
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: AppStr.providerCommentHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12.0,
                          horizontal: 12.0,
                        ),
                      ),
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
                    vertical: 12.0,
                  ),
                  child: Row(
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
                                foregroundColor: Colors.black,
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
                                backgroundColor: Colors.orange,
                              ).backgroundColor,
                              foregroundColor: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
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
                ),
              ),
            ),

            if (_loading)
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

// lib/review_reviews_screen.dart
// ReviewReviewsScreen — show reviews that match a review-request filter and let provider
// exclude/include specific reviews before accepting a request. Saves exCount/exKeys back
// into users/<myUid>/friends/<friendUid>/review when navigating back.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/strings.dart';
import 'sub_preview_screen/review_context.dart';
import 'preview_screen.dart';

class ReviewReviewsScreen extends StatefulWidget {
  const ReviewReviewsScreen({
    super.key,
    required this.friendUid,
    required this.friendEntryUid,
    required this.filters, // expected map: {country, cuisine, city} — legacy; we will prefer friend review node
    this.initialExKeys,
  });

  // friendUid: the requester uid stored as friend record key under current user
  // friendEntryUid is the friend record owner uid as stored in users/<myUid>/friends/<friendUid>
  final String friendUid;
  final String friendEntryUid;
  final Map<String, String?> filters;
  final List<String>? initialExKeys;

  @override
  State<ReviewReviewsScreen> createState() => _ReviewReviewsScreenState();
}

class _ReviewReviewsScreenState extends State<ReviewReviewsScreen> {
  final List<Map<String, dynamic>> _reviews =
      <
        Map<String, dynamic>
      >[]; // each item contains at least 'key' and review fields
  final Set<String> _excludedKeys = <String>{};
  String? _selectedKey;
  bool _loading = true;
  bool _saving = false;

  String get myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.initialExKeys != null) {
      _excludedKeys.addAll(widget.initialExKeys!.where((e) => e.isNotEmpty));
    }
    _loadMatchingReviews();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Helper: normalize string for comparison (trim + lowercase)
  String _norm(String? s) => (s ?? '').trim().toLowerCase();

  // Helper: try multiple possible keys for a field and return first non-empty string
  String? _extractField(Map<dynamic, dynamic> rv, List<String> keys) {
    for (final String k in keys) {
      if (rv.containsKey(k) && rv[k] is String) {
        final String v = (rv[k] as String).trim();
        if (v.isNotEmpty) {
          return v;
        }
      }
    }
    return null;
  }

  // Load friend review filters (from users/<myUid>/friends/<friendUid>/review) then
  // load current user's reviews and filter client-side by those filters.
  Future<void> _loadMatchingReviews() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _reviews.clear();
      _selectedKey = null;
    });

    // Determine filters: prefer the friend's review subnode under current user's friends record.
    List<Map<String, String?>> filters = <Map<String, String?>>[];

    try {
      final DatabaseReference friendReviewRef = FirebaseDatabase.instance.ref(
        'users/$myUid/friends/${widget.friendUid}/review_request',
      );
      final DataSnapshot friendSnap = await friendReviewRef.get();
      if (friendSnap.exists &&
          friendSnap.value != null &&
          friendSnap.value is Map) {
        final Map<dynamic, dynamic> friendReview = Map<dynamic, dynamic>.from(
          friendSnap.value as Map,
        );

        // Read filters array from review_request structure
        if (friendReview['filters'] is List) {
          final List<dynamic> filtersList = friendReview['filters'] as List;
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
        
        // Fallback to legacy single filter if filters array is empty
        if (filters.isEmpty) {
          final String? countryFilter =
              (friendReview['filterCountry'] is String &&
                  (friendReview['filterCountry'] as String).trim().isNotEmpty)
              ? (friendReview['filterCountry'] as String).trim()
              : null;
          final String? cityFilter =
              (friendReview['filterCity'] is String &&
                  (friendReview['filterCity'] as String).trim().isNotEmpty)
              ? (friendReview['filterCity'] as String).trim()
              : null;
          
          if (countryFilter != null && countryFilter.isNotEmpty) {
            filters.add(<String, String?>{
              'country': countryFilter,
              'city': (cityFilter == 'none') ? null : cityFilter,
            });
          }
        }
      }
      
      // Fallback to widget.filters if still empty
      if (filters.isEmpty) {
        final String? countryFilter = (widget.filters['country'] ?? '').trim().isEmpty
            ? null
            : widget.filters['country']?.trim();
        final String? cityFilter = (widget.filters['city'] ?? '').trim().isEmpty
            ? null
            : widget.filters['city']?.trim();
        if (countryFilter != null && countryFilter.isNotEmpty) {
          filters.add(<String, String?>{
            'country': countryFilter,
            'city': cityFilter,
          });
        }
      }
    } catch (e) {
      // On error reading friend review node, fall back to widget.filters
      final String? countryFilter = (widget.filters['country'] ?? '').trim().isEmpty
          ? null
          : widget.filters['country']?.trim();
      final String? cityFilter = (widget.filters['city'] ?? '').trim().isEmpty
          ? null
          : widget.filters['city']?.trim();
      if (countryFilter != null && countryFilter.isNotEmpty) {
        filters.add(<String, String?>{
          'country': countryFilter,
          'city': cityFilter,
        });
      }
    }

    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref(
        'users/$myUid/reviews',
      );
      final DataSnapshot snap = await ref.get();
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }

      final Map<dynamic, dynamic> all = Map<dynamic, dynamic>.from(
        snap.value as Map,
      );

      final List<Map<String, dynamic>> found = <Map<String, dynamic>>[];
      all.forEach((dynamic k, dynamic v) {
        if (k == null || v == null) {
          return;
        }
        final String key = k.toString();
        if (v is! Map) {
          return;
        }
        final Map<dynamic, dynamic> rv = Map<dynamic, dynamic>.from(v);

        // Extract fields using multiple possible keys to be tolerant of schema differences
        final String? country = _extractField(rv, <String>[
          'country',
          'restcountry',
          'countryCode',
        ]);
        final String? city = _extractField(rv, <String>[
          'city',
          'restcity',
          'restaurantCity',
        ]);

        // Normalize review values
        final String rvCountry = _norm(country);
        final String rvCity = _norm(city);

        // Check if review matches ANY filter (OR logic)
        bool matchesAnyFilter = false;
        for (final Map<String, String?> filter in filters) {
          final String fCountry = _norm(filter['country']);
          final String fCity = _norm(filter['city']);

          // Country must match if specified in filter
          if (fCountry.isNotEmpty && rvCountry != fCountry) {
            continue;
          }
          // City must match if specified in filter
          if (fCity.isNotEmpty && rvCity != fCity) {
            continue;
          }
          // If we get here, this filter matches
          matchesAnyFilter = true;
          break;
        }

        if (!matchesAnyFilter) {
          return;
        }

        final Map<String, dynamic> item = <String, dynamic>{};
        item['key'] = key;
        item['data'] = rv;
        found.add(item);
      });

      if (mounted) {
        setState(() {
          _reviews.addAll(found);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _selectReview(String key) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedKey = (_selectedKey == key) ? null : key;
    });
  }

  void _clearExclusions() {
    if (!mounted) {
      return;
    }
    setState(() {
      _excludedKeys.clear();
      _selectedKey = null;
    });
  }

  void _excludeSelected() {
    if (_selectedKey == null) {
      return;
    }
    if (_excludedKeys.contains(_selectedKey)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _excludedKeys.add(_selectedKey!);
    });
  }

  void _includeSelected() {
    if (_selectedKey == null) {
      return;
    }
    if (!_excludedKeys.contains(_selectedKey)) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _excludedKeys.remove(_selectedKey);
    });
  }

  Future<void> _previewSelected() async {
    if (_selectedKey == null) {
      return;
    }
    final Map<String, dynamic> chosen = _reviews.firstWhere(
      (r) => r['key'] == _selectedKey,
      orElse: () => <String, dynamic>{},
    );
    if (chosen.isEmpty) {
      return;
    }
    final Map<dynamic, dynamic> data = (chosen['data'] is Map)
        ? Map<dynamic, dynamic>.from(chosen['data'] as Map)
        : <dynamic, dynamic>{};

    final ReviewContext ctx = ReviewContext(
      reviewMap: data.map((k, v) => MapEntry(k.toString(), v)),
      isEditing: false,
      reviewKey: _selectedKey,
    );

    if (!mounted) {
      return;
    }
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(context: ctx, mode: 'exclude'),
      ),
    );
    // If preview returned true, caller signalled to exclude this review — add to exclusions
    // Do NOT pop this screen; remain on the review list so the user can continue and persist changes.
    if (result == true) {
      if (!mounted) return;
      setState(() {
        _excludedKeys.add(_selectedKey!);
      });
    }
  }

  // Public/well-named wrappers to match button semantics
  void onExclude() {
    _excludeSelected();
  }

  void onInclude() {
    _includeSelected();
  }

  Future<void> onPreview() async {
    await _previewSelected();
  }

  // Save exCount/exKeys to users/<myUid>/friends/<friendUid>/review and return to previous screen.
  // IMPORTANT: always persist the correct exCount and exKeys values; do not modify rvCount.
  Future<void> _saveStateAndPop() async {
    if (myUid.isEmpty) {
      if (mounted) {
        Navigator.of(context).pop(false);
      }
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });

    final String reviewPath =
        'users/$myUid/friends/${widget.friendUid}/review_request';
    final DatabaseReference rootRef = FirebaseDatabase.instance.ref();

    final int exCount = _excludedKeys.length;
    final Map<String, dynamic> patch = <String, dynamic>{};

    // Always persist the correct exCount and exKeys values to review_request. Do not touch rvCount.
    patch['$reviewPath/exCount'] = exCount;
    patch['$reviewPath/exKeys'] = _excludedKeys.isNotEmpty
        ? _excludedKeys.toList()
        : <String>[];
    patch['$reviewPath/updatedAt'] = DateTime.now().toUtc().toIso8601String();

    bool updateSucceeded = false;
    try {
      await rootRef.update(patch);
      updateSucceeded = true;
    } catch (err) {
      updateSucceeded = false;
    }

    // Guard use of mounted/context after async gap
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
    });

    // Navigate back to the previous route (review request details) so Back returns there.
    if (updateSucceeded) {
      Navigator.of(context).pop(true);
    } else {
      // If update failed, still pop with false so caller knows nothing changed
      Navigator.of(context).pop(false);
    }
  }

  Widget _buildRow(Map<String, dynamic> rv) {
    // Render the review row using the same fields and layout as ReviewListItem
    final String key = rv['key'] as String;
    final bool excluded = _excludedKeys.contains(key);
    final bool selected = _selectedKey == key;
    final Map<dynamic, dynamic> data = (rv['data'] is Map)
        ? Map<dynamic, dynamic>.from(rv['data'] as Map)
        : <dynamic, dynamic>{};

    // Extract display fields with fallbacks
    final String restname =
        (data['restname'] is String && (data['restname'] as String).isNotEmpty)
        ? (data['restname'] as String)
        : (data['name'] is String ? (data['name'] as String) : key);

    final String reviewdate = data['reviewdate']?.toString() ?? '';

    final dynamic restratingRaw = data['restrating'] ?? data['rating'] ?? 0;
    int rating;
    if (restratingRaw is int) {
      rating = restratingRaw;
    } else {
      rating =
          int.tryParse(restratingRaw?.toString() ?? '') ??
          (double.tryParse(restratingRaw?.toString() ?? '')?.round() ?? 0);
    }

    final String restcountry = (data['restcountry'] is String)
        ? (data['restcountry'] as String)
        : (data['country']?.toString() ?? '');
    final String restcity = (data['restcity'] is String)
        ? (data['restcity'] as String)
        : (data['city']?.toString() ?? '');
    final String restcuisine = (data['restcuisine'] is String)
        ? (data['restcuisine'] as String)
        : (data['cuisine']?.toString() ?? '');

    // Use withValues(alpha: double) to avoid withOpacity; selected background uses AppColors.ochre
    final Color selectedBg = AppColors.ochre.withValues(alpha: 0.15);
    final Color excludedCircleBg = AppColors.red.withValues(alpha: 0.15);

    return Material(
      color: selected ? selectedBg : Colors.transparent,
      child: InkWell(
        onTap: () {
          _selectReview(key);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Line 1: Restaurant name left, Rating right
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      restname,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.bold.copyWith(
                        color: AppColors.blue,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${AppStr.ratingLabel} $rating',
                    style: AppFonts.standard.copyWith(color: Colors.black),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Line 2: Country/City left, Date center, Cuisine right
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: Text(
                      (restcountry.isNotEmpty && restcity.isNotEmpty)
                          ? '$restcountry, $restcity'
                          : (restcountry + restcity),
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.standard,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        reviewdate,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.standard,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        restcuisine,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.standard,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  if (excluded)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: excludedCircleBg,
                      ),
                      child: const Center(
                        child: Icon(Icons.close, color: AppColors.red, size: 18),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int total = _reviews.length;
    final int excluded = _excludedKeys.length;
    final int included = total - excluded;

    final bool canExclude =
        _selectedKey != null && !_excludedKeys.contains(_selectedKey);
    final bool canInclude =
        _selectedKey != null && _excludedKeys.contains(_selectedKey);
    final bool canPreview =
        _selectedKey != null && !_excludedKeys.contains(_selectedKey);

    // Base button style created with styleFrom to avoid deprecated MaterialStateProperty usage
    final ButtonStyle baseBtn = ElevatedButton.styleFrom(
      textStyle: AppFonts.bold.copyWith(fontSize: 14),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      minimumSize: const Size(0, 44),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStr.reviewReviewsTitle,
          style: AppFonts.title.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12.0,
                    horizontal: 16.0,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${AppStr.matchingReviews} ($total)',
                          style: AppFonts.standard,
                        ),
                      ),
                      Text(
                        '${AppStr.includedLabel}: $included',
                        style: AppFonts.smallHint.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${AppStr.excludedLabel}: $excluded',
                        style: AppFonts.smallHint.copyWith(
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _reviews.isEmpty
                      ? Center(
                          child: Text(
                            AppStr.noMatchingReviews,
                            style: AppFonts.standard.copyWith(
                              color: AppColors.mutedText,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _reviews.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (BuildContext ctx, int idx) {
                            final Map<String, dynamic> rv = _reviews[idx];
                            return Opacity(
                              opacity: _excludedKeys.contains(rv['key'])
                                  ? 0.45
                                  : 1.0,
                              child: _buildRow(rv),
                            );
                          },
                        ),
                ),

                // Two rows of buttons at bottom
                Container(
                  color: AppColors.beige,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    children: <Widget>[
                      // Row 1: Back (LJ) and Clear (RJ)
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton(
                                onPressed: _saveStateAndPop,
                                style: baseBtn.merge(
                                  ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.btnBack,
                                    foregroundColor: AppColors.btnText,
                                  ),
                                ),
                                child: Text(AppStr.backButtonLabel),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: _clearExclusions,
                                style: baseBtn.merge(
                                  ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.btnClear,
                                    foregroundColor: AppColors.btnText,
                                  ),
                                ),
                                child: Text(AppStr.clear),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Row 2: Exclude (LJ), Include (CJ), Preview (RJ)
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton(
                                onPressed: canExclude ? onExclude : null,
                                style: baseBtn.merge(
                                  ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.red,
                                  ),
                                ),
                                child: Text(AppStr.exclude),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: ElevatedButton(
                                onPressed: canInclude ? onInclude : null,
                                style: baseBtn.merge(
                                  ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.green,
                                  ),
                                ),
                                child: Text(AppStr.include),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: canPreview
                                    ? () => onPreview()
                                    : null,
                                style: baseBtn.merge(
                                  ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.btnPreview,
                                    foregroundColor: AppColors.btnText,
                                  ),
                                ),
                                child: Text(AppStr.preview),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_saving)
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

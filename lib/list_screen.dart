// list_screen.dart
// Main screen for displaying and filtering restaurant reviews

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'preview_screen.dart';
import 'general_screen.dart';
import 'top_screen.dart';
import 'goodfor_filter_screen.dart';
import 'constants/restiview_constants.dart';
import 'constants/colors.dart';
import 'constants/strings.dart';
import 'sub_preview_screen/review_context.dart';
import 'services/session_cache.dart';
import 'services/db_utils.dart';
import 'services/review_info_builder.dart';
import 'services/audit_info.dart';
import 'sub_list_screen/sort_filter.dart';
import 'sub_list_screen/review_list_item.dart';
import 'constants/fonts.dart';

class ReviewListScreen extends StatefulWidget {
  final String? newReviewKey;
  final String mode; // 'list' or 'requested'

  const ReviewListScreen({super.key, this.newReviewKey, this.mode = 'list'});

  @override
  State<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends State<ReviewListScreen> {
  late DatabaseReference _reviewsRef;
  List<Map<String, dynamic>> _allReviews = [];
  List<Map<String, dynamic>> _filteredReviews = [];
  bool _isLoading = true;

  String? localCityFilter;
  String? localCuisineFilter;
  String? localCountryFilter;
  String? localFriendFilter;
  String localSortOption = '';
  final ScrollController _scrollController = ScrollController();
  String? _highlightedKey;

  StreamSubscription<DatabaseEvent>? _reviewSubscription;
  Map<String, String> _friendsMap = {}; // email -> username
  bool _metaRefreshed = false;

  @override
  void initState() {
    super.initState();

    // For requested mode, default to showing all countries and all friends
    localCountryFilter = widget.mode == 'requested'
        ? 'ALL'
        : SessionCache.countryFilter;
    localCityFilter = SessionCache.cityFilter;
    localCuisineFilter = SessionCache.cuisineFilter;
    localFriendFilter = widget.mode == 'requested' ? 'ALL' : null;

    SessionCache.getSortOption().then((stored) {
      if (!mounted) return;
      setState(() {
        localSortOption = _capitalize(stored);
      });
    });

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final String dbPath = widget.mode == 'requested'
          ? 'users/$userId/reviews_requested'
          : 'users/$userId/reviews';
      _reviewsRef = FirebaseDatabase.instance.ref(dbPath);

      // Load existing friends meta record for requested mode
      if (widget.mode == 'requested') {
        _loadFriendsMeta();
      }

      _reviewSubscription = _reviewsRef.onValue.listen(
        (event) {
          final rawValue = event.snapshot.value;
          final data = (rawValue is Map)
              ? Map<dynamic, dynamic>.from(rawValue)
              : <dynamic, dynamic>{};
          final reviews = data.entries
              .where(
                (e) => !e.key.toString().startsWith('_'),
              ) // Exclude meta records like _meta
              .map((e) {
                final review = Map<String, dynamic>.from(e.value as Map);
                review['key'] = e.key;
                return review;
              })
              .toList();

          if (!mounted) return;
          setState(() {
            _allReviews = reviews;

            // Refresh friends meta record once when in requested mode
            if (widget.mode == 'requested' && !_metaRefreshed) {
              _metaRefreshed = true;
              _refreshFriendsMeta();
            }

            // Check if we need to update review_info (only for user's own reviews)
            if (widget.mode == 'list') {
              _checkAndUpdateReviewInfo();
            }

            _applyFiltersAndSort();

            if (widget.newReviewKey != null) {
              final index = _filteredReviews.indexWhere(
                (r) => r['key'] == widget.newReviewKey,
              );
              if (index >= 0) {
                _highlightedKey = widget.newReviewKey;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final target = (index * 96.0).clamp(
                    0.0,
                    _scrollController.hasClients
                        ? _scrollController.position.maxScrollExtent
                        : double.infinity,
                  );
                  _scrollController.animateTo(
                    target,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                });
              } else {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(AppStr.noReviewsMatch)),
                  );
                });
              }
            }

            _isLoading = false;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${AppStr.loadFailed}: $e')));
        },
      );
    } else {
      _isLoading = false;
    }
  }

  void _applyFiltersAndSort() {
    final filterTags = SessionCache.goodForFilter;
    final city = localCityFilter;
    final cuisine = localCuisineFilter;
    final friend = localFriendFilter;

    final rawCountry =
        localCountryFilter ??
        (SessionCache.defaultCountry != 'Any'
            ? SessionCache.defaultCountry
            : null);
    final country = (rawCountry == 'ALL') ? null : rawCountry;

    final filtered = _allReviews.where((review) {
      final cityMatch =
          city == null ||
          (review['restcity']?.toString().toLowerCase() ?? '') ==
              city.toLowerCase();
      final cuisineMatch =
          cuisine == null ||
          (review['restcuisine']?.toString().toLowerCase() ?? '') ==
              cuisine.toLowerCase();
      final countryMatch =
          country == null ||
          (review['restcountry']?.toString().toLowerCase() ?? '') ==
              country.toLowerCase();
      final friendMatch =
          friend == null ||
          friend == 'ALL' ||
          (review['userEmail']?.toString() ?? '') == friend;

      final binary = review['goodfor'] ?? '';
      final String binaryStr = binary.toString();
      final goodForMatch =
          filterTags.isEmpty ||
          filterTags.every((tag) {
            final index = goodForTags.indexOf(tag);
            return index >= 0 &&
                index < binaryStr.length &&
                binaryStr[index] == 'Y';
          });

      return cityMatch &&
          cuisineMatch &&
          countryMatch &&
          friendMatch &&
          goodForMatch;
    }).toList();

    _filteredReviews = _sortReviews(filtered);
  }

  List<Map<String, dynamic>> _sortReviews(List<Map<String, dynamic>> reviews) {
    final sortBy = localSortOption.toLowerCase();

    switch (sortBy) {
      case 'rating':
        reviews.sort(
          (a, b) => (double.tryParse(b['restrating']?.toString() ?? '') ?? 0)
              .compareTo(
                double.tryParse(a['restrating']?.toString() ?? '') ?? 0,
              ),
        );
        break;
      case 'name':
        reviews.sort(
          (a, b) => (a['restname'] ?? '').toString().toLowerCase().compareTo(
            (b['restname'] ?? '').toString().toLowerCase(),
          ),
        );
        break;
      case 'date':
      default:
        // Prefer numeric timestamp if available (ServerValue.timestamp resolves to an int)
        int toTs(dynamic v) {
          if (v == null) return 0;
          if (v is int) return v;
          if (v is double) return v.toInt();
          if (v is String) return int.tryParse(v) ?? 0;
          return 0;
        }

        DateTime? parseSortDate(dynamic sd) {
          try {
            if (sd == null) return null;
            final s = sd.toString();
            // expected format from formatter: yyyy/MM/dd
            return DateTime.parse(s.replaceAll('/', '-'));
          } catch (_) {
            return null;
          }
        }

        reviews.sort((a, b) {
          // Primary: sortdate (yyyy/MM/dd) if present
          final sa = parseSortDate(a['sortdate']);
          final sb = parseSortDate(b['sortdate']);
          if (sa != null && sb != null) return sb.compareTo(sa);

          // Secondary: numeric timestamp (if sortdate missing)
          final ta = toTs(a['timestamp']);
          final tb = toTs(b['timestamp']);
          if (ta != 0 || tb != 0) {
            return tb.compareTo(ta);
          }

          // Final fallback: parse displayed reviewdate (dd/MM/yyyy)
          try {
            final da = a['reviewdate']?.toString() ?? '';
            final db = b['reviewdate']?.toString() ?? '';
            final dateA = da.isNotEmpty
                ? DateTime.parse(da.split('/').reversed.join('-'))
                : DateTime.fromMillisecondsSinceEpoch(0);
            final dateB = db.isNotEmpty
                ? DateTime.parse(db.split('/').reversed.join('-'))
                : DateTime.fromMillisecondsSinceEpoch(0);
            return dateB.compareTo(dateA);
          } catch (_) {
            // last resort: alpha compare
            return (b['reviewdate'] ?? '').toString().compareTo(
              (a['reviewdate'] ?? '').toString(),
            );
          }
        });
        break;
    }

    return reviews;
  }

  void _openReview(Map<String, dynamic> review) {
    final reviewKey = review['key'] as String?;
    final reviewContext = ReviewContext(
      reviewMap: review,
      isEditing: true,
      reviewKey: reviewKey,
    );

    if (!mounted) return;
    // Use 'requested' mode when viewing friend's shared reviews, otherwise 'preview'
    final String previewMode = widget.mode == 'requested'
        ? 'requested'
        : 'preview';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PreviewScreen(context: reviewContext, mode: previewMode),
      ),
    );
  }

  void _openFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SortFilterPanel(
        currentSort: localSortOption,
        currentCountry: localCountryFilter,
        currentCity: localCityFilter,
        currentCuisine: localCuisineFilter,
        currentFriend: localFriendFilter,
        allReviews: _allReviews,
        friendsMap: _friendsMap,
        isRequestedMode: widget.mode == 'requested',
        onApply: (sort, ct, cy, cz, fr) {
          SessionCache.setSortOption(sort.toLowerCase());
          SessionCache.countryFilter = ct;

          if (!mounted) return;
          setState(() {
            localSortOption = sort;
            localCountryFilter = ct;
            localCityFilter = cy;
            localCuisineFilter = cz;
            localFriendFilter = fr;
            _applyFiltersAndSort();
          });
        },
        onClear: () {
          SessionCache.setSortOption('date');
          SessionCache.countryFilter = SessionCache.defaultCountry != 'Any'
              ? SessionCache.defaultCountry
              : null;
          SessionCache.cityFilter = null;
          SessionCache.cuisineFilter = null;
          SessionCache.clearGoodForFilter();

          if (!mounted) return;
          setState(() {
            localSortOption = _capitalize(SessionCache.sortOption);
            localCountryFilter = SessionCache.countryFilter;
            localCityFilter = null;
            localCuisineFilter = null;
            _applyFiltersAndSort();
          });
        },
      ),
    );
  }

  Future<void> _loadFriendsMeta() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('users/$userId/reviews_requested/_meta/friends')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value;
        if (data is Map) {
          final Map<String, String> friends = {};
          data.forEach((key, value) {
            final parts = value?.toString().split('|');
            if (parts != null && parts.length >= 2) {
              // Extract email from "email|username" format
              final email = parts[0];
              friends[email] = parts[1]; // Map email -> username
            }
          });
          if (!mounted) return;
          setState(() {
            _friendsMap = friends;
          });
        }
      }
    } catch (e) {
      // Silent fail - will build from reviews instead
    }
  }

  Future<void> _refreshFriendsMeta() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    // Build friends map from current reviews
    // Map uses normalized email as key (Firebase-safe) with value being "email|username"
    final Map<String, String> friends = {};
    for (final review in _allReviews) {
      final email = review['userEmail']?.toString();
      final username = review['userName']?.toString();

      if (email != null && email.isNotEmpty) {
        // Normalize email for Firebase key (replaces @ and . with _)
        final normalizedEmail = normalizeEmailForPath(email);
        // Store as "email|username" so we can reconstruct both
        friends[normalizedEmail] = '$email|${username ?? ''}';
      }
    }

    if (friends.isEmpty) return;

    // Update meta record in Firebase
    try {
      final metaPath = 'users/$userId/reviews_requested/_meta/friends';

      // Write normalized email keys to Firebase
      await FirebaseDatabase.instance.ref(metaPath).set(friends);

      // Convert back to email -> username map for local use
      final Map<String, String> localFriendsMap = {};
      friends.forEach((normalizedKey, emailAndUsername) {
        final parts = emailAndUsername.split('|');
        if (parts.length >= 2) {
          localFriendsMap[parts[0]] = parts[1]; // email -> username
        }
      });

      if (!mounted) return;
      setState(() {
        _friendsMap = localFriendsMap;
      });
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _checkAndUpdateReviewInfo() async {
    // Only run if flag is set
    final shouldUpdate = await SessionCache.getReviewsAdded();
    if (!shouldUpdate) return;

    // Check if already updated today
    final lastUpdateDate = await SessionCache.getReviewInfoLastUpdate();
    final today = DateTime.now().toIso8601String().substring(0, 10); // yyyy-MM-dd
    if (lastUpdateDate == today) {
      // Already updated today, clear flag and skip
      await SessionCache.setReviewsAdded(false);
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final userEmail = SessionCache.userEmail;

    if (userId == null || userEmail.isEmpty) return;

    try {
      // Show brief status message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Updating review info...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Import and call the update function
      final normalizedEmail = normalizeEmailForPath(userEmail);
      await updateReviewInfo(userId, normalizedEmail);

      // Update last update date and clear the flag
      await SessionCache.setReviewInfoLastUpdate(today);
      await SessionCache.setReviewsAdded(false);
    } catch (e) {
      // Silent fail - non-critical operation
    }
  }

  Future<void> _handleDeleteRequestedReviews() async {
    if (_filteredReviews.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No reviews to delete')));
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reviews'),
        content: Text(
          'Are you sure you want to delete these ${_filteredReviews.length} review(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final deletedCount = _filteredReviews.length;

      // Delete each review from Firebase
      for (final review in _filteredReviews) {
        final key = review['key'] as String?;
        if (key != null) {
          await FirebaseDatabase.instance
              .ref('users/$userId/reviews_requested/$key')
              .remove();
        }
      }

      // Write audit record after deletions
      try {
        await writeAuditInfo(
          userId: userId,
          userEmail: SessionCache.userEmail,
          type: 'requested_review_delete',
          target: 'requested_reviews',
          details: {'deletedCount': deletedCount},
        );
      } catch (e) {
        debugPrint('Failed to write audit info: $e');
      }

      if (!mounted) return;

      // Reset filters to ALL and refresh
      setState(() {
        localCountryFilter = 'ALL';
        localCityFilter = null;
        localCuisineFilter = null;
        localFriendFilter = 'ALL';
        _applyFiltersAndSort();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$deletedCount review(s) deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error deleting reviews: $e')));
    }
  }

  String _capitalize(String input) {
    return input.isNotEmpty
        ? '${input[0].toUpperCase()}${input.substring(1)}'
        : '';
  }

  @override
  void dispose() {
    _reviewSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle actionBtnBase = ElevatedButton.styleFrom(
      textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      minimumSize: const Size(0, 44),
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Text(
            widget.mode == 'requested'
                ? 'Requested Reviews: (${_filteredReviews.length})'
                : 'Restaurant Reviews: (${_filteredReviews.length})',
            style: AppFonts.title.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.red,
        ),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredReviews.isEmpty
                  ? Center(
                      child: Text(
                        AppStr.noReviewsMatch,
                        style: AppFonts.standard.copyWith(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _filteredReviews.length,
                      itemBuilder: (context, index) {
                        final review = _filteredReviews[index];
                        final isHighlighted = review['key'] == _highlightedKey;

                        return ReviewListItem(
                          review: review,
                          onTap: () => _openReview(review),
                          highlight: isHighlighted,
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Container(
                color: AppColors.beige,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        ElevatedButton(
                          onPressed: _openFilterDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlue.shade100,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            textStyle: AppFonts.bold,
                          ),
                          child: Text(AppStr.sortFilter, style: AppFonts.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Requested mode: show Back, Clear, and Delete buttons
                    // List mode: show all 4 buttons (Back, Add, Clear, GoodFor)
                    widget.mode == 'requested'
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (!mounted) return;
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TopScreen(),
                                        ),
                                        (route) => false,
                                      );
                                    },
                                    style: actionBtnBase.copyWith(
                                      backgroundColor: WidgetStateProperty.all(
                                        AppColors.ochre,
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        Colors.black,
                                      ),
                                    ),
                                    child: Text(
                                      AppStr.back,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (!mounted) return;
                                      SessionCache.setSortOption('date');
                                      SessionCache.cityFilter = null;
                                      SessionCache.cuisineFilter = null;
                                      SessionCache.countryFilter = null;
                                      SessionCache.clearGoodForFilter();

                                      setState(() {
                                        localCityFilter = null;
                                        localCuisineFilter = null;
                                        localCountryFilter = 'ALL';
                                        localFriendFilter = 'ALL';
                                        localSortOption = _capitalize(
                                          SessionCache.sortOption,
                                        );
                                        _applyFiltersAndSort();
                                      });
                                    },
                                    style: actionBtnBase.copyWith(
                                      backgroundColor: WidgetStateProperty.all(
                                        AppColors.btnClear,
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        AppColors.btnText,
                                      ),
                                    ),
                                    child: Text(
                                      AppStr.clear,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _handleDeleteRequestedReviews,
                                    style: actionBtnBase.copyWith(
                                      backgroundColor: WidgetStateProperty.all(
                                        AppColors.btnDelete,
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        AppColors.btnText,
                                      ),
                                    ),
                                    child: Text(
                                      AppStr.delete,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (!mounted) return;
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TopScreen(),
                                        ),
                                        (route) => false,
                                      );
                                    },
                                    style: actionBtnBase.copyWith(
                                      backgroundColor: WidgetStateProperty.all(
                                        AppColors.ochre,
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        Colors.black,
                                      ),
                                    ),
                                    child: Text(
                                      AppStr.back,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      final newContext = ReviewContext(
                                        reviewMap: {},
                                        isEditing: false,
                                        reviewKey: null,
                                      );
                                      if (!mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => GeneralScreen(
                                            context: newContext,
                                          ),
                                        ),
                                      );
                                    },
                                    style: actionBtnBase.copyWith(
                                      backgroundColor: WidgetStateProperty.all(
                                        AppColors.btnAdd,
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        AppColors.btnText,
                                      ),
                                    ),
                                    child: Text(
                                      AppStr.add,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (!mounted) return;
                                      SessionCache.setSortOption('date');
                                      SessionCache.cityFilter = null;
                                      SessionCache.cuisineFilter = null;
                                      SessionCache.countryFilter = null;
                                      SessionCache.clearGoodForFilter();

                                      setState(() {
                                        localCityFilter = null;
                                        localCuisineFilter = null;
                                        localCountryFilter = null;
                                        localSortOption = _capitalize(
                                          SessionCache.sortOption,
                                        );
                                        _applyFiltersAndSort();
                                      });
                                    },
                                    style: actionBtnBase.copyWith(
                                      backgroundColor: WidgetStateProperty.all(
                                        AppColors.btnClear,
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        AppColors.btnText,
                                      ),
                                    ),
                                    child: Text(
                                      AppStr.clear,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.bold,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (!mounted) return;
                                      final selected =
                                          await Navigator.push<List<String>>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  GoodForFilterScreen(
                                                    initialSelection:
                                                        SessionCache
                                                            .goodForFilter,
                                                  ),
                                            ),
                                          );
                                      if (!mounted) return;
                                      if (selected != null) {
                                        setState(() {
                                          SessionCache.setGoodForFilter(
                                            selected,
                                          );
                                          _applyFiltersAndSort();
                                        });
                                      }
                                    },
                                    style: actionBtnBase.copyWith(
                                      backgroundColor: WidgetStateProperty.all(
                                        SessionCache.goodForFilter.isNotEmpty
                                            ? Colors.yellow
                                            : Colors.white,
                                      ),
                                      foregroundColor: WidgetStateProperty.all(
                                        Colors.black,
                                      ),
                                    ),
                                    child: Text(
                                      AppStr.goodForTitle.toUpperCase(),
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.bold.copyWith(
                                        decoration:
                                            SessionCache
                                                .goodForFilter
                                                .isNotEmpty
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                        color: Colors.black,
                                      ),
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
          ],
        ),
      ),
    );
  }
}

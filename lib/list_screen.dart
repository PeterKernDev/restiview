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
import 'sub_list_screen/sort_filter.dart';
import 'sub_list_screen/review_list_item.dart';
import 'constants/fonts.dart';

class ReviewListScreen extends StatefulWidget {
  final String? newReviewKey;

  const ReviewListScreen({super.key, this.newReviewKey});

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
  String localSortOption = '';
  final ScrollController _scrollController = ScrollController();
  String? _highlightedKey;

  StreamSubscription<DatabaseEvent>? _reviewSubscription;

  @override
  void initState() {
    super.initState();

    localCountryFilter = SessionCache.countryFilter;
    localCityFilter = SessionCache.cityFilter;
    localCuisineFilter = SessionCache.cuisineFilter;

    SessionCache.getSortOption().then((stored) {
      if (!mounted) return;
      setState(() {
        localSortOption = _capitalize(stored);
      });
    });

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _reviewsRef = FirebaseDatabase.instance.ref('users/$userId/reviews');

      _reviewSubscription = _reviewsRef.onValue.listen((event) {
        final rawValue = event.snapshot.value;
        final data = (rawValue is Map) ? Map<dynamic, dynamic>.from(rawValue) : <dynamic, dynamic>{};
        final reviews = data.entries.map((e) {
          final review = Map<String, dynamic>.from(e.value as Map);
          review['key'] = e.key;
          return review;
        }).toList();

        if (!mounted) return;
        setState(() {
          _allReviews = reviews;
          _applyFiltersAndSort();

          if (widget.newReviewKey != null) {
            final index = _filteredReviews.indexWhere((r) => r['key'] == widget.newReviewKey);
            if (index >= 0) {
              _highlightedKey = widget.newReviewKey;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final target = (index * 96.0).clamp(
                  0.0,
                  _scrollController.hasClients ? _scrollController.position.maxScrollExtent : double.infinity,
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
      }, onError: (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.loadFailed}: $e')));
      });
    } else {
      _isLoading = false;
    }
  }

  void _applyFiltersAndSort() {
    final filterTags = SessionCache.goodForFilter;
    final city = localCityFilter;
    final cuisine = localCuisineFilter;

    final rawCountry = localCountryFilter ?? (SessionCache.defaultCountry != 'Any' ? SessionCache.defaultCountry : null);
    final country = (rawCountry == 'ALL') ? null : rawCountry;

    // debugPrint('Filters → Country: $country, City: $city, Cuisine: $cuisine');

    final filtered = _allReviews.where((review) {
      final cityMatch = city == null || (review['restcity']?.toString().toLowerCase() ?? '') == city.toLowerCase();
      final cuisineMatch = cuisine == null || (review['restcuisine']?.toString().toLowerCase() ?? '') == cuisine.toLowerCase();
      final countryMatch = country == null || (review['restcountry']?.toString().toLowerCase() ?? '') == country.toLowerCase();

      final binary = review['goodfor'] ?? '';
      final String binaryStr = binary.toString();
      final goodForMatch = filterTags.isEmpty || filterTags.every((tag) {
        final index = goodForTags.indexOf(tag);
        return index >= 0 && index < binaryStr.length && binaryStr[index] == 'Y';
      });

      return cityMatch && cuisineMatch && countryMatch && goodForMatch;
    }).toList();

    _filteredReviews = _sortReviews(filtered);
  }

  List<Map<String, dynamic>> _sortReviews(List<Map<String, dynamic>> reviews) {
    final sortBy = localSortOption.toLowerCase();

    switch (sortBy) {
      case 'rating':
        reviews.sort((a, b) =>
            (double.tryParse(b['restrating']?.toString() ?? '') ?? 0)
                .compareTo(double.tryParse(a['restrating']?.toString() ?? '') ?? 0));
        break;
      case 'name':
        reviews.sort((a, b) => (a['restname'] ?? '').toString().toLowerCase().compareTo((b['restname'] ?? '').toString().toLowerCase()));
        break;
      case 'date':
      default:
        reviews.sort((a, b) => (b['reviewdate'] ?? '').toString().compareTo((a['reviewdate'] ?? '').toString()));
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(context: reviewContext)));
  }

  void _openFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SortFilterPanel(
        currentSort: localSortOption,
        currentCountry: localCountryFilter,
        currentCity: localCityFilter,
        currentCuisine: localCuisineFilter,
        allReviews: _allReviews,
        onApply: (sort, ct, cy, cz) {
          SessionCache.setSortOption(sort.toLowerCase());
          SessionCache.countryFilter = ct;

          if (!mounted) return;
          setState(() {
            localSortOption = sort;
            localCountryFilter = ct;
            localCityFilter = cy;
            localCuisineFilter = cz;
            _applyFiltersAndSort();
          });
        },
        onClear: () {
          SessionCache.setSortOption('date');
          SessionCache.countryFilter = SessionCache.defaultCountry != 'Any' ? SessionCache.defaultCountry : null;
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

  String _capitalize(String input) {
    return input.isNotEmpty ? '${input[0].toUpperCase()}${input.substring(1)}' : '';
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
          title: Text('Restaurant Reviews: (${_filteredReviews.length})', style: AppFonts.title.copyWith(color: Colors.white)),
          backgroundColor: AppColors.red,
        ),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredReviews.isEmpty
                      ? Center(child: Text(AppStr.noReviewsMatch, style: AppFonts.standard.copyWith(fontSize: 16, color: Colors.grey)))
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: ElevatedButton(
                              onPressed: () {
                                if (!mounted) return;
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (_) => TopScreen()),
                                  (route) => false,
                                );
                              },
                              style: actionBtnBase.copyWith(
                                backgroundColor: WidgetStateProperty.all(AppColors.ochre),
                                foregroundColor: WidgetStateProperty.all(Colors.black),
                              ),
                              child: Text(AppStr.back, overflow: TextOverflow.ellipsis, style: AppFonts.bold),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: ElevatedButton(
                              onPressed: () {
                                final newContext = ReviewContext(reviewMap: {}, isEditing: false, reviewKey: null);
                                if (!mounted) return;
                                Navigator.push(context, MaterialPageRoute(builder: (_) => GeneralScreen(context: newContext)));
                              },
                              style: actionBtnBase.copyWith(
                                backgroundColor: WidgetStateProperty.all(AppColors.darkGreen),
                                foregroundColor: WidgetStateProperty.all(Colors.white),
                              ),
                              child: Text(AppStr.add, overflow: TextOverflow.ellipsis, style: AppFonts.bold),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
                                  localSortOption = _capitalize(SessionCache.sortOption);
                                  _applyFiltersAndSort();
                                });
                              },
                              style: actionBtnBase.copyWith(
                                backgroundColor: WidgetStateProperty.all(Colors.blueGrey),
                                foregroundColor: WidgetStateProperty.all(Colors.white),
                              ),
                              child: Text(AppStr.clear, overflow: TextOverflow.ellipsis, style: AppFonts.bold),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: ElevatedButton(
                              onPressed: () async {
                                if (!mounted) return;
                                final selected = await Navigator.push<List<String>>(
                                  context,
                                  MaterialPageRoute(builder: (_) => GoodForFilterScreen(initialSelection: SessionCache.goodForFilter)),
                                );
                                if (!mounted) return;
                                if (selected != null) {
                                  setState(() {
                                    SessionCache.setGoodForFilter(selected);
                                    _applyFiltersAndSort();
                                  });
                                }
                              },
                              style: actionBtnBase.copyWith(
                                backgroundColor: WidgetStateProperty.all(
                                  SessionCache.goodForFilter.isNotEmpty ? Colors.yellow : Colors.white,
                                ),
                                foregroundColor: WidgetStateProperty.all(Colors.black),
                              ),
                              child: Text(
                                AppStr.goodForTitle.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.bold.copyWith(
                                  decoration: SessionCache.goodForFilter.isNotEmpty ? TextDecoration.underline : TextDecoration.none,
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
            )
          ],
        ),
      ),
    );
  }
}

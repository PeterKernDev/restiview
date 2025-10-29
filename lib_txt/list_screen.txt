// list_screen.dart
// Main screen for displaying and filtering restaurant reviews
//
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
import 'sub_list_screen/review_list_item.dart';
import 'sub_list_screen/review_filter_bar.dart';

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
  String localSortOption = '';
  final ScrollController _scrollController = ScrollController();
  String? _highlightedKey;

  StreamSubscription<DatabaseEvent>? _reviewSubscription;

  @override
  void initState() {
    super.initState();

    // Restore persisted sort option (async) and apply capitalization for display.
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
        final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
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
                _scrollController.animateTo(
                  index * 100.0,
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
      });
    }
  }

  void _applyFiltersAndSort() {
    final filterTags = SessionCache.goodForFilter;
    final city = localCityFilter;
    final cuisine = localCuisineFilter;

    final filtered = _allReviews.where((review) {
      final cityMatch = city == null ||
          review['restcity']?.toLowerCase() == city.toLowerCase();

      final cuisineMatch = cuisine == null ||
          review['restcuisine']?.toLowerCase() == cuisine.toLowerCase();

      final binary = review['goodfor'] ?? '';
      final goodForMatch = filterTags.isEmpty ||
          filterTags.every((tag) {
            final index = goodForTags.indexOf(tag);
            return index >= 0 &&
                index < binary.length &&
                binary[index] == 'Y';
          });

      return cityMatch && cuisineMatch && goodForMatch;
    }).toList();

    _filteredReviews = _sortReviews(filtered);
  }

  List<Map<String, dynamic>> _sortReviews(List<Map<String, dynamic>> reviews) {
    final sortBy = localSortOption.toLowerCase();

    switch (sortBy) {
      case 'rating':
        reviews.sort((a, b) =>
            (double.tryParse(b['restrating'].toString()) ?? 0)
                .compareTo(double.tryParse(a['restrating'].toString()) ?? 0));
        break;
      case 'name':
        reviews.sort((a, b) => (a['restname'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['restname'] ?? '').toString().toLowerCase()));
        break;
      case 'date':
      default:
        reviews.sort((a, b) =>
            (b['reviewdate'] ?? '').compareTo(a['reviewdate'] ?? ''));
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(context: reviewContext),
      ),
    );
  }

  void _openFilterDialog() {
    final sortOptions = [
      AppStr.sortOptionDate,
      AppStr.sortOptionRating,
      AppStr.sortOptionName,
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) {
        String? modalSort = localSortOption.isNotEmpty ? localSortOption : _capitalize(SessionCache.sortOption);
        String? modalCity = localCityFilter;
        String? modalCuisine = localCuisineFilter;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: sortOptions.contains(modalSort) ? modalSort : null,
                items: sortOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (value) {
                  if (!mounted || value == null) return;
                  // persist canonical key (lowercase) immediately
                  SessionCache.setSortOption(value.toLowerCase());
                  setState(() {
                    localSortOption = value;
                  });
                },
                decoration: const InputDecoration(labelText: AppStr.sortByLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: AppStr.cityLabel),
                controller: TextEditingController(text: modalCity),
                onChanged: (value) {
                  if (!mounted) return;
                  modalCity = value.trim().isEmpty ? null : value.trim();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: SessionCache.customCuisines.contains(modalCuisine) ? modalCuisine : null,
                items: SessionCache.customCuisines
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  if (!mounted) return;
                  modalCuisine = value;
                },
                decoration: const InputDecoration(labelText: AppStr.cuisineLabel),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      if (!mounted) return;
                      // apply modal values
                      setState(() {
                        localCityFilter = modalCity;
                        localCuisineFilter = modalCuisine;
                        _applyFiltersAndSort();
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        Navigator.pop(context);
                      });
                    },
                    child: const Text(AppStr.apply),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                    onPressed: () {
                      if (!mounted) return;
                      // reset filters and persist canonical default sort
                      SessionCache.setSortOption('date');
                      setState(() {
                        localCityFilter = null;
                        localCuisineFilter = null;
                        localSortOption = _capitalize(SessionCache.sortOption);
                        _applyFiltersAndSort();
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        Navigator.pop(context);
                      });
                    },
                    child: const Text(AppStr.clear),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _capitalize(String input) {
    return input.isNotEmpty
        ? '${input[0].toUpperCase()}${input.substring(1)}'
        : '';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Text(
            'Restaurant Reviews: (${_filteredReviews.length})',
            style: const TextStyle(
              fontFamily: 'Gelica',
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: AppColors.red,
        ),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredReviews.isEmpty
                      ? const Center(
                          child: Text(
                            AppStr.noReviewsMatch,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                              fontFamily: 'Gelica',
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ReviewFilterBar(
                        sortOption: localSortOption,
                        city: localCityFilter,
                        cuisine: localCuisineFilter,
                        onTap: _openFilterDialog,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            if (!mounted) return;
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => TopScreen()),
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.ochre,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text(AppStr.back,
                              style: TextStyle(fontFamily: 'Gelica')),
                        ),
                        ElevatedButton(
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
                                builder: (_) => GeneralScreen(context: newContext),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.darkGreen,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(AppStr.add,
                              style: TextStyle(fontFamily: 'Gelica')),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            if (!mounted) return;
                            // reset filters and persist canonical default sort
                            SessionCache.setSortOption('date');
                            setState(() {
                              localCityFilter = null;
                              localCuisineFilter = null;
                              localSortOption = _capitalize(SessionCache.sortOption);
                              SessionCache.goodForFilter.clear();
                              _applyFiltersAndSort();
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(AppStr.clear,
                              style: TextStyle(fontFamily: 'Gelica')),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            if (!mounted) return;
                            final selected = await Navigator.push<List<String>>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GoodForFilterScreen(
                                  initialSelection: SessionCache.goodForFilter,
                                ),
                              ),
                            );
                            if (selected != null && mounted) {
                              setState(() {
                                SessionCache.goodForFilter = selected;
                                _applyFiltersAndSort();
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SessionCache.goodForFilter.isNotEmpty
                                ? Colors.yellow
                                : Colors.white,
                            foregroundColor: Colors.black,
                          ),
                          child: Text(
                            AppStr.goodForTitle.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Gelica',
                              decoration: SessionCache.goodForFilter.isNotEmpty
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              fontWeight: FontWeight.bold,
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

  @override
  void dispose() {
    _reviewSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
}
// lib/sub_list_screen/sort_filter.dart
// Bottom sheet panel for selecting sort and filter options on the review list screen

import 'package:flutter/material.dart';
import '../services/session_cache.dart';
import '../constants/restiview_constants.dart';
import '../constants/strings.dart';
import '../constants/colors.dart';
import '../constants/fonts.dart';

class SortFilterPanel extends StatefulWidget {
  final String currentSort;
  final String? currentCountry;
  final String? currentCity;
  final String? currentCuisine;
  final String? currentFriend;
  final List<Map<String, dynamic>> allReviews;
  final Map<String, String> friendsMap; // email -> username
  final bool isRequestedMode;
  final void Function(String sort, String? ct, String? cy, String? cz, String? fr) onApply;
  final VoidCallback onClear;

  const SortFilterPanel({
    super.key,
    required this.currentSort,
    required this.currentCountry,
    required this.currentCity,
    required this.currentCuisine,
    this.currentFriend,
    required this.allReviews,
    this.friendsMap = const {},
    this.isRequestedMode = false,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<SortFilterPanel> createState() => _SortFilterPanelState();
}

class _SortFilterPanelState extends State<SortFilterPanel> {
  late String _selectedSort;
  String? _selectedCT;
  String? _selectedCY;
  String? _selectedCZ;
  String? _selectedFR;

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.currentSort;
    _selectedCT = widget.currentCountry ??
        SessionCache.countryFilter ??
        (SessionCache.defaultCountry != 'Any' ? SessionCache.defaultCountry : null);
    _selectedCY = widget.currentCity;
    _selectedCZ = widget.currentCuisine;
    _selectedFR = widget.currentFriend;

    SessionCache.goodForNotifier.addListener(_onGoodForChanged);
  }

  void _onGoodForChanged() {
    if (!mounted) return;
    setState(() {
      // no-op: triggers rebuild so _getFilteredCount() re-evaluates
    });
  }

  @override
  void dispose() {
    SessionCache.goodForNotifier.removeListener(_onGoodForChanged);
    super.dispose();
  }

  int _getFilteredCount() {
    final rawCountry = _selectedCT ?? (SessionCache.defaultCountry != 'Any' ? SessionCache.defaultCountry : null);
    final country = (rawCountry == 'ALL') ? null : rawCountry;
    final city = _selectedCY;
    final cuisine = _selectedCZ;
    final friend = _selectedFR;
    final tags = SessionCache.goodForFilter;

    final filtered = widget.allReviews.where((review) {
      final cityMatch = city == null ||
          (review['restcity']?.toString().toLowerCase() == city.toLowerCase());

      final cuisineMatch = cuisine == null ||
          (review['restcuisine']?.toString().toLowerCase() == cuisine.toLowerCase());

      final countryMatch = country == null ||
          (review['restcountry']?.toString().toLowerCase() == country.toLowerCase());

      final friendMatch = friend == null || friend == 'ALL' ||
          (review['userEmail']?.toString() == friend);

      final binary = review['goodfor'] ?? '';
      final goodForMatch = tags.isEmpty ||
          tags.every((tag) {
            final index = goodForTags.indexOf(tag);
            return index >= 0 && index < binary.length && binary[index] == 'Y';
          });

      return cityMatch && cuisineMatch && countryMatch && friendMatch && goodForMatch;
    });

    return filtered.length;
  }

  List<String> getAvailableCountries() {
    final Set<String> countries = {};

    for (final review in widget.allReviews) {
      final country = review['restcountry']?.toString();
      final city = review['restcity']?.toString();
      final cuisine = review['restcuisine']?.toString();

      if (country != null && country.isNotEmpty) {
        // Filter by selected city if any
        if (_selectedCY != null && city?.toLowerCase() != _selectedCY!.toLowerCase()) {
          continue;
        }
        // Filter by selected cuisine if any
        if (_selectedCZ != null && cuisine?.toLowerCase() != _selectedCZ!.toLowerCase()) {
          continue;
        }
        countries.add(country);
      }
    }

    if (_selectedCT != null && !countries.contains(_selectedCT!)) {
      countries.add(_selectedCT!);
    }

    final sorted = countries.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (!sorted.contains('ALL')) {
      sorted.insert(0, 'ALL');
    }
    return sorted;
  }

  List<String> getAvailableCities() {
    final Set<String> cities = {};

    for (final review in widget.allReviews) {
      final country = review['restcountry']?.toString();
      final city = review['restcity']?.toString();
      final cuisine = review['restcuisine']?.toString();

      if (city != null && city.isNotEmpty) {
        // Filter by selected country if any
        if (_selectedCT != null && _selectedCT != 'ALL' && country?.toLowerCase() != _selectedCT!.toLowerCase()) {
          continue;
        }
        // Filter by selected cuisine if any
        if (_selectedCZ != null && cuisine?.toLowerCase() != _selectedCZ!.toLowerCase()) {
          continue;
        }
        cities.add(city);
      }
    }

    if (_selectedCY != null && !cities.contains(_selectedCY!)) {
      cities.add(_selectedCY!);
    }

    final sorted = cities.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<String> getAvailableCuisines() {
    final Set<String> cuisines = {};

    for (final review in widget.allReviews) {
      final country = review['restcountry']?.toString();
      final city = review['restcity']?.toString();
      final cuisine = review['restcuisine']?.toString();

      if (cuisine != null && cuisine.isNotEmpty) {
        // Filter by selected country if any
        if (_selectedCT != null && _selectedCT != 'ALL' && country?.toLowerCase() != _selectedCT!.toLowerCase()) {
          continue;
        }
        // Filter by selected city if any
        if (_selectedCY != null && city?.toLowerCase() != _selectedCY!.toLowerCase()) {
          continue;
        }
        cuisines.add(cuisine);
      }
    }

    if (_selectedCZ != null && !cuisines.contains(_selectedCZ!)) {
      cuisines.add(_selectedCZ!);
    }

    final sorted = cuisines.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  void _handleApply() {
    SessionCache.setSortOption(_selectedSort.toLowerCase());
    SessionCache.countryFilter = _selectedCT;
    SessionCache.cityFilter = _selectedCY;
    SessionCache.cuisineFilter = _selectedCZ;

    widget.onApply(_selectedSort, _selectedCT, _selectedCY, _selectedCZ, _selectedFR);

    if (!mounted) return;
    Navigator.pop(context);
  }

  void _handleReset() {
    SessionCache.setSortOption('date');
    setState(() {
      _selectedSort = AppStr.sortOptionDate;
      _selectedCT = SessionCache.defaultCountry != 'Any' ? SessionCache.defaultCountry : null;
      _selectedCY = null;
      _selectedCZ = null;
      _selectedFR = widget.isRequestedMode ? 'ALL' : null;
    });
    widget.onClear();
  }

  void _handleBack() {
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final sortOptions = [
      AppStr.sortOptionName,
      AppStr.sortOptionDate,
      AppStr.sortOptionRating,
    ];
    final ctOptions = getAvailableCountries();
    final cyOptions = getAvailableCities();
    final czOptions = getAvailableCuisines();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSort,
                    items: sortOptions.map((s) => DropdownMenuItem(value: s, child: Text(s, style: AppFonts.standard))).toList(),
                    onChanged: (val) {
                      if (!mounted || val == null) return;
                      setState(() {
                        _selectedSort = val;
                      });
                    },
                    decoration: InputDecoration(labelText: AppStr.sortByLabel, labelStyle: AppFonts.standard),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Reviews: (${_getFilteredCount()})',
                  style: AppFonts.bold.copyWith(fontSize: 16, color: AppColors.darkGreen),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.isRequestedMode) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedFR,
                items: [
                  const DropdownMenuItem(value: 'ALL', child: Text('ALL')),
                  ...widget.friendsMap.entries.map((e) {
                    final displayText = '${e.key}(${e.value})';
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(displayText, style: AppFonts.standard),
                    );
                  }),
                ],
                onChanged: (val) {
                  if (!mounted) return;
                  setState(() {
                    _selectedFR = val;
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Friend',
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: _selectedCT,
              items: ctOptions.map((c) => DropdownMenuItem(value: c, child: Text(c, style: AppFonts.standard))).toList(),
              onChanged: (val) {
                if (!mounted) return;
                setState(() {
                  _selectedCT = val;
                  _selectedCY = null;
                  _selectedCZ = null;
                });
              },
              decoration: InputDecoration(labelText: AppStr.countryLabel, labelStyle: AppFonts.standard),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCY,
                    items: cyOptions.map((c) => DropdownMenuItem(value: c, child: Text(c, style: AppFonts.standard))).toList(),
                    onChanged: (val) {
                      if (!mounted) return;
                      setState(() {
                        _selectedCY = val;

                        final validCuisines = getAvailableCuisines();
                        if (_selectedCZ != null && !validCuisines.contains(_selectedCZ)) {
                          _selectedCZ = null;
                        }
                      });
                    },
                    decoration: InputDecoration(labelText: AppStr.cityLabel, labelStyle: AppFonts.standard),
                  ),
                ),
                if (_selectedCY != null)
                  IconButton(
                    icon: Text('<C>', style: AppFonts.standard.copyWith(fontSize: 14, fontWeight: FontWeight.bold)),
                    tooltip: 'Clear city',
                    onPressed: () {
                      if (!mounted) return;
                      setState(() {
                        _selectedCY = null;

                        final validCuisines = getAvailableCuisines();
                        if (_selectedCZ != null && !validCuisines.contains(_selectedCZ)) {
                          _selectedCZ = null;
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCZ,
                    items: czOptions.map((c) => DropdownMenuItem(value: c, child: Text(c, style: AppFonts.standard))).toList(),
                    onChanged: (val) {
                      if (!mounted) return;
                      setState(() {
                        _selectedCZ = val;
                      });
                    },
                    decoration: InputDecoration(labelText: AppStr.cuisineLabel, labelStyle: AppFonts.standard),
                  ),
                ),
                if (_selectedCZ != null)
                  IconButton(
                    icon: Text('<C>', style: AppFonts.standard.copyWith(fontSize: 14, fontWeight: FontWeight.bold)),
                    tooltip: 'Clear cuisine',
                    onPressed: () {
                      if (!mounted) return;
                      setState(() {
                        _selectedCZ = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _handleBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(100, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: AppFonts.standard,
                  ),
                  child: Text(AppStr.back, style: AppFonts.standard),
                ),
                ElevatedButton(
                  onPressed: _handleReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(100, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: AppFonts.standard,
                  ),
                  child: Text(AppStr.resetButton, style: AppFonts.standard),
                ),
                ElevatedButton(
                  onPressed: _handleApply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(100, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: AppFonts.standard.copyWith(color: Colors.white),
                  ),
                  child: Text(AppStr.apply, style: AppFonts.standard.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// custom_values_screen.dart
// Full file with all uses of BuildContext guarded after async gaps.
// Each method checks `if (!mounted) return;` before using context, ScaffoldMessenger, or setState.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'constants/restiview_constants.dart';
import 'constants/colors.dart';
import 'constants/strings.dart';
import 'constants/fonts.dart';
import 'settings_screen.dart';
import 'top_screen.dart';
import 'services/session_cache.dart';

class CustomValuesScreen extends StatefulWidget {
  const CustomValuesScreen({super.key});

  @override
  State<CustomValuesScreen> createState() => _CustomValuesScreenState();
}

class _CustomValuesScreenState extends State<CustomValuesScreen> {
  // Cuisine controllers
  final TextEditingController _cuisineController = TextEditingController();
  final TextEditingController _cuisineEditController = TextEditingController();
  bool _isEditingCuisine = false;
  String _selectedCuisine = '';
  bool _selectedCuisineUsed = false;

  // Occasion controllers (mirrors cuisine)
  final TextEditingController _occasionController = TextEditingController();
  final TextEditingController _occasionEditController = TextEditingController();
  bool _isEditingOccasion = false;
  String _selectedOccasion = '';
  bool _selectedOccasionUsed = false;

  // Country
  String _selectedCountry = '';

  bool _isBusy = false;

  // Cached pairs [name, usedFlag] loaded once from Firebase
  List<List<dynamic>> _cuisinePairs = [];
  List<List<dynamic>> _occasionPairs = [];

  Future<T?> _withBusy<T>(Future<T> Function() action) async {
    if (_isBusy || !mounted) {
      return null;
    }
    setState(() {
      _isBusy = true;
    });
    T? res;
    try {
      res = await action();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
    return res;
  }

  List<List<dynamic>> _parsePairList(dynamic raw) {
    if (raw is List) {
      return raw.map<List<dynamic>>((item) {
        if (item is List) {
          return List<dynamic>.from(item);
        }
        if (item is Map) {
          return item.values.toList();
        }
        return [item, 0];
      }).toList();
    }
    return <List<dynamic>>[];
  }

  List<String> _mergedAndSorted(List<String> system, List<String> custom) {
    final merged = <String>[];
    for (final s in system) {
      if (!merged.contains(s)) {
        merged.add(s);
      }
    }
    for (final c in custom) {
      if (!merged.contains(c)) {
        merged.add(c);
      }
    }
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return merged;
  }

  // ---------------- Cuisine handlers ----------------
  Future<void> _saveEditedCuisine() async {
    final edited = _cuisineEditController.text.trim();

    if (edited.isEmpty || edited.length > 24) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.cuisineMaxLength)));
      return;
    }

    if (_selectedCuisine.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.selectCuisineToEdit)),
      );
      return;
    }

    if (edited == _selectedCuisine) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.valueUnchanged)));
      return;
    }

    final mergedList = _mergedAndSorted(
      systemCuisines,
      SessionCache.customCuisines,
    );
    final isDuplicate = mergedList.any(
      (c) => c.toLowerCase() == edited.toLowerCase(),
    );
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$edited" ${AppStr.alreadyExists}')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.notSignedIn)));
      return;
    }

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    final snapshot = await ref.get();
    if (!mounted) return;
    if (!snapshot.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.noCustomValuesToEdit)),
      );
      return;
    }

    if (snapshot.value is! Map) return;
    final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
    final cuisineList = _parsePairList(data['cuisine']);
    final index = cuisineList.indexWhere((pair) => pair[0] == _selectedCuisine);
    if (index == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.selectedCuisineNotFound)),
      );
      return;
    }

    if (cuisineList[index][1] == 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$_selectedCuisine" ${AppStr.usedInReview}')),
      );
      return;
    }

    cuisineList[index][0] = edited;
    await ref.update({'cuisine': cuisineList});
    if (!mounted) return;

    final merged = <String>[];
    for (final s in systemCuisines) {
      if (!merged.contains(s)) {
        merged.add(s);
      }
    }
    for (final pair in cuisineList) {
      final name = pair[0] as String;
      if (!merged.contains(name)) {
        merged.add(name);
      }
    }
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    SessionCache.customCuisines = merged;

    if (!mounted) return;
    setState(() {
      _isEditingCuisine = false;
      _selectedCuisine = edited;
      _cuisineEditController.clear();
      _cuisineController.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$edited" ${AppStr.updatedCuisine}')),
    );
  }

  Future<void> _addCustomCuisine() async {
    final newCuisine = _cuisineController.text.trim();

    if (newCuisine.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.enterCustomCuisine)));
      return;
    }
    if (newCuisine.length > 24) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.cuisineMaxLength)));
      return;
    }

    final exists = _mergedAndSorted(
      systemCuisines,
      SessionCache.customCuisines,
    ).any((c) => c.toLowerCase() == newCuisine.toLowerCase());
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$newCuisine" ${AppStr.alreadyExists}')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    final snapshot = await ref.get();
    if (!mounted) return;

    List<List<dynamic>> updatedCustoms = [];
    if (snapshot.exists) {
      if (snapshot.value is! Map) return;
      final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
      updatedCustoms = _parsePairList(data['cuisine']);
      updatedCustoms.add([newCuisine, 0]);
      await ref.update({'cuisine': updatedCustoms});
    } else {
      updatedCustoms = [
        [newCuisine, 0],
      ];
      await ref.set({'cuisine': updatedCustoms, 'occasion': [], 'country': []});
    }

    if (!mounted) return;
    final merged = <String>[];
    for (final s in systemCuisines) {
      if (!merged.contains(s)) {
        merged.add(s);
      }
    }
    for (final pair in updatedCustoms) {
      final name = pair[0] as String;
      if (!merged.contains(name)) {
        merged.add(name);
      }
    }
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    SessionCache.customCuisines = merged;

    if (!mounted) return;
    setState(() {
      _selectedCuisine = newCuisine;
      _cuisineController.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$newCuisine" ${AppStr.addedToCuisines}')),
    );
  }

  Future<void> _removeCustomCuisine() async {
    final selected = _selectedCuisine;

    if (systemCuisines.contains(selected)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStr.builtInCuisineBlock)));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    final snapshot = await ref.get();
    if (!mounted) return;
    if (!snapshot.exists) return;

    if (snapshot.value is! Map) return;
    final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
    final cuisineList = _parsePairList(data['cuisine']);
    final index = cuisineList.indexWhere((pair) => pair[0] == selected);
    if (index == -1) {
      return;
    }

    if (cuisineList[index][1] == 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$selected" is used in a review and cannot be removed',
          ),
        ),
      );
      return;
    }

    cuisineList.removeAt(index);
    await ref.update({'cuisine': cuisineList});
    if (!mounted) return;
    SessionCache.customCuisines = _mergedAndSorted(
      systemCuisines,
      cuisineList.map((p) => p[0] as String).toList(),
    );

    if (!mounted) return;
    setState(() {
      _selectedCuisine = '';
      _isEditingCuisine = false;
      _cuisineEditController.clear();
      _cuisineController.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"$selected" has been removed')));
  }

  // ---------------- Occasion handlers (mirror cuisine) ----------------
  Future<void> _saveEditedOccasion() async {
    final edited = _occasionEditController.text.trim();

    if (edited.isEmpty || edited.length > 24) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.occasionMaxLength)));
      return;
    }

    if (_selectedOccasion.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.selectOccasionToEdit)),
      );
      return;
    }

    if (edited == _selectedOccasion) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.valueUnchanged)));
      return;
    }

    final mergedList = _mergedAndSorted(
      systemOccasions,
      SessionCache.customOccasions,
    );
    final isDuplicate = mergedList.any(
      (c) => c.toLowerCase() == edited.toLowerCase(),
    );
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$edited" ${AppStr.alreadyExists}')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.notSignedIn)));
      return;
    }

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    final snapshot = await ref.get();
    if (!mounted) return;
    if (!snapshot.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.noCustomValuesToEdit)),
      );
      return;
    }

    if (snapshot.value is! Map) return;
    final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
    final occasionList = _parsePairList(data['occasion']);
    final index = occasionList.indexWhere(
      (pair) => pair[0] == _selectedOccasion,
    );
    if (index == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.selectedOccasionNotFound)),
      );
      return;
    }

    if (occasionList[index][1] == 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$_selectedOccasion" ${AppStr.usedInReview}')),
      );
      return;
    }

    occasionList[index][0] = edited;
    await ref.update({'occasion': occasionList});
    if (!mounted) return;

    final merged = <String>[];
    for (final s in systemOccasions) {
      if (!merged.contains(s)) {
        merged.add(s);
      }
    }
    for (final pair in occasionList) {
      final name = pair[0] as String;
      if (!merged.contains(name)) {
        merged.add(name);
      }
    }
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    SessionCache.customOccasions = merged;

    if (!mounted) return;
    setState(() {
      _isEditingOccasion = false;
      _selectedOccasion = edited;
      _occasionEditController.clear();
      _occasionController.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$edited" ${AppStr.updatedOccasion}')),
    );
  }

  Future<void> _addCustomOccasionLocal() async {
    final newOccasion = _occasionController.text.trim();

    if (newOccasion.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.enterCustomOccasion)));
      return;
    }
    if (newOccasion.length > 24) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.occasionMaxLength)));
      return;
    }

    final exists = _mergedAndSorted(
      systemOccasions,
      SessionCache.customOccasions,
    ).any((c) => c.toLowerCase() == newOccasion.toLowerCase());
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$newOccasion" ${AppStr.alreadyExists}')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    final snapshot = await ref.get();
    if (!mounted) return;

    List<List<dynamic>> updatedOccasions = [];
    if (snapshot.exists) {
      if (snapshot.value is! Map) return;
      final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
      updatedOccasions = _parsePairList(data['occasion']);
      updatedOccasions.add([newOccasion, 0]);
      await ref.update({'occasion': updatedOccasions});
    } else {
      updatedOccasions = [
        [newOccasion, 0],
      ];
      await ref.set({
        'cuisine': [],
        'occasion': updatedOccasions,
        'country': [],
      });
    }

    if (!mounted) return;
    final merged = <String>[];
    for (final s in systemOccasions) {
      if (!merged.contains(s)) {
        merged.add(s);
      }
    }
    for (final pair in updatedOccasions) {
      final name = pair[0] as String;
      if (!merged.contains(name)) {
        merged.add(name);
      }
    }
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    SessionCache.customOccasions = merged;

    if (!mounted) return;
    setState(() {
      _selectedOccasion = newOccasion;
      _occasionController.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$newOccasion" ${AppStr.addedToOccasions}')),
    );
  }

  Future<void> _removeCustomOccasionLocal() async {
    final selected = _selectedOccasion;

    if (systemOccasions.contains(selected)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStr.builtInValue)));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    final snapshot = await ref.get();
    if (!mounted) return;
    if (!snapshot.exists) return;

    if (snapshot.value is! Map) return;
    final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
    final occasionList = _parsePairList(data['occasion']);
    final index = occasionList.indexWhere((pair) => pair[0] == selected);
    if (index == -1) {
      return;
    }

    if (occasionList[index][1] == 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$selected" is used in a review and cannot be removed',
          ),
        ),
      );
      return;
    }

    occasionList.removeAt(index);
    await ref.update({'occasion': occasionList});
    if (!mounted) return;
    SessionCache.customOccasions = _mergedAndSorted(
      systemOccasions,
      occasionList.map((p) => p[0] as String).toList(),
    );

    if (!mounted) return;
    setState(() {
      _selectedOccasion = '';
      _isEditingOccasion = false;
      _occasionEditController.clear();
      _occasionController.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"$selected" has been removed')));
  }

  // ---------------- Country handlers ----------------
  Future<void> _addCustomCountry() async {
    final newCountry = _selectedCountry.trim();
    if (newCountry.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.enterCustomCountry)));
      return;
    }

    if (!allCountries.contains(newCountry)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$newCountry" ${AppStr.notApprovedCountry}')),
      );
      return;
    }
    final exists = _mergedAndSorted(
      getSystemCountryNames(),
      SessionCache.customCountries,
    ).any((c) => c.toLowerCase() == newCountry.toLowerCase());
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$newCountry" ${AppStr.alreadyInList}')),
      );
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    final snapshot = await ref.get();
    if (!mounted) return;
    List<String> updatedCountries = [];
    if (snapshot.exists) {
      if (snapshot.value is! Map) return;
      final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
      updatedCountries = List<String>.from(data['country'] ?? []);
      updatedCountries.add(newCountry);
      await ref.update({'country': updatedCountries});
    } else {
      updatedCountries = [newCountry];
      await ref.set({
        'cuisine': [],
        'occasion': [],
        'country': updatedCountries,
      });
    }
    if (!mounted) return;
    SessionCache.customCountries = _mergedAndSorted(
      getSystemCountryNames(),
      updatedCountries,
    );
    if (!mounted) return;
    setState(() {
      _selectedCountry = newCountry;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$newCountry" ${AppStr.addedToCountries}')),
    );
  }

  Future<void> _loadCustomValPairs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('users/$uid/customvals')
          .get();
      if (!mounted || !snapshot.exists || snapshot.value is! Map) return;
      final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
      if (!mounted) return;
      setState(() {
        _cuisinePairs = _parsePairList(data['cuisine']);
        _occasionPairs = _parsePairList(data['occasion']);
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _selectedCuisine = '';
    _selectedOccasion = '';
    _selectedCountry = '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomValPairs());
  }

  @override
  void dispose() {
    _cuisineController.dispose();
    _cuisineEditController.dispose();
    _occasionController.dispose();
    _occasionEditController.dispose();
    super.dispose();
  }

  void _goBackToSettings() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) {
          return const SettingsScreen();
        },
      ),
    );
  }

  void _goToTopScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) {
          return const TopScreen();
        },
      ),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final extendedCuisines = _mergedAndSorted(
      systemCuisines,
      SessionCache.customCuisines,
    );
    final extendedOccasions = _mergedAndSorted(
      systemOccasions,
      SessionCache.customOccasions,
    );
    // Only offer countries not already in the user's list
    final countryList = allCountries
        .where((c) => !SessionCache.customCountries.contains(c))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        title: Text(
          AppStr.customValuesTitle,
          style: AppFonts.bold.copyWith(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ---------------- Cuisine UI ----------------
              TextField(
                controller: _isEditingCuisine
                    ? _cuisineEditController
                    : _cuisineController,
                decoration: InputDecoration(
                  labelText: _isEditingCuisine
                      ? AppStr.editCuisineLabel
                      : AppStr.newCuisineLabel,
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: extendedCuisines.contains(_selectedCuisine)
                    ? _selectedCuisine
                    : null,
                hint: Text(AppStr.selectCuisineHint, style: AppFonts.standard),
                items: extendedCuisines.map((c) {
                  final bool isCustom = !systemCuisines.contains(c);
                  return DropdownMenuItem<String>(
                    value: c,
                    child: Text(
                      isCustom ? '$c (custom)' : c,
                      style: AppFonts.standard,
                    ),
                  );
                }).toList(),
                selectedItemBuilder: (BuildContext context) {
                  return extendedCuisines.map((c) {
                    return Text(c, style: AppFonts.standard);
                  }).toList();
                },
                onChanged: (value) {
                  if (!mounted) return;
                  final rawValue = (value ?? '').replaceAll(' (custom)', '').trim();
                  final bool isCustom = !systemCuisines.contains(rawValue);
                  bool usedInReview = false;
                  if (isCustom && rawValue.isNotEmpty) {
                    final pair = _cuisinePairs.firstWhere(
                      (p) => p[0] == rawValue,
                      orElse: () => [rawValue, 0],
                    );
                    usedInReview = pair[1] == 1;
                  }
                  setState(() {
                    _selectedCuisine = rawValue;
                    _selectedCuisineUsed = usedInReview;
                    if (_isEditingCuisine) {
                      _cuisineEditController.text = _selectedCuisine;
                    }
                  });
                  if (isCustom && usedInReview) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStr.valueUsedInReview),
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: AppStr.currentCuisinesLabel,
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _isBusy
                          ? null
                          : () {
                              _withBusy(() async {
                                await _addCustomCuisine();
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.btnAdd,
                        foregroundColor: AppColors.btnText,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        AppStr.add,
                        style: AppFonts.standard.copyWith(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: (_isBusy || systemCuisines.contains(_selectedCuisine) || _selectedCuisineUsed)
                          ? null
                          : () {
                              _withBusy(() async {
                                await _removeCustomCuisine();
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        AppStr.removeButton,
                        style: AppFonts.standard.copyWith(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: (_isBusy || systemCuisines.contains(_selectedCuisine) || _selectedCuisineUsed)
                          ? null
                          : () {
                              if (_selectedCuisine.isEmpty) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please select a cuisine to edit',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _isEditingCuisine = true;
                                _cuisineEditController.text = _selectedCuisine;
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        AppStr.edit,
                        style: AppFonts.standard.copyWith(fontSize: 13),
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  SizedBox(
                    width: 40,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: (!_isEditingCuisine || _isBusy)
                          ? null
                          : () {
                              _withBusy(() async {
                                await _saveEditedCuisine();
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isEditingCuisine
                            ? AppColors.lightGreenAccent
                            : AppColors.greyShade300,
                        disabledBackgroundColor: AppColors.greyShade300,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  SizedBox(
                    width: 40,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isEditingCuisine = false;
                          _cuisineEditController.clear();
                          _cuisineController.clear();
                          _selectedCuisine = '';
                          _selectedCuisineUsed = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.redShade100,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const Divider(height: 32, thickness: 1),

              // ---------------- Occasion UI (mirrors Cuisine) ----------------
              TextField(
                controller: _isEditingOccasion
                    ? _occasionEditController
                    : _occasionController,
                decoration: InputDecoration(
                  labelText: _isEditingOccasion
                      ? AppStr.editOccasionLabel
                      : AppStr.occasionLabel,
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: extendedOccasions.contains(_selectedOccasion)
                    ? _selectedOccasion
                    : null,
                hint: Text(AppStr.selectOccasionHint, style: AppFonts.standard),
                items: extendedOccasions.map((c) {
                  final bool isCustom = !systemOccasions.contains(c);
                  return DropdownMenuItem<String>(
                    value: c,
                    child: Text(
                      isCustom ? '$c (custom)' : c,
                      style: AppFonts.standard,
                    ),
                  );
                }).toList(),
                selectedItemBuilder: (BuildContext context) {
                  return extendedOccasions.map((c) {
                    return Text(c, style: AppFonts.standard);
                  }).toList();
                },
                onChanged: (value) {
                  if (!mounted) return;
                  final rawValue = (value ?? '').replaceAll(' (custom)', '').trim();
                  final bool isCustom = !systemOccasions.contains(rawValue);
                  bool usedInReview = false;
                  if (isCustom && rawValue.isNotEmpty) {
                    final pair = _occasionPairs.firstWhere(
                      (p) => p[0] == rawValue,
                      orElse: () => [rawValue, 0],
                    );
                    usedInReview = pair[1] == 1;
                  }
                  setState(() {
                    _selectedOccasion = rawValue;
                    _selectedOccasionUsed = usedInReview;
                    if (_isEditingOccasion) {
                      _occasionEditController.text = _selectedOccasion;
                    }
                  });
                  if (isCustom && usedInReview) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStr.valueUsedInReview),
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: AppStr.currentOccasionsLabel,
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _isBusy
                          ? null
                          : () {
                              _withBusy(() async {
                                await _addCustomOccasionLocal();
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.btnAdd,
                        foregroundColor: AppColors.btnText,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        AppStr.add,
                        style: AppFonts.standard.copyWith(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: (_isBusy || systemOccasions.contains(_selectedOccasion) || _selectedOccasionUsed)
                          ? null
                          : () {
                              _withBusy(() async {
                                await _removeCustomOccasionLocal();
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        AppStr.removeButton,
                        style: AppFonts.standard.copyWith(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: (_isBusy || systemOccasions.contains(_selectedOccasion) || _selectedOccasionUsed)
                          ? null
                          : () {
                              if (_selectedOccasion.isEmpty) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please select an occasion to edit',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _isEditingOccasion = true;
                                _occasionEditController.text =
                                    _selectedOccasion;
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        AppStr.edit,
                        style: AppFonts.standard.copyWith(fontSize: 13),
                      ),
                    ),
                  ),

                  const SizedBox(width: 24),

                  SizedBox(
                    width: 40,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: (!_isEditingOccasion || _isBusy)
                          ? null
                          : () {
                              _withBusy(() async {
                                await _saveEditedOccasion();
                              });
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isEditingOccasion
                            ? AppColors.lightGreenAccent
                            : AppColors.greyShade300,
                        disabledBackgroundColor: AppColors.greyShade300,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  SizedBox(
                    width: 40,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isEditingOccasion = false;
                          _occasionEditController.clear();
                          _occasionController.clear();
                          _selectedOccasion = '';
                          _selectedOccasionUsed = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.redShade100,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const Divider(height: 32, thickness: 1),

              // ---------------- Country UI ----------------
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: countryList.contains(_selectedCountry)
                    ? _selectedCountry
                    : null,
                hint: Text(AppStr.selectCountryHint, style: AppFonts.standard),
                items: countryList.map((c) {
                  return DropdownMenuItem<String>(
                    value: c,
                    child: Text(c, style: AppFonts.standard),
                  );
                }).toList(),
                onChanged: (value) {
                  if (!mounted) return;
                  // only set local selection here; do NOT add to DB until user taps Add Country
                  setState(() {
                    _selectedCountry = value ?? '';
                  });
                },
                decoration: InputDecoration(
                  labelText: AppStr.countryLabel,
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _isBusy
                    ? null
                    : () {
                        _withBusy(() async {
                          await _addCustomCountry();
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.btnAdd,
                  foregroundColor: AppColors.btnText,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(AppStr.addCountry, style: AppFonts.standard),
              ),

              const Divider(height: 32, thickness: 1),

              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _goBackToSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ochre,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(100, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(AppStr.back, style: AppFonts.standard),
                  ),
                  ElevatedButton(
                    onPressed: _goToTopScreen,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(100, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      AppStr.done,
                      style: AppFonts.standard.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// general_screen.dart
// Collects general review information including restaurant, city, cuisine, occasion, date, diners, and cost.
// Uses default country from SessionCache and passes data via ReviewContext.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'ratings_screen.dart';
import 'sub_preview_screen/review_context.dart';
import 'constants/restiview_constants.dart';
import 'constants/colors.dart';
import 'services/session_cache.dart';
import 'top_screen.dart';
import 'services/location_restaurant_helper.dart';
import 'constants/strings.dart';

class GeneralScreen extends StatefulWidget {
  final ReviewContext context;

  const GeneralScreen({super.key, required this.context});

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _restaurantController;
  late TextEditingController _cityController;
  late TextEditingController _dinersController;
  late TextEditingController _costController;
  final TextEditingController _newCuisineController = TextEditingController();
  final TextEditingController _newOccasionController = TextEditingController();

  int _restaurantSearchAttempts = 0;
  bool _isSearching = false;
  bool _showAddCuisineField = false;
  bool _showAddOccasionField = false;

  late String _selectedCuisine;
  late String _selectedOccasion;
  DateTime _selectedDate = DateTime.now();
  List<NearbyRestaurant> _restaurantOptions = [];

  @override
  void initState() {
    super.initState();

    final reviewMap = widget.context.reviewMap;

    // Ensure context has sensible defaults when creating a new review flow
    if (!widget.context.isEditing && reviewMap.isEmpty) {
      widget.context.reviewMap.addAll({
        'restaurantName': '',
        'country': SessionCache.defaultCountry,
        'city': '',
        'cuisine': systemCuisines.first,
        'occasion': AppStr.defaultOccasion,
        'numberOfDiners': '',
        'cost': '',
        'currency': SessionCache.currency,
        'dateOfReview': DateTime.now().toIso8601String(),
      });
      widget.context.isEditing = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoFillRestaurantFromLocation();
      });
    }

    _restaurantController = TextEditingController(text: reviewMap['restaurantName'] ?? '');
    _cityController = TextEditingController(text: reviewMap['city'] ?? '');
    _dinersController = TextEditingController(text: reviewMap['numberOfDiners']?.toString() ?? '');
    final costValue = reviewMap['cost'];
    _costController = TextEditingController(
      text: (costValue == null || costValue == '0') ? '' : costValue.toString(),
    );

    final cuisine = reviewMap['cuisine'] as String?;
    _selectedCuisine = (cuisine != null && SessionCache.customCuisines.contains(cuisine)) ? cuisine : '';

    final occasion = reviewMap['occasion'] as String?;
    _selectedOccasion = occasion ?? AppStr.defaultOccasion;

    if (reviewMap['dateOfReview'] != null) {
      _selectedDate = DateTime.tryParse(reviewMap['dateOfReview']) ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _cityController.dispose();
    _dinersController.dispose();
    _costController.dispose();
    _newCuisineController.dispose();
    _newOccasionController.dispose();
    super.dispose();
  }

  Future<bool> getLocationPermissionStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) return false;
      if (permission == LocationPermission.denied) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addInlineCustomCuisine() async {
    final messenger = ScaffoldMessenger.of(context);
    final newCuisine = _newCuisineController.text.trim();
    if (newCuisine.isEmpty) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStr.cuisineRequired)),
      );
      return;
    }

    final existsLocally = SessionCache.customCuisines.any(
      (c) => c.toLowerCase() == newCuisine.toLowerCase(),
    );
    if (existsLocally) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStr.cuisineExists)),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    try {
      final snapshot = await ref.get();
      if (!mounted) return;

      final List<List<dynamic>> updatedCustoms = [];

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final raw = data['cuisine'];
        if (raw is List) {
          for (final item in raw) {
            if (item is List && item.isNotEmpty) {
              updatedCustoms.add(List<dynamic>.from(item));
            }
          }
        }
        updatedCustoms.add([newCuisine, 0]);
      } else {
        updatedCustoms.add([newCuisine, 0]);
      }

      updatedCustoms.sort((a, b) =>
          (a[0] as String).toLowerCase().compareTo((b[0] as String).toLowerCase()));

      if (snapshot.exists) {
        await ref.update({'cuisine': updatedCustoms});
      } else {
        await ref.set({
          'cuisine': updatedCustoms,
          'occasion': [],
          'country': [],
        });
      }

      final merged = <String>[];
      for (final s in systemCuisines) {
        if (!merged.contains(s)) merged.add(s);
      }
      for (final pair in updatedCustoms) {
        final name = pair[0] as String;
        if (!merged.contains(name)) merged.add(name);
      }
      SessionCache.customCuisines = merged;

      if (!mounted) return;
      setState(() {
        _selectedCuisine = newCuisine;
        _newCuisineController.clear();
        _showAddCuisineField = false;
      });

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStr.cuisineAdded)),
      );
    } catch (e) {
      if (!mounted) return;
      final messengerErr = ScaffoldMessenger.of(context);
      messengerErr.showSnackBar(
        SnackBar(content: Text('${AppStr.saveError}: $e')),
      );
    }
  }

  Future<void> _addInlineCustomOccasion() async {
    final messenger = ScaffoldMessenger.of(context);
    final newOccasion = _newOccasionController.text.trim();

    if (newOccasion.isEmpty || newOccasion.length > 24) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStr.occasionMaxLength)),
      );
      return;
    }

    final existsLocally = SessionCache.customOccasions.any(
      (o) => o.toLowerCase() == newOccasion.toLowerCase(),
    );
    if (existsLocally) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('"$newOccasion" ${AppStr.alreadyExists}')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    try {
      final snapshot = await ref.get();
      if (!mounted) return;

      final List<List<dynamic>> updatedOccasions = [];

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final raw = data['occasion'];
        if (raw is List) {
          for (final item in raw) {
            if (item is List && item.isNotEmpty) {
              updatedOccasions.add(List<dynamic>.from(item));
            }
          }
        }
        updatedOccasions.add([newOccasion, 0]);
      } else {
        updatedOccasions.add([newOccasion, 0]);
      }

      updatedOccasions.sort((a, b) =>
          (a[0] as String).toLowerCase().compareTo((b[0] as String).toLowerCase()));

      if (snapshot.exists) {
        await ref.update({'occasion': updatedOccasions});
      } else {
        await ref.set({
          'cuisine': [],
          'occasion': updatedOccasions,
          'country': [],
        });
      }

      final merged = <String>[];
      for (final s in systemOccasions) {
        if (!merged.contains(s)) merged.add(s);
      }
      for (final pair in updatedOccasions) {
        final name = pair[0] as String;
        if (!merged.contains(name)) merged.add(name);
      }
      merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      SessionCache.customOccasions = merged;

      if (!mounted) return;
      setState(() {
        _selectedOccasion = newOccasion;
        _newOccasionController.clear();
        _showAddOccasionField = false;
      });

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('"$newOccasion" ${AppStr.addedToOccasions}')),
      );
    } catch (e) {
      if (!mounted) return;
      final messengerErr = ScaffoldMessenger.of(context);
      messengerErr.showSnackBar(
        SnackBar(content: Text('${AppStr.saveError}: $e')),
      );
    }
  }

  void _clearForm() {
    if (!mounted) return;
    setState(() {
      _restaurantController.clear();
      _cityController.clear();
      _dinersController.clear();
      _costController.clear();
      _selectedCuisine = '';
      _selectedOccasion = AppStr.defaultOccasion;
      _selectedDate = DateTime.now();

      _newCuisineController.clear();
      _newOccasionController.clear();
      _showAddCuisineField = false;
      _showAddOccasionField = false;

      final reviewMap = widget.context.reviewMap;
      reviewMap['restaurantName'] = '';
      reviewMap['city'] = '';
      reviewMap['cuisine'] = '';
      reviewMap['occasion'] = '';
      reviewMap['numberOfDiners'] = '';
      reviewMap['cost'] = '';
      reviewMap['dateOfReview'] = _selectedDate.toIso8601String();
      reviewMap['restaddress'] = '';
      reviewMap['restphone'] = '';
    });
  }

  void _showRestaurantSelector() async {
    final selected = await showDialog<NearbyRestaurant>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppStr.selectRestaurant, style: AppFonts.bold),
        children: _restaurantOptions.map((rest) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, rest),
            child: Text(rest.name),
          );
        }).toList(),
      ),
    );

    if (selected != null && mounted) {
      final isValidCuisine = SessionCache.customCuisines.contains(selected.cuisine);

      setState(() {
        widget.context.reviewMap['restaurantName'] = selected.name;
        widget.context.reviewMap['restaddress'] = selected.address;
        widget.context.reviewMap['restphone'] = selected.phone ?? '';
        widget.context.reviewMap['city'] = selected.city;
        widget.context.reviewMap['cuisine'] = isValidCuisine ? selected.cuisine : '';

        _restaurantController.text = selected.name;
        _cityController.text = selected.city;
        _selectedCuisine = isValidCuisine ? selected.cuisine : '';
      });
    }
  }

  Future<void> _autoFillRestaurantFromLocation() async {
    _restaurantSearchAttempts++;
    if (mounted) setState(() => _isSearching = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      if (!SessionCache.allowLocation) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Location search skipped — allowLocation is false.')),
        );
        return;
      }

      final ready = await getLocationPermissionStatus();
      if (!ready) {
        if (!mounted) return;

        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Location services are disabled. Please enable them in Settings.')),
          );
          await Geolocator.openLocationSettings();
          return;
        }

        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.deniedForever) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Location permission permanently denied. Enable it in app settings.')),
          );
          return;
        }

        if (permission == LocationPermission.denied) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Location permission denied. Cannot auto-fill.')),
          );
          return;
        }

        return;
      }

      final results = await findNearbyRestaurants().timeout(const Duration(seconds: 12));
      if (!mounted) return;

      if (results.isNotEmpty) {
        _restaurantOptions = results;
        final selected = results.first;
        final isValidCuisine = SessionCache.customCuisines.contains(selected.cuisine);

        if (!mounted) return;
        setState(() {
          widget.context.reviewMap['restaurantName'] = selected.name;
          widget.context.reviewMap['restaddress'] = selected.address;
          widget.context.reviewMap['restphone'] = selected.phone ?? '';
          widget.context.reviewMap['city'] = selected.city;
          widget.context.reviewMap['cuisine'] = isValidCuisine ? selected.cuisine : '';

          _restaurantController.text = selected.name;
          _cityController.text = selected.city;
          _selectedCuisine = isValidCuisine ? selected.cuisine : '';
        });

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('${AppStr.autoFillSuccess} ${selected.name}')),
        );
      } else {
        if (!mounted) return;
        _clearForm();
        final message = _restaurantSearchAttempts >= 2 ? AppStr.autoFillFailed : AppStr.autoFillNone;
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on TimeoutException {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(AppStr.autoFillFailed)));
    } catch (e) {
      if (!mounted) return;
      final message = _restaurantSearchAttempts >= 2 ? AppStr.autoFillFailed : 'Search failed: $e';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _saveGeneralInfoToMap() {
    final reviewMap = widget.context.reviewMap;

    reviewMap['restaurantName'] = _restaurantController.text;
    reviewMap['country'] = SessionCache.defaultCountry;
    reviewMap['city'] = _cityController.text;
    reviewMap['cuisine'] = SessionCache.customCuisines.contains(_selectedCuisine) ? _selectedCuisine : '';
    reviewMap['occasion'] = _selectedOccasion;
    final dinersText = _dinersController.text.trim();
    reviewMap['numberOfDiners'] = dinersText.isEmpty ? '' : int.tryParse(dinersText);
    final costText = _costController.text.trim();
    reviewMap['cost'] = costText.isEmpty ? '' : costText;
    reviewMap['currency'] = SessionCache.currency;
    reviewMap['dateOfReview'] = _selectedDate.toIso8601String();
  }

  void _goToRatingsScreen() {
    if (_formKey.currentState?.validate() ?? false) {
      _saveGeneralInfoToMap();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RatingsScreen(context: widget.context),
        ),
      );
    }
  }

  void _goBackToTop() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStr.discardTitle),
        content: const Text(AppStr.discardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStr.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStr.yes),
          ),
        ],
      ),
    );

    if (shouldLeave ?? false) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => TopScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topCities = systemCitiesByCountry[SessionCache.defaultCountry] ?? [];
    final cuisineItemsOrdered = <String>{}
      ..addAll(systemCuisines)
      ..addAll(SessionCache.customCuisines);
    final cuisineList = cuisineItemsOrdered.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final occasionItemsOrdered = <String>[
      ...systemOccasions,
      ...SessionCache.customOccasions.where((o) => !systemOccasions.contains(o)),
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(AppStr.generalInfo, style: AppFonts.bold.copyWith(color: Colors.white)),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          return Stack(
            children: [
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _restaurantController,
                            decoration: const InputDecoration(labelText: AppStr.restaurantLabel),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return AppStr.restaurantRequired;
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Autocomplete<String>(
                            optionsBuilder: (textEditingValue) {
                              if (textEditingValue.text == '' || topCities.isEmpty) return const Iterable<String>.empty();
                              return topCities.where((city) => city.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                            },
                            onSelected: (selection) => _cityController.text = selection,
                            fieldViewBuilder: (fieldCtx, controller, focusNode, onEditingComplete) {
                              return TextField(
                                controller: _cityController,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  labelText: AppStr.cityLabel,
                                  hintText: topCities.isEmpty ? AppStr.cityHint : null,
                                ),
                                onEditingComplete: onEditingComplete,
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: cuisineList.contains(_selectedCuisine) ? _selectedCuisine : null,
                                      items: cuisineList.map((cuisine) => DropdownMenuItem(value: cuisine, child: Text(cuisine))).toList(),
                                      onChanged: (value) {
                                        if (!mounted) return;
                                        setState(() => _selectedCuisine = value ?? '');
                                      },
                                      decoration: const InputDecoration(labelText: AppStr.cuisineLabel),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      if (!mounted) return;
                                      setState(() => _showAddCuisineField = !_showAddCuisineField);
                                    },
                                    child: Text(AppStr.add, style: AppFonts.standard),
                                  ),
                                ],
                              ),
                              if (_showAddCuisineField)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _newCuisineController,
                                          decoration: const InputDecoration(hintText: AppStr.newCuisineHint),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: AppStr.confirm,
                                        color: Colors.green,
                                        icon: const Icon(Icons.check),
                                        onPressed: () async => await _addInlineCustomCuisine(),
                                      ),
                                      IconButton(
                                        tooltip: AppStr.cancel,
                                        color: Colors.grey,
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          if (!mounted) return;
                                          setState(() {
                                            _newCuisineController.clear();
                                            _showAddCuisineField = false;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          // Occasion moved here under cuisine
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: occasionItemsOrdered.contains(_selectedOccasion) ? _selectedOccasion : occasionItemsOrdered.first,
                                      items: occasionItemsOrdered
                                          .map((occasion) => DropdownMenuItem(value: occasion, child: Text(occasion)))
                                          .toList(),
                                      onChanged: (value) {
                                        if (!mounted) return;
                                        setState(() => _selectedOccasion = value ?? AppStr.defaultOccasion);
                                      },
                                      decoration: const InputDecoration(labelText: AppStr.occasionLabel),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      if (!mounted) return;
                                      setState(() => _showAddOccasionField = !_showAddOccasionField);
                                    },
                                    child: Text(AppStr.add, style: AppFonts.standard),
                                  ),
                                ],
                              ),
                              if (_showAddOccasionField)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _newOccasionController,
                                          decoration: const InputDecoration(hintText: AppStr.newOccasionHint),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: AppStr.confirm,
                                        color: Colors.green,
                                        icon: const Icon(Icons.check),
                                        onPressed: () async => await _addInlineCustomOccasion(),
                                      ),
                                      IconButton(
                                        tooltip: AppStr.cancel,
                                        color: Colors.grey,
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          if (!mounted) return;
                                          setState(() {
                                            _newOccasionController.clear();
                                            _showAddOccasionField = false;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          TextField(
                            controller: _dinersController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: AppStr.dinersLabel),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text(AppStr.costLabel, style: AppFonts.standard),
                              const SizedBox(width: 12),
                              Text(SessionCache.currency, style: AppFonts.standard),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _costController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: AppStr.amountLabel),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text('${AppStr.dateLabel} ${_selectedDate.toLocal().toString().split(' ')[0]}', style: AppFonts.standard),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () async {
                                  DateTime? picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: _selectedDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null && mounted) {
                                    setState(() => _selectedDate = picked);
                                  }
                                },
                                child: Text(AppStr.pickDate, style: AppFonts.standard),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text('Location search : ', style: AppFonts.standard),
                              SessionCache.allowLocation
                                  ? Expanded(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: _restaurantOptions.length > 1
                                            ? ElevatedButton(
                                                onPressed: _showRestaurantSelector,
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                                                child: Text(AppStr.multi, style: AppFonts.standard),
                                              )
                                            : ElevatedButton(
                                                onPressed: _autoFillRestaurantFromLocation,
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                                child: Text(AppStr.search, style: AppFonts.standard.copyWith(color: Colors.white)),
                                              ),
                                      ),
                                    )
                                  : Text(
                                      '(OFF)',
                                      style: AppFonts.standard.copyWith(color: AppColors.mutedText, fontStyle: FontStyle.italic),
                                    ),
                            ],
                          ),
                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_isSearching)
                Container(
                  color: Colors.black.withAlpha(77),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _goBackToTop,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.ochre),
                child: Text(AppStr.back, style: AppFonts.standard.copyWith(color: Colors.black)),
              ),
              ElevatedButton(
                onPressed: _clearForm,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.lightGrey),
                child: Text(AppStr.clear, style: AppFonts.standard.copyWith(color: Colors.black87)),
              ),
              ElevatedButton(
                onPressed: _goToRatingsScreen,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black),
                child: Text(AppStr.next, style: AppFonts.standard.copyWith(color: Colors.black)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
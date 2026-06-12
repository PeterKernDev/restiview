// general_screen.dart
// Collects general review information including restaurant, city, cuisine, occasion, date, diners, and cost.
// Uses default country from SessionCache and passes data via ReviewContext.

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'comments_screen.dart';
import 'sub_preview_screen/review_context.dart';
import 'constants/restiview_constants.dart';
import 'constants/colors.dart';
import 'services/session_cache.dart';
import 'top_screen.dart';
import 'services/location_restaurant_helper.dart';
import 'constants/strings.dart';
import 'constants/fonts.dart';

class GeneralScreen extends StatefulWidget {
  final ReviewContext context;

  const GeneralScreen({super.key, required this.context});

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
    bool _countryMismatchChecked = false;

  final _formKey = GlobalKey<FormState>();

  late TextEditingController _restaurantController;
  late TextEditingController _cityController;
  late TextEditingController _dinersController;
  final TextEditingController _newCuisineController = TextEditingController();
  final TextEditingController _newOccasionController = TextEditingController();
  final FocusNode _restaurantFocusNode = FocusNode();

  int _restaurantSearchAttempts = 0;
  bool _isSearching = false;
  bool _isLookingUpName = false;
  bool _showAddCuisineField = false;
  bool _showAddOccasionField = false;

  late String _selectedCuisine;
  late String _selectedOccasion;
  DateTime _selectedDate = DateTime.now();
  List<NearbyRestaurant> _restaurantOptions = [];
  bool _searchDoneNoResults = false;
  NearbyRestaurant? _selectedGeoRestaurant;

  Future<void> checkCountryMismatch() async {
    if (_countryMismatchChecked) return;
    _countryMismatchChecked = true;
    final String? currentCountry = await getCurrentCountrySafe();
    final String homeCountry = SessionCache.defaultCountry;
    if (currentCountry != null && currentCountry.isNotEmpty && currentCountry != homeCountry) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(AppStr.countryMismatchTitle),
            content: const Text(AppStr.countryMismatchBody),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    SessionCache.defaultCountry = currentCountry;
                    widget.context.reviewMap['country'] = currentCountry;
                  });
                },
                child: const Text(AppStr.countryMismatchUpdate),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(AppStr.countryMismatchContinue),
              ),
            ],
          );
        },
      );
    }
  }

  /// Sequences the post-frame initialisation for new reviews: country mismatch
  /// check first (may show a dialog and awaits user response), then location
  /// search. Running them concurrently caused Geolocator to hang because
  /// checkCountryMismatch uses getCurrentLocationSafe() at the same time as
  /// _autoFillRestaurantFromLocation calls requestPermission().
  Future<void> _initAfterFirstFrame() async {
    await checkCountryMismatch();
    if (!mounted) {
      return;
    }
    _autoFillRestaurantFromLocation();
  }

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

      // Warm up cuisine cache in background (fire-and-forget)
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null && !SessionCache.restaurantCuisineCacheLoaded) {
        SessionCache.warmUpRestaurantCuisineCache(userId);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _initAfterFirstFrame();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        checkCountryMismatch();
      });
    }

    _restaurantController = TextEditingController(
      text: reviewMap['restaurantName'] ?? '',
    );
    _cityController = TextEditingController(text: reviewMap['city'] ?? '');
    _dinersController = TextEditingController(
      text: reviewMap['numberOfDiners']?.toString() ?? '',
    );

    // Add listeners to track changes
    _restaurantController.addListener(() => widget.context.hasChanges = true);
    _cityController.addListener(() => widget.context.hasChanges = true);
    _dinersController.addListener(() => widget.context.hasChanges = true);

    // When the user manually types a restaurant name and moves focus away,
    // attempt a name-based lookup to fill city, cuisine, address and phone.
    _restaurantFocusNode.addListener(() {
      if (!_restaurantFocusNode.hasFocus) {
        _lookUpRestaurantByName();
      }
    });

    final cuisine = reviewMap['cuisine'] as String?;
    _selectedCuisine =
        (cuisine != null && SessionCache.customCuisines.contains(cuisine))
        ? cuisine
        : '';

    final occasion = reviewMap['occasion'] as String?;
    _selectedOccasion = occasion ?? AppStr.defaultOccasion;

    if (reviewMap['dateOfReview'] != null) {
      _selectedDate =
          DateTime.tryParse(reviewMap['dateOfReview']) ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _cityController.dispose();
    _dinersController.dispose();
    _newCuisineController.dispose();
    _newOccasionController.dispose();
    _restaurantFocusNode.dispose();
    super.dispose();
  }

  /// Fires a Places Text Search for the manually typed restaurant name.
  /// Only runs when:
  ///   • the name field has at least 3 characters
  ///   • restaddress is currently empty (not already filled by geo search)
  ///   • a lookup is not already in progress
  /// Fills city (if blank), cuisine (if blank/unknown), restaddress and
  /// restphone silently. Shows a brief snackbar on success.
  Future<void> _lookUpRestaurantByName() async {
    final String name = _restaurantController.text.trim();
    if (name.length < 3) {
      return;
    }
    final String existingAddress =
        (widget.context.reviewMap['restaddress'] as String?)?.trim() ?? '';
    if (existingAddress.isNotEmpty) {
      return;
    }
    if (_isLookingUpName || _isSearching) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLookingUpName = true;
      });
    }

    try {
      final NearbyRestaurant? found = await searchRestaurantByName(name);
      if (!mounted) {
        return;
      }

      if (found != null) {
        // Resolve cuisine — prefer history cache, then API guess, don't
        // overwrite a choice the user already made.
        final String existingCuisine =
            (widget.context.reviewMap['cuisine'] as String?)?.trim() ?? '';
        final bool cuisineBlank =
            existingCuisine.isEmpty || existingCuisine == 'Unknown';
        final String cacheKey =
            '${SessionCache.defaultCountry}|${name.toLowerCase()}';
        final String? cachedCuisine =
            SessionCache.restaurantCuisineCache[cacheKey];
        final String resolvedCuisine;
        if (!cuisineBlank) {
          resolvedCuisine = existingCuisine;
        } else if (cachedCuisine != null &&
            SessionCache.customCuisines.contains(cachedCuisine)) {
          resolvedCuisine = cachedCuisine;
        } else if (SessionCache.customCuisines.contains(found.cuisine)) {
          resolvedCuisine = found.cuisine;
        } else {
          resolvedCuisine = existingCuisine;
        }

        setState(() {
          widget.context.reviewMap['restaddress'] = found.address;
          widget.context.reviewMap['restphone'] = found.phone ?? '';

          if (_cityController.text.trim().isEmpty && found.city.isNotEmpty) {
            _cityController.text = found.city;
            widget.context.reviewMap['city'] = found.city;
          }

          if (cuisineBlank && resolvedCuisine.isNotEmpty) {
            _selectedCuisine = resolvedCuisine;
            widget.context.reviewMap['cuisine'] = resolvedCuisine;
          }

          widget.context.hasChanges = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.restDetailsFound)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLookingUpName = false;
        });
      }
    }
  }

  Future<bool> getLocationPermissionStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }
      if (permission == LocationPermission.denied) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addInlineCustomCuisine() async {
    final String newCuisine = _newCuisineController.text.trim();
    if (newCuisine.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.cuisineRequired)));
      return;
    }

    final bool existsLocally = SessionCache.customCuisines.any(
      (c) => c.toLowerCase() == newCuisine.toLowerCase(),
    );
    if (existsLocally) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.cuisineExists)));
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final DatabaseReference ref = FirebaseDatabase.instance.ref(
      'users/$uid/customvals',
    );
    try {
      final DataSnapshot snapshot = await ref.get();
      if (!mounted) {
        return;
      }

      final List<List<dynamic>> updatedCustoms = <List<dynamic>>[];

      if (snapshot.exists) {
        final Map<dynamic, dynamic> data =
            snapshot.value as Map<dynamic, dynamic>;
        final dynamic raw = data['cuisine'];
        if (raw is List) {
          for (final dynamic item in raw) {
            if (item is List && item.isNotEmpty) {
              updatedCustoms.add(List<dynamic>.from(item));
            }
          }
        }
        updatedCustoms.add([newCuisine, 0]);
      } else {
        updatedCustoms.add([newCuisine, 0]);
      }

      updatedCustoms.sort(
        (a, b) => (a[0] as String).toLowerCase().compareTo(
          (b[0] as String).toLowerCase(),
        ),
      );

      if (snapshot.exists) {
        await ref.update({'cuisine': updatedCustoms});
      } else {
        await ref.set({
          'cuisine': updatedCustoms,
          'occasion': [],
          'country': [],
        });
      }

      final List<String> merged = <String>[];
      for (final String s in systemCuisines) {
        if (!merged.contains(s)) {
          merged.add(s);
        }
      }
      for (final List<dynamic> pair in updatedCustoms) {
        final String name = pair[0] as String;
        if (!merged.contains(name)) {
          merged.add(name);
        }
      }
      SessionCache.customCuisines = merged;

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedCuisine = newCuisine;
        _newCuisineController.clear();
        _showAddCuisineField = false;
        widget.context.hasChanges = true;
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.cuisineAdded)));
    } catch (e) {
      appLog('Error adding custom cuisine: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.saveError)));
    }
  }

  Future<void> _addInlineCustomOccasion() async {
    final String newOccasion = _newOccasionController.text.trim();
    if (newOccasion.isEmpty || newOccasion.length > 24) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.occasionMaxLength)));
      return;
    }

    final bool existsLocally = SessionCache.customOccasions.any(
      (o) => o.toLowerCase() == newOccasion.toLowerCase(),
    );
    if (existsLocally) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$newOccasion" ${AppStr.alreadyExists}')),
      );
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final DatabaseReference ref = FirebaseDatabase.instance.ref(
      'users/$uid/customvals',
    );
    try {
      final DataSnapshot snapshot = await ref.get();
      if (!mounted) {
        return;
      }

      final List<List<dynamic>> updatedOccasions = <List<dynamic>>[];

      if (snapshot.exists) {
        final Map<dynamic, dynamic> data =
            snapshot.value as Map<dynamic, dynamic>;
        final dynamic raw = data['occasion'];
        if (raw is List) {
          for (final dynamic item in raw) {
            if (item is List && item.isNotEmpty) {
              updatedOccasions.add(List<dynamic>.from(item));
            }
          }
        }
        updatedOccasions.add([newOccasion, 0]);
      } else {
        updatedOccasions.add([newOccasion, 0]);
      }

      updatedOccasions.sort(
        (a, b) => (a[0] as String).toLowerCase().compareTo(
          (b[0] as String).toLowerCase(),
        ),
      );

      if (snapshot.exists) {
        await ref.update({'occasion': updatedOccasions});
      } else {
        await ref.set({
          'cuisine': [],
          'occasion': updatedOccasions,
          'country': [],
        });
      }

      final List<String> merged = <String>[];
      for (final String s in systemOccasions) {
        if (!merged.contains(s)) {
          merged.add(s);
        }
      }
      for (final List<dynamic> pair in updatedOccasions) {
        final String name = pair[0] as String;
        if (!merged.contains(name)) {
          merged.add(name);
        }
      }
      merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      SessionCache.customOccasions = merged;

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedOccasion = newOccasion;
        _newOccasionController.clear();
        _showAddOccasionField = false;
        widget.context.hasChanges = true;
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$newOccasion" ${AppStr.addedToOccasions}')),
      );
    } catch (e) {
      appLog('Error adding custom occasion: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.saveError)));
    }
  }

  void _clearForm() {
    if (!mounted) {
      return;
    }
    setState(() {
      _restaurantController.clear();
      _cityController.clear();
      _dinersController.clear();
      _selectedCuisine = '';
      _selectedOccasion = AppStr.defaultOccasion;
      _selectedDate = DateTime.now();

      _newCuisineController.clear();
      _newOccasionController.clear();
      _showAddCuisineField = false;
      _showAddOccasionField = false;
      _restaurantOptions = [];
      _searchDoneNoResults = false;
      _selectedGeoRestaurant = null;

      final Map<String, dynamic> reviewMap = widget.context.reviewMap;
      reviewMap['restaurantName'] = '';
      reviewMap['city'] = '';
      reviewMap['cuisine'] = '';
      reviewMap['occasion'] = '';
      reviewMap['numberOfDiners'] = '';

      // Reset hasChanges after clearing form
      widget.context.hasChanges = false;
      reviewMap['cost'] = '';
      reviewMap['dateOfReview'] = _selectedDate.toIso8601String();
      reviewMap['restaddress'] = '';
      reviewMap['restphone'] = '';
    });
  }

  Future<void> _changeSearchRadius() async {
    int tempRadius = SessionCache.searchRadius;
    final int? newRadius = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Search Radius'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('${tempRadius}m', style: AppFonts.bold),
                  Slider(
                    value: tempRadius.toDouble(),
                    min: 10,
                    max: 200,
                    divisions: 19,
                    label: '${tempRadius}m',
                    onChanged: (double v) {
                      setDialogState(() => tempRadius = v.round());
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text(AppStr.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(tempRadius),
                  child: const Text(AppStr.search),
                ),
              ],
            );
          },
        );
      },
    );
    if (newRadius != null && mounted) {
      SessionCache.searchRadius = newRadius;
      await _autoFillRestaurantFromLocation();
    }
  }

  Future<void> _autoFillRestaurantFromLocation() async {
    _restaurantSearchAttempts += 1;
    if (mounted) {
      setState(() {
        _isSearching = true;
      });
    }

    try {
      if (!SessionCache.allowLocation) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStr.autoFillSkipped)));
        return;
      }

      final bool ready = await getLocationPermissionStatus();
      if (!ready) {
        if (!mounted) {
          return;
        }

        final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStr.locationDisabled)),
          );
          await Geolocator.openLocationSettings();
          return;
        }

        final LocationPermission permission =
            await Geolocator.checkPermission();
        if (permission == LocationPermission.deniedForever) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStr.permissionDeniedForever)),
          );
          return;
        }

        if (permission == LocationPermission.denied) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStr.permissionDenied)),
          );
          return;
        }

        return;
      }

      final List<NearbyRestaurant> results = await findNearbyRestaurants()
          .timeout(const Duration(seconds: 12));
      if (!mounted) {
        return;
      }

      if (results.isNotEmpty) {
        _restaurantOptions = results;
        final NearbyRestaurant selected = results.first;
        final bool isValidCuisine = SessionCache.customCuisines.contains(
          selected.cuisine,
        );

        // Check history cache first; fall back to keyword guess
        final String cacheKey =
            '${SessionCache.defaultCountry}|${selected.name.toLowerCase()}';
        final String? cachedCuisine =
            SessionCache.restaurantCuisineCache[cacheKey];
        final String resolvedCuisine =
            (cachedCuisine != null &&
                SessionCache.customCuisines.contains(cachedCuisine))
            ? cachedCuisine
            : (isValidCuisine ? selected.cuisine : '');
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedGeoRestaurant = selected;
          _searchDoneNoResults = false;
          widget.context.reviewMap['restaurantName'] = selected.name;
          widget.context.reviewMap['restaddress'] = selected.address;
          widget.context.reviewMap['restphone'] = selected.phone ?? '';
          widget.context.reviewMap['city'] = selected.city;
          widget.context.reviewMap['cuisine'] = resolvedCuisine;

          _restaurantController.text = selected.name;
          _cityController.text = selected.city;
          _selectedCuisine = resolvedCuisine;
        });

        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStr.autoFillSuccess} ${selected.name}')),
        );
      } else {
        if (!mounted) {
          return;
        }
        // Only reset the form if the restaurant name is currently empty
        if (_restaurantController.text.trim().isEmpty) {
          _clearForm();
        }
        if (mounted) {
          setState(() {
            _restaurantOptions = [];
            _searchDoneNoResults = true;
            _selectedGeoRestaurant = null;
          });
        }
        // No restaurants found, but we still have a location fix — use it to
        // back-fill the city field so the user doesn't have to type it manually.
        try {
          final String? detectedCity = await getCurrentCitySafe()
              .timeout(const Duration(seconds: 8));
          if (detectedCity != null && detectedCity.isNotEmpty && mounted) {
            setState(() {
              _cityController.text = detectedCity;
              widget.context.reviewMap['city'] = detectedCity;
              widget.context.hasChanges = true;
            });
          }
        } catch (_) {}
        if (!mounted) return;
        final String message = _restaurantSearchAttempts >= 2
            ? AppStr.autoFillFailed
            : AppStr.autoFillNone;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStr.autoFillFailed)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      appLog('Auto-fill search failed: $e');
      final String message = _restaurantSearchAttempts >= 2
          ? AppStr.autoFillFailed
          : AppStr.searchFailed;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _saveGeneralInfoToMap() {
    final Map<String, dynamic> reviewMap = widget.context.reviewMap;

    reviewMap['restaurantName'] = _restaurantController.text;
    reviewMap['country'] = SessionCache.defaultCountry;
    reviewMap['city'] = _cityController.text;
    reviewMap['cuisine'] =
        SessionCache.customCuisines.contains(_selectedCuisine)
        ? _selectedCuisine
        : '';
    reviewMap['occasion'] = _selectedOccasion;
    final String dinersText = _dinersController.text.trim();
    reviewMap['numberOfDiners'] = dinersText.isEmpty
        ? ''
        : int.tryParse(dinersText);
    reviewMap['currency'] = SessionCache.currency;
    reviewMap['dateOfReview'] = _selectedDate.toIso8601String();
  }

  void _goToRatingsScreen() {
    if (_formKey.currentState?.validate() ?? false) {
      _saveGeneralInfoToMap();
      if (!mounted) {
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommentsScreen(context: widget.context),
        ),
      );
    }
  }

  void _goBackToTop() async {
    // Only show warning if changes have been made
    bool shouldLeave = true;

    if (widget.context.hasChanges) {
      final bool? result = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(AppStr.discardTitle),
            content: const Text(AppStr.discardMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                child: const Text(AppStr.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                child: const Text(AppStr.yes),
              ),
            ],
          );
        },
      );
      shouldLeave = result ?? false;
    }

    if (shouldLeave) {
      if (!mounted) {
        return;
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => TopScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> topCities =
        systemCitiesByCountry[SessionCache.defaultCountry] ?? <String>[];
    final Set<String> cuisineItemsOrdered = <String>{}
      ..addAll(systemCuisines)
      ..addAll(SessionCache.customCuisines);
    final List<String> cuisineList = cuisineItemsOrdered.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final List<String> occasionItemsOrdered = <String>[
      ...systemOccasions,
      ...SessionCache.customOccasions.where(
        (String o) => !systemOccasions.contains(o),
      ),
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Helper to produce a style with colors using styleFrom (no MaterialStateProperty)
    ButtonStyle buttonStyle(Color bg, Color fg) {
      return ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        minimumSize: const Size(0, 44),
        textStyle: AppFonts.bold.copyWith(fontSize: 14),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          _goBackToTop();
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          AppStr.generalInfo,
          style: AppFonts.bold.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints constraints) {
          return Stack(
            children: <Widget>[
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (_restaurantOptions.length > 1)
                            DropdownButtonFormField<NearbyRestaurant>(
                              value: _selectedGeoRestaurant,
                              items: _restaurantOptions
                                  .map(
                                    (NearbyRestaurant r) =>
                                        DropdownMenuItem<NearbyRestaurant>(
                                          value: r,
                                          child: Text(r.name),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (NearbyRestaurant? selected) {
                                if (selected == null || !mounted) return;
                                final String cacheKey =
                                    '${SessionCache.defaultCountry}|${selected.name.toLowerCase()}';
                                final String? cachedCuisine =
                                    SessionCache.restaurantCuisineCache[cacheKey];
                                final bool isValidCuisine =
                                    SessionCache.customCuisines.contains(
                                      selected.cuisine,
                                    );
                                final String resolvedCuisine =
                                    (cachedCuisine != null &&
                                        SessionCache.customCuisines.contains(
                                          cachedCuisine,
                                        ))
                                    ? cachedCuisine
                                    : (isValidCuisine ? selected.cuisine : '');
                                setState(() {
                                  _selectedGeoRestaurant = selected;
                                  widget.context.reviewMap['restaurantName'] =
                                      selected.name;
                                  widget.context.reviewMap['restaddress'] =
                                      selected.address;
                                  widget.context.reviewMap['restphone'] =
                                      selected.phone ?? '';
                                  widget.context.reviewMap['city'] =
                                      selected.city;
                                  widget.context.reviewMap['cuisine'] =
                                      resolvedCuisine;
                                  _restaurantController.text = selected.name;
                                  _cityController.text = selected.city;
                                  _selectedCuisine = resolvedCuisine;
                                  widget.context.hasChanges = true;
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: AppStr.restaurantLabel,
                              ),
                              validator: (NearbyRestaurant? value) {
                                if (value == null) {
                                  return AppStr.restaurantRequired;
                                }
                                return null;
                              },
                            )
                          else if (_searchDoneNoResults)
                            DropdownButtonFormField<String>(
                              value: null,
                              hint: const Text('No restaurants found nearby'),
                              items: <DropdownMenuItem<String>>[
                                const DropdownMenuItem<String>(
                                  value: 'search_again',
                                  child: Text('Search again'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'search_radius',
                                  child: Text(
                                    'Search radius (${SessionCache.searchRadius}m)',
                                  ),
                                ),
                              ],
                              onChanged: (String? value) async {
                                if (value == 'search_again') {
                                  await _autoFillRestaurantFromLocation();
                                } else if (value == 'search_radius') {
                                  await _changeSearchRadius();
                                }
                              },
                              decoration: const InputDecoration(
                                labelText: AppStr.restaurantLabel,
                              ),
                              validator: (_) => AppStr.restaurantRequired,
                            )
                          else
                            TextFormField(
                              controller: _restaurantController,
                              focusNode: _restaurantFocusNode,
                              decoration: InputDecoration(
                                labelText: AppStr.restaurantLabel,
                                suffixIcon: _isLookingUpName
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: Padding(
                                          padding: EdgeInsets.all(12.0),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              validator: (String? value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppStr.restaurantRequired;
                                }
                                return null;
                              },
                            ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              'Country: ${widget.context.reviewMap['country'] ?? SessionCache.defaultCountry}',
                              style: AppFonts.standard.copyWith(
                                fontSize: 12,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Autocomplete<String>(
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text == '' ||
                                      topCities.isEmpty) {
                                    return const Iterable<String>.empty();
                                  }
                                  return topCities.where(
                                    (String city) =>
                                        city.toLowerCase().contains(
                                          textEditingValue.text.toLowerCase(),
                                        ),
                                  );
                                },
                            onSelected: (String selection) {
                              _cityController.text = selection;
                            },
                            fieldViewBuilder:
                                (
                                  BuildContext fieldCtx,
                                  TextEditingController controller,
                                  FocusNode focusNode,
                                  VoidCallback onEditingComplete,
                                ) {
                                  return TextField(
                                    controller: _cityController,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      labelText: AppStr.cityLabel,
                                      hintText: topCities.isEmpty
                                          ? AppStr.cityHint
                                          : null,
                                    ),
                                    onEditingComplete: onEditingComplete,
                                  );
                                },
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue:
                                          cuisineList.contains(_selectedCuisine)
                                          ? _selectedCuisine
                                          : null,
                                      items: cuisineList.map((String cuisine) {
                                        return DropdownMenuItem(
                                          value: cuisine,
                                          child: Text(cuisine),
                                        );
                                      }).toList(),
                                      onChanged: (String? value) {
                                        if (!mounted) {
                                          return;
                                        }
                                        setState(() {
                                          _selectedCuisine = value ?? '';
                                          widget.context.hasChanges = true;
                                        });
                                      },
                                      decoration: const InputDecoration(
                                        labelText: AppStr.cuisineLabel,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      if (!mounted) {
                                        return;
                                      }
                                      setState(() {
                                        _showAddCuisineField =
                                            !_showAddCuisineField;
                                      });
                                    },
                                    child: Text(
                                      AppStr.add,
                                      style: AppFonts.standard,
                                    ),
                                  ),
                                ],
                              ),
                              if (_showAddCuisineField)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: TextField(
                                          controller: _newCuisineController,
                                          decoration: const InputDecoration(
                                            hintText: AppStr.newCuisineHint,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: AppStr.confirm,
                                        color: AppColors.green,
                                        icon: const Icon(Icons.check),
                                        onPressed: () async {
                                          await _addInlineCustomCuisine();
                                        },
                                      ),
                                      IconButton(
                                        tooltip: AppStr.cancel,
                                        color: AppColors.grey,
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          if (!mounted) {
                                            return;
                                          }
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue:
                                          occasionItemsOrdered.contains(
                                            _selectedOccasion,
                                          )
                                          ? _selectedOccasion
                                          : occasionItemsOrdered.first,
                                      items: occasionItemsOrdered.map((
                                        String occasion,
                                      ) {
                                        return DropdownMenuItem(
                                          value: occasion,
                                          child: Text(occasion),
                                        );
                                      }).toList(),
                                      onChanged: (String? value) {
                                        if (!mounted) {
                                          return;
                                        }
                                        setState(() {
                                          _selectedOccasion =
                                              value ?? AppStr.defaultOccasion;
                                          widget.context.hasChanges = true;
                                        });
                                      },
                                      decoration: const InputDecoration(
                                        labelText: AppStr.occasionLabel,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      if (!mounted) {
                                        return;
                                      }
                                      setState(() {
                                        _showAddOccasionField =
                                            !_showAddOccasionField;
                                      });
                                    },
                                    child: Text(
                                      AppStr.add,
                                      style: AppFonts.standard,
                                    ),
                                  ),
                                ],
                              ),
                              if (_showAddOccasionField)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: TextField(
                                          controller: _newOccasionController,
                                          decoration: const InputDecoration(
                                            hintText: AppStr.newOccasionHint,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: AppStr.confirm,
                                        color: AppColors.green,
                                        icon: const Icon(Icons.check),
                                        onPressed: () async {
                                          await _addInlineCustomOccasion();
                                        },
                                      ),
                                      IconButton(
                                        tooltip: AppStr.cancel,
                                        color: AppColors.grey,
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          if (!mounted) {
                                            return;
                                          }
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
                            keyboardType: const TextInputType.numberWithOptions(decimal: false),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                            decoration: const InputDecoration(
                              labelText: AppStr.dinersLabel,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: <Widget>[
                              Text(
                                '${AppStr.dateLabel} ${_selectedDate.toLocal().toString().split(' ')[0]}',
                                style: AppFonts.standard,
                              ),
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
                                    setState(() {
                                      _selectedDate = picked;
                                      widget.context.hasChanges = true;
                                    });
                                  }
                                },
                                child: Text(
                                  AppStr.pickDate,
                                  style: AppFonts.standard,
                                ),
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
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          'Searching for restaurants\u2026',
                          style: AppFonts.smallHint.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: ElevatedButton(
                      onPressed: _goBackToTop,
                      style: buttonStyle(AppColors.ochre, Colors.black),
                      child: Text(
                        AppStr.back,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.bold.copyWith(color: Colors.black),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: ElevatedButton(
                      onPressed: _clearForm,
                      style: buttonStyle(AppColors.btnClear, AppColors.btnText),
                      child: Text(
                        AppStr.clear,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.bold.copyWith(color: AppColors.btnText),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: ElevatedButton(
                      onPressed: _goToRatingsScreen,
                      style: buttonStyle(AppColors.yellow, Colors.black),
                      child: Text(
                        AppStr.next,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.bold.copyWith(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),  // child: Scaffold
    );  // PopScope
  }
}

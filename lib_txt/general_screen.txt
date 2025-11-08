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
import 'constants/fonts.dart';

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
        if (!mounted) {
          return;
        }
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.cuisineRequired)));
      return;
    }

    final bool existsLocally = SessionCache.customCuisines.any((c) => c.toLowerCase() == newCuisine.toLowerCase());
    if (existsLocally) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.cuisineExists)));
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final DatabaseReference ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    try {
      final DataSnapshot snapshot = await ref.get();
      if (!mounted) {
        return;
      }

      final List<List<dynamic>> updatedCustoms = <List<dynamic>>[];

      if (snapshot.exists) {
        final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
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

      updatedCustoms.sort((a, b) => (a[0] as String).toLowerCase().compareTo((b[0] as String).toLowerCase()));

      if (snapshot.exists) {
        await ref.update({'cuisine': updatedCustoms});
      } else {
        await ref.set({'cuisine': updatedCustoms, 'occasion': [], 'country': []});
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
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.cuisineAdded)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.saveError}: $e')));
    }
  }

  Future<void> _addInlineCustomOccasion() async {
    final String newOccasion = _newOccasionController.text.trim();
    if (newOccasion.isEmpty || newOccasion.length > 24) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.occasionMaxLength)));
      return;
    }

    final bool existsLocally = SessionCache.customOccasions.any((o) => o.toLowerCase() == newOccasion.toLowerCase());
    if (existsLocally) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$newOccasion" ${AppStr.alreadyExists}')));
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final DatabaseReference ref = FirebaseDatabase.instance.ref('users/$uid/customvals');
    try {
      final DataSnapshot snapshot = await ref.get();
      if (!mounted) {
        return;
      }

      final List<List<dynamic>> updatedOccasions = <List<dynamic>>[];

      if (snapshot.exists) {
        final Map<dynamic, dynamic> data = snapshot.value as Map<dynamic, dynamic>;
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

      updatedOccasions.sort((a, b) => (a[0] as String).toLowerCase().compareTo((b[0] as String).toLowerCase()));

      if (snapshot.exists) {
        await ref.update({'occasion': updatedOccasions});
      } else {
        await ref.set({'cuisine': [], 'occasion': updatedOccasions, 'country': []});
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
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$newOccasion" ${AppStr.addedToOccasions}')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.saveError}: $e')));
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
      _costController.clear();
      _selectedCuisine = '';
      _selectedOccasion = AppStr.defaultOccasion;
      _selectedDate = DateTime.now();

      _newCuisineController.clear();
      _newOccasionController.clear();
      _showAddCuisineField = false;
      _showAddOccasionField = false;

      final Map<String, dynamic> reviewMap = widget.context.reviewMap;
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
    final NearbyRestaurant? selected = await showDialog<NearbyRestaurant>(
      context: context,
      builder: (BuildContext ctx) {
        return SimpleDialog(
          title: Text(AppStr.selectRestaurant, style: AppFonts.bold),
          children: _restaurantOptions.map((NearbyRestaurant rest) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx, rest);
              },
              child: Text(rest.name),
            );
          }).toList(),
        );
      },
    );

    if (selected != null && mounted) {
      final bool isValidCuisine = SessionCache.customCuisines.contains(selected.cuisine);

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.autoFillSkipped)));
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.locationDisabled)));
          await Geolocator.openLocationSettings();
          return;
        }

        final LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.deniedForever) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.permissionDeniedForever)));
          return;
        }

        if (permission == LocationPermission.denied) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.permissionDenied)));
          return;
        }

        return;
      }

      final List<NearbyRestaurant> results = await findNearbyRestaurants().timeout(const Duration(seconds: 12));
      if (!mounted) {
        return;
      }

      if (results.isNotEmpty) {
        _restaurantOptions = results;
        final NearbyRestaurant selected = results.first;
        final bool isValidCuisine = SessionCache.customCuisines.contains(selected.cuisine);

        if (!mounted) {
          return;
        }
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

        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.autoFillSuccess} ${selected.name}')));
      } else {
        if (!mounted) {
          return;
        }
        _clearForm();
        final String message = _restaurantSearchAttempts >= 2 ? AppStr.autoFillFailed : AppStr.autoFillNone;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.autoFillFailed)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      final String message = _restaurantSearchAttempts >= 2 ? AppStr.autoFillFailed : '${AppStr.searchFailed}: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    reviewMap['cuisine'] = SessionCache.customCuisines.contains(_selectedCuisine) ? _selectedCuisine : '';
    reviewMap['occasion'] = _selectedOccasion;
    final String dinersText = _dinersController.text.trim();
    reviewMap['numberOfDiners'] = dinersText.isEmpty ? '' : int.tryParse(dinersText);
    final String costText = _costController.text.trim();
    reviewMap['cost'] = costText.isEmpty ? '' : costText;
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
          builder: (_) => RatingsScreen(context: widget.context),
        ),
      );
    }
  }

  void _goBackToTop() async {
    final bool? shouldLeave = await showDialog<bool>(
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

    if (shouldLeave ?? false) {
      if (!mounted) {
        return;
      }
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => TopScreen()), (Route<dynamic> route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> topCities = systemCitiesByCountry[SessionCache.defaultCountry] ?? <String>[];
    final Set<String> cuisineItemsOrdered = <String>{}
      ..addAll(systemCuisines)
      ..addAll(SessionCache.customCuisines);
    final List<String> cuisineList = cuisineItemsOrdered.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final List<String> occasionItemsOrdered = <String>[
      ...systemOccasions,
      ...SessionCache.customOccasions.where((String o) => !systemOccasions.contains(o)),
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

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(AppStr.generalInfo, style: AppFonts.bold.copyWith(color: Colors.white)),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: LayoutBuilder(builder: (BuildContext ctx, BoxConstraints constraints) {
        return Stack(children: <Widget>[
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    TextFormField(
                      controller: _restaurantController,
                      decoration: const InputDecoration(labelText: AppStr.restaurantLabel),
                      validator: (String? value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppStr.restaurantRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '' || topCities.isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return topCities.where((String city) => city.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                      },
                      onSelected: (String selection) {
                        _cityController.text = selection;
                      },
                      fieldViewBuilder: (BuildContext fieldCtx, TextEditingController controller, FocusNode focusNode, VoidCallback onEditingComplete) {
                        return TextField(
                          controller: _cityController,
                          focusNode: focusNode,
                          decoration: InputDecoration(labelText: AppStr.cityLabel, hintText: topCities.isEmpty ? AppStr.cityHint : null),
                          onEditingComplete: onEditingComplete,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: cuisineList.contains(_selectedCuisine) ? _selectedCuisine : null,
                            items: cuisineList.map((String cuisine) {
                              return DropdownMenuItem(value: cuisine, child: Text(cuisine));
                            }).toList(),
                            onChanged: (String? value) {
                              if (!mounted) {
                                return;
                              }
                              setState(() {
                                _selectedCuisine = value ?? '';
                              });
                            },
                            decoration: const InputDecoration(labelText: AppStr.cuisineLabel),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _showAddCuisineField = !_showAddCuisineField;
                            });
                          },
                          child: Text(AppStr.add, style: AppFonts.standard),
                        ),
                      ]),
                      if (_showAddCuisineField)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(children: <Widget>[
                            Expanded(
                              child: TextField(controller: _newCuisineController, decoration: const InputDecoration(hintText: AppStr.newCuisineHint)),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: AppStr.confirm,
                              color: Colors.green,
                              icon: const Icon(Icons.check),
                              onPressed: () async {
                                await _addInlineCustomCuisine();
                              },
                            ),
                            IconButton(
                              tooltip: AppStr.cancel,
                              color: Colors.grey,
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
                          ]),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: occasionItemsOrdered.contains(_selectedOccasion) ? _selectedOccasion : occasionItemsOrdered.first,
                            items: occasionItemsOrdered.map((String occasion) {
                              return DropdownMenuItem(value: occasion, child: Text(occasion));
                            }).toList(),
                            onChanged: (String? value) {
                              if (!mounted) {
                                return;
                              }
                              setState(() {
                                _selectedOccasion = value ?? AppStr.defaultOccasion;
                              });
                            },
                            decoration: const InputDecoration(labelText: AppStr.occasionLabel),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _showAddOccasionField = !_showAddOccasionField;
                            });
                          },
                          child: Text(AppStr.add, style: AppFonts.standard),
                        ),
                      ]),
                      if (_showAddOccasionField)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(children: <Widget>[
                            Expanded(
                              child: TextField(controller: _newOccasionController, decoration: const InputDecoration(hintText: AppStr.newOccasionHint)),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: AppStr.confirm,
                              color: Colors.green,
                              icon: const Icon(Icons.check),
                              onPressed: () async {
                                await _addInlineCustomOccasion();
                              },
                            ),
                            IconButton(
                              tooltip: AppStr.cancel,
                              color: Colors.grey,
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
                          ]),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    TextField(controller: _dinersController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: AppStr.dinersLabel)),
                    const SizedBox(height: 16),
                    Row(children: <Widget>[
                      Text(AppStr.costLabel, style: AppFonts.standard),
                      const SizedBox(width: 12),
                      Text(SessionCache.currency, style: AppFonts.standard),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(controller: _costController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: AppStr.amountLabel)),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: <Widget>[
                      Text('${AppStr.dateLabel} ${_selectedDate.toLocal().toString().split(' ')[0]}', style: AppFonts.standard),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          DateTime? picked = await showDatePicker(context: ctx, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                          if (picked != null && mounted) {
                            setState(() {
                              _selectedDate = picked;
                            });
                          }
                        },
                        child: Text(AppStr.pickDate, style: AppFonts.standard),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: <Widget>[
                      Text(AppStr.locationSearchLabel, style: AppFonts.standard),
                      SessionCache.allowLocation
                          ? Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _restaurantOptions.length > 1
                                    ? ElevatedButton(
                                        onPressed: _showRestaurantSelector,
                                        style: buttonStyle(Colors.amber, Colors.black),
                                        child: Text(AppStr.multi, style: AppFonts.standard),
                                      )
                                    : ElevatedButton(
                                        onPressed: _autoFillRestaurantFromLocation,
                                        style: buttonStyle(Colors.blue, Colors.white),
                                        child: Text(AppStr.search, style: AppFonts.standard.copyWith(color: Colors.white)),
                                      ),
                              ),
                            )
                          : Text('(OFF)', style: AppFonts.standard.copyWith(color: AppColors.mutedText, fontStyle: FontStyle.italic)),
                    ]),
                    const SizedBox(height: 36),
                  ]),
                ),
              ),
            ),
          ),
          if (_isSearching)
            Container(color: Colors.black.withAlpha(77), child: const Center(child: CircularProgressIndicator())),
        ]);
      }),
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
                      child: Text(AppStr.back, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.black)),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: ElevatedButton(
                      onPressed: _clearForm,
                      style: buttonStyle(AppColors.lightGrey, Colors.black87),
                      child: Text(AppStr.clear, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.black87)),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: ElevatedButton(
                      onPressed: _goToRatingsScreen,
                      style: buttonStyle(AppColors.yellow, Colors.black),
                      child: Text(AppStr.next, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.black)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

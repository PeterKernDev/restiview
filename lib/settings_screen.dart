// settings_screen.dart
//
// Settings screen for RestiView — migrated styles to AppFonts/AppColors,
// replaced MaterialStateProperty usage with WidgetStateProperty,
// guarded async/context flows, kept layout and behaviour intact.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'top_screen.dart';
import 'services/session_cache.dart';
import 'custom_values_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _selectedSort;
  late String _selectedCountry;
  late bool _allowLocation;
  late bool _allowPhotos;
  late int _searchRadius;
  late bool _allowAutoCapture;

  void _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStr.deleteAccountTitle, style: AppFonts.bold),
        content: Text(AppStr.deleteAccountConfirm, style: AppFonts.standard),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStr.noLabel, style: AppFonts.standard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStr.yes, style: AppFonts.standard),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseDatabase.instance.ref('users/$uid').remove();
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStr.deleteAccountError}: ${e.toString()}')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStr.deleteAccountSuccess)),
    );

    Navigator.pushReplacementNamed(context, '/');

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStr.deleteAccountSignedOut)),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();

    _selectedSort = SessionCache.sortOption;

    final countryList = SessionCache.customCountries.isNotEmpty
        ? SessionCache.customCountries
        : getSystemCountryNames();

    if (countryList.isNotEmpty) {
      _selectedCountry = countryList.contains(SessionCache.defaultCountry)
          ? SessionCache.defaultCountry
          : countryList.first;
    } else {
      _selectedCountry = SessionCache.defaultCountry.isNotEmpty
          ? SessionCache.defaultCountry
          : '';
    }

    _allowLocation = SessionCache.allowLocation;
    _allowPhotos = SessionCache.allowPhotos;
    _searchRadius = SessionCache.searchRadius.clamp(10, 200);
    _allowAutoCapture = SessionCache.allowAutoCapture;
  }

  void _resetSettings() {
    if (!mounted) return;
    setState(() {
      _selectedSort = AppStr.sortOptionRating;
      _selectedCountry = SessionCache.defaultCountry;
      _allowLocation = false;
      _allowPhotos = false;
      _allowAutoCapture = false;
      _searchRadius = 50;
    });
  }

  Future<void> _saveSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseDatabase.instance.ref('users/$uid').update({
        'userSettings1': _selectedSort,
        'userSettings2': _selectedCountry,
        'userSettings3': _allowLocation,
        'userSettings4': _allowPhotos,
        'userSettings5': _searchRadius,
        'userSettings6': _allowAutoCapture,
      });

      SessionCache.sortOption = _selectedSort;
      SessionCache.defaultCountry = _selectedCountry;
      SessionCache.allowLocation = _allowLocation;
      SessionCache.allowPhotos = _allowPhotos;
      SessionCache.searchRadius = _searchRadius;
      SessionCache.allowAutoCapture = _allowAutoCapture;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.settingsSaved)),
      );
    }
  }

  void _goBack() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TopScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortOptions = [
      AppStr.sortOptionRating,
      AppStr.sortOptionDate,
      AppStr.sortOptionName,
      AppStr.sortOptionCity,
      AppStr.sortOptionCuisine,
    ];

    final effectiveSort = sortOptions.contains(_selectedSort) ? _selectedSort : sortOptions.first;

    final countryList = SessionCache.customCountries.isNotEmpty
        ? SessionCache.customCountries
        : getSystemCountryNames();
    final effectiveCountry = countryList.contains(_selectedCountry)
        ? _selectedCountry
        : (countryList.isNotEmpty ? countryList.first : '');

    final ButtonStyle topActionStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: AppFonts.standard,
    );

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        title: Text(AppStr.settingsTitle, style: AppFonts.bold.copyWith(color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  '${SessionCache.userName} : ${SessionCache.userEmail}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.standard.copyWith(fontSize: 14, color: AppColors.darkGreen, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Text(AppStr.defaultSearchFilters, style: AppFonts.bold),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: effectiveSort,
                items: sortOptions.map((sort) => DropdownMenuItem(value: sort, child: Text(sort, style: AppFonts.standard))).toList(),
                onChanged: (value) {
                  if (!mounted || value == null) return;
                  setState(() => _selectedSort = value);
                },
                decoration: InputDecoration(labelText: AppStr.sortByLabel, labelStyle: AppFonts.standard),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: effectiveCountry.isNotEmpty ? effectiveCountry : null,
                items: countryList.map((country) => DropdownMenuItem(value: country, child: Text(country, style: AppFonts.standard))).toList(),
                onChanged: (value) {
                  if (!mounted || value == null) return;
                  final newCurrency = getCurrencyForCountry(value);
                  setState(() {
                    _selectedCountry = value;
                    SessionCache.currency = newCurrency;
                    SessionCache.countryFilter = value;
                  });
                },
                decoration: InputDecoration(labelText: AppStr.countryLabel, labelStyle: AppFonts.standard),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                title: Text(AppStr.allowLocationLabel, style: AppFonts.standard),
                value: _allowLocation,
                onChanged: (value) {
                  if (!mounted) return;
                  setState(() => _allowLocation = value);
                },
                activeThumbColor: AppColors.darkGreen,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppStr.searchRadiusLabel, style: AppFonts.bold),
                      Text('$_searchRadius m', style: AppFonts.bold),
                    ],
                  ),
                  Slider(
                    value: _searchRadius.toDouble(),
                    min: 10,
                    max: 200,
                    divisions: 180,
                    label: '$_searchRadius m',
                    onChanged: (value) {
                      if (!mounted) return;
                      setState(() => _searchRadius = value.round());
                    },
                  ),
                ],
              ),
              SwitchListTile(
                title: Text(AppStr.allowPhotosLabel, style: AppFonts.standard),
                value: _allowPhotos,
                onChanged: (value) {
                  if (!mounted) return;
                  setState(() => _allowPhotos = value);
                },
                activeThumbColor: AppColors.darkGreen,
              ),
              SwitchListTile(
                title: Text(AppStr.allowAutoCaptureLabel, style: AppFonts.standard),
                subtitle: Text(AppStr.allowAutoCaptureSubtitle, style: AppFonts.standard),
                value: _allowAutoCapture,
                onChanged: null,
                activeThumbColor: AppColors.darkGreen,
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomValuesScreen()));
                      },
                      style: topActionStyle.copyWith(
                        backgroundColor: WidgetStateProperty.all(Colors.orange),
                        foregroundColor: WidgetStateProperty.all(Colors.black87),
                        minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                      ),
                      child: Text(AppStr.customValuesButton, style: AppFonts.standard, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirmDeleteAccount,
                      style: topActionStyle.copyWith(
                        backgroundColor: WidgetStateProperty.all(AppColors.red),
                        foregroundColor: WidgetStateProperty.all(Colors.white),
                        minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                      ),
                      child: Text(AppStr.deleteAccountButton, style: AppFonts.standard, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _goBack,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ochre,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: AppFonts.standard,
                        ),
                        child: Text(AppStr.back, style: AppFonts.standard, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: AppFonts.standard,
                        ),
                        child: Text(AppStr.saveChangesButton, style: AppFonts.standard.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _resetSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: AppFonts.standard,
                        ),
                        child: Text(AppStr.resetButton, style: AppFonts.standard, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

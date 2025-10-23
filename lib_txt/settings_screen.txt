// settings_screen.dart
//
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart'; // ✅ Import centralized strings
import 'constants/colours.dart';
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
        title: Text(AppStr.deleteAccountTitle),
        content: Text(AppStr.deleteAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStr.noLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStr.yes),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteAccount(); // ✅ Move async logic to separate method
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

  // Choose SessionCache.defaultCountry if it exists in the list;
  // otherwise fall back to the first entry or an empty string when list is empty.
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
// 
// part 2
//
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

  return Scaffold(
    backgroundColor: AppColors.beige,
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.darkGreen,
      title: const Text(
        AppStr.settingsTitle,
        style: TextStyle(
          fontFamily: 'Gelica',
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              '${SessionCache.userName} : ${SessionCache.userEmail}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'Gelica',
                color: AppColors.darkGreen,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            AppStr.defaultSearchFilters,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Gelica',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: effectiveSort,
            items: sortOptions
                .map((sort) => DropdownMenuItem(value: sort, child: Text(sort)))
                .toList(),
            onChanged: (value) {
              if (!mounted || value == null) return;
              setState(() => _selectedSort = value);
            },
            decoration: const InputDecoration(labelText: AppStr.sortByLabel),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: effectiveCountry.isNotEmpty ? effectiveCountry : null,
            items: countryList
                .map((country) => DropdownMenuItem(value: country, child: Text(country)))
                .toList(),
            onChanged: (value) {
              if (!mounted || value == null) return;
              final newCurrency = getCurrencyForCountry(value);
              setState(() {
                _selectedCountry = value;
                SessionCache.currency = newCurrency;
              });
            },
            decoration: const InputDecoration(labelText: AppStr.countryLabel),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text(AppStr.allowLocationLabel, style: TextStyle(fontFamily: 'Gelica')),
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
                  const Text(
                    AppStr.searchRadiusLabel,
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Gelica'),
                  ),
                  Text(
                    '$_searchRadius m',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Gelica'),
                  ),
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
            title: const Text(AppStr.allowPhotosLabel, style: TextStyle(fontFamily: 'Gelica')),
            value: _allowPhotos,
            onChanged: (value) {
              if (!mounted) return;
              setState(() => _allowPhotos = value);
            },
            activeThumbColor: AppColors.darkGreen,
          ),
          SwitchListTile(
            title: const Text(AppStr.allowAutoCaptureLabel, style: TextStyle(fontFamily: 'Gelica')),
            subtitle: const Text(AppStr.allowAutoCaptureSubtitle, style: TextStyle(fontFamily: 'Gelica')),
            value: _allowAutoCapture,
            onChanged: null,
            activeThumbColor: AppColors.darkGreen,
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomValuesScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(160, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(AppStr.customValuesButton, style: TextStyle(fontFamily: 'Gelica')),
              ),
              ElevatedButton(
                onPressed: _confirmDeleteAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(100, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(AppStr.deleteAccountButton, style: TextStyle(fontFamily: 'Gelica')),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SafeArea(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _goBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ochre,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(100, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(AppStr.back, style: TextStyle(fontFamily: 'Gelica')),
                ),
                ElevatedButton(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(100, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(AppStr.saveChangesButton, style: TextStyle(fontFamily: 'Gelica')),
                ),
                ElevatedButton(
                  onPressed: _resetSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(100, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(AppStr.resetButton, style: TextStyle(fontFamily: 'Gelica')),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}


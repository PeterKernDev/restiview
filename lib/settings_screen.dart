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
import 'services/audit_info.dart';

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
      String? reason;
      if (mounted) {
        reason = await showDialog<String?>(
          context: context,
          builder: (context) => const _DeleteReasonDialog(),
        );
      }
      if (reason != null) {
        _deleteAccount(reason);
      }
    }
  }

  Future<void> _deleteAccount([String? reason]) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final email = SessionCache.userEmail;
    if (uid == null || user == null) return;

    // Write audit record before deleting user
    try {
      await writeAuditInfo(
        userId: uid,
        userEmail: email,
        type: 'account_delete',
        target: 'account',
        details: (reason != null && reason.isNotEmpty) ? {'reason': reason} : null,
      );
    } catch (e) {
      debugPrint('Failed to write audit info: $e');
    }

    try {
      // Delete database node first
      await FirebaseDatabase.instance.ref('users/$uid').remove();
      
      // Attempt to delete the auth user - may require re-authentication
      try {
        await user.delete();
      } on FirebaseAuthException catch (authError) {
        if (authError.code == 'requires-recent-login') {
          // Need to re-authenticate before deletion
          if (!mounted) return;
          final password = await _promptForPassword();
          if (password == null || password.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Account deletion cancelled - password required')),
            );
            return;
          }
          
          // Re-authenticate and try again
          final credential = EmailAuthProvider.credential(email: email, password: password);
          await user.reauthenticateWithCredential(credential);
          await user.delete();
        } else {
          rethrow;
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStr.deleteAccountError}: ${e.toString()}'),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppStr.deleteAccountSuccess)));

    Navigator.pushReplacementNamed(context, '/');

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.deleteAccountSignedOut)));
      }
    });
  }

  Future<String?> _promptForPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Confirm Password', style: AppFonts.bold),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'For security, please enter your password to confirm account deletion:',
              style: AppFonts.standard,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(AppStr.cancel, style: AppFonts.standard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('Confirm', style: AppFonts.standard),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.settingsSaved)));
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

    final effectiveSort = sortOptions.contains(_selectedSort)
        ? _selectedSort
        : sortOptions.first;

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
        title: Text(
          AppStr.settingsTitle,
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
              Center(
                child: Text(
                  '${SessionCache.userName} : ${SessionCache.userEmail}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.standard.copyWith(
                    fontSize: 14,
                    color: AppColors.darkGreen,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Text(AppStr.defaultSearchFilters, style: AppFonts.bold),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: effectiveSort,
                items: sortOptions
                    .map(
                      (sort) => DropdownMenuItem(
                        value: sort,
                        child: Text(sort, style: AppFonts.standard),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (!mounted || value == null) return;
                  setState(() => _selectedSort = value);
                },
                decoration: InputDecoration(
                  labelText: AppStr.sortByLabel,
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: effectiveCountry.isNotEmpty
                    ? effectiveCountry
                    : null,
                items: countryList
                    .map(
                      (country) => DropdownMenuItem(
                        value: country,
                        child: Text(country, style: AppFonts.standard),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (!mounted || value == null) return;
                  final newCurrency = getCurrencyForCountry(value);
                  setState(() {
                    _selectedCountry = value;
                    SessionCache.currency = newCurrency;
                    SessionCache.countryFilter = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: AppStr.countryLabel,
                  labelStyle: AppFonts.standard,
                ),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                title: Text(
                  AppStr.allowLocationLabel,
                  style: AppFonts.standard,
                ),
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
                title: Text(
                  AppStr.allowAutoCaptureLabel,
                  style: AppFonts.standard,
                ),
                subtitle: Text(
                  AppStr.allowAutoCaptureSubtitle,
                  style: AppFonts.standard,
                ),
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CustomValuesScreen(),
                          ),
                        );
                      },
                      style: topActionStyle.copyWith(
                        backgroundColor: WidgetStateProperty.all(AppColors.orange),
                        foregroundColor: WidgetStateProperty.all(
                          Colors.black87,
                        ),
                        minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                      ),
                      child: Text(
                        AppStr.customValuesButton,
                        style: AppFonts.standard,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirmDeleteAccount,
                      style: topActionStyle.copyWith(
                        backgroundColor: WidgetStateProperty.all(
                          AppColors.btnDelete,
                        ),
                        foregroundColor: WidgetStateProperty.all(
                          AppColors.btnText,
                        ),
                        minimumSize: WidgetStateProperty.all(const Size(0, 48)),
                      ),
                      child: Text(
                        AppStr.deleteAccountButton,
                        style: AppFonts.standard,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: AppFonts.standard,
                        ),
                        child: Text(
                          AppStr.back,
                          style: AppFonts.standard,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.btnSave,
                          foregroundColor: AppColors.btnText,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: AppFonts.standard,
                        ),
                        child: Text(
                          AppStr.saveChangesButton,
                          style: AppFonts.standard.copyWith(
                            color: AppColors.btnText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _resetSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.grey,
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: AppFonts.standard,
                        ),
                        child: Text(
                          AppStr.resetButton,
                          style: AppFonts.standard,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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

// Separate StatefulWidget for delete reason dialog to properly manage TextEditingController lifecycle
class _DeleteReasonDialog extends StatefulWidget {
  const _DeleteReasonDialog();

  @override
  State<_DeleteReasonDialog> createState() => _DeleteReasonDialogState();
}

class _DeleteReasonDialogState extends State<_DeleteReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('We are sorry to see you go', style: AppFonts.bold),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'If you wish, please let us know why you are deleting your account (optional):',
            style: AppFonts.standard,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(AppStr.cancel, style: AppFonts.standard),
        ),
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.pop(context, text);
          },
          child: Text('Continue', style: AppFonts.standard),
        ),
      ],
    );
  }
}

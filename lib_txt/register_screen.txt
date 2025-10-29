// register_screen.dart
// Registration flow with device-aware country detection and dropdown override

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'services/session_cache.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _allowLocation = false;
  bool _allowPhotos = false;
  bool _loading = false;
  bool _termsAccepted = false;

  late String _homeCountry;

  String _getDeviceCountryName() {
    final deviceCode = SessionCache.deviceCountryCode;
    final match = systemCountries.firstWhere(
      (c) => c['code'] == deviceCode,
      orElse: () => {'name': 'USA'},
    );
    return match['name']!;
  }

  @override
  void initState() {
    super.initState();

    // Set device country code if not already set
    if (SessionCache.deviceCountryCode.isEmpty) {
      final localeCode = PlatformDispatcher.instance.locale.countryCode ?? 'US';
      SessionCache.deviceCountryCode = localeCode;
    }

    _homeCountry = _getDeviceCountryName();
  }

  void _toggleLoading(bool value) {
    if (!mounted) return;
    setState(() {
      _loading = value;
    });
  }

  void _goBack() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

bool _validateInputs() {
  if (!_termsAccepted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStr.acceptTandCs)),
    );
    return false;
  }

  final name = _nameController.text.trim();
  final email = _emailController.text.trim();
  final password = _passwordController.text.trim();

  if (name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStr.nameHint)),
    );
    return false;
  }

  if (email.isEmpty || password.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStr.emailPasswordRequired)),
    );
    return false;
  }

  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
  if (!emailRegex.hasMatch(email)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStr.emailRequired)),
    );
    return false;
  }

  return true;
}

  Future<void> _registerUser() async {
    if (!_validateInputs()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    _toggleLoading(true);
    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = userCredential.user?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance.ref('users/$uid').set({
          'userName': name,
          'userEmail': email,
          'userSettings1': 'Name',
          'userSettings2': _homeCountry,
          'baseCountry': _homeCountry,
          'userSettings3': _allowLocation,
          'userSettings4': _allowPhotos,
          'userSettings5': 50,
        });

        await userCredential.user!.updateDisplayName(name);

        SessionCache.userName = name;
        SessionCache.userEmail = email;
        SessionCache.sortOption = 'Name';
        SessionCache.defaultCountry = _homeCountry;
        SessionCache.allowLocation = _allowLocation;
        SessionCache.allowPhotos = _allowPhotos;
        SessionCache.allowAutoCapture = false;
        SessionCache.searchRadius = 50;
        SessionCache.currency = getCurrencyForCountry(_homeCountry);

        SessionCache.customValsLoaded = false;
        SessionCache.customCuisines = [...systemCuisines];
        SessionCache.customOccasions = [...systemOccasions];
        SessionCache.customCountries = [...getSystemCountryNames()];

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/main', arguments: name);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStr.registrationFailed}: ${e.message}')),
      );
    } finally {
      _toggleLoading(false);
    }
  }
  //  
  // part 2
  //
@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.beige,
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.darkGreen,
      title: Text(
        AppStr.registerTitle,
        style: AppFonts.bold.copyWith(color: Colors.white),
      ),
      centerTitle: true,
    ),
    body: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: AppStr.emailLabel,
                    labelStyle: AppFonts.standard,
                    border: const UnderlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: AppStr.passwordLabel,
                    labelStyle: AppFonts.standard,
                    border: const UnderlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() => _showPassword = !_showPassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: AppStr.nameLabel,
                    labelStyle: AppFonts.standard,
                    border: const UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _homeCountry,
                  items: systemCountries
                      .map((c) => DropdownMenuItem(
                            value: c['name'],
                            child: Text(c['name']!, style: AppFonts.standard),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (!mounted || value == null) return;
                    setState(() => _homeCountry = value);
                  },
                  decoration: InputDecoration(
                    labelText: AppStr.homeCountryLabel,
                    labelStyle: AppFonts.standard,
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: Text(AppStr.allowLocationLabel, style: AppFonts.standard),
                  value: _allowLocation,
                  onChanged: (value) {
                    if (!mounted) return;
                    setState(() => _allowLocation = value);
                  },
                  activeThumbColor: AppColors.darkGreen,
                  activeTrackColor: AppColors.ochre,
                ),
                SwitchListTile(
                  title: Text(AppStr.allowPhotosLabel, style: AppFonts.standard),
                  value: _allowPhotos,
                  onChanged: (value) {
                    if (!mounted) return;
                    setState(() => _allowPhotos = value);
                  },
                  activeThumbColor: AppColors.darkGreen,
                  activeTrackColor: AppColors.ochre,
                ),
                SwitchListTile(
                  title: Text(AppStr.acceptTermsLabel, style: AppFonts.standard),
                  value: _termsAccepted,
                  onChanged: (value) {
                    if (!mounted) return;
                    setState(() => _termsAccepted = value);
                  },
                  activeThumbColor: AppColors.red, // 🔴 Red dot
                  activeTrackColor: AppColors.ochre,
                ),
                const SizedBox(height: 24),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, '/tandc');
                  },
                  child: Text(AppStr.viewTermsLabel, style: AppFonts.standard.copyWith(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: (_loading || !_termsAccepted) ? null : _registerUser,
                  child: Text(AppStr.registerButton, style: AppFonts.standard.copyWith(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ochre,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _loading ? null : _goBack,
                  child: Text(AppStr.back, style: AppFonts.standard.copyWith(color: Colors.black)),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}
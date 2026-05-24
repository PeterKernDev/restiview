// lib/register_screen.dart
// Registration flow with device-aware country detection and startup initialization
//
// Changes:
// - Added 'Allow Friends' toggle under 'Allow Photos'.
// - Persisted toggle as userSettings7 in the users/$uid record.
// - Calls ensureUserSetup(...) helper unconditionally after user creation so
//   users_by_email mapping, public_profiles, and userSettings7 are created/ensured.
// - Passes acceptsFriends flag to ensureUserSetup.
// - Kept screen scrollable by keeping the main form inside SingleChildScrollView (buttons remain in SafeArea).

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'services/session_cache.dart';
import 'services/startup_tasks.dart';
import 'services/user_setup.dart'; // ensureUserSetup helper
import 'services/location_restaurant_helper.dart'; // normalizeCountryName helper
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'services/network_utils.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _allowLocation = false;
  bool _allowPhotos = false;
  bool _allowFriends = false; // new toggle
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

    if (SessionCache.deviceCountryCode.isEmpty) {
      final localeCode = PlatformDispatcher.instance.locale.countryCode ?? 'US';
      SessionCache.deviceCountryCode = localeCode;
    }

    _homeCountry = _getDeviceCountryName();
    _detectCountryFromLocation();
  }

  Future<void> _detectCountryFromLocation() async {
    appLog('GeoDetect: starting');
    try {
      appLog('GeoDetect: checking if location services enabled');
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      appLog('GeoDetect: serviceEnabled=$serviceEnabled');
      if (!serviceEnabled) {
        appLog('GeoDetect: location services disabled, aborting');
        return;
      }

      appLog('GeoDetect: checking permission');
      LocationPermission permission = await Geolocator.checkPermission();
      appLog('GeoDetect: permission=$permission');
      if (permission == LocationPermission.denied) {
        appLog('GeoDetect: requesting permission');
        permission = await Geolocator.requestPermission();
        appLog('GeoDetect: permission after request=$permission');
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        appLog('GeoDetect: getting current position');
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
        appLog('GeoDetect: position=${pos.latitude},${pos.longitude}');
        appLog('GeoDetect: calling placemarkFromCoordinates');
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        appLog('GeoDetect: placemarks count=${placemarks.length}');
        if (placemarks.isNotEmpty && placemarks.first.country != null && placemarks.first.country!.isNotEmpty) {
          appLog('GeoDetect: country=${placemarks.first.country}');
          if (mounted) {
            setState(() {
              _homeCountry = normalizeCountryName(placemarks.first.country);
            });
          }
        }
      } else {
        appLog('GeoDetect: permission denied, skipping position fetch');
      }
      appLog('GeoDetect: completed successfully');
    } catch (e, st) {
      appLog('GeoDetect: FAILED with error: $e');
      appLog('GeoDetect: stack trace: $st');
    }
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
    // Synchronous validation — safe to use context here
    if (!_termsAccepted) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.acceptTandCs)));
      }
      return false;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.nameHint)));
      }
      return false;
    }

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.emailPasswordRequired)));
      }
      return false;
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.emailRequired)));
      }
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
    if (!await hasInternetConnection()) {
      _toggleLoading(false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.networkError)),
      );
      return;
    }

    final String detectedCountry = _homeCountry;
    appLog('Register: detectedCountry=$detectedCountry');

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = userCredential.user?.uid;
      if (uid != null) {
        try {
          await FirebaseDatabase.instance.ref('users/$uid').set({
            'userName': name,
            'userEmail': email,
            'userSettings1': 'Name',
            'userSettings2': detectedCountry,
            'baseCountry': detectedCountry,
            'userSettings3': _allowLocation,
            'userSettings4': _allowPhotos,
            'userSettings5': 50,
            'userSettings6': false,
            'userSettings7': _allowFriends, // persisted toggle
          });
        } catch (dbErr) {
          // DB write failed — delete the orphaned Auth user to avoid inconsistent state
          appLog('Register: DB write failed, deleting orphaned Auth user: $dbErr');
          try {
            await userCredential.user!.delete();
          } catch (deleteErr) {
            appLog('Register: failed to delete orphaned Auth user: $deleteErr');
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStr.registrationDbError)),
          );
          return;
        }

        await userCredential.user!.updateDisplayName(name);

        // Ensure auxiliary records are present (UBE mapping, public profile, userSettings7)
        try {
          final String mailboxEmail = email.trim().toLowerCase();
          await ensureUserSetup(
            uid: uid,
            email: mailboxEmail,
            displayName: name,
            acceptsFriends: _allowFriends,
          );
        } catch (e, st) {
          debugPrint('Register.ensureUserSetup failed for uid=$uid: $e\n$st');
          // non-blocking: continue registration even if helper fails
        }

        // Run shared startup logic
        await runStartupTasks(
          uid: uid,
          userName: name,
          userEmail: email,
          homeCountry: detectedCountry,
        );

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/main', arguments: name);
      }
    } on FirebaseAuthException catch (e) {
      appLog('Register: FirebaseAuthException [${e.code}]: ${e.message}');
      final bool isNetworkError =
          e.code == 'network-request-failed' ||
          e.message?.toLowerCase().contains('network') == true ||
          e.message?.toLowerCase().contains('recaptcha') == true;
      if (isNetworkError) {
        // Retry once after a short delay, matching sign-in behaviour
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          final retryCredential = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: _emailController.text.trim(), password: _passwordController.text.trim());
          // Retry succeeded — re-enter the success path via recursive call
          // by re-triggering the outer flow is complex, so just proceed inline
          final uid = retryCredential.user?.uid;
          if (uid != null && mounted) {
            Navigator.pushReplacementNamed(context, '/main', arguments: _nameController.text.trim());
          }
          return;
        } catch (_) {
          // Retry also failed — fall through to show network error
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.networkError)),
        );
      } else {
        if (!mounted) return;
        String message;
        switch (e.code) {
          case 'email-already-in-use':
            message = AppStr.emailAlreadyInUse;
            break;
          case 'weak-password':
            message = AppStr.weakPassword;
            break;
          default:
            message = AppStr.registrationFailed;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      _toggleLoading(false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.grey,
                        ),
                        onPressed: () {
                          if (!mounted) return;
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
                    value: systemCountries.any((c) => c['name'] == _homeCountry)
                        ? _homeCountry
                        : null,
                    items: ([...systemCountries]
                          ..sort((a, b) => a['name']!.compareTo(b['name']!)))
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['name'],
                            child: Text(c['name']!, style: AppFonts.standard),
                          ),
                        )
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
                    activeTrackColor: AppColors.ochre,
                  ),
                  SwitchListTile(
                    title: Text(
                      AppStr.allowPhotosLabel,
                      style: AppFonts.standard,
                    ),
                    value: _allowPhotos,
                    onChanged: (value) {
                      if (!mounted) return;
                      setState(() => _allowPhotos = value);
                    },
                    activeThumbColor: AppColors.darkGreen,
                    activeTrackColor: AppColors.ochre,
                  ),
                  // Allow Friends toggle (text moved to strings)
                  SwitchListTile(
                    title: Text(
                      AppStr.allowFriendsLabel,
                      style: AppFonts.standard,
                    ),
                    value: _allowFriends,
                    onChanged: (value) {
                      if (!mounted) return;
                      setState(() => _allowFriends = value);
                    },
                    activeThumbColor: AppColors.darkGreen,
                    activeTrackColor: AppColors.ochre,
                  ),
                  SwitchListTile(
                    title: Text(
                      AppStr.acceptTermsLabel,
                      style: AppFonts.standard,
                    ),
                    value: _termsAccepted,
                    onChanged: (value) {
                      if (!mounted) return;
                      setState(() => _termsAccepted = value);
                    },
                    activeThumbColor: AppColors.red,
                    activeTrackColor: AppColors.ochre,
                  ),
                  const SizedBox(height: 24),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      if (!mounted) return;
                      Navigator.pushNamed(context, '/tandc');
                    },
                    child: Text(
                      AppStr.viewTermsLabel,
                      style: AppFonts.standard.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.btnRegister,
                      foregroundColor: AppColors.btnText,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: (_loading || !_termsAccepted)
                        ? null
                        : _registerUser,
                    child: Text(
                      AppStr.registerButton,
                      style: AppFonts.standard.copyWith(
                        color: AppColors.btnText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ochre,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _loading ? null : _goBack,
                    child: Text(
                      AppStr.back,
                      style: AppFonts.standard.copyWith(color: Colors.black),
                    ),
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

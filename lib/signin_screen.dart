// signin_screen.dart
//
// Sign-in flow that, after authentication and startup tasks, scans the user's UBE mailbox
// (users_by_email/<normalized>/requests) for incoming requests and creates friend stubs.
// Ensures a users_by_email/<normalized> mapping exists after successful sign-in.
// Writes a small public_profiles/<uid> record (displayName/email) so clients can read
// minimal public profile info without accessing private /users/<uid>.
// All user-visible strings must come from AppStr. Uses braced blocks, mounted guards,
// and defensive parsing.
//
// Updated to call ensureUserSetup(...) helper to create mapping, public_profile, and
// ensure users/$uid/userSettings7 exists for older accounts. Passes acceptsFriends flag
// based on users/$uid/userSettings7 when available; defaults to true.

import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/session_cache.dart';
import 'services/startup_tasks.dart';
import 'services/db_utils.dart'; // normalizeEmailForPath helper
import 'services/user_setup.dart'; // ensureUserSetup helper
import 'services/mailbox_helper.dart'; // Mailbox processing service
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';

List<String> getSystemCountryNames([BuildContext? context]) {
  String? code;
  try {
    if (context != null) {
      final String? ctxCode = Localizations.localeOf(context).countryCode;
      if (ctxCode != null && ctxCode.isNotEmpty) {
        code = ctxCode;
      }
    }
  } catch (_) {}
  try {
    code ??= WidgetsBinding.instance.platformDispatcher.locale.countryCode;
  } catch (_) {}
  if (code != null && code.isNotEmpty) return <String>[code];
  return <String>['US'];
}

bool looksLikeUid(String s) {
  if (s.isEmpty) return false;
  final String trimmed = s.trim();
  if (trimmed.length < 16) return false;
  final RegExp uidLike = RegExp(r'^[A-Za-z0-9_-]+$');
  return uidLike.hasMatch(trimmed);
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() {
    return _SignInScreenState();
  }
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _staySignedIn = false;
  bool _showPassword = false;
  bool _loading = false;
  bool _initialSSI = false;
  bool _enableReset = false;

  @override
  void initState() {
    super.initState();
    _logEnvironmentHints();
    SessionCache.getStaySignedIn().then((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _staySignedIn = value;
        _initialSSI = value;
        if (_staySignedIn) {
          SessionCache.getSavedEmail().then((email) {
            if (!mounted) return;
            _emailController.text = email ?? '';
          });
          SessionCache.getSavedPassword().then((password) {
            if (!mounted) return;
            _passwordController.text = password ?? '';
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleLoading(bool value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = value;
    });
  }

  void _goBack() {
    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, '/');
  }

  bool _validateInputs({required bool requireName}) {
    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (requireName && name.isEmpty) {
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

    final RegExp emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
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

  Future<void> _signInUser() async {
    if (!_validateInputs(requireName: false)) {
      return;
    }

    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    _toggleLoading(true);
    try {
      try {
        final UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        await _onSignedIn(userCredential, email, password);
        return;
      } on FirebaseAuthException catch (e) {
        final bool isRecaptchaOrNetwork =
            e.message?.toLowerCase().contains('recaptcha') == true ||
            e.message?.toLowerCase().contains('network') == true ||
            e.code == 'network-request-failed';

        if (isRecaptchaOrNetwork) {
          await Future<void>.delayed(const Duration(seconds: 1));
          try {
            final UserCredential retryCredential = await FirebaseAuth.instance
                .signInWithEmailAndPassword(email: email, password: password);
            await _onSignedIn(retryCredential, email, password);
            return;
          } catch (retryErr) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${AppStr.signInFailed}: ${retryErr.toString()}',
                  ),
                ),
              );
            }
          }
        }

        String message;
        switch (e.code) {
          case 'wrong-password':
            message = AppStr.emailIncorrect;
            break;
          case 'user-not-found':
            message = AppStr.emailNotFound;
            break;
          default:
            message = '${AppStr.signInFailed}: ${e.message ?? e.code}';
        }

        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        if (mounted) {
          setState(() {
            _staySignedIn = false;
          });
        }
        await SessionCache.setStaySignedIn(false);
        await SessionCache.clearCredentials();
        return;
      } on FirebaseException catch (fe) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppStr.signInFailed}: ${fe.message ?? fe.code}'),
            ),
          );
        }
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${AppStr.signInFailed}: $e')));
        }
        return;
      }
    } finally {
      _toggleLoading(false);
    }
  }

  Future<void> _onSignedIn(
    UserCredential userCredential,
    String email,
    String password,
  ) async {
    final String? uid = userCredential.user?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.signInFailed)));
      }
      return;
    }

    // Ensure /users/$uid exists (heal orphaned profile)
    final DataSnapshot snapshot = await FirebaseDatabase.instance
        .ref('users/$uid')
        .get();

    if (!snapshot.exists) {
      final String defaultCountry = getSystemCountryNames().first;
      await FirebaseDatabase.instance.ref('users/$uid').set({
        'userName': 'New User',
        'userSettings1': 'Name',
        'userSettings2': defaultCountry,
        'userSettings3': false,
        'userSettings4': false,
        'userSettings5': 50,
        'userSettings6': false,
        'baseCountry': defaultCountry,
        // userSettings7 will be ensured by ensureUserSetup below
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.healingOrphanedAccount)));
      }
    }

    // Build mapping refs
    final String mailboxEmail = email.toLowerCase();
    final String normalizedMailbox = normalizeEmailForPath(mailboxEmail);

    // Gather displayName for mapping/public profile (best-effort)
    String currentDisplayName = userCredential.user?.displayName ?? '';
    if (currentDisplayName.isEmpty) {
      try {
        final DataSnapshot ds = await FirebaseDatabase.instance
            .ref('users/$uid')
            .get();
        if (ds.exists && ds.value != null && ds.value is Map) {
          final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(
            ds.value as Map,
          );
          final String candidate =
              (m['userName'] as String?) ?? (m['displayName'] as String?) ?? '';
          if (candidate.isNotEmpty) {
            currentDisplayName = candidate;
          }
        }
      } catch (_) {
        // best-effort, ignore
      }
    }
    if (currentDisplayName.isEmpty) {
      currentDisplayName = mailboxEmail;
    }

    // Determine acceptsFriends flag from users/$uid/userSettings7 when available (default true)
    bool acceptsFriends = true;
    try {
      final DataSnapshot settings7Snap = await FirebaseDatabase.instance
          .ref('users/$uid/userSettings7')
          .get();
      if (settings7Snap.exists && settings7Snap.value != null) {
        final Object? v = settings7Snap.value;
        if (v is bool) {
          acceptsFriends = v;
        } else if (v is String) {
          acceptsFriends = v.toLowerCase() == 'true';
        } else if (v is num) {
          acceptsFriends = v != 0;
        }
      } else {
        // If missing, keep default true — helper will create userSettings7 if needed
      }
    } catch (e) {
      // Keep default on error
    }

    // Ensure mapping, public profile, and userSettings7 via helper (pass acceptsFriends)
    try {
      await ensureUserSetup(
        uid: uid,
        email: mailboxEmail,
        displayName: currentDisplayName,
        acceptsFriends: acceptsFriends,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStr.mappingWriteFailed}: $e')),
        );
      }
    }

    // Re-read user record to extract display name / homeCountry if needed
    final DataSnapshot dataSnapshot = await FirebaseDatabase.instance
        .ref('users/$uid')
        .get();
    final Object? data = dataSnapshot.value;

    String userName;
    String homeCountry;
    if (data is! Map) {
      final String defaultCountry = getSystemCountryNames().first;
      await FirebaseDatabase.instance.ref('users/$uid').set({
        'userName': 'New User',
        'userSettings1': 'Name',
        'userSettings2': defaultCountry,
        'userSettings3': false,
        'userSettings4': false,
        'userSettings5': 50,
        'userSettings6': false,
        'baseCountry': defaultCountry,
        'userSettings7': true,
      });
      userName = 'User';
      homeCountry = defaultCountry;
    } else {
      final Map<dynamic, dynamic> userMap = Map<dynamic, dynamic>.from(data);
      userName = (userMap['userName'] as String?) ?? 'User';
      homeCountry =
          (userMap['userSettings2'] as String?) ??
          getSystemCountryNames().first;

      // Ensure userSettings7 exists for existing accounts; helper already attempted to set it,
      // but keep this defensive write to cover rare races
      try {
        if (!userMap.containsKey('userSettings7')) {
          await FirebaseDatabase.instance
              .ref('users/$uid/userSettings7')
              .set(true);
        }
      } catch (e) {
        // Silently handle error
      }
    }

    await SessionCache.setStaySignedIn(_staySignedIn);
    if (_staySignedIn) {
      await SessionCache.setCredentials(email, password);
    } else {
      await SessionCache.clearCredentials();
    }

    await runStartupTasks(
      uid: uid,
      userName: userName,
      userEmail: email,
      homeCountry: homeCountry,
    );

    try {
      await processUserMailbox(uid, normalizedMailbox);
    } catch (e) {
      // Silently handle error
    }

    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, '/main', arguments: userName);
  }

  // Mailbox processing moved to lib/services/mailbox_helper.dart

  void _logEnvironmentHints() {
    try {
      // Environment diagnostics removed
    } catch (e) {
      // Silently handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        title: Text(
          AppStr.signInTitle,
          style: AppFonts.bold.copyWith(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _emailController,
                    enabled: !_initialSSI || !_staySignedIn,
                    decoration: InputDecoration(
                      labelText: AppStr.emailLabel,
                      labelStyle: AppFonts.standard,
                      border: const UnderlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    enabled: !_initialSSI || !_staySignedIn,
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
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _showPassword = !_showPassword;
                          });
                        },
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: Text(
                      AppStr.enableResetToggleLabel,
                      style: AppFonts.standard,
                    ),
                    value: _enableReset,
                    onChanged: (bool value) {
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _enableReset = value;
                      });
                    },
                    activeThumbColor: AppColors.darkGreen,
                    activeTrackColor: AppColors.ochre,
                  ),
                  TextButton(
                    onPressed: _enableReset
                        ? () async {
                            final String email = _emailController.text.trim();
                            final ScaffoldMessengerState messenger =
                                ScaffoldMessenger.of(context);

                            if (email.isEmpty) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(AppStr.emailRequired)),
                              );
                              return;
                            }

                            if (!email.contains('@')) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(AppStr.emailFormatInvalid),
                                ),
                              );
                              return;
                            }

                            try {
                              await FirebaseAuth.instance
                                  .sendPasswordResetEmail(email: email);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${AppStr.resetLinkSent} $email',
                                  ),
                                ),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${AppStr.resetLinkError}: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          }
                        : null,
                    child: Text(
                      AppStr.forgotPasswordLabel,
                      style: AppFonts.standard.copyWith(
                        color: _enableReset ? AppColors.blue : AppColors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(AppStr.staySignedIn, style: AppFonts.standard),
                    value: _staySignedIn,
                    onChanged: (bool value) async {
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _staySignedIn = value;
                      });

                      if (!value) {
                        _emailController.clear();
                        _passwordController.clear();
                        await SessionCache.setStaySignedIn(false);
                        await SessionCache.clearCredentials();
                      }
                    },
                    activeThumbColor: AppColors.darkGreen,
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
                children: <Widget>[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _loading
                        ? null
                        : () {
                            _signInUser();
                          },
                    child: Text(
                      AppStr.signInButton,
                      style: AppFonts.standard.copyWith(color: Colors.white),
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
                    onPressed: _loading
                        ? null
                        : () {
                            _goBack();
                          },
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

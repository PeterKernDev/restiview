// signin_screen.dart
//
// Sign-in flow that, after authentication and startup tasks, scans the user's UBE mailbox
// (users_by_email/<normalized>/requests) for incoming requests and creates friend stubs.
// Ensures a users_by_email/<normalized> mapping exists after successful sign-in.
// Writes a small public_profiles/<uid> record (displayName/email) so clients can read
// minimal public profile info without accessing private /users/<uid>.
// All user-visible strings must come from AppStr. Uses braced blocks, mounted guards,
// defensive parsing and diagnostic debugPrints.
//
// Updated to call ensureUserSetup(...) helper to create mapping, public_profile, and
// ensure users/$uid/userSettings7 exists for older accounts. Passes acceptsFriends flag
// based on users/$uid/userSettings7 when available; defaults to true.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/session_cache.dart';
import 'services/startup_tasks.dart';
import 'services/db_utils.dart'; // normalizeEmailForPath helper
import 'services/user_setup.dart'; // ensureUserSetup helper
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.nameHint)));
      }
      return false;
    }

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.emailPasswordRequired)));
      }
      return false;
    }

    final RegExp emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.emailRequired)));
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
      debugPrint('SignIn: start sign-in attempt for email="$email"');
      final bool netOk = await _probeNetwork();
      debugPrint('SignIn: network probe result: $netOk');

      try {
        final UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        debugPrint('SignIn: FirebaseAuth sign-in succeeded for uid=${userCredential.user?.uid}');
        await _onSignedIn(userCredential, email, password);
        return;
      } on FirebaseAuthException catch (e, st) {
        debugPrint('SignIn: FirebaseAuthException code=${e.code} message=${e.message}\n$st');

        final bool isRecaptchaOrNetwork = e.message?.toLowerCase().contains('recaptcha') == true ||
            e.message?.toLowerCase().contains('network') == true ||
            e.code == 'network-request-failed';

        if (isRecaptchaOrNetwork) {
          debugPrint('SignIn: transient network/recaptcha error detected, retrying in 1s');
          await Future<void>.delayed(const Duration(seconds: 1));
          try {
            final UserCredential retryCredential = await FirebaseAuth.instance
                .signInWithEmailAndPassword(email: email, password: password);
            debugPrint('SignIn: retry succeeded for uid=${retryCredential.user?.uid}');
            await _onSignedIn(retryCredential, email, password);
            return;
          } catch (retryErr, retrySt) {
            debugPrint('SignIn: retry failed: $retryErr\n$retrySt');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${AppStr.signInFailed}: ${retryErr.toString()}')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (mounted) {
          setState(() {
            _staySignedIn = false;
          });
        }
        await SessionCache.setStaySignedIn(false);
        await SessionCache.clearCredentials();
        return;
      } on FirebaseException catch (fe, st) {
        debugPrint('SignIn: FirebaseException ${fe.code} ${fe.message}\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${AppStr.signInFailed}: ${fe.message ?? fe.code}')));
        }
        return;
      } catch (e, st) {
        debugPrint('SignIn: unexpected exception: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.signInFailed}: $e')));
        }
        return;
      }
    } finally {
      debugPrint('SignIn: finishing sign-in attempt for email="$email" (loading false)');
      _toggleLoading(false);
    }
  }

  Future<void> _onSignedIn(UserCredential userCredential, String email, String password) async {
    final String? uid = userCredential.user?.uid;
    if (uid == null) {
      debugPrint('SignIn._onSignedIn: missing uid after sign-in');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.signInFailed)));
      }
      return;
    }
    debugPrint('SignIn._onSignedIn: uid=$uid email=$email');

    // Ensure /users/$uid exists (heal orphaned profile)
    final DataSnapshot snapshot = await FirebaseDatabase.instance.ref('users/$uid').get();
    debugPrint('SignIn._onSignedIn: users/$uid exists=${snapshot.exists}');

    if (!snapshot.exists) {
      final String defaultCountry = getSystemCountryNames().first;
      debugPrint('SignIn._onSignedIn: creating default user record for uid=$uid');
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.healingOrphanedAccount)));
      }
      debugPrint('SignIn._onSignedIn: created users/$uid');
    }

    // Build mapping refs
    final String mailboxEmail = email.toLowerCase();
    final String normalizedMailbox = normalizeEmailForPath(mailboxEmail);
    debugPrint('SignIn._onSignedIn: mailbox normalized="$normalizedMailbox"');

    // Gather displayName for mapping/public profile (best-effort)
    String currentDisplayName = userCredential.user?.displayName ?? '';
    if (currentDisplayName.isEmpty) {
      try {
        final DataSnapshot ds = await FirebaseDatabase.instance.ref('users/$uid').get();
        if (ds.exists && ds.value != null && ds.value is Map) {
          final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(ds.value as Map);
          final String candidate = (m['userName'] as String?) ?? (m['displayName'] as String?) ?? '';
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
      final DataSnapshot settings7Snap = await FirebaseDatabase.instance.ref('users/$uid/userSettings7').get();
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
    } catch (e, st) {
      debugPrint('SignIn._onSignedIn: failed to read userSettings7 for uid=$uid: $e\n$st');
    }

    // Ensure mapping, public profile, and userSettings7 via helper (pass acceptsFriends)
    try {
      await ensureUserSetup(
        uid: uid,
        email: mailboxEmail,
        displayName: currentDisplayName,
        acceptsFriends: acceptsFriends,
      );
      debugPrint('SignIn._onSignedIn: ensureUserSetup completed for uid=$uid (acceptsFriends=$acceptsFriends)');
    } catch (e, st) {
      debugPrint('SignIn._onSignedIn: ensureUserSetup failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${AppStr.mappingWriteFailed}: $e')));
      }
    }

    // Re-read user record to extract display name / homeCountry if needed
    final DataSnapshot dataSnapshot = await FirebaseDatabase.instance.ref('users/$uid').get();
    final Object? data = dataSnapshot.value;
    debugPrint('SignIn._onSignedIn: re-read users/$uid exists=${dataSnapshot.exists}');

    String userName;
    String homeCountry;
    if (data is! Map) {
      final String defaultCountry = getSystemCountryNames().first;
      debugPrint('SignIn._onSignedIn: user record missing or malformed, writing defaults');
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
      homeCountry = (userMap['userSettings2'] as String?) ?? getSystemCountryNames().first;
      debugPrint('SignIn._onSignedIn: extracted userName="$userName" homeCountry="$homeCountry"');

      // Ensure userSettings7 exists for existing accounts; helper already attempted to set it,
      // but keep this defensive write to cover rare races
      try {
        if (!userMap.containsKey('userSettings7')) {
          debugPrint('SignIn._onSignedIn: userSettings7 missing for uid=$uid, setting to true');
          await FirebaseDatabase.instance.ref('users/$uid/userSettings7').set(true);
          debugPrint('SignIn._onSignedIn: userSettings7 set for uid=$uid');
        }
      } catch (e, st) {
        debugPrint('SignIn._onSignedIn: failed to set userSettings7 for uid=$uid: $e\n$st');
      }
    }

    await SessionCache.setStaySignedIn(_staySignedIn);
    if (_staySignedIn) {
      await SessionCache.setCredentials(email, password);
      debugPrint('SignIn._onSignedIn: saved credentials for staySignedIn=true');
    } else {
      await SessionCache.clearCredentials();
      debugPrint('SignIn._onSignedIn: cleared saved credentials for staySignedIn=false');
    }

    debugPrint('SignIn._onSignedIn: running startup tasks');
    await runStartupTasks(uid: uid, userName: userName, userEmail: email, homeCountry: homeCountry);
    debugPrint('SignIn._onSignedIn: startup tasks completed');

    try {
      debugPrint('SignIn._onSignedIn: starting mailbox processing for $normalizedMailbox');
      await _processPendingFriendRequests(uid, normalizedMailbox);
      debugPrint('SignIn._onSignedIn: mailbox processing complete for $normalizedMailbox');
    } catch (e, st) {
      debugPrint('SignIn._onSignedIn: processPendingFriendRequests failed: $e\n$st');
    }

    if (!mounted) {
      debugPrint('SignIn._onSignedIn: widget unmounted, aborting navigation');
      return;
    }
    debugPrint('SignIn._onSignedIn: navigating to /main with userName="$userName"');
    Navigator.pushReplacementNamed(context, '/main', arguments: userName);
  }

  // Safe canonical resolver: prefer mapping then public_profiles; DO NOT read /users for client enrichment.
  Future<Map<String, String>> _resolveCanonicalProfile(String uid, Map<dynamic, dynamic>? mapping) async {
    String email = '';
    String username = '';

    if (mapping != null) {
      if (mapping['email'] is String && (mapping['email'] as String).isNotEmpty) {
        email = mapping['email'] as String;
      }
      if (mapping['userEmail'] is String && (mapping['userEmail'] as String).isNotEmpty) {
        email = mapping['userEmail'] as String;
      }
      if (mapping['displayName'] is String && (mapping['displayName'] as String).isNotEmpty) {
        username = mapping['displayName'] as String;
      }
      if (mapping['userName'] is String && (mapping['userName'] as String).isNotEmpty) {
        username = mapping['userName'] as String;
      }
    }

    // Prefer mapping, then public_profiles; do NOT attempt clients to read private /users
    if (username.isEmpty || email.isEmpty) {
      try {
        debugPrint('SignIn.resolveProfile: reading public_profiles/$uid as preferred public source');
        final DataSnapshot pub = await FirebaseDatabase.instance.ref('public_profiles/$uid').get();
        debugPrint('SignIn.resolveProfile: public_profiles/$uid exists=${pub.exists}');
        if (pub.exists && pub.value != null && pub.value is Map) {
          final Map<dynamic, dynamic> pm = Map<dynamic, dynamic>.from(pub.value as Map);
          if ((pm['displayName'] is String) && (pm['displayName'] as String).isNotEmpty) {
            username = pm['displayName'] as String;
          }
          if ((pm['email'] is String) && (pm['email'] as String).isNotEmpty) {
            email = pm['email'] as String;
          }
        }
      } catch (e) {
        debugPrint('SignIn.resolveProfile: public_profiles read failed (non-fatal): $e');
      }
    }

    if (email.isEmpty) email = uid;
    if (username.isEmpty) username = email;
    debugPrint('SignIn.resolveProfile: resolved uid=$uid email=$email username=$username');
    return {'email': email, 'username': username};
  }

  Future<void> _processPendingFriendRequests(String myUid, String normalizedMailbox) async {
    final DatabaseReference ref = FirebaseDatabase.instance.ref('users_by_email/$normalizedMailbox/requests');
    debugPrint('SignIn.processMailbox: reading mailbox path=${ref.path}');

    DataSnapshot snap;
    try {
      snap = await ref.get();
    } catch (e, st) {
      debugPrint('SignIn.processMailbox: Failed to read mailbox for $normalizedMailbox: $e\n$st');
      return;
    }

    if (!snap.exists || snap.value == null) {
      debugPrint('SignIn.processMailbox: mailbox empty for $normalizedMailbox');
      return;
    }

    final Object? raw = snap.value;
    if (raw is! Map) {
      debugPrint('SignIn.processMailbox: mailbox payload unexpected type=${raw.runtimeType}');
      return;
    }

    final Map<String, dynamic> entries = Map<String, dynamic>.from(raw);
    debugPrint('SignIn.processMailbox: entries found=${entries.length}');

    for (final MapEntry<String, dynamic> entry in entries.entries) {
      final String reqId = entry.key;
      final Object? requestData = entry.value;
      debugPrint('SignIn.processMailbox: handling reqId=$reqId');

      if (requestData is! Map) {
        debugPrint('SignIn.processMailbox: skipping malformed reqId=$reqId');
        continue;
      }

      final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(requestData);

      int statusCode = -1;
      if (m['statusCode'] is int) {
        statusCode = m['statusCode'] as int;
      } else if (m['statusCode'] is String) {
        statusCode = int.tryParse(m['statusCode'] as String) ?? -1;
      } else if (m['status'] is String) {
        final String s = (m['status'] as String).toUpperCase();
        if (s.contains('FR-ASKED') || s.contains('FR_ASKED')) {
          statusCode = 0;
        } else if (s.contains('FR-WANTED') || s.contains('FR_WANTS') || s.contains('FR-WANTS')) {
          statusCode = 2;
        } else {
          statusCode = -1;
        }
      }
      debugPrint('SignIn.processMailbox: reqId=$reqId parsed statusCode=$statusCode');

      final String fromUid = m['fromUid']?.toString() ?? '';
      final String clientRequestId = m['clientRequestId']?.toString() ?? '';
      final String comment = m['comment']?.toString() ?? '';

      debugPrint(
          'SignIn.processMailbox: reqId=$reqId fromUid="$fromUid" clientRequestId="$clientRequestId" comment="$comment"');

      if (statusCode < 0) {
        debugPrint('SignIn.processMailbox: reqId=$reqId unknown statusCode, skipping');
        continue;
      }
      if (fromUid.isEmpty) {
        debugPrint('SignIn.processMailbox: reqId=$reqId missing fromUid, skipping');
        continue;
      }

      try {
        Map<dynamic, dynamic>? mapping;
        if (m.isNotEmpty) {
          mapping = Map<dynamic, dynamic>.from(m);
        }
        final Map<String, String> canonical = await _resolveCanonicalProfile(fromUid, mapping);
        final String fromEmail = canonical['email']!;
        final String fromDisplayName = canonical['username']!;
        debugPrint(
            'SignIn.processMailbox: reqId=$reqId canonical fromEmail="$fromEmail" fromDisplayName="$fromDisplayName"');

        // Idempotency check: skip if friend stub already has same clientRequestId
        final DatabaseReference friendRef = FirebaseDatabase.instance.ref('users/$myUid/friends/$fromUid');
        final DataSnapshot friendSnap = await friendRef.get();
        debugPrint('SignIn.processMailbox: reqId=$reqId friend stub exists=${friendSnap.exists}');

        bool shouldWriteFriend = true;
        if (friendSnap.exists && friendSnap.value != null && friendSnap.value is Map) {
          final Map<dynamic, dynamic> f = Map<dynamic, dynamic>.from(friendSnap.value as Map);
          if (clientRequestId.isNotEmpty &&
              f['clientRequestId'] != null &&
              f['clientRequestId'].toString() == clientRequestId) {
            shouldWriteFriend = false;
            debugPrint(
                'SignIn.processMailbox: reqId=$reqId existing stub has matching clientRequestId, skipping write');
          }
        }

        if (shouldWriteFriend) {
          final int recipientViewStatus = (statusCode == 0) ? 2 : statusCode;
          final Map<String, dynamic> recipientStub = <String, dynamic>{
            'statusCode': recipientViewStatus,
            'email': fromEmail,
            'username': fromDisplayName,
            'comment': comment,
            'clientRequestId': clientRequestId,
            'updatedAt': DateTime.now().toIso8601String(),
          };
          final String myEmail = (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();
          final Map<String, dynamic> senderStub = <String, dynamic>{
            'statusCode': statusCode,
            'email': myEmail,
            'username': (FirebaseAuth.instance.currentUser?.displayName ?? myEmail),
            'comment': comment,
            'clientRequestId': clientRequestId,
            'updatedAt': DateTime.now().toIso8601String(),
          };

          // Atomic multi-path update: create both friend stubs and mark processed
          final Map<String, dynamic> atomic = <String, dynamic>{
            'users/$myUid/friends/$fromUid': recipientStub,
            'users/$fromUid/friends/$myUid': senderStub,
            'users_by_email/$normalizedMailbox/requests/$reqId/processedAt': DateTime.now().toIso8601String(),
            'users_by_email/$normalizedMailbox/requests/$reqId/processedBy': myUid,
          };
          debugPrint('SignIn.processMailbox: reqId=$reqId performing atomic update with keys: ${atomic.keys}');
          await FirebaseDatabase.instance.ref().update(atomic);
          debugPrint('SignIn.processMailbox: reqId=$reqId atomic update succeeded');
        } else {
          final Map<String, dynamic> processedMark = <String, dynamic>{
            'processedAt': DateTime.now().toIso8601String(),
            'processedBy': myUid,
          };
          debugPrint('SignIn.processMailbox: reqId=$reqId marking entry processed only');
          await FirebaseDatabase.instance
              .ref('users_by_email/$normalizedMailbox/requests/$reqId')
              .update(processedMark);
          debugPrint('SignIn.processMailbox: reqId=$reqId processed mark written');
        }
      } catch (e, st) {
        debugPrint('SignIn.processMailbox: reqId=$reqId failed processing: $e\n$st');
      }
    }
  }

  Future<bool> _probeNetwork() async {
    final List<String> urls = <String>[
      'https://www.gstatic.com/recaptcha/releases/',
      'https://www.googleapis.com/',
      'https://firebase.googleapis.com/'
    ];

    for (final String url in urls) {
      try {
        final http.Response r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        debugPrint('SignIn.probeNetwork: GET $url status=${r.statusCode} len=${r.contentLength ?? r.body.length}');
        if (r.statusCode >= 200 && r.statusCode < 500) {
          return true;
        }
      } on TimeoutException catch (te) {
        debugPrint('SignIn.probeNetwork: timeout for $url: $te');
      } catch (e, st) {
        debugPrint('SignIn.probeNetwork: error for $url: $e\n$st');
      }
    }
    debugPrint('SignIn.probeNetwork: all probes failed');
    return false;
  }

  void _logEnvironmentHints() {
    try {
      debugPrint('SignIn.env: starting diagnostics');
      debugPrint('SignIn.env: platform locale=${WidgetsBinding.instance.platformDispatcher.locale}');
    } catch (e) {
      debugPrint('SignIn.env: env hint failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        title: Text(AppStr.signInTitle, style: AppFonts.bold.copyWith(color: Colors.white)),
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
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
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
                    title: Text(AppStr.enableResetToggleLabel, style: AppFonts.standard),
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
                            final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

                            if (email.isEmpty) {
                              messenger.showSnackBar(SnackBar(content: Text(AppStr.emailRequired)));
                              return;
                            }

                            if (!email.contains('@')) {
                              messenger.showSnackBar(SnackBar(content: Text(AppStr.emailFormatInvalid)));
                              return;
                            }

                            try {
                              await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                              messenger.showSnackBar(SnackBar(content: Text('${AppStr.resetLinkSent} $email')));
                            } catch (e) {
                              messenger.showSnackBar(SnackBar(content: Text('${AppStr.resetLinkError}: ${e.toString()}')));
                            }
                          }
                        : null,
                    child: Text(AppStr.forgotPasswordLabel, style: AppFonts.standard.copyWith(color: _enableReset ? Colors.blue : Colors.grey)),
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
                        debugPrint('SignIn: user toggled staySignedIn -> false, cleared cached creds');
                      }
                    },
                    activeThumbColor: AppColors.darkGreen,
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
                children: <Widget>[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _loading
                        ? null
                        : () {
                            _signInUser();
                          },
                    child: Text(AppStr.signInButton, style: AppFonts.standard.copyWith(color: Colors.white)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ochre,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _loading
                        ? null
                        : () {
                            _goBack();
                          },
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

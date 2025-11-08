// signin_screen.dart
//
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/session_cache.dart';
import 'services/startup_tasks.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _staySignedIn = false;
  bool _showPassword = false;
  bool _loading = false;
  bool _initialSSI = false;
  bool _enableReset = false;

  void _toggleLoading(bool value) {
    if (!mounted) return;
    setState(() => _loading = value);
  }

  @override
  void initState() {
    super.initState();

    SessionCache.getStaySignedIn().then((value) {
      if (!mounted) return;
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

  void _goBack() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  bool _validateInputs({required bool requireName}) {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (requireName && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.nameHint)));
      return false;
    }

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.emailPasswordRequired)));
      return false;
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.emailRequired)));
      return false;
    }

    return true;
  }

  Future<void> _signInUser() async {
    if (!_validateInputs(requireName: false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    _toggleLoading(true);
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);

      final uid = userCredential.user?.uid;
      if (uid != null) {
        final snapshot = await FirebaseDatabase.instance.ref('users/$uid').get();

        if (!snapshot.exists) {
          final defaultCountry = getSystemCountryNames().first;
          await FirebaseDatabase.instance.ref('users/$uid').set({
            'userName': 'New User',
            'userSettings1': 'Name',
            'userSettings2': defaultCountry,
            'userSettings3': false,
            'userSettings4': false,
            'userSettings5': 50,
            'userSettings6': false,
            'baseCountry': defaultCountry,
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.healingOrphanedAccount)));
          }
        }

        final dataSnapshot = await FirebaseDatabase.instance.ref('users/$uid').get();
        final data = dataSnapshot.value;

        String userName;
        String homeCountry;

        if (data is! Map) {
          final defaultCountry = getSystemCountryNames().first;
          await FirebaseDatabase.instance.ref('users/$uid').set({
            'userName': 'New User',
            'userSettings1': 'Name',
            'userSettings2': defaultCountry,
            'userSettings3': false,
            'userSettings4': false,
            'userSettings5': 50,
            'userSettings6': false,
            'baseCountry': defaultCountry,
          });

          userName = 'User';
          homeCountry = defaultCountry;
        } else {
          final Map<dynamic, dynamic> userMap = data;
          userName = (userMap['userName'] as String?) ?? 'User';
          homeCountry = (userMap['userSettings2'] as String?) ?? getSystemCountryNames().first;
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

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/main', arguments: userName);
      }
    } on FirebaseAuthException catch (e) {
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

      if (mounted) setState(() => _staySignedIn = false);
      await SessionCache.setStaySignedIn(false);
      await SessionCache.clearCredentials();
    } finally {
      _toggleLoading(false);
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
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                          _showPassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() => _showPassword = !_showPassword);
                        },
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: Text(AppStr.enableResetToggleLabel, style: AppFonts.standard),
                    value: _enableReset,
                    onChanged: (value) {
                      setState(() => _enableReset = value);
                    },
                    activeThumbColor: AppColors.darkGreen,
                    activeTrackColor: AppColors.ochre,
                  ),
                  TextButton(
                    onPressed: _enableReset
                        ? () async {
                            final email = _emailController.text.trim();
                            final messenger = ScaffoldMessenger.of(context);

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
                    child: Text(
                      AppStr.forgotPasswordLabel,
                      style: AppFonts.standard.copyWith(color: _enableReset ? Colors.blue : Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(AppStr.staySignedIn, style: AppFonts.standard),
                    value: _staySignedIn,
                    onChanged: (value) async {
                      setState(() => _staySignedIn = value);

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
                      backgroundColor: AppColors.darkGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _loading ? null : _signInUser,
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

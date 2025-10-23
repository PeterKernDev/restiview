// main.dart
// App entry point for RestiView v1.3.0

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'landing_screen.dart';
import 'signin_screen.dart';
import 'register_screen.dart';
import 'help_screen.dart';
import 'top_screen.dart';
import 'list_screen.dart'; // correct relative path to ReviewListScreen
import 'settings_screen.dart';
import 'tandc_screen.dart';
import 'services/session_cache.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warm session cache before UI so screens can read persisted values synchronously.
  await SessionCache.initializeFromStorage();

  // Then initialize Firebase.
  await Firebase.initializeApp();
  FirebaseAuth.instance.setLanguageCode('en');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Gelica',
        scaffoldBackgroundColor: AppColors.beige,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.darkGreen),
        useMaterial3: true,
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const LandingScreen());
          case '/signin':
            return MaterialPageRoute(builder: (_) => const SignInScreen());
          case '/register':
            return MaterialPageRoute(builder: (_) => const RegisterScreen());
          case '/help':
            return MaterialPageRoute(builder: (_) => const HelpScreen());
          case '/main':
            return MaterialPageRoute(builder: (_) => const TopScreen());
          case '/list':
            return MaterialPageRoute(builder: (_) {
              final args = settings.arguments;
              if (args is Map && args['newReviewKey'] != null) {
                return ReviewListScreen(newReviewKey: args['newReviewKey'] as String?);
              }
              return const ReviewListScreen();
            });
          case '/settings':
            return MaterialPageRoute(builder: (_) => const SettingsScreen());
          case '/tandc':
            return MaterialPageRoute(builder: (_) => const TandCScreen());
          default:
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(
                  child: Text('Page not found', style: TextStyle(fontFamily: 'Gelica')),
                ),
              ),
            );
        }
      },
    );
  }
}
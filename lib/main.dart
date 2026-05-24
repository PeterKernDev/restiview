// lib/main.dart
//
// Enforces portrait-only orientation at startup and initializes SessionCache and Firebase.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'friends_screen.dart';
import 'friend_request_screen.dart'; // dedicated friend request screen
import 'review_request_screen.dart'; // dedicated review request screen
import 'review_request_details_screen.dart'; // provider review request details
import 'sub_friends_screen/friend_entry.dart'; // FriendEntry type for routing arguments
import 'services/session_cache.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock the app to portrait only (portraitUp and portraitDown)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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
        fontFamily: 'Literata',
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
              if (args is Map && args.containsKey('newReviewKey')) {
                return ReviewListScreen(newReviewKey: args['newReviewKey'] as String?, mode: 'list');
              }
              return const ReviewListScreen(mode: 'list');
            });
          case '/settings':
            return MaterialPageRoute(builder: (_) => const SettingsScreen());
          case '/tandc':
            return MaterialPageRoute(builder: (_) => const TandCScreen());
          case '/friends':
            return MaterialPageRoute(builder: (_) => const FriendsScreen());
          case '/friend-request':
            return MaterialPageRoute(builder: (_) => const FriendRequestScreen());
          case '/request': // kept for backward compatibility — now routes to ReviewRequestScreen
            return MaterialPageRoute(builder: (_) => const ReviewRequestScreen());
          case '/review-request': // explicit route name (optional)
            return MaterialPageRoute(builder: (_) => const ReviewRequestScreen());
          case '/review-request-details':
            return MaterialPageRoute(builder: (_) {
              final args = settings.arguments;
              if (args is Map) {
                final dynamic feObj = args['friendEntry'];
                final Map<dynamic, dynamic>? friendVmap =
                    (args['friendVmap'] is Map) ? args['friendVmap'] as Map<dynamic, dynamic> : null;

                if (feObj is FriendEntry) {
                  return ReviewRequestDetailsScreen(friendEntry: feObj, friendVmap: friendVmap);
                }
              }
              // Fallback: navigate back to friends if args missing or of wrong type
              return const FriendsScreen();
            });
          default:
            return MaterialPageRoute(
              builder: (_) => Scaffold(
                body: const Center(
                  child: Text(AppStr.pageNotFound),
                ),
              ),
            );
        }
      },
    );
  }
}

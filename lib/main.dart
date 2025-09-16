import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'landing_screen.dart';
import 'signin_screen.dart';
import 'help_screen.dart';
import 'top_screen.dart'; // ✅ Import the MainScreen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RestiView',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const LandingScreen());

          case '/signin':
            return MaterialPageRoute(builder: (_) => const SignInScreen());

          case '/help':
            return MaterialPageRoute(builder: (_) => const HelpScreen());

          case '/main':
            final userName = settings.arguments as String? ?? 'Guest';
            debugPrint('🟢 Routing to MainScreen with userName: $userName');
            return MaterialPageRoute(
              builder: (_) => TopScreen(userName: userName),
            );

          default:
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(child: Text('Page not found')),
              ),
            );
        }
      },
    );
  }
}
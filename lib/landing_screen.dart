import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for SystemNavigator.pop()

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo at the top
              Image.asset(
                'assets/restiview_hi_res_512.png',
                height: 120,
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                '** Restaurant Reviews **',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Welcome Message
              const Text(
                'Welcome to RESTVIEW\nPlease sign in or register.',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // HELP Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () => Navigator.pushNamed(context, '/help'),
                child: const Text('HELP'),
              ),
              const SizedBox(height: 16),

              // SIGN IN / REGISTER Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () => Navigator.pushNamed(context, '/signin'),
                child: const Text('SIGN IN / REGISTER'),
              ),
              const SizedBox(height: 16),

              // QUIT Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () => SystemNavigator.pop(),
                child: const Text('QUIT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
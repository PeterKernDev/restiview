// Landing_screen
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/restiview_icon_V4_yg.png',
                height: 160,
                semanticLabel: 'RestiView logo',
              ),
              const SizedBox(height: 24),
              Text(
                AppStr.appTitle,
                style: AppFonts.bold.copyWith(fontSize: 32, color: AppColors.darkGreen),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                AppStr.subtitle,
                style: AppFonts.standard.copyWith(fontSize: 18, color: AppColors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              Text(
                AppStr.welcomeMessage,
                style: AppFonts.standard.copyWith(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pushNamed(context, '/signin'),
                child: Text(AppStr.signInButton, style: AppFonts.standard.copyWith(color: Colors.white)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: Text(AppStr.registerButton, style: AppFonts.standard.copyWith(color: Colors.black)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ochre,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pushNamed(context, '/help'),
                child: Text(AppStr.help, style: AppFonts.standard.copyWith(color: Colors.black)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => SystemNavigator.pop(),
                child: Text(AppStr.quit, style: AppFonts.standard.copyWith(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
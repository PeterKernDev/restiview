// tandc_screen.dart
// Terms and Conditions screen — scrollable with back button

import 'package:flutter/material.dart';
import 'constants/strings.dart';
import 'constants/colours.dart';
import 'constants/tandc_constants.dart';

class TandCScreen extends StatelessWidget {
  const TandCScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        title: Text(
          'Terms & Conditions',
          style: AppFonts.bold.copyWith(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                TandCText.terms,
                style: AppFonts.standard.copyWith(fontSize: 14, color: Colors.black87),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ochre,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(AppStr.back, style: AppFonts.standard.copyWith(color: Colors.black)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
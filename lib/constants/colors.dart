// constants/colors.dart
//
// Brand colors and shared text styles used across the app.

import 'package:flutter/material.dart';

class AppColors {
  static const darkGreen = Color(0xFF2E4F3E);
  static const beige = Color(0xFFF5F0E6);
  static const ochre = Color(0xFFE2C48F);
  static const red = Color(0xFFD94F4F);

  // New tokens
  static const lightGrey = Color(0xFFF0F0F0);
  static const mutedText = Color(0xFF7A7A7A);
  static const ratingHighlight = Color(0xFFB00020); // 🔥 Used for rating emphasis

  // Added yellow (used for primary action buttons / highlights)
  static const yellow = Colors.yellow;
}

class AppFonts {
  static const gelica = 'Gelica';

  static const standard = TextStyle(
    fontFamily: gelica,
  );

  static const bold = TextStyle(
    fontFamily: gelica,
    fontWeight: FontWeight.bold,
  );

  static const title = TextStyle(
    fontFamily: gelica,
    fontWeight: FontWeight.bold,
    fontSize: 22,
  );

  static const smallHint = TextStyle(
    fontFamily: gelica,
    fontSize: 12,
    color: AppColors.mutedText,
  );
}
// lib/constants/fonts.dart
//
// Brand fonts and shared text styles used across the app.
// Use non-const TextStyle instances to avoid analyzer issues when combining
// with non-const colors or calling copyWith at runtime.

import 'package:flutter/material.dart';
import 'colors.dart';

class AppFonts {
  static const String gelica = 'Gelica';

  static final TextStyle standard = TextStyle(
    fontFamily: gelica,
    fontSize: 14,
    color: AppColors.black87,
  );

  static final TextStyle bold = TextStyle(
    fontFamily: gelica,
    fontWeight: FontWeight.bold,
    fontSize: 14,
    color: AppColors.black87,
  );

  static final TextStyle title = TextStyle(
    fontFamily: gelica,
    fontWeight: FontWeight.bold,
    fontSize: 22,
    color: AppColors.black87,
  );

  static final TextStyle smallHint = TextStyle(
    fontFamily: gelica,
    fontSize: 12,
    color: AppColors.mutedText,
  );

  static final TextStyle small = TextStyle(
    fontFamily: gelica,
    fontSize: 11,
    color: AppColors.mutedText,
  );
}

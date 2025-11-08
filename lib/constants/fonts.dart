// constants/fonts.dart
//
// Brand fonts and shared text styles used across the app.

import 'package:flutter/material.dart';
import 'colors.dart';

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
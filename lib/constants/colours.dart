import 'package:flutter/material.dart';

class AppColors {
  static const darkGreen = Color(0xFF2E4F3E);
  static const beige = Color(0xFFF5F0E6);
  static const ochre = Color(0xFFE2C48F);
  static const red = Color(0xFFD94F4F);
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
    color: Colors.grey,
  );
}
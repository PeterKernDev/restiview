// lib/constants/colors.dart
//
// Brand colors and shared tokens used across the app.

import 'package:flutter/material.dart';

class AppColors {
  static const Color darkGreen = Color(0xFF2E4F3E);
  static const Color beige = Color(0xFFF5F0E6);
  static const Color lightGrey = Color(0xFFF0F0F0);
  static const Color overlayDefault = Color.fromARGB(80, 0, 0, 0);

  static const Color ochre = Color(0xFFE2C48F);
  static const Color yellow = Color(0xFFFFEB3B);
  static const Color amber = Colors.amber;

  static const Color green = Color(0xFF2E7D32);
  static const Color red = Color(0xFFD94F4F);
  static const Color redShade100 = Color(0xFFFFCDD2);

  static const Color mutedText = Color(0xFF7A7A7A);
  static const Color ratingHighlight = Color(0xFFB00020);

  static const Color avatarBg = Color(0xFF8FB29E);
  static const Color selectedRow = Color(0xFFFFF6EA);
  static const Color lightOrange = Color(0xFFFFF2E0);

  static const Color blueAccent = Color(0xFF3B82F6);
  static const Color blue = Color(0xFF2196F3);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color greyShade200 = Color(0xFFEEEEEE);
  static const Color greyShade300 = Color(0xFFE0E0E0);
  static const Color greyShade400 = Color(0xFFBDBDBD);
  static const Color orange = Color(0xFFFF9800);
  static const Color orangeShade700 = Color(0xFFF57C00);
  static const Color orangeAccent = Color(0xFFFFAB40);
  static const Color lightGreenAccent = Color(0xFFB2FF59);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color black12 = Color(0x1F000000);
  static const Color black38 = Color(0x61000000);
  static const Color black54 = Color(0x8A000000);
  static const Color black87 = Color(0xDD000000);

  // Standard button colors
  static const Color btnDelete = red; // Red / Black text
  static const Color btnBack = ochre; // Ochre / Black text
  static const Color btnClear = grey; // Grey / Black text
  static const Color btnSave = green; // Green / Black text
  static const Color btnAdd = green; // Green / Black text
  static const Color btnPreview = Color(
    0xFFCE93D8,
  ); // Light purple / Black text
  static const Color btnRegister = orange; // Orange / Black text
  static const Color btnText = black; // Standard button text color

  // Helper to construct overlay colors with variable alpha at runtime.
  // Not const because it returns a new Color instance computed from the alpha.
  static Color overlay({int alpha = 80}) => Color.fromARGB(alpha, 0, 0, 0);
}

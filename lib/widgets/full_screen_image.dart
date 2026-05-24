// lib/widgets/full_screen_image.dart
// Reusable full screen image viewer used by Thumbnail, Details, Comments, Preview.
// Tap anywhere to dismiss. Uses Image.file with errorBuilder to avoid crashes.

import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/fonts.dart';
import '../constants/strings.dart';

class FullScreenImage extends StatelessWidget {
  final String path;

  const FullScreenImage({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Text(
              AppStr.photoError,
              style: AppFonts.standard.copyWith(color: AppColors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

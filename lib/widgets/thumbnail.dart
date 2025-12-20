// lib/widgets/thumbnail.dart
// Small, robust thumbnail used across the app for comment/detail photos.
// - Constrained size with min/max
// - Image.file with errorBuilder to avoid crashes on missing files
// - Optional remove button
// - InkWell overlay for taps

import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class Thumbnail extends StatelessWidget {
  final String? path;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final BoxFit fit;
  final Widget? placeholder;

  const Thumbnail({
    super.key,
    this.path,
    this.size = 84,
    this.onTap,
    this.onRemove,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _buildImageOrPlaceholder(),
          ),
          if (onRemove != null && path != null && path!.isNotEmpty)
            Positioned(
              top: 2,
              right: 2,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Material(
                  color: Colors.black38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: InkWell(
                    onTap: onRemove,
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          // Enable onTap when provided: either to view existing image or to capture new one
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageOrPlaceholder() {
    if (path == null || path!.isEmpty) {
      return Container(
        color: AppColors.lightGrey,
        child: Center(
          child:
              placeholder ??
              Icon(
                Icons.camera_alt,
                size: size * 0.38,
                color: AppColors.mutedText,
              ),
        ),
      );
    }

    try {
      final file = File(path!);
      final bool exists = file.existsSync();
      if (!exists) {
        // Missing file: show grey box with a small cross and do not present camera icon
        return Container(
          color: AppColors.greyShade300,
          width: size,
          height: size,
          child: const Center(child: Icon(Icons.close, color: Colors.white70)),
        );
      }

      return Image.file(
        file,
        fit: fit,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.lightGrey,
          child: Center(
            child: Icon(
              Icons.broken_image,
              size: size * 0.32,
              color: AppColors.mutedText,
            ),
          ),
        ),
      );
    } catch (_) {
      return Container(
        color: AppColors.lightGrey,
        child: Center(
          child: Icon(
            Icons.broken_image,
            size: size * 0.32,
            color: AppColors.mutedText,
          ),
        ),
      );
    }
  }
}

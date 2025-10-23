// review_filter_bar.dart
//
import 'package:flutter/material.dart';
import '../constants/strings.dart';
import '../services/session_cache.dart';

class ReviewFilterBar extends StatelessWidget {
  final String sortOption;
  final String? city;
  final String? cuisine;
  final VoidCallback onTap;

  const ReviewFilterBar({
    required this.sortOption,
    required this.city,
    required this.cuisine,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cuisineOptions = SessionCache.customCuisines;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Text(
            '${AppStr.sortLabel} ${_capitalize(sortOption)}',
            style: const TextStyle(fontFamily: 'Gelica'),
          ),
          const SizedBox(width: 16),
          AbsorbPointer( // ✅ Prevents dropdown from changing value directly
            child: DropdownButton<String>(
              value: cuisineOptions.contains(cuisine) ? cuisine : null,
              items: cuisineOptions
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (_) {}, // Disabled — triggers via GestureDetector
              hint: Text(AppStr.anyValue, style: const TextStyle(fontFamily: 'Gelica')),
              underline: const SizedBox(),
              style: const TextStyle(fontFamily: 'Gelica', color: Colors.black),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${AppStr.cityLabel} ${city ?? AppStr.anyValue}',
            style: const TextStyle(fontFamily: 'Gelica'),
          ),
        ],
      ),
    );
  }

  String _capitalize(String input) {
    return input.isNotEmpty
        ? '${input[0].toUpperCase()}${input.substring(1)}'
        : '';
  }
}
// lib/sub_list_screen/review_filter_bar.dart
// Compact filter bar shown at bottom of list screen.
// Displays current sort, cuisine, and city; taps open the filter dialog.

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${AppStr.sortLabel} ${_capitalize(sortOption)}',
            style: const TextStyle(fontFamily: 'Gelica'),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: AbsorbPointer(
              child: DropdownButtonFormField<String>(
                initialValue: cuisineOptions.contains(cuisine) ? cuisine : null,
                items: cuisineOptions
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (_) {},
                decoration: const InputDecoration(border: InputBorder.none),
                hint: Text(AppStr.anyValue, style: const TextStyle(fontFamily: 'Gelica')),
                style: const TextStyle(fontFamily: 'Gelica', color: Colors.black),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.35),
              child: Text(
                '${AppStr.cityLabel} ${city ?? AppStr.anyValue}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Gelica'),
              ),
            ),
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
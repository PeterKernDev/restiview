// review_list_item.dart
// Widget for displaying a single restaurant review in the list view.

import 'package:flutter/material.dart';
import '../constants/strings.dart'; // ✅ For AppStr

class ReviewListItem extends StatelessWidget {
  final Map<String, dynamic> review;
  final VoidCallback onTap;
  final bool highlight; // ✅ New parameter

  const ReviewListItem({
    required this.review,
    required this.onTap,
    this.highlight = false, // ✅ Default to false
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final restname = review['restname'] ?? '';
    final reviewdate = review['reviewdate'] ?? '';
    final rating = double.tryParse(review['restrating'].toString())?.round() ?? '';
    final restcountry = review['restcountry'] ?? '';
    final restcity = review['restcity'] ?? '';
    final restcuisine = review['restcuisine'] ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: highlight ? Colors.orange.withOpacity(0.2) : null, // ✅ Highlight background
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line 1: Restaurant name left, Rating right
              Row(
                children: [
                  Expanded(
                    child: Text(
                      restname,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Gelica',
                      ),
                    ),
                  ),
                  Text(
                    '${AppStr.ratingLabel} $rating',
                    style: const TextStyle(
                      color: Colors.black,
                      fontFamily: 'Gelica',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Line 2: Country/City left, Date center, Cuisine right
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$restcountry, $restcity',
                      style: const TextStyle(
                        color: Colors.black,
                        fontFamily: 'Gelica',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        reviewdate,
                        style: const TextStyle(
                          color: Colors.black,
                          fontFamily: 'Gelica',
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        restcuisine,
                        style: const TextStyle(
                          color: Colors.black,
                          fontFamily: 'Gelica',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
            ],
          ),
        ),
      ),
    );
  }
}
// lib/sub_list_screen/review_list_item.dart
// Widget for displaying a single restaurant review in the list view.

import 'package:flutter/material.dart';
import '../constants/strings.dart';
import '../constants/colors.dart';
import '../constants/fonts.dart';

class ReviewListItem extends StatelessWidget {
  final Map<String, dynamic> review;
  final VoidCallback onTap;
  final bool highlight;

  const ReviewListItem({
    required this.review,
    required this.onTap,
    this.highlight = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final restname = review['restname']?.toString() ?? '';
    final reviewdate = review['reviewdate']?.toString() ?? '';
    final restratingRaw = review['restrating'];
    int rating;
    if (restratingRaw is int) {
      rating = restratingRaw;
    } else {
      rating = int.tryParse(restratingRaw?.toString() ?? '') ??
          (double.tryParse(restratingRaw?.toString() ?? '')?.round() ?? 0);
    }

    final restcountry = review['restcountry']?.toString() ?? '';
    final restcity = review['restcity']?.toString() ?? '';
    final restcuisine = review['restcuisine']?.toString() ?? '';

    // Use AppColors.ochre with opacity for highlight
    // new: use withAlpha to set exact alpha value (0-255)
    final highlightColor = AppColors.ochre.withAlpha((0.12 * 255).round());

    return Material(
      color: highlight ? highlightColor : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      style: AppFonts.bold.copyWith(
                        color: AppColors.blue,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${AppStr.ratingLabel} $rating',
                    style: AppFonts.standard.copyWith(color: Colors.black),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Line 2: Country/City left, Date center, Cuisine right
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      (restcountry.isNotEmpty && restcity.isNotEmpty) ? '$restcountry, $restcity' : (restcountry + restcity),
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.standard,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        reviewdate,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.standard,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        restcuisine,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.standard,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
            ],
          ),
        ),
      ),
    );
  }
}

// sub_preview_screen/review_formatter.dart
//
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '/constants/restiview_constants.dart';
import '/constants/colors.dart';
import '/constants/strings.dart';
import '/constants/fonts.dart';

Widget reviewRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          '$label: ',
          style: AppFonts.bold,
        ),
        Expanded(
          child: Text(
            value,
            style: AppFonts.standard,
          ),
        ),
      ],
    ),
  );
}

Widget tagDisplay(List<String> tags) {
  if (tags.isEmpty) {
    return Text(
      AppStr.noTags,
      style: AppFonts.standard,
    );
  }

  final tagText = tags.join(', ');
  return Text(
    tagText,
    style: AppFonts.standard,
  );
}

Widget ratingSummary(int rating, int michelinStars) {
  final michelinPrefix = michelinStars > 0 ? 'M${'*' * michelinStars} ' : '';

  return Center(
    child: Text(
      '$michelinPrefix${AppStr.totalRatingLabel} $rating / 100',
      textAlign: TextAlign.center,
      style: AppFonts.bold.copyWith(
        fontSize: 20,
        color: AppColors.ratingHighlight,
      ),
    ),
  );
}

Map<String, dynamic> formatReviewData(Map<String, dynamic> data, String email, String name) {
  final date = DateTime.tryParse(data['dateOfReview'] ?? '') ?? DateTime.now();
  final formattedDate = DateFormat('dd/MM/yyyy').format(date);
  final sortDate = DateFormat('yyyy/MM/dd').format(date);

  final sortRating = (data['foodRating'] ?? 0) +
      (data['serviceRating'] ?? 0) +
      (data['ambianceRating'] ?? 0) +
      (data['drinksRating'] ?? 0) +
      (data['vfmsRating'] ?? 0);

  final List<String> selectedTags = List<String>.from(data['goodForTags'] ?? []);
  final goodForBinary = goodForTags.map((tag) => selectedTags.contains(tag) ? 'Y' : 'N').join();

  final Map<String, dynamic> formatted = {
    'restname': data['restaurantName'],
    'restcountry': data['country'],
    'restcity': data['city'],
    'restcuisine': data['cuisine'],
    'rfood': (data['foodRating'] ?? 0).toString(),
    'rservice': (data['serviceRating'] ?? 0).toString(),
    'rambiance': (data['ambianceRating'] ?? 0).toString(),
    'rdrinks': (data['drinksRating'] ?? 0).toString(),
    'rvfm': (data['vfmsRating'] ?? 0).toString(),
    'rmichlin': (data['michelinStars'] ?? 0).toString(),
    'restrating': sortRating.toString(),
    'cpersons': (data['numberOfDiners'] == '' || data['numberOfDiners'] == null)
        ? ''
        : data['numberOfDiners'].toString(),
    'cost': (data['cost'] == null || data['cost'].toString().trim().isEmpty)
        ? ''
        : (double.tryParse(data['cost'].toString())?.toStringAsFixed(2) ?? ''),
    'currency': data['currency'],
    'coccasion': data['occasion'],
    'ccomments': data['comments'],
    'reviewdate': formattedDate,
    'sortdate': sortDate,
    'sortrr': sortRating.toString().padLeft(3, '0'),
    'goodfor': goodForBinary,
    'userEmail': email,
    'userName': name,
    'photoPath': data['photoPath'],
    'restaddress': data['restaddress'],
    'restphone': data['restphone'],
    'timestamp': ServerValue.timestamp,
  };

  // Include up to 3 comment photo paths
  for (int i = 0; i < 3; i++) {
    final key = 'photoPath$i';
    if (data[key] != null) {
      formatted[key] = data[key];
    }
  }

  // Include detail categories if present
  for (final key in [
    'details_cocktails',
    'details_starters',
    'details_wine',
    'details_main',
    'details_dessert',
    'details_otherdrinks',
  ]) {
    if (data[key] != null) {
      formatted[key] = data[key];
    }
  }

  return formatted;
}

// review_formatter.dart
//
// Formats review data for Firebase storage and display.
// Converts raw review input into structured fields, including ratings (0–20 scale),
// tags, cost, and metadata like user info and timestamp.

import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '/constants/restiview_constants.dart';
import '/constants/strings.dart'; // ✅ Centralized strings

Widget reviewRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Gelica',
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontFamily: 'Gelica'),
          ),
        ),
      ],
    ),
  );
}

Widget tagDisplay(List<String> tags) {
  if (tags.isEmpty) {
    return const Text(
      AppStr.noTags,
      style: TextStyle(fontFamily: 'Gelica'),
    );
  }

  final tagText = tags.join(', ');
  return Text(
    tagText,
    style: const TextStyle(fontFamily: 'Gelica'),
  );
}

Widget ratingSummary(int rating, int michelinStars) {
  final michelinText = michelinStars > 0 ? '  (M-${'*' * michelinStars})' : '';

  return Center(
    child: Text(
      '${AppStr.totalRatingLabel} $rating / 100$michelinText',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        fontFamily: 'Gelica',
        color: Color(0xFFB00020),
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

  return {
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
}
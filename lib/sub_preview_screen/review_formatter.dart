import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

Widget reviewRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

Widget tagDisplay(List<String> tags) {
  if (tags.isEmpty) {
    return const Text('No tags selected');
  }

  final tagText = tags.join(', ');
  return Text(tagText);
}

Widget ratingSummary(double totalRating, int michelinStars) {
  return Row(
    children: [
      Text('REST RATING: ${totalRating.toStringAsFixed(1)}'),
      if (michelinStars > 0)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            'M-${'*' * michelinStars}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
    ],
  );
}

Map<String, dynamic> formatReviewData(Map<String, dynamic> data, String email, String name) {
  final date = DateTime.tryParse(data['dateOfReview'] ?? '') ?? DateTime.now();
  final formattedDate = DateFormat('dd/MM/yyyy').format(date);
  final sortDate = DateFormat('yyyy/MM/dd').format(date);

  final sortRating = (data['foodRating'] ?? 0.0) +
      (data['serviceRating'] ?? 0.0) +
      (data['ambianceRating'] ?? 0.0) +
      (data['drinksRating'] ?? 0.0) +
      (data['vfmsRating'] ?? 0.0);

  final List<String> goodForTags = List<String>.from(data['goodForTags'] ?? []);
  const goodForMap = [
    'Healthy', 'Authentic', 'A Date', 'Great Wine/Beer', 'Cozy', 'Waterfront',
    'Sunday Lunch', 'Happy Hour', 'Vegan', 'Business Meals', 'Vegetarian',
    'Creative Cuisine', 'Anniversaries', 'Scenic View', 'Special Occasion', 'Organic',
  ];
  final goodForBinary = goodForMap.map((tag) => goodForTags.contains(tag) ? 'Y' : 'N').join();

  return {
    'restname': data['restaurantName'],
    'restcountry': data['country'],
    'restcity': data['city'],
    'restcuisine': data['cuisine'],
    'rfood': (data['foodRating'] ?? 0.0).toStringAsFixed(1),
    'rservice': (data['serviceRating'] ?? 0.0).toStringAsFixed(1),
    'rambiance': (data['ambianceRating'] ?? 0.0).toStringAsFixed(1),
    'rdrinks': (data['drinksRating'] ?? 0.0).toStringAsFixed(1),
    'rvfm': (data['vfmsRating'] ?? 0.0).toStringAsFixed(1),
    'rmichlin': (data['michelinStars'] ?? 0.0).toStringAsFixed(1),
    'restrating': sortRating.toStringAsFixed(1),
    'cpersons': (data['numberOfDiners'] ?? 0).toString(),
    'cost': (data['cost'] ?? 0.0).toStringAsFixed(2),
    'currency': data['currency'],
    'coccasion': data['occasion'],
    'ccomments': data['comments'],
    'reviewdate': formattedDate,
    'sortdate': sortDate,
    'sortrr': sortRating.toStringAsFixed(3).padLeft(6, '0'),
    'goodfor': goodForBinary,
    'userEmail': email,
    'userName': name,
    'timestamp': ServerValue.timestamp,
  };
}
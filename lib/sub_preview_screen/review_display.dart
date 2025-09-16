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

  // Display tags as gf1, gf2, gf3,...
  final tagText = tags
      .asMap()
      .entries
      .map((entry) => 'gf${entry.key + 1}')
      .join(', ');

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
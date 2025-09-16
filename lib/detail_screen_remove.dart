import 'package:flutter/material.dart';

class DetailScreen extends StatelessWidget {
  final Map<dynamic, dynamic> review;

  const DetailScreen({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(review['restname'] ?? 'Review Detail'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Restaurant: ${review['restname'] ?? ''}', style: const TextStyle(fontSize: 18)),
            Text('Date: ${review['reviewdate'] ?? ''}'),
            Text('Rating: ${review['restrating'] ?? ''}'),
            const SizedBox(height: 12),
            Text('Country: ${review['restcountry'] ?? ''}'),
            Text('City: ${review['restcity'] ?? ''}'),
            Text('Cuisine: ${review['restcuisine'] ?? ''}'),
            const SizedBox(height: 12),
            Text('Food: ${review['rfood'] ?? ''}'),
            Text('Service: ${review['rservice'] ?? ''}'),
            Text('Ambiance: ${review['rambiance'] ?? ''}'),
            Text('Drinks: ${review['rdrinks'] ?? ''}'),
            Text('Value for Money: ${review['rvfm'] ?? ''}'),
            Text('Michelin Stars: ${review['rmichlin'] ?? ''}'),
            const SizedBox(height: 12),
            Text('Occasion: ${review['coccasion'] ?? ''}'),
            Text('Comments: ${review['ccomments'] ?? ''}'),
            Text('Cost: ${review['cost'] ?? ''} ${review['currency'] ?? ''}'),
            Text('Persons: ${review['cpersons'] ?? ''}'),
            const SizedBox(height: 12),
            Text('Good For: ${review['goodfor'] ?? ''}'),
          ],
        ),
      ),
    );
  }
}
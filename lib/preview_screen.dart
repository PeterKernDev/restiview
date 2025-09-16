import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'sub_preview_screen/review_display.dart';
import 'sub_preview_screen/review_context.dart';
import 'list_screen.dart';

class PreviewScreen extends StatefulWidget {
  final ReviewContext context;

  const PreviewScreen({super.key, required this.context});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  Map<String, dynamic>? reviewData;
  String? reviewKey;

  @override
  void initState() {
    super.initState();

    if (widget.context.reviewMap.isNotEmpty) {
      reviewData = widget.context.reviewMap;
      reviewKey = widget.context.reviewKey;
    } else if (widget.context.reviewKey != null) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        FirebaseDatabase.instance
            .ref('users/$userId/reviews/${widget.context.reviewKey}')
            .get()
            .then((snapshot) {
          if (snapshot.exists) {
            setState(() {
              reviewData = Map<String, dynamic>.from(snapshot.value as Map);
              reviewKey = widget.context.reviewKey;
            });
          }
        });
      }
    }
  }

  Future<void> saveReview() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || reviewData == null) return;

    final newRef = FirebaseDatabase.instance.ref('users/$userId/reviews').push();
    await newRef.set(reviewData);

    setState(() {
      reviewKey = newRef.key;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review saved successfully!')),
    );
  }

  Future<void> updateReview() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || reviewData == null || reviewKey == null) return;

    await FirebaseDatabase.instance
        .ref('users/$userId/reviews/$reviewKey')
        .update(reviewData!);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review updated successfully!')),
    );
  }

  Future<void> deleteReview() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null && reviewKey != null) {
      await FirebaseDatabase.instance.ref('users/$userId/reviews/$reviewKey').remove();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review deleted')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ReviewListScreen()),
      );
    }
  }

  void goToList() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ReviewListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (reviewData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final double totalRating = double.tryParse(reviewData!['restrating']?.toString() ?? '0.0') ?? 0.0;
    final michelinStars = int.tryParse(reviewData!['rmichlin']?.toString() ?? '0') ?? 0;
    final goodForTags = _extractTags(reviewData!['goodfor'], reviewData!);
    final dateString = reviewData!['reviewdate'] ?? 'Unknown';

    final isSaved = reviewKey != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restiview – Preview'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            reviewRow('Restaurant', reviewData!['restname'] ?? 'Unknown'),
            reviewRow('Country', reviewData!['restcountry'] ?? 'Unknown'),
            reviewRow('City', reviewData!['restcity'] ?? 'Unknown'),
            reviewRow('Cuisine', reviewData!['restcuisine'] ?? 'Unknown'),
            const SizedBox(height: 12),
            reviewRow('Food Rating', reviewData!['rfood']?.toString() ?? '0.0'),
            reviewRow('Service Rating', reviewData!['rservice']?.toString() ?? '0.0'),
            reviewRow('Ambiance Rating', reviewData!['rambiance']?.toString() ?? '0.0'),
            reviewRow('Drinks Rating', reviewData!['rdrinks']?.toString() ?? '0.0'),
            reviewRow('VFMS Rating', reviewData!['rvfm']?.toString() ?? '0.0'),
            ratingSummary(totalRating, michelinStars),
            const SizedBox(height: 12),
            reviewRow('Number of Diners', reviewData!['cpersons']?.toString() ?? '0'),
            reviewRow('Occasion', reviewData!['coccasion'] ?? 'None'),
            Row(
              children: [
                const Text('Cost:'), const SizedBox(width: 8),
                Text('${reviewData!['currency'] ?? 'USD'}'), const SizedBox(width: 8),
                Text(reviewData!['cost']?.toString() ?? '0.00'),
              ],
            ),
            const SizedBox(height: 12),
            reviewRow('Date of Review', dateString),
            const SizedBox(height: 12),
            reviewRow('Comment', reviewData!['ccomments'] ?? ''),
            const SizedBox(height: 16),
            const Text('============= Good For ============='),
            const SizedBox(height: 8),
            tagDisplay(goodForTags),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('BACK'),
                ),
                if (!isSaved)
                  ElevatedButton(
                    onPressed: () async => await saveReview(),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: const Text('SAVE'),
                  )
                else ...[
                  ElevatedButton(
                    onPressed: () async => await updateReview(),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    child: const Text('UPDATE'),
                  ),
                  ElevatedButton(
                    onPressed: () async => await deleteReview(),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('DELETE'),
                  ),
                  ElevatedButton(
                    onPressed: goToList,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                    child: const Text('LIST'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _extractTags(dynamic rawValue, Map<String, dynamic> reviewMap) {
    const goodForMap = [
      'Healthy', 'Authentic', 'A Date', 'Great Wine/Beer', 'Cozy', 'Waterfront',
      'Sunday Lunch', 'Happy Hour', 'Vegan', 'Business Meals', 'Vegetarian',
      'Creative Cuisine', 'Anniversaries', 'Scenic View', 'Special Occasion', 'Organic',
    ];

    if (rawValue is String && rawValue.length == goodForMap.length) {
      final tags = <String>[];
      for (int i = 0; i < goodForMap.length; i++) {
        if (rawValue[i] == 'Y') tags.add(goodForMap[i]);
      }
      return tags;
    }

    if (reviewMap.containsKey('goodForTags')) {
      final tagList = reviewMap['goodForTags'];
      if (tagList is List) {
        return List<String>.from(tagList);
      }
    }

    return [];
  }
}
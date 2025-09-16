import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'preview_screen.dart';
import 'sub_preview_screen/review_context.dart';

class ReviewListScreen extends StatefulWidget {
  const ReviewListScreen({super.key});

  @override
  State<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends State<ReviewListScreen> {
  late DatabaseReference _reviewsRef;
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _reviewsRef = FirebaseDatabase.instance.ref('users/$userId/reviews');
      _reviewsRef.onValue.listen((event) {
        final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
        final reviews = data.entries.map((e) {
          final review = Map<String, dynamic>.from(e.value as Map);
          review['key'] = e.key; // Store the Firebase key
          return review;
        }).toList();

        setState(() {
          _reviews = reviews;
        });
      });
    }
  }

  void _openReview(Map<String, dynamic> review) {
    final reviewKey = review['key'] as String?;
    final reviewContext = ReviewContext(
      reviewMap: review,
      isEditing: true,
      reviewKey: reviewKey,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(context: reviewContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Restaurant Reviews'),
        backgroundColor: Colors.red,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _reviews.length,
              itemBuilder: (context, index) {
                final review = _reviews[index];

                return GestureDetector(
                  onTap: () => _openReview(review),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                review['restname'] ?? '',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  review['reviewdate'] ?? '',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Rating: ${review['restrating'] ?? ''}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${review['restcountry'] ?? ''}, ${review['restcity'] ?? ''}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  review['restcuisine'] ?? '',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: const [
                    Text('Sort By: Rating'),
                    SizedBox(width: 16),
                    Text('Cuisine: Any'),
                    SizedBox(width: 16),
                    Text('Country: Any'),
                    SizedBox(width: 16),
                    Text('City: Any'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('BACK'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final newContext = ReviewContext(
                          reviewMap: {},
                          isEditing: false,
                          reviewKey: null,
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PreviewScreen(context: newContext),
                          ),
                        );
                      },
                      child: const Text('ADD'),
                    ),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('CLEAR'),
                    ),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('GOOD-FOR'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
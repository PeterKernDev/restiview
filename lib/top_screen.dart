import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'general_screen.dart';
import 'list_screen.dart';
import 'sub_preview_screen/review_context.dart';

class TopScreen extends StatefulWidget {
  final String userName;

  const TopScreen({super.key, required this.userName});

  @override
  State<TopScreen> createState() => _TopScreenState();
}

class _TopScreenState extends State<TopScreen> {
  bool _isLoading = false;

  void _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacementNamed(context, '/');
  }

  Future<void> _handleViewReviews() async {
    setState(() => _isLoading = true);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    final reviewsRef = FirebaseDatabase.instance.ref('users/$userId/reviews');
    final snapshot = await reviewsRef.get();
    setState(() => _isLoading = false);

    if (snapshot.exists && snapshot.value is Map) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReviewListScreen()),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No Reviews Found'),
          content: const Text('You haven’t submitted any reviews yet.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _startNewReview() {
    final newContext = ReviewContext(
      reviewMap: {},
      isEditing: false,
      reviewKey: null,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralScreen(context: newContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text('RestiView : ${widget.userName}', style: const TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const Text(
              '*** Restaurant Reviews ***',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _startNewReview,
              child: const Text('ADD REVIEW'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _isLoading ? null : _handleViewReviews,
              child: _isLoading
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('VIEW REVIEWS'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              child: const Text('SETTINGS'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => Navigator.pushNamed(context, '/help'),
              child: const Text('HELP'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => _signOut(context),
              child: const Text('SIGN OUT'),
            ),
          ],
        ),
      ),
    );
  }
}
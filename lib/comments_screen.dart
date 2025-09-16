import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'preview_screen.dart';
import 'sub_preview_screen/review_context.dart';
import 'sub_preview_screen/review_formatter.dart';

class CommentsScreen extends StatefulWidget {
  final ReviewContext context;

  const CommentsScreen({super.key, required this.context});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  late TextEditingController _commentsController;
  late TextEditingController _occasionController;

  @override
  void initState() {
    super.initState();
    _commentsController = TextEditingController(
      text: widget.context.reviewMap['comments'] ?? '',
    );
    _occasionController = TextEditingController(
      text: widget.context.reviewMap['occasion'] ?? '',
    );
  }

  @override
  void dispose() {
    _commentsController.dispose();
    _occasionController.dispose();
    super.dispose();
  }

  void _goToPreviewScreen() {
    // Update raw reviewMap with latest inputs
    widget.context.reviewMap['comments'] = _commentsController.text;
    widget.context.reviewMap['occasion'] = _occasionController.text;

    // Format the review data for preview
    final email = FirebaseAuth.instance.currentUser?.email ?? 'unknown';
    final name = FirebaseAuth.instance.currentUser?.displayName ?? 'anonymous';

    final formatted = formatReviewData(widget.context.reviewMap, email, name);

    final previewContext = ReviewContext(
      reviewMap: formatted,
      isEditing: widget.context.isEditing,
      reviewKey: widget.context.reviewKey,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(context: previewContext),
      ),
    );
  }

  void _goBack() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.context.isEditing;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Comments' : 'Add Comments'),
        backgroundColor: Colors.green, // ✅ Matches GoodFor and Ratings screens
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _occasionController,
              decoration: const InputDecoration(labelText: 'Occasion'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentsController,
              decoration: const InputDecoration(labelText: 'Comments'),
              maxLines: 5,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _goBack,
                  child: const Text('BACK'),
                ),
                ElevatedButton(
                  onPressed: _goToPreviewScreen,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('PREVIEW'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
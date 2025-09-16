// lib/models/review_context.dart

class ReviewContext {
  final Map<String, dynamic> reviewMap;
  final bool isEditing;
  final String? reviewKey;

  ReviewContext({
    required this.reviewMap,
    required this.isEditing,
    this.reviewKey,
  });
}
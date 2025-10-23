// review_context.dart
//
// Holds review data and editing state for navigation between screens.

class ReviewContext {
  Map<String, dynamic> reviewMap;
  bool isEditing; // ✅ Now mutable
  String? reviewKey; // ✅ No longer final

  ReviewContext({
    required this.reviewMap,
    required this.isEditing,
    this.reviewKey,
  });
}
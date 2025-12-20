// sub_preview_screen/review_context.dart
//
// Holds review data and editing state for navigation between screens.

class ReviewContext {
  Map<String, dynamic> reviewMap;
  bool isEditing; // ✅ Now mutable
  String? reviewKey; // ✅ No longer final
  bool hasChanges; // Track if any changes made to review data

  ReviewContext({
    required this.reviewMap,
    required this.isEditing,
    this.reviewKey,
    this.hasChanges = false,
  });
}

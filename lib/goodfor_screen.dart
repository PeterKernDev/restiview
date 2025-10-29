// goodfor_screen.dart
// Allows the user to select tags describing what the restaurant is good for (e.g., brunch, date night).
// Saves selections to ReviewContext and navigates to the comments screen.

import 'package:flutter/material.dart';
import 'ratings_screen.dart';
import 'comments_screen.dart';
import 'preview_screen.dart';
import 'sub_preview_screen/review_context.dart';
import 'sub_preview_screen/review_formatter.dart';
import 'constants/restiview_constants.dart';
import 'constants/colors.dart';
import 'constants/strings.dart'; // ✅ Centralized strings
import 'services/session_cache.dart';

class GoodForScreen extends StatefulWidget {
  final ReviewContext context;

  const GoodForScreen({super.key, required this.context});

  @override
  State<GoodForScreen> createState() => _GoodForScreenState();
}

class _GoodForScreenState extends State<GoodForScreen> {
  late Map<String, bool> _goodForOptions;

  @override
  void initState() {
    super.initState();

    _goodForOptions = {
      for (var tag in goodForTags) tag: false,
    };

    final selectedTags = List<String>.from(widget.context.reviewMap['goodForTags'] ?? []);
    for (var tag in selectedTags) {
      if (_goodForOptions.containsKey(tag)) {
        _goodForOptions[tag] = true;
      }
    }
  }

  void _saveToContext() {
    final selectedTags = _goodForOptions.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    widget.context.reviewMap['goodForTags'] = selectedTags;
  }

  void _goBack() {
    _saveToContext();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RatingsScreen(context: widget.context),
      ),
    );
  }

  void _goToNext() {
    _saveToContext();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(context: widget.context),
      ),
    );
  }

  void _goToPreviewScreen() {
    _saveToContext();

    final email = SessionCache.userEmail;
    final name = SessionCache.userName;

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

  void _clearSelections() {
    if (!mounted) return;
    setState(() {
      for (var key in _goodForOptions.keys) {
        _goodForOptions[key] = false;
      }
    });
  }

@override
Widget build(BuildContext context) {
  final options = _goodForOptions.entries.toList();

  return Scaffold(
    backgroundColor: const Color(0xFFF5F0E6),
    appBar: AppBar(
      automaticallyImplyLeading: false, // ✅ Disables top-left back arrow
      title: const Text(
        AppStr.goodForTitle,
        style: TextStyle(
          fontFamily: 'Gelica',
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      backgroundColor: const Color(0xFF2E4F3E),
      centerTitle: true,
    ),
    body: Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const Text(
                  AppStr.goodForPrompt,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Gelica',
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 4.5,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: options.map((entry) {
                      return Row(
                        children: [
                          Checkbox(
                            value: entry.value,
                            onChanged: (bool? value) {
                              if (!mounted) return;
                              setState(() {
                                _goodForOptions[entry.key] = value ?? false;
                              });
                            },
                          ),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 16,
                                fontFamily: 'Gelica',
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 36), // ✅ Replaces Spacer safely
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _goBack,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.ochre), // ✅ brand ochre

                  child: const Text(AppStr.back),
                ),
                ElevatedButton(
                  onPressed: _clearSelections,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  child: const Text(AppStr.clear),
                ),
                ElevatedButton(
                  onPressed: _goToPreviewScreen,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text(AppStr.preview),
                ),
                ElevatedButton(
                  onPressed: _goToNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text(AppStr.next),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}
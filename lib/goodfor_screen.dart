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
        builder: (_) => PreviewScreen(context: previewContext, mode: 'preview'),
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

    // Shared button style for consistent label sizes
    final ButtonStyle actionBtnBase = ElevatedButton.styleFrom(
      textStyle: const TextStyle(
        fontFamily: 'Gelica',
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      minimumSize: const Size(0, 44),
    );

    // Tile size: will be used by GridView childAspectRatio calculation
    const double tileHeight = 56.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0E6),
      appBar: AppBar(
        automaticallyImplyLeading: false,
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

                  // Grid with 2 columns, uniform tiles
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      // Calculate item width to keep two columns with spacing
                      final double spacing = 12;
                      final double availableWidth = constraints.maxWidth - spacing;
                      final double itemWidth = (availableWidth / 2);
                      final double childAspectRatio = itemWidth / tileHeight;

                      return GridView.count(
                        crossAxisCount: 2,
                        childAspectRatio: childAspectRatio,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        children: options.map((entry) {
                          final label = entry.key;
                          final checked = entry.value;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              if (!mounted) return;
                              setState(() {
                                _goodForOptions[label] = !checked;
                              });
                            },
                            child: Container(
                              height: tileHeight,
                              decoration: BoxDecoration(
                                color: checked ? Colors.yellow.shade100 : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: checked ? Colors.black54 : Colors.grey.shade300),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: const TextStyle(fontFamily: 'Gelica', fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    checked ? Icons.check_box : Icons.check_box_outline_blank,
                                    size: 18,
                                    color: checked ? Colors.black87 : Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Action row: single row of 4 buttons with consistent sizing.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _goBack,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(AppColors.ochre),
                          foregroundColor: WidgetStateProperty.all(Colors.black),
                        ),
                        child: const Text(AppStr.back, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _clearSelections,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(Colors.grey),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                        ),
                        child: const Text(AppStr.clear, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _goToPreviewScreen,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(Colors.green),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                        ),
                        child: const Text(AppStr.preview, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _goToNext,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(Colors.yellow),
                          foregroundColor: WidgetStateProperty.all(Colors.black),
                        ),
                        child: const Text(AppStr.next, overflow: TextOverflow.ellipsis),
                      ),
                    ),
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

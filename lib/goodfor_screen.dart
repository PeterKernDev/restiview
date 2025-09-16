import 'package:flutter/material.dart';
import 'ratings_screen.dart';
import 'comments_screen.dart';
import 'sub_preview_screen/review_context.dart';

class GoodForScreen extends StatefulWidget {
  final ReviewContext context;

  const GoodForScreen({super.key, required this.context});

  @override
  State<GoodForScreen> createState() => _GoodForScreenState();
}

class _GoodForScreenState extends State<GoodForScreen> {
  final Map<String, bool> _goodForOptions = {
    'Healthy': false,
    'Authentic': false,
    'A Date': false,
    'Great Wine/Beer': false,
    'Cozy': false,
    'Waterfront': false,
    'Sunday Lunch': false,
    'Happy Hour': false,
    'Vegan': false,
    'Business Meals': false,
    'Vegetarian': false,
    'Creative Cuisine': false,
    'Anniversaries': false,
    'Scenic View': false,
    'Special Occasion': false,
    'Organic': false,
  };

  @override
  void initState() {
    super.initState();
    final tags = List<String>.from(widget.context.reviewMap['goodForTags'] ?? []);
    for (var tag in tags) {
      if (_goodForOptions.containsKey(tag)) {
        _goodForOptions[tag] = true;
      }
    }
  }

  void _goBack() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RatingsScreen(context: widget.context),
      ),
    );
  }

  void _goToNext() {
    final selectedTags = _goodForOptions.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    widget.context.reviewMap['goodForTags'] = selectedTags;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(context: widget.context),
      ),
    );
  }

  void _clearSelections() {
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
      appBar: AppBar(
        title: const Text('Good For'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Select what this restaurant is good for:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 4.5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 4,
                children: options.map((entry) {
                  return Row(
                    children: [
                      Checkbox(
                        value: entry.value,
                        onChanged: (bool? value) {
                          setState(() {
                            _goodForOptions[entry.key] = value ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(entry.key, style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _clearSelections,
                  child: const Text('CLEAR'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                ),
                ElevatedButton(
                  onPressed: _goBack,
                  child: const Text('BACK'),
                ),
                ElevatedButton(
                  onPressed: null,
                  child: const Text('PREVIEW'),
                ),
                ElevatedButton(
                  onPressed: _goToNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('NEXT'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
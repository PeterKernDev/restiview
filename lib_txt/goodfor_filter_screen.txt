// goodfor_filter_screen.dart
// Allows users to select GoodFor tags to filter the review list view. Returns selected tags to caller.

import 'package:flutter/material.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart'; // ✅ Centralized strings
import 'constants/colors.dart';

class GoodForFilterScreen extends StatefulWidget {
  final List<String> initialSelection;

  const GoodForFilterScreen({super.key, required this.initialSelection});

  @override
  State<GoodForFilterScreen> createState() => _GoodForFilterScreenState();
}

class _GoodForFilterScreenState extends State<GoodForFilterScreen> {
  late Map<String, bool> _filterOptions;

  @override
  void initState() {
    super.initState();
    _filterOptions = {
      for (var tag in goodForTags) tag: false,
    };
    for (var tag in widget.initialSelection) {
      if (_filterOptions.containsKey(tag)) {
        _filterOptions[tag] = true;
      }
    }
  }

  void _clearFilters() {
    setState(() {
      for (var key in _filterOptions.keys) {
        _filterOptions[key] = false;
      }
    });
  }

  void _returnFilters() {
    final selected = _filterOptions.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    Navigator.pop(context, selected);
  }

@override
Widget build(BuildContext context) {
  final options = _filterOptions.entries.toList();

  return Scaffold(
    backgroundColor: AppColors.beige, // ✅ Brand beige
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text(
        AppStr.goodForFilterTitle,
        style: TextStyle(
          fontFamily: 'Gelica',
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      backgroundColor: AppColors.darkGreen, // ✅ Brand dark green
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
                  AppStr.goodForFilterPrompt,
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
                              setState(() {
                                _filterOptions[entry.key] = value ?? false;
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
        const SizedBox(height: 36),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _returnFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ochre, // ✅ Brand ochre
                  ),
                  child: const Text(AppStr.back),
                ),
                ElevatedButton(
                  onPressed: _clearFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey, // ✅ Always grey
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(AppStr.clear),
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
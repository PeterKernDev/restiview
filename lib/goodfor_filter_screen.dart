// goodfor_filter_screen.dart
// Matches GoodForScreen appearance but returns selected tags to caller.

import 'package:flutter/material.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';

class GoodForFilterScreen extends StatefulWidget {
  final List<String> initialSelection;

  const GoodForFilterScreen({super.key, required this.initialSelection});

  @override
  State<GoodForFilterScreen> createState() => _GoodForFilterScreenState();
}

class _GoodForFilterScreenState extends State<GoodForFilterScreen> {
  late Map<String, bool> _filterOptions;
  late Map<String, bool> _initialOptions;

  @override
  void initState() {
    super.initState();

    _filterOptions = {for (var tag in goodForTags) tag: false};

    for (var tag in widget.initialSelection) {
      if (_filterOptions.containsKey(tag)) {
        _filterOptions[tag] = true;
      }
    }

    _initialOptions = Map<String, bool>.from(_filterOptions);
  }

  bool get _hasChanged => !_mapsEqual(_filterOptions, _initialOptions);

  void _clearFilters() {
    setState(() {
      for (var key in _filterOptions.keys) {
        _filterOptions[key] = false;
      }
    });
  }

  void _returnFilters() {
    final selected = _filterOptions.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (!mounted) return;
    Navigator.pop(context, selected);
  }

  bool _mapsEqual(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final options = _filterOptions.entries.toList();

    // Shared button style for consistent label sizes
    final ButtonStyle actionBtnBase = ElevatedButton.styleFrom(
      textStyle: AppFonts.bold.copyWith(letterSpacing: 0.4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      minimumSize: const Size(0, 44),
    );

    // Tile height to match GoodForScreen visuals
    const double tileHeight = 56.0;

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          AppStr.goodForFilterTitle,
          style: AppFonts.bold.copyWith(color: AppColors.white),
        ),
        backgroundColor: AppColors.darkGreen,
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
                  Text(
                    AppStr.goodForFilterPrompt,
                    style: AppFonts.bold.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 24),

                  // Grid with same tile style as GoodForScreen (2 columns)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double spacing = 12;
                        final double availableWidth =
                            constraints.maxWidth - spacing;
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
                                  _filterOptions[label] = !checked;
                                });
                              },
                              child: Container(
                                height: tileHeight,
                                decoration: BoxDecoration(
                                  color: checked
                                      ? AppColors.yellowShade100
                                      : AppColors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: checked
                                        ? AppColors.black54
                                        : AppColors.greyShade300,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: AppColors.black12,
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: AppFonts.standard,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      checked
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      size: 18,
                                      color: checked
                                          ? AppColors.black87
                                          : AppColors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _returnFilters,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(
                            AppColors.ochre,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            AppColors.black,
                          ),
                        ),
                        child: Text(
                          _hasChanged ? AppStr.apply : AppStr.back,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: () {
                          _clearFilters();
                        },
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(
                            AppColors.btnClear,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            AppColors.btnText,
                          ),
                        ),
                        child: const Text(
                          AppStr.clear,
                          overflow: TextOverflow.ellipsis,
                        ),
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

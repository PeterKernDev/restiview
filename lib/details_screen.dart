// lib/details_screen.dart
// Reusable details screen for any category (cocktails, starters, wine, main, dessert, other).
// Uses shared Thumbnail and ActionRow widgets for consistent, overflow-safe behaviour.
// Fix: bottom action buttons use non-wrapping, scale-down text and reduced internal padding
// to prevent line-wrapping on narrow screens and at large textScaleFactor.
// Change: Add More button no longer uses an icon; label comes from AppStr.addMore (contains '+More').

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'sub_preview_screen/review_context.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/strings.dart';
import 'widgets/full_screen_image.dart';
import 'widgets/thumbnail.dart';

class DetailItem {
  String id;
  String name;
  String? photoPath;
  DateTime timestamp;
  late final TextEditingController controller;

  DetailItem({
    required this.id,
    this.name = '',
    this.photoPath,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now() {
    controller = TextEditingController(text: name);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'photoPath': photoPath,
        'timestamp': timestamp.toIso8601String(),
      };

  static DetailItem fromMap(Map<dynamic, dynamic> m) => DetailItem(
        id: m['id']?.toString() ?? UniqueKey().toString(),
        name: (m['name'] as String?) ?? '',
        photoPath: (m['photoPath'] as String?),
        timestamp: m['timestamp'] != null ? DateTime.tryParse(m['timestamp']) ?? DateTime.now() : DateTime.now(),
      );

  void disposeController() {
    controller.dispose();
  }
}

class DetailsScreen extends StatefulWidget {
  final String categoryKey;
  final String title;
  final ReviewContext context;

  const DetailsScreen({
    super.key,
    required this.categoryKey,
    required this.title,
    required this.context,
  });

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final List<DetailItem> _items = <DetailItem>[];
  final ImagePicker _picker = ImagePicker();
  bool _isBusy = false;

  // keep references to listeners so we can remove them before disposing controllers
  final Map<String, VoidCallback> _controllerListeners = {};

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    for (final entry in _controllerListeners.entries) {
      final id = entry.key;
      final listener = entry.value;
      final existing = _items.firstWhere((it) => it.id == id, orElse: () => DetailItem(id: UniqueKey().toString()));
      try {
        existing.controller.removeListener(listener);
      } catch (_) {}
    }
    for (final item in _items) {
      item.disposeController();
    }
    _controllerListeners.clear();
    super.dispose();
  }

  void _attachListener(DetailItem item) {
    if (_controllerListeners.containsKey(item.id)) {
      return;
    }
    void listener() {
      if (mounted) setState(() {});
    }

    item.controller.addListener(listener);
    _controllerListeners[item.id] = listener;
  }

  void _detachListener(DetailItem item) {
    final listener = _controllerListeners.remove(item.id);
    if (listener != null) {
      try {
        item.controller.removeListener(listener);
      } catch (_) {}
    }
  }

  void _showFullImage(String path) {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImage(path: path)));
  }

  void _loadExisting() {
    final key = 'details_${widget.categoryKey}';
    final raw = widget.context.reviewMap[key];
    if (raw is List) {
      for (final r in raw) {
        if (r is Map) {
          final item = DetailItem.fromMap(r);
          _items.add(item);
        }
      }
    }
    if (_items.isEmpty) {
      _items.add(DetailItem(id: UniqueKey().toString()));
    }
    for (final item in _items) {
      _attachListener(item);
    }
  }

  Future<void> _pickPhoto(int index) async {
    if (_isBusy || !mounted) return;
    try {
      setState(() => _isBusy = true);
      final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _items[index].photoPath = picked.path;
        _items[index].timestamp = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.saveError}: $e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _deletePhoto(int index) {
    if (!mounted) return;
    setState(() {
      _items[index].photoPath = null;
      _items[index].timestamp = DateTime.now();
    });
  }

  bool _lastItemHasContent() {
    if (_items.isEmpty) return false;
    final last = _items.last;
    final hasText = last.controller.text.trim().isNotEmpty;
    final hasPhoto = last.photoPath != null && last.photoPath!.isNotEmpty;
    return hasText || hasPhoto;
  }

  void _addMore() {
    if (!mounted) return;
    if (!_lastItemHasContent()) return;
    setState(() {
      final item = DetailItem(id: UniqueKey().toString());
      _items.add(item);
      _attachListener(item);
    });
  }

  void _removeItem(int index) {
    if (!mounted) return;
    setState(() {
      final removed = _items.removeAt(index);
      _detachListener(removed);
      removed.disposeController();
      if (_items.isEmpty) {
        final newItem = DetailItem(id: UniqueKey().toString());
        _items.add(newItem);
        _attachListener(newItem);
      }
    });
  }

  String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _saveAndReturn() async {
    if (!mounted) return;
    setState(() => _isBusy = true);
    try {
      for (var i = 0; i < _items.length; i++) {
        _items[i].name = _items[i].controller.text.trim();
      }
      final mapped = _items
          .where((it) => it.name.isNotEmpty || (it.photoPath != null && it.photoPath!.isNotEmpty))
          .map((it) => it.toMap())
          .toList();
      final key = 'details_${widget.categoryKey}';
      widget.context.reviewMap[key] = mapped;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.detailsSaved)));
      if (!mounted) return;
      Navigator.pop(context, widget.context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.saveError}: $e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Widget _photoColumn(int index, DetailItem item) {
    final photoPath = item.photoPath;
    return Column(
      children: <Widget>[
        Thumbnail(
          path: photoPath,
          size: 84,
          onTap: _isBusy
              ? null
              : () {
                  if (photoPath != null && photoPath.isNotEmpty) {
                    _showFullImage(photoPath);
                  } else {
                    _pickPhoto(index);
                  }
                },
          onRemove: (photoPath != null && photoPath.isNotEmpty) ? () => _deletePhoto(index) : null,
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 84,
          height: 28,
          child: TextButton.icon(
            onPressed: (photoPath == null || _isBusy) ? null : () => _deletePhoto(index),
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            label: const SizedBox.shrink(),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          ),
        ),
      ],
    );
  }

  Widget _itemCard(int index) {
    final item = _items[index];

    return Card(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            _photoColumn(index, item),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: ValueKey('textfield-${item.id}'),
                controller: item.controller,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 3,
                decoration: InputDecoration(labelText: AppStr.itemNameHint, alignLabelWithHint: true),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: AppStr.remove,
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _isBusy
                  ? null
                  : () {
                      final hasText = item.controller.text.trim().isNotEmpty;
                      final hasPhoto = item.photoPath != null && item.photoPath!.isNotEmpty;
                      if (!hasText && !hasPhoto && index > 0) {
                        _removeItem(index);
                      } else {
                        setState(() {
                          item.controller.clear();
                          item.name = '';
                        });
                      }
                    },
            ),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
            Text(item.photoPath == null ? AppStr.noPhoto : AppStr.photoAttached, style: AppFonts.smallHint),
            Text('${_formatDate(item.timestamp)} ${_formatTime(item.timestamp)}', style: AppFonts.smallHint),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore = !_isBusy && _lastItemHasContent();

    // Helper to produce a style with colors using styleFrom (no MaterialStateProperty)
    ButtonStyle buttonStyle(Color bg, Color fg) {
      return ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        minimumSize: const Size(0, 44),
        textStyle: AppFonts.standard,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
        title: Text(widget.title, style: AppFonts.bold.copyWith(color: Colors.white)),
        actions: <Widget>[
          TextButton(
            onPressed: _isBusy ? null : _saveAndReturn,
            child: Text(AppStr.save, style: AppFonts.standard.copyWith(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: <Widget>[
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) => _itemCard(i),
                ),
              ),
              const SizedBox(height: 12),

              // Fixed-height action row to prevent expansion
              SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: ElevatedButton(
                            onPressed: () {
                              if (!mounted) return;
                              Navigator.pop(context, widget.context);
                            },
                            style: buttonStyle(AppColors.red, Colors.white),
                            child: Text(AppStr.cancel, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.white)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: ElevatedButton(
                            onPressed: canAddMore ? _addMore : null,
                            style: buttonStyle(AppColors.ochre, Colors.black),
                            child: Text(AppStr.addMore, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: canAddMore ? Colors.black : Colors.black45)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: ElevatedButton(
                            onPressed: _isBusy ? null : _saveAndReturn,
                            style: buttonStyle(AppColors.darkGreen, Colors.white),
                            child: Text(AppStr.save, overflow: TextOverflow.ellipsis, style: AppFonts.bold.copyWith(color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ]),
          ),
          if (_isBusy)
            Container(
              color: Colors.black.withAlpha(80),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ]),
      ),
    );
  }
}

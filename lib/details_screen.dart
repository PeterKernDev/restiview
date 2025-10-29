// details_screen.dart
// Reusable details screen for any category (cocktails, starters, wine, main, dessert, other).
// Allows add-photo + editable text cards with "Add more". Saves list to ReviewContext.reviewMap.
// Controllers are owned by DetailItem to avoid controller/index mismatch when removing items.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'sub_preview_screen/review_context.dart';
import 'constants/colors.dart';
import 'constants/strings.dart';
import 'sub_preview_screen/full_screen_picture.dart';

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
      final item = _items.firstWhere((it) => it.id == id, orElse: () => DetailItem(id: UniqueKey().toString()));
      try {
        item.controller.removeListener(listener);
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
      // trigger rebuild so Add more button and other UI reflect controller changes
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
    if (!mounted) {
      return;
    }
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
    // attach listeners for controllers
    for (final item in _items) {
      _attachListener(item);
    }
  }

  Future<void> _pickPhoto(int index) async {
    if (_isBusy || !mounted) {
      return;
    }
    try {
      final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
      if (picked == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _items[index].photoPath = picked.path;
        _items[index].timestamp = DateTime.now();
      });
      // Recognition/computer-vision stub:
      // Trigger image recognition in a background isolate and update _items[index].controller.text when ready.
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.saveError}: $e')));
    }
  }

  void _deletePhoto(int index) {
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
    // guard: only add if last item has content
    if (!_lastItemHasContent()) {
      // no-op; button should be disabled in UI, but guard defensively
      return;
    }
    setState(() {
      final item = DetailItem(id: UniqueKey().toString());
      _items.add(item);
      _attachListener(item);
    });
  }

  void _removeItem(int index) {
    if (!mounted) {
      return;
    }
    setState(() {
      final removed = _items.removeAt(index);
      _detachListener(removed);
      removed.disposeController();
      // Ensure at least one card remains
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
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      // Sync controller values into items
      for (var i = 0; i < _items.length; i++) {
        _items[i].name = _items[i].controller.text.trim();
      }
      final mapped = _items
          .where((it) => it.name.isNotEmpty || (it.photoPath != null && it.photoPath!.isNotEmpty))
          .map((it) => it.toMap())
          .toList();
      final key = 'details_${widget.categoryKey}';
      widget.context.reviewMap[key] = mapped;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStr.detailsSaved)));
      if (!mounted) {
        return;
      }
      Navigator.pop(context, widget.context);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.saveError}: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Widget _photoColumn(int index, DetailItem item) {
    return Column(
      children: <Widget>[
        GestureDetector(
          onTap: _isBusy
              ? null
              : () {
                  final p = item.photoPath;
                  if (p != null && p.isNotEmpty) {
                    _showFullImage(p);
                  } else {
                    _pickPhoto(index);
                  }
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints.tightFor(width: 84, height: 84),
            child: Container(
              color: AppColors.lightGrey,
              child: item.photoPath == null
                  ? Icon(Icons.camera_alt, size: 32, color: AppColors.mutedText)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Builder(builder: (_) {
                        try {
                          final f = File(item.photoPath!);
                          if (!f.existsSync()) {
                            return Icon(Icons.broken_image, size: 32, color: AppColors.mutedText);
                          }
                          return Image.file(f, fit: BoxFit.cover);
                        } catch (_) {
                          return Icon(Icons.broken_image, size: 32, color: AppColors.mutedText);
                        }
                      }),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 84,
          height: 28,
          child: TextButton.icon(
            onPressed: (item.photoPath == null || _isBusy) ? null : () => _deletePhoto(index),
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            label: const SizedBox.shrink(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
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
                decoration: InputDecoration(
                  labelText: AppStr.itemNameHint,
                  alignLabelWithHint: true,
                ),
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
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
                ElevatedButton(
                  onPressed: () {
                    if (!mounted) {
                      return;
                    }
                    Navigator.pop(context, widget.context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  child: Text(AppStr.cancel, style: AppFonts.standard.copyWith(color: Colors.white)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.ochre, foregroundColor: Colors.black),
                  onPressed: canAddMore ? _addMore : null,
                  icon: const Icon(Icons.add),
                  label: Text(AppStr.addMore, style: AppFonts.standard.copyWith(color: canAddMore ? Colors.black : Colors.black45)),
                ),
                ElevatedButton(
                  onPressed: _isBusy ? null : _saveAndReturn,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkGreen),
                  child: Text(AppStr.save, style: AppFonts.standard.copyWith(color: Colors.white)),
                ),
              ]),
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

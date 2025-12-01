// comments_screen.dart
// "Details" screen: captures comments, up to three photos, and six detail categories (cocktails, starters, wine, main, dessert, other).
// Photo UI: three small tiles (left, center, right). Tapping a tile opens camera when empty or full-screen when present.
// Clear button only clears comments. Next button uses AppColors.yellow.
// Fixes applied:
//  - avoid synchronous File.existsSync during initState (don't block/throw on missing files)
//  - render the three photo slots using a Wrap so thumbnails never cause a horizontal RenderFlex overflow
//  - use Image.file with errorBuilder everywhere so missing/unreadable files don't break layout

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'preview_screen.dart';
import 'sub_preview_screen/review_context.dart';
import 'sub_preview_screen/review_formatter.dart';
import 'services/session_cache.dart';
import 'goodfor_screen.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'details_screen.dart';
import 'widgets/full_screen_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Small request object used when calling compute() to resize/encode images.
class _ResizeRequest {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
  _ResizeRequest(this.bytes, this.maxDimension, this.quality);
}

class CommentsScreen extends StatefulWidget {
  final ReviewContext context;

  const CommentsScreen({super.key, required this.context});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  late TextEditingController _commentsController;
  final ImagePicker _picker = ImagePicker();
  bool _isBusy = false;

  // up to 3 photo paths, contiguous from index 0. null means empty slot.
  final List<String?> _photoPaths = [null, null, null];

  @override
  void initState() {
    super.initState();
    _commentsController = TextEditingController(
      text: widget.context.reviewMap['comments'] ?? '',
    );

    // Do not perform synchronous File.existsSync calls in initState.
    // Accept stored paths if present; Image.file will handle missing files at paint time.
    for (var i = 0; i < 3; i++) {
      final key = 'photoPath$i';
      final p = widget.context.reviewMap[key];
      if (p is String && p.isNotEmpty) {
        _photoPaths[i] = p;
      } else {
        _photoPaths[i] = null;
      }
    }

    // Migrate legacy single photo key if present (without existsSync)
    if (_photoPaths.every((e) => e == null)) {
      final legacy = widget.context.reviewMap['photoPath'];
      if (legacy is String && legacy.isNotEmpty) {
        _photoPaths[0] = legacy;
        widget.context.reviewMap.remove('photoPath');
        widget.context.reviewMap['photoPath0'] = legacy;
      }
    }
  }

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  void _savePhotoPathsToContext() {
    for (var i = 0; i < 3; i++) {
      final key = 'photoPath$i';
      if (_photoPaths[i] != null) {
        widget.context.reviewMap[key] = _photoPaths[i];
      } else {
        widget.context.reviewMap.remove(key);
      }
    }
    widget.context.reviewMap.remove('photoPath');
  }

  void _showFullImage(String path) {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImage(path: path)));
  }

  // Runs in background isolate
  static Future<Uint8List> _resizeAndEncode(_ResizeRequest req) async {
    final bytes = req.bytes;
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final maxDim = req.maxDimension;
    final w = image.width;
    final h = image.height;
    if (w <= maxDim && h <= maxDim) {
      // no resize needed, just re-encode to desired quality
      return Uint8List.fromList(img.encodeJpg(image, quality: req.quality));
    }
    final ratio = w > h ? maxDim / w : maxDim / h;
    final newW = (w * ratio).round();
    final newH = (h * ratio).round();
    final resized = img.copyResize(image, width: newW, height: newH, interpolation: img.Interpolation.average);
    return Uint8List.fromList(img.encodeJpg(resized, quality: req.quality));
  }

  Future<String> _writeTempFile(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final id = const Uuid().v4();
    final file = File('${dir.path}/restiview_$id.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _capturePhotoAt(int index) async {
    if (_isBusy) return;
    if (!SessionCache.allowPhotos) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.photoDisabled)));
      return;
    }

    try {
      setState(() => _isBusy = true);
      final XFile? picked = await _picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      if (!mounted) return;

      // Read bytes and send to compute for resize/encode
      final bytes = await picked.readAsBytes();

      // Resize/encode in background. Choose target max dimension and quality.
      final resized = await compute<_ResizeRequest, Uint8List>(
        _resizeAndEncode,
        _ResizeRequest(bytes, 1024, 80),
      );

      // Write resized bytes to temp file
      final path = await _writeTempFile(resized);

      if (!mounted) return;
      setState(() {
        // place into the requested slot (index)
        _photoPaths[index] = path;
        _savePhotoPathsToContext();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStr.saveError}: $e')));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _removePhotoAt(int index) {
    if (!mounted) return;
    setState(() {
      // remove file if exists (best-effort)
      final path = _photoPaths[index];
      if (path != null) {
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      // shift left to keep contiguous
      for (var i = index; i < 2; i++) {
        _photoPaths[i] = _photoPaths[i + 1];
      }
      _photoPaths[2] = null;
      _savePhotoPathsToContext();
    });
  }

  void _clearCommentsOnly() {
    if (!mounted) return;
    setState(() {
      _commentsController.clear();
      widget.context.reviewMap['comments'] = '';
    });
  }

  void _saveToContext() {
    widget.context.reviewMap['comments'] = _commentsController.text;
    _savePhotoPathsToContext();
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

  void _goBack() {
    _saveToContext();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GoodForScreen(context: widget.context),
      ),
    );
  }

  Future<void> _openDetailsCategory(String categoryKey, String title) async {
    if (!mounted) return;
    await Navigator.push<ReviewContext>(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          categoryKey: categoryKey,
          title: title,
          context: widget.context,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {}); // refresh counts and UI after returning from details
  }

  Widget _detailTile(String key, String title, IconData icon) {
    final raw = widget.context.reviewMap['details_$key'];
    final count = (raw is List) ? raw.length : 0;
    // Replaced hard-coded labels with AppStr tokens
    final countLabel = count == 0 ? '${AppStr.detailsNone}: 0' : '${AppStr.detailsCountPrefix}: $count';

    return InkWell(
      onTap: () => _openDetailsCategory(key, title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.ochre,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: AppFonts.bold),
            ),
            const SizedBox(width: 8),
            Text(countLabel, style: AppFonts.standard.copyWith(color: AppColors.mutedText)),
          ],
        ),
      ),
    );
  }

  Widget _photoTileContent(String? path, bool enabled, int index) {
    if (path == null || path.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: AppColors.lightGrey, borderRadius: BorderRadius.circular(4)),
        child: Center(
          child: Icon(Icons.camera_alt, size: 32, color: enabled ? AppColors.mutedText : AppColors.mutedText.withAlpha(80)),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: AppColors.mutedText),
      ),
    );
  }

  Widget _photoSlot(int index) {
    final path = _photoPaths[index];
    final bool enabled = index == 0 ? true : _photoPaths[index - 1] != null;

    return GestureDetector(
      onTap: (!_isBusy && enabled)
          ? () {
              if (path != null && path.isNotEmpty) {
                _showFullImage(path);
              } else {
                _capturePhotoAt(index);
              }
            }
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 72, minHeight: 72, maxWidth: 84, maxHeight: 84),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
              child: _photoTileContent(path, enabled, index),
            ),
            if (path != null && path.isNotEmpty)
              Positioned(
                top: 2,
                right: 2,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Material(
                    color: Colors.black38,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    child: InkWell(
                      onTap: () => _removePhotoAt(index),
                      child: const Icon(Icons.close, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // detail categories
    final detailList = <Map<String, dynamic>>[
      {'key': 'cocktails', 'label': AppStr.cocktails, 'icon': Icons.local_bar},
      {'key': 'starters', 'label': AppStr.starters, 'icon': Icons.restaurant_menu},
      {'key': 'wine', 'label': AppStr.wine, 'icon': Icons.wine_bar},
      {'key': 'main', 'label': AppStr.mainCourse, 'icon': Icons.set_meal},
      {'key': 'dessert', 'label': AppStr.dessert, 'icon': Icons.icecream},
      {'key': 'otherdrinks', 'label': AppStr.otherDrinks, 'icon': Icons.local_drink},
    ];

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(AppStr.detailsMenuTitle, style: AppFonts.bold.copyWith(color: Colors.white)),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          TextField(
                            controller: _commentsController,
                            decoration: const InputDecoration(labelText: AppStr.commentsLabel),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),

                          // Thumbnails: use Wrap so slots wrap on narrow screens and never overflow
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: List<Widget>.generate(3, (i) => _photoSlot(i)),
                            ),
                          ),

                          const SizedBox(height: 20),
                          for (final cat in detailList) _detailTile(cat['key'] as String, cat['label'] as String, cat['icon'] as IconData),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _goBack,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.ochre),
                          child: Text(AppStr.back, style: AppFonts.standard.copyWith(color: Colors.black)), 
                        ),
                        ElevatedButton(
                          onPressed: _clearCommentsOnly,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.lightGrey),
                          child: Text(AppStr.clear, style: AppFonts.standard.copyWith(color: Colors.black87)), 
                        ),
                        ElevatedButton(
                          onPressed: _goToPreviewScreen,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.yellow,
                            foregroundColor: Colors.black,
                          ),
                          child: Text(AppStr.next, style: AppFonts.standard.copyWith(color: Colors.black)), 
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isBusy)
              Container(
                color: Colors.black.withAlpha(80),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

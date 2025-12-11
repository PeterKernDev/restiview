// preview_screen.dart
//
// Preview screen for showing a formatted review and allowing save/edit/delete actions.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'constants/restiview_constants.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'services/session_cache.dart';
import 'widgets/full_screen_image.dart';
import 'sub_preview_screen/review_context.dart';
import 'sub_preview_screen/review_formatter.dart' as formatter;
import 'sub_preview_screen/review_transform.dart';
import 'top_screen.dart';
import 'general_screen.dart';

class PreviewScreen extends StatefulWidget {
  final ReviewContext context;
  final String mode;

  const PreviewScreen({super.key, required this.context, this.mode = 'preview'});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

List<String> extractTags(dynamic rawValue, Map<String, dynamic> reviewMap) {
  final tagList = goodForTags;
  if (rawValue is String && rawValue.length == tagList.length) {
    final tags = <String>[];
    for (int i = 0; i < tagList.length; i++) {
      if (rawValue[i] == 'Y') {
        tags.add(tagList[i]);
      }
    }
    return tags;
  }
  if (reviewMap.containsKey('goodForTags')) {
    final rawTags = reviewMap['goodForTags'];
    if (rawTags is List) {
      return List<String>.from(rawTags);
    }
  }
  return <String>[];
}

int _computeRestrating(Map<String, dynamic> map) {
  final keys = ['rfood', 'rservice', 'rambiance', 'rdrinks', 'rvfm'];
  int total = 0;
  for (final k in keys) {
    final raw = map[k];
    if (raw == null) {
      continue;
    }
    final parsed = int.tryParse(raw.toString());
    if (parsed != null) {
      total += parsed;
    }
  }
  return total;
}

class _PreviewScreenState extends State<PreviewScreen> {
  Map<String, dynamic>? reviewData;
  String? reviewKey;
  final Set<String> expandedCategories = <String>{};
  bool _isSaving = false;

  // Cached ModalRoute reference to avoid ancestor lookups in dispose
  ModalRoute<dynamic>? _modalRoute;

  // route-scoped will-pop callback for SDK 3.9.x
  Future<bool> _onWillPop() async => false;

  void _showSaveConfirmation() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.reviewSaved)));
    widget.context.reviewMap.clear();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        goToList();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final email = SessionCache.userEmail;
    final name = SessionCache.userName;

    if (widget.context.reviewMap.isNotEmpty) {
      reviewKey = widget.context.reviewKey;
      final rawMap = reverseFormatReviewData(widget.context.reviewMap);
      widget.context.reviewMap = rawMap;
      reviewData = formatter.formatReviewData(rawMap, email, name);
    } else if (widget.context.reviewKey != null) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        FirebaseDatabase.instance
            .ref('users/$userId/reviews/${widget.context.reviewKey}')
            .get()
            .then((snapshot) {
          if (snapshot.exists && mounted) {
            final raw = Map<String, dynamic>.from(snapshot.value as Map);
            setState(() {
              reviewKey = widget.context.reviewKey;
              widget.context.reviewMap = reverseFormatReviewData(raw);
              reviewData = formatter.formatReviewData(widget.context.reviewMap, email, name);
            });
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture ModalRoute while element is active and register the scoped will-pop callback.
    // ignore: deprecated_member_use
    _modalRoute ??= ModalRoute.of(context);
    // ignore: deprecated_member_use
    _modalRoute?.addScopedWillPopCallback(_onWillPop);
  }

  // Helpers to keep SessionCache.indexedMatrix consistent
  void _addToIndexedMatrix(Map<String, dynamic> review) {
    final ctRaw = review['restcountry'];
    final cyRaw = review['restcity'];
    final czRaw = review['restcuisine'];

    final ct = ctRaw is String ? ctRaw.trim() : (ctRaw?.toString().trim());
    final cy = cyRaw is String ? cyRaw.trim() : (cyRaw?.toString().trim());
    final cz = czRaw is String ? czRaw.trim() : (czRaw?.toString().trim());

    if (ct == null || ct.isEmpty || cy == null || cy.isEmpty || cz == null || cz.isEmpty) {
      return;
    }

    final matrix = SessionCache.indexedMatrix;
    matrix.putIfAbsent(ct, () => <String, Set<String>>{});
    matrix[ct]!.putIfAbsent(cy, () => <String>{});
    matrix[ct]![cy]!.add(cz);
    SessionCache.indexedMatrix = matrix;
  }

  void _removeFromIndexedMatrix(Map<String, dynamic> review) {
    final ctRaw = review['restcountry'];
    final cyRaw = review['restcity'];
    final czRaw = review['restcuisine'];

    final ct = ctRaw is String ? ctRaw.trim() : (ctRaw?.toString().trim());
    final cy = cyRaw is String ? cyRaw.trim() : (cyRaw?.toString().trim());
    final cz = czRaw is String ? czRaw.trim() : (czRaw?.toString().trim());

    if (ct == null || ct.isEmpty || cy == null || cy.isEmpty || cz == null || cz.isEmpty) {
      return;
    }

    final matrix = SessionCache.indexedMatrix;
    if (!matrix.containsKey(ct)) return;
    final cityMap = matrix[ct]!;
    if (!cityMap.containsKey(cy)) return;
    final cuisineSet = cityMap[cy]!;
    cuisineSet.remove(cz);
    if (cuisineSet.isEmpty) {
      cityMap.remove(cy);
    } else {
      cityMap[cy] = cuisineSet;
    }
    if (cityMap.isEmpty) {
      matrix.remove(ct);
    } else {
      matrix[ct] = cityMap;
    }
    SessionCache.indexedMatrix = matrix;
  }

  Future<bool> _checkForDuplicateReview(String name, String date) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return true;
    final reviewsRef = FirebaseDatabase.instance.ref('users/$userId/reviews');
    final snapshot = await reviewsRef.get();
    if (!snapshot.exists) return true;
    final data = snapshot.value as Map<dynamic, dynamic>;
    final duplicates = data.values.where((review) {
      final reviewMap = Map<String, dynamic>.from(review as Map);
      return reviewMap['restname']?.toString().trim().toLowerCase() == name.trim().toLowerCase() &&
          reviewMap['reviewdate']?.toString().trim() == date.trim();
    });
    if (duplicates.isEmpty) return true;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate Review Detected'),
        content: Text('A review for "$name" on "$date" already exists.\nDo you still want to create a new one?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed')),
        ],
      ),
    );
    return proceed ?? false;
  }

  List<Map<String, dynamic>> normalizeCards(dynamic raw) {
    final normalized = <Map<String, dynamic>>[];
    if (raw == null) return normalized;
    if (raw is! List) return normalized;
    for (final item in raw) {
      if (item == null) continue;
      if (item is String) {
        final txt = item.trim();
        if (txt.isNotEmpty) {
          normalized.add({'text': txt, 'name': txt});
        }
        continue;
      }
      if (item is Map) {
        final text = (item['text'] ?? item['name'] ?? '').toString().trim();
        final photo = (item['photoPath'] ?? item['photo'] ?? '').toString().trim();
        if (text.isEmpty && photo.isEmpty) continue;
        final m = <String, dynamic>{};
        if (text.isNotEmpty) {
          m['text'] = text;
          m['name'] = text;
        }
        if (photo.isNotEmpty) {
          m['photoPath'] = photo;
        }
        normalized.add(m);
      }
    }
    return normalized;
  }

  Future<void> saveReview() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || reviewData == null) return;
    setState(() {
      _isSaving = true;
    });
    try {
      final restName = reviewData?['restname']?.toString().trim() ?? '';
      final reviewDate = reviewData?['reviewdate']?.toString().trim() ?? '';
      final shouldProceed = await _checkForDuplicateReview(restName, reviewDate);
      if (!shouldProceed) return;

      final nowIso = DateTime.now().toIso8601String();
      final payload = Map<String, dynamic>.from(reviewData!);

      if (payload['photoPath'] == null ||
          (payload['photoPath'] is String && payload['photoPath'].toString().trim().isEmpty)) {
        payload.remove('photoPath');
      }

      for (int i = 0; i < 3; i++) {
        final key = 'photoPath$i';
        if (payload.containsKey(key)) {
          final v = payload[key];
          if (v == null || (v is String && v.trim().isEmpty)) {
            payload.remove(key);
          }
        }
      }

      final detailKeys = <String>[
        'details_cocktails',
        'details_starters',
        'details_wine',
        'details_main',
        'details_dessert',
        'details_otherdrinks',
      ];
      for (final k in detailKeys) {
        if (payload.containsKey(k)) {
          final normalized = normalizeCards(payload[k]);
          if (normalized.isNotEmpty) {
            payload[k] = normalized;
          } else {
            payload.remove(k);
          }
        }
      }

      payload['restrating'] = _computeRestrating(payload).toString();

      payload['createdAt'] = nowIso;
      payload['updatedAt'] = nowIso;

      final newRef = FirebaseDatabase.instance.ref('users/$userId/reviews').push();
      await newRef.set(payload);

      // update custom values as before
      final cuisine = payload['restcuisine'];
      final occasion = payload['coccasion'];
      final customRef = FirebaseDatabase.instance.ref('users/$userId/customvals');
      final snapshot = await customRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        final updates = <String, dynamic>{};
        if (cuisine != null && !systemCuisines.contains(cuisine) && data['cuisine'] is List) {
          final List<dynamic> cuisines = List.from(data['cuisine']);
          for (int i = 0; i < cuisines.length; i++) {
            if (cuisines[i] is List && cuisines[i][0] == cuisine && cuisines[i][1] == 0) {
              cuisines[i][1] = 1;
              updates['cuisine'] = cuisines;
              break;
            }
          }
        }
        if (occasion != null &&
            !systemOccasions.contains(occasion) &&
            occasion != AppStr.defaultOccasion &&
            data['occasion'] is List) {
          final List<dynamic> occasions = List.from(data['occasion']);
          for (int i = 0; i < occasions.length; i++) {
            if (occasions[i] is List && occasions[i][0] == occasion && occasions[i][1] == 0) {
              occasions[i][1] = 1;
              updates['occasion'] = occasions;
              break;
            }
          }
        }
        if (updates.isNotEmpty) {
          await customRef.update(updates);
        }
      }

      _addToIndexedMatrix(payload);

      if (!mounted) return;
      setState(() {
        reviewKey = newRef.key;
        widget.context.reviewKey = newRef.key;
        try {
          widget.context.reviewMap = reverseFormatReviewData(payload);
        } catch (_) {}
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> updateReview() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || reviewData == null || reviewKey == null) return;
    setState(() {
      _isSaving = true;
    });
    try {
      final nowIso = DateTime.now().toIso8601String();
      final payload = Map<String, dynamic>.from(reviewData!);

      final previous = widget.context.reviewMap.isNotEmpty ? Map<String, dynamic>.from(widget.context.reviewMap) : null;

      if (payload['photoPath'] == null ||
          (payload['photoPath'] is String && payload['photoPath'].toString().trim().isEmpty)) {
        payload.remove('photoPath');
      }
      for (int i = 0; i < 3; i++) {
        final key = 'photoPath$i';
        if (payload.containsKey(key)) {
          final v = payload[key];
          if (v == null || (v is String && v.trim().isEmpty)) {
            payload.remove(key);
          }
        } else {
          payload[key] = null;
        }
      }

      final detailKeys = <String>[
        'details_cocktails',
        'details_starters',
        'details_wine',
        'details_main',
        'details_dessert',
        'details_otherdrinks',
      ];
      for (final k in detailKeys) {
        if (payload.containsKey(k)) {
          final normalized = normalizeCards(payload[k]);
          if (normalized.isNotEmpty) {
            payload[k] = normalized;
          } else {
            payload[k] = null;
          }
        } else {
          payload[k] = null;
        }
      }

      payload['restrating'] = _computeRestrating(payload).toString();

      payload['updatedAt'] = nowIso;

      await FirebaseDatabase.instance.ref('users/$userId/reviews/$reviewKey').update(payload);

      // update custom values as before
      final cuisine = payload['restcuisine'];
      final occasion = payload['coccasion'];
      final customRef = FirebaseDatabase.instance.ref('users/$userId/customvals');
      final snapshot = await customRef.get();
      if (snapshot.exists) {
        final data = snapshot.value as Map;
        final updates = <String, dynamic>{};
        if (cuisine != null && !systemCuisines.contains(cuisine) && data['cuisine'] is List) {
          final List<dynamic> cuisines = List.from(data['cuisine']);
          for (int i = 0; i < cuisines.length; i++) {
            if (cuisines[i] is List && cuisines[i][0] == cuisine && cuisines[i][1] == 0) {
              cuisines[i][1] = 1;
              updates['cuisine'] = cuisines;
              break;
            }
          }
        }
        if (occasion != null &&
            !systemOccasions.contains(occasion) &&
            occasion != AppStr.defaultOccasion &&
            data['occasion'] is List) {
          final List<dynamic> occasions = List.from(data['occasion']);
          for (int i = 0; i < occasions.length; i++) {
            if (occasions[i] is List && occasions[i][0] == occasion && occasions[i][1] == 0) {
              occasions[i][1] = 1;
              updates['occasion'] = occasions;
              break;
            }
          }
        }
        if (updates.isNotEmpty) {
          await customRef.update(updates);
        }
      }

      try {
        if (previous != null && previous.isNotEmpty) {
          final prevRaw = reverseFormatReviewData(previous);
          _removeFromIndexedMatrix(prevRaw);
        }
      } catch (_) {}

      _addToIndexedMatrix(payload);

      try {
        widget.context.reviewMap = reverseFormatReviewData(payload);
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> deleteReview() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(AppStr.deleteTitle),
        content: Text(
          widget.context.reviewKey == null ? AppStr.deletePendingMessage : AppStr.deletePermanentMessage,
          style: AppFonts.standard,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(AppStr.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text(AppStr.confirmDelete)),
        ],
      ),
    );
    if (confirm ?? false) {
      if (!mounted) return;
      if (widget.context.reviewKey == null) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => TopScreen()), (route) => false);
      } else {
        try {
          final local = widget.context.reviewMap.isNotEmpty ? reverseFormatReviewData(widget.context.reviewMap) : null;
          if (local != null && local.isNotEmpty) {
            _removeFromIndexedMatrix(local);
          }
        } catch (_) {}

        await FirebaseDatabase.instance.ref('users/$userId/reviews/${widget.context.reviewKey}').remove();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(AppStr.reviewDeleted)));
        Navigator.pushReplacementNamed(context, '/list', arguments: {'newReviewKey': null});
      }
    }
  }

  void goToList() {
    Navigator.pushReplacementNamed(context, '/list', arguments: {'newReviewKey': widget.context.reviewKey});
  }

  void goToEditFlow() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GeneralScreen(context: widget.context)));
  }

  String _formatCost(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '';
    try {
      final parsed = double.tryParse(value.toString());
      return parsed?.toStringAsFixed(2) ?? '';
    } catch (_) {
      return '';
    }
  }

  Widget _detailSummaryRow(String detailKey, String label, int count, IconData icon) {
    final fullKey = 'details_$detailKey';
    final isExpanded = expandedCategories.contains(fullKey);
    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            expandedCategories.remove(fullKey);
          } else {
            expandedCategories.add(fullKey);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: AppColors.ochre, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppFonts.bold, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Row(
              children: [
                Text('Items: $count', style: AppFonts.standard.copyWith(color: AppColors.mutedText)),
                const SizedBox(width: 8),
                if (isExpanded)
                  const Icon(Icons.expand_less, color: AppColors.mutedText)
                else
                  const Icon(Icons.expand_more, color: AppColors.mutedText),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Expanded block: label and a single collapse control on the label line (so text can use full width)
  Widget _expandedDetailBlock(String detailKey, String label, List<Map<String, dynamic>> cards) {
    final fullKey = 'details_$detailKey';
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row: reserve thumbnail width on left, shift label ~3 chars to the right, collapse control at right
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Row(
              children: [
                const SizedBox(width: 102), // reserve thumbnail + gap
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.left,
                    style: AppFonts.standard.copyWith(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), minimumSize: const Size(0, 36)),
                  child: const Text('<->', style: TextStyle(color: Color(0xFFB00020), fontWeight: FontWeight.w600)),
                  onPressed: () {
                    setState(() {
                      expandedCategories.remove(fullKey);
                    });
                  },
                ),
              ],
            ),
          ),
          Column(
            children: List<Widget>.generate(
              cards.length,
              (index) {
                final card = cards[index];
                final photo = (card['photoPath'] ?? '').toString();
                final text = (card['name'] ?? card['text'] ?? '').toString();
                final hasPhoto = photo.isNotEmpty; // avoid existsSync in build

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: hasPhoto
                            ? () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImage(path: photo)));
                              }
                            : null,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.grey.shade200),
                          child: hasPhoto
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(photo),
                                    fit: BoxFit.cover,
                                    width: 72,
                                    height: 72,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                )
                              : const Center(child: Icon(Icons.camera_alt_outlined, color: Colors.grey)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(text.isNotEmpty ? text : AppStr.detailsNoText, style: AppFonts.standard),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _cardsFor(String keyShort) {
    final fullKey = 'details_$keyShort';
    final raw = reviewData?[fullKey];
    return normalizeCards(raw);
  }

  // Overflow-safe rating row: label expands and value is constrained
  Widget _alignedRatingRow(String label, dynamic value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: AppFonts.standard.copyWith(fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 24, maxWidth: 80),
            child: Text(
              value?.toString() ?? '',
              textAlign: TextAlign.right,
              style: AppFonts.standard.copyWith(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (reviewData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final int totalRating = int.tryParse(reviewData!['restrating']?.toString() ?? '') ?? 0;
    final int michelinStars = int.tryParse(reviewData!['rmichlin']?.toString() ?? '0') ?? 0;
    final goodForTags = extractTags(reviewData!['goodfor'], reviewData!);
    final dateString = reviewData!['reviewdate']?.toString().trim();
    final isPending = widget.context.reviewKey == null && widget.context.isEditing;
    final costValue = reviewData!['cost']?.toString().trim();
    final dinersValue = reviewData!['cpersons']?.toString().trim();
    final occasionValue = reviewData!['coccasion']?.toString().trim();
    final commentsValue = reviewData!['ccomments']?.toString().trim();
    final photoPath = reviewData!['photoPath'];
    final cuisineValue = reviewData!['restcuisine']?.toString().trim();

    // Collect comment photo paths without synchronous filesystem checks; Image.file will use errorBuilder if missing
    final List<String> commentPhotos = <String>[];
    for (int i = 0; i < 3; i++) {
      final path = reviewData!['photoPath$i'];
      if (path != null && path is String && path.trim().isNotEmpty) {
        commentPhotos.add(path);
      }
    }

    final List<Map<String, dynamic>> detailCategories = <Map<String, dynamic>>[
      {'key': 'cocktails', 'label': AppStr.cocktails, 'icon': Icons.local_bar},
      {'key': 'starters', 'label': AppStr.starters, 'icon': Icons.restaurant_menu},
      {'key': 'wine', 'label': AppStr.wine, 'icon': Icons.wine_bar},
      {'key': 'main', 'label': AppStr.mainCourse, 'icon': Icons.set_meal},
      {'key': 'dessert', 'label': AppStr.dessert, 'icon': Icons.icecream},
      {'key': 'otherdrinks', 'label': AppStr.otherDrinks, 'icon': Icons.local_drink},
    ];

    final List<Widget> detailWidgets = <Widget>[];
    for (final cat in detailCategories) {
      final keyShort = cat['key'] as String;
      final cards = _cardsFor(keyShort);
      final count = cards.length;
      if (count == 0) {
        continue;
      }
      final fullKey = 'details_$keyShort';
      final isExpanded = expandedCategories.contains(fullKey);
      if (isExpanded) {
        detailWidgets.add(_expandedDetailBlock(keyShort, cat['label'] as String, cards));
      } else {
        detailWidgets.add(_detailSummaryRow(keyShort, cat['label'] as String, count, cat['icon'] as IconData));
      }
    }

    final String? addressValue = (reviewData!['restaddress']?.toString().trim().isNotEmpty ?? false)
        ? reviewData!['restaddress']?.toString().trim()
        : null;
    final String? phoneValue = (reviewData!['restphone']?.toString().trim().isNotEmpty ?? false)
        ? reviewData!['restphone']?.toString().trim()
        : null;

    final bool hasDetails = detailWidgets.isNotEmpty;
    final bool hasAddressOrPhone = (addressValue != null && addressValue.isNotEmpty) || (phoneValue != null && phoneValue.isNotEmpty);

    final String cityCountry = (reviewData!['restcity']?.toString().trim().isEmpty ?? true)
        ? (reviewData!['restcountry'] ?? '').toString()
        : '${reviewData!['restcity']}, ${reviewData!['restcountry']}';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F0E6),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(AppStr.previewTitle, style: AppFonts.bold.copyWith(color: Colors.white)),
          backgroundColor: const Color(0xFF2E4F3E),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  // Header rows: label left, value right
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 120, child: Text('${AppStr.restaurantLabel}:', style: AppFonts.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reviewData!['restname']?.toString().trim() ?? '',
                          style: AppFonts.bold.copyWith(fontSize: 16, color: Colors.blue),
                          maxLines: 2, // cap to 2 lines
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(width: 120, child: Text('${AppStr.locationLabel}:', style: AppFonts.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cityCountry,
                          style: AppFonts.standard,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (cuisineValue != null && cuisineValue.isNotEmpty)
                    Row(
                      children: [
                        SizedBox(width: 120, child: Text('${AppStr.cuisineLabel}:', style: AppFonts.bold)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            cuisineValue,
                            style: AppFonts.standard,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (cuisineValue != null && cuisineValue.isNotEmpty) const SizedBox(height: 4),
                  if (occasionValue != null && occasionValue.isNotEmpty && occasionValue != AppStr.defaultOccasion)
                    Row(
                      children: [
                        SizedBox(width: 120, child: Text('${AppStr.occasionLabel}:', style: AppFonts.bold)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            occasionValue,
                            style: AppFonts.standard,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (occasionValue != null && occasionValue.isNotEmpty && occasionValue != AppStr.defaultOccasion)
                    const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(width: 120, child: Text(AppStr.dateLabel, style: AppFonts.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dateString ?? '',
                          style: AppFonts.standard,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  const Divider(thickness: 1),
                  const SizedBox(height: 6),

                  // Ratings
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _alignedRatingRow(AppStr.foodLabel, reviewData!['rfood']),
                            _alignedRatingRow(AppStr.serviceLabel, reviewData!['rservice']),
                            _alignedRatingRow(AppStr.ambianceLabel, reviewData!['rambiance']),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _alignedRatingRow(AppStr.drinksLabel, reviewData!['rdrinks']),
                            _alignedRatingRow(AppStr.vfmsLabel, reviewData!['rvfm']),
                            _alignedRatingRow(
                              '${michelinStars > 0 ? 'M${'*' * michelinStars} ' : ''}Rating',
                              '$totalRating / ${AppStr.maxRating}',
                              isBold: true,
                              color: AppColors.ratingHighlight,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const Divider(thickness: 1),
                  const SizedBox(height: 6),

                  // Count / cost / main photo row — constrained to avoid overflow
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (dinersValue != null && dinersValue.isNotEmpty)
                              Flexible(child: formatter.reviewRow(AppStr.dinersLabel, dinersValue)),
                            if (costValue != null && costValue.isNotEmpty)
                              Flexible(child: formatter.reviewRow(AppStr.costLabel, '${reviewData!['currency']} ${_formatCost(costValue)}')),
                          ],
                        ),
                      ),
                      if (photoPath != null && photoPath.toString().trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Builder(builder: (context) {
                            final String p = photoPath.toString();
                            bool exists = false;
                            try {
                              exists = File(p).existsSync();
                            } catch (_) {
                              exists = false;
                            }

                            if (exists) {
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImage(path: p)));
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(p),
                                    height: 100,
                                    width: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Text(AppStr.photoError),
                                  ),
                                ),
                              );
                            }

                            return Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: const Center(child: Icon(Icons.close, color: Colors.white70)),
                            );
                          }),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  if (commentsValue != null && commentsValue.isNotEmpty) formatter.reviewRow(AppStr.commentLabel, commentsValue),
                  if (goodForTags.isNotEmpty) formatter.reviewRow('Good for', goodForTags.join(', ')),

                  // Comment photos rendered with Wrap to avoid overflow
                  if (commentPhotos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: commentPhotos.map((path) {
                          final String p = path;
                          bool exists = false;
                          try {
                            exists = File(p).existsSync();
                          } catch (_) {
                            exists = false;
                          }

                          if (exists) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImage(path: p)));
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minWidth: 72, minHeight: 72, maxWidth: 84, maxHeight: 84),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                    File(p),
                                    width: 84,
                                    height: 84,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                ),
                              ),
                            );
                          }

                          return ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 72, minHeight: 72, maxWidth: 84, maxHeight: 84),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: const Center(child: Icon(Icons.close, color: Colors.white70)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  // Details block (summary or expanded)
                  if (detailWidgets.isNotEmpty) ...[
                    const Divider(thickness: 1),
                    const SizedBox(height: 12),
                    ...detailWidgets,
                  ],

                  // Address/phone moved to after details; show divider only if there were details and address/phone exists
                  if (hasDetails && hasAddressOrPhone) ...[
                    const Divider(thickness: 1),
                    const SizedBox(height: 12),
                  ],

                  if (addressValue != null && addressValue.isNotEmpty) formatter.reviewRow(AppStr.addressLabel, addressValue),
                  if (phoneValue != null && phoneValue.isNotEmpty) formatter.reviewRow(AppStr.phoneLabel, phoneValue),

                  const Divider(thickness: 1),
                  const SizedBox(height: 36),

                  // Bottom action row: show preview buttons or exclude buttons depending on mode
                  if (widget.mode == 'preview')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: ElevatedButton(
                                onPressed: () {
                                  goToList();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey,
                                  foregroundColor: Colors.white,
                                  textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(AppStr.list, overflow: TextOverflow.ellipsis, style: AppFonts.bold),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: ElevatedButton(
                                onPressed: () {
                                  goToEditFlow();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(AppStr.change, overflow: TextOverflow.ellipsis, style: AppFonts.bold),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (isPending) {
                                    await saveReview();
                                  } else {
                                    await updateReview();
                                  }
                                  _showSaveConfirmation();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.yellow,
                                  foregroundColor: Colors.black,
                                  textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(AppStr.save, overflow: TextOverflow.ellipsis, style: AppFonts.bold),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: ElevatedButton(
                                onPressed: () async {
                                  await deleteReview();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(AppStr.delete, overflow: TextOverflow.ellipsis, style: AppFonts.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (widget.mode == 'exclude')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: ElevatedButton(
                                onPressed: () {
                                  // exclude_back: simply return to previous screen without excluding
                                  Navigator.pop(context, null);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.ochre,
                                  foregroundColor: Colors.white,
                                  textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: const Text('Back', overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: ElevatedButton(
                                onPressed: () {
                                  // Signal to caller that the current review should be excluded
                                  Navigator.pop(context, true);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: const Text('Exclude', overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_isSaving) Container(color: const Color(0xFF000000).withAlpha(77), child: const Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Unregister the scoped will-pop callback using the cached ModalRoute reference.
    // ignore: deprecated_member_use
    _modalRoute?.removeScopedWillPopCallback(_onWillPop);

    super.dispose();
  }
}

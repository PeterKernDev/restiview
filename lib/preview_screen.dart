// preview_screen.dart
//
// Preview screen for showing a formatted review and allowing save/edit/delete actions.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:disk_space_2/disk_space_2.dart';
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
import 'services/audit_info.dart';
import 'services/draft_cache.dart';

class PreviewScreen extends StatefulWidget {
  final ReviewContext context;
  final String mode;
  final String? friendUsername;

  const PreviewScreen({
    super.key,
    required this.context,
    this.mode = 'preview',
    this.friendUsername,
  });

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
  bool _loadFailed = false;

  void _showSaveConfirmation() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AppStr.reviewSaved)));
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

      // Auto-save: when returning to preview after editing an existing review,
      // persist the changes to Firebase immediately so the user never loses work.
      if (widget.context.reviewKey != null && widget.context.hasChanges) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await updateReview();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(AppStr.autoSaved),
              duration: Duration(seconds: 2),
            ),
          );
        });
      }
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
                  reviewData = formatter.formatReviewData(
                    widget.context.reviewMap,
                    email,
                    name,
                  );
                });
              }
            })
            .catchError((Object e) {
              appLog('initState review fetch error: $e');
              if (mounted) setState(() => _loadFailed = true);
            });
      }
    }
  }

  // Helpers to keep SessionCache.indexedMatrix consistent
  void _addToIndexedMatrix(Map<String, dynamic> review) {
    final ctRaw = review['restcountry'];
    final cyRaw = review['restcity'];
    final czRaw = review['restcuisine'];

    final ct = ctRaw is String ? ctRaw.trim() : (ctRaw?.toString().trim());
    final cy = cyRaw is String ? cyRaw.trim() : (cyRaw?.toString().trim());
    final cz = czRaw is String ? czRaw.trim() : (czRaw?.toString().trim());

    if (ct == null ||
        ct.isEmpty ||
        cy == null ||
        cy.isEmpty ||
        cz == null ||
        cz.isEmpty) {
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

    if (ct == null ||
        ct.isEmpty ||
        cy == null ||
        cy.isEmpty ||
        cz == null ||
        cz.isEmpty) {
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
    final DataSnapshot snapshot;
    try {
      snapshot = await reviewsRef.get().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return true; // timeout — proceed without duplicate check
    }
    if (!snapshot.exists) return true;
    final rawValue = snapshot.value;
    if (rawValue is! Map) return true;
    final data = rawValue;
    final duplicates = data.values.where((review) {
      if (review is! Map) return false;
      final reviewMap = Map<String, dynamic>.from(review);
      return reviewMap['restname']?.toString().trim().toLowerCase() ==
              name.trim().toLowerCase() &&
          reviewMap['reviewdate']?.toString().trim() == date.trim();
    });
    if (duplicates.isEmpty) return true;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStr.duplicateTitle),
        content: Text(
          'A review for "$name" on "$date" already exists.\nDo you still want to create a new one?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStr.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStr.proceed),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<bool> _checkStorageSpace() async {
    try {
      final freeDiskSpace = await DiskSpace.getFreeDiskSpace
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (freeDiskSpace == null) return true; // If we can't check, proceed
      
      // Check if less than 100 MB (convert MB to appropriate comparison)
      if (freeDiskSpace < 100) {
        if (!mounted) return false;
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppStr.lowStorageTitle, style: AppFonts.bold),
            content: Text(
              '${AppStr.lowStorageMessage} ${freeDiskSpace.toStringAsFixed(0)} ${AppStr.lowStorageMB}',
              style: AppFonts.standard,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppStr.cancel, style: AppFonts.standard),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppStr.continueAnyway, style: AppFonts.standard),
              ),
            ],
          ),
        );
        return shouldContinue ?? false;
      }
      return true; // Enough space available
    } catch (e) {
      appLog('Storage check failed: $e');
      return true; // If check fails, allow save to proceed
    }
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
        final photo = (item['photoPath'] ?? item['photo'] ?? '')
            .toString()
            .trim();
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
      // Check storage space before proceeding
      final hasSpace = await _checkStorageSpace();
      if (!hasSpace) return;
      
      final restName = reviewData?['restname']?.toString().trim() ?? '';
      final reviewDate = reviewData?['reviewdate']?.toString().trim() ?? '';
      final shouldProceed = await _checkForDuplicateReview(
        restName,
        reviewDate,
      );
      if (!shouldProceed) return;

      final nowIso = DateTime.now().toIso8601String();
      final payload = Map<String, dynamic>.from(reviewData!);

      if (payload['photoPath'] == null ||
          (payload['photoPath'] is String &&
              payload['photoPath'].toString().trim().isEmpty)) {
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

      final newRef = FirebaseDatabase.instance
          .ref('users/$userId/reviews')
          .push();
      await newRef.set(payload);

      // Update restaurant cuisine cache so future auto-fills pick it up
      final String cacheName =
          (payload['restname'] as String?)?.trim().toLowerCase() ?? '';
      final String cacheCountry =
          (payload['restcountry'] as String?)?.trim() ?? '';
      final String cacheCuisine =
          (payload['restcuisine'] as String?)?.trim() ?? '';
      if (cacheName.isNotEmpty &&
          cacheCountry.isNotEmpty &&
          cacheCuisine.isNotEmpty) {
        SessionCache.restaurantCuisineCache[
            '$cacheCountry|$cacheName'] = cacheCuisine;
      }

      // update custom values as before (best-effort; skip silently on timeout/error)
      try {
        final cuisine = payload['restcuisine'];
        final occasion = payload['coccasion'];
        final customRef = FirebaseDatabase.instance.ref(
          'users/$userId/customvals',
        );
        final snapshot = await customRef.get().timeout(const Duration(seconds: 10));
        if (snapshot.exists) {
          final data = snapshot.value as Map;
          final updates = <String, dynamic>{};
          if (cuisine != null &&
              !systemCuisines.contains(cuisine) &&
              data['cuisine'] is List) {
            final List<dynamic> cuisines = List.from(data['cuisine']);
            for (int i = 0; i < cuisines.length; i++) {
              if (cuisines[i] is List &&
                  cuisines[i][0] == cuisine &&
                  cuisines[i][1] == 0) {
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
              if (occasions[i] is List &&
                  occasions[i][0] == occasion &&
                  occasions[i][1] == 0) {
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
      } on TimeoutException {
        appLog('saveReview: customRef.get timed out — skipping custom vals update');
      } catch (e) {
        appLog('saveReview: custom vals update failed: $e');
      }

      _addToIndexedMatrix(payload);

      // Mark that a new review was added (for review_info update)
      await SessionCache.setReviewsAdded(true);
      unawaited(DraftCache.clear());

      if (!mounted) return;
      final savedKey = newRef.key;
      setState(() {
        reviewKey = savedKey;
        widget.context.reviewKey = savedKey;
        widget.context.hasChanges = false; // Reset after successful save
        try {
          widget.context.reviewMap = reverseFormatReviewData(payload);
        } catch (_) {}
      });
      final savedCountry = (payload['restcountry'] as String?)?.trim();
      SessionCache.countryFilter = (savedCountry != null && savedCountry.isNotEmpty) ? savedCountry : 'ALL';
      SessionCache.cityFilter = null;
      SessionCache.cuisineFilter = null;
      SessionCache.clearGoodForFilter();
      await SessionCache.setSortOption('date');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStr.reviewSaved)),
      );
      widget.context.reviewMap.clear();
      Navigator.pushReplacementNamed(
        context,
        '/list',
        arguments: {'newReviewKey': savedKey},
      );
    } catch (e) {
      appLog('saveReview error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.saveError)),
        );
      }
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
      // Check storage space before proceeding
      final hasSpace = await _checkStorageSpace();
      if (!hasSpace) return;
      
      final nowIso = DateTime.now().toIso8601String();
      final payload = Map<String, dynamic>.from(reviewData!);

      final previous = widget.context.reviewMap.isNotEmpty
          ? Map<String, dynamic>.from(widget.context.reviewMap)
          : null;

      if (payload['photoPath'] == null ||
          (payload['photoPath'] is String &&
              payload['photoPath'].toString().trim().isEmpty)) {
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

      await FirebaseDatabase.instance
          .ref('users/$userId/reviews/$reviewKey')
          .update(payload);

      // update custom values as before (best-effort; skip silently on timeout/error)
      try {
        final cuisine = payload['restcuisine'];
        final occasion = payload['coccasion'];
        final customRef = FirebaseDatabase.instance.ref(
          'users/$userId/customvals',
        );
        final snapshot = await customRef.get().timeout(const Duration(seconds: 10));
        if (snapshot.exists) {
          final data = snapshot.value as Map;
          final updates = <String, dynamic>{};
          if (cuisine != null &&
              !systemCuisines.contains(cuisine) &&
              data['cuisine'] is List) {
            final List<dynamic> cuisines = List.from(data['cuisine']);
            for (int i = 0; i < cuisines.length; i++) {
              if (cuisines[i] is List &&
                  cuisines[i][0] == cuisine &&
                  cuisines[i][1] == 0) {
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
              if (occasions[i] is List &&
                  occasions[i][0] == occasion &&
                  occasions[i][1] == 0) {
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
      } on TimeoutException {
        appLog('updateReview: customRef.get timed out — skipping custom vals update');
      } catch (e) {
        appLog('updateReview: custom vals update failed: $e');
      }

      try {
        if (previous != null && previous.isNotEmpty) {
          final prevRaw = reverseFormatReviewData(previous);
          _removeFromIndexedMatrix(prevRaw);
        }
      } catch (_) {}

      _addToIndexedMatrix(payload);
      unawaited(DraftCache.clear());

      widget.context.hasChanges = false; // Reset after successful update
      try {
        widget.context.reviewMap = reverseFormatReviewData(payload);
      } catch (_) {}
    } catch (e) {
      appLog('updateReview error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.saveError)),
        );
      }
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
    final userEmail = SessionCache.userEmail;
    if (userId == null) return;
    
    // Collect all photo paths from the review
    final List<String> photoPaths = [];
    if (reviewData != null) {
      // Main photo
      final mainPhoto = reviewData!['photoPath'];
      if (mainPhoto != null && mainPhoto is String && mainPhoto.trim().isNotEmpty) {
        photoPaths.add(mainPhoto);
      }
      
      // Comment photos (photoPath0, photoPath1, photoPath2)
      for (int i = 0; i < 3; i++) {
        final path = reviewData!['photoPath$i'];
        if (path != null && path is String && path.trim().isNotEmpty) {
          photoPaths.add(path);
        }
      }
      
      // Detail category photos
      final detailKeys = [
        'details_cocktails',
        'details_starters',
        'details_wine',
        'details_main',
        'details_dessert',
        'details_otherdrinks',
      ];
      for (final key in detailKeys) {
        final details = reviewData![key];
        if (details is List) {
          for (final item in details) {
            if (item is Map) {
              final photo = item['photoPath'];
              if (photo != null && photo is String && photo.trim().isNotEmpty) {
                photoPaths.add(photo);
              }
            }
          }
        }
      }
    }
    
    // Remove duplicates
    final uniquePhotoPaths = photoPaths.toSet().toList();
    final hasPhotos = uniquePhotoPaths.isNotEmpty;
    
    // Show delete dialog with optional photo toggle
    bool deletePhotos = false;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(AppStr.deleteTitle, style: AppFonts.bold),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.context.reviewKey == null
                        ? AppStr.deletePendingMessage
                        : AppStr.deletePermanentMessage,
                    style: AppFonts.standard,
                  ),
                  if (hasPhotos) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${uniquePhotoPaths.length} ${AppStr.photosWillBeDeleted}',
                      style: AppFonts.standard.copyWith(
                        fontSize: 12,
                        color: AppColors.orangeShade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: Text(
                        AppStr.deletePhotosLabel,
                        style: AppFonts.standard.copyWith(fontSize: 14),
                      ),
                      value: deletePhotos,
                      onChanged: (value) {
                        setState(() {
                          deletePhotos = value ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(AppStr.cancel, style: AppFonts.standard),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    {'confirm': true, 'deletePhotos': deletePhotos},
                  ),
                  child: Text(AppStr.confirmDelete, style: AppFonts.standard),
                ),
              ],
            );
          },
        );
      },
    );
    
    if (result == null || result['confirm'] != true) {
      return;
    }
    
    final shouldDeletePhotos = result['deletePhotos'] == true;
    
    if (!mounted) {
      return;
    }
    
    if (widget.context.reviewKey == null) {
      // Pending review - just navigate away
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => TopScreen()),
        (route) => false,
      );
    } else {
      // Delete saved review
      try {
        final local = widget.context.reviewMap.isNotEmpty
            ? reverseFormatReviewData(widget.context.reviewMap)
            : null;
        if (local != null && local.isNotEmpty) {
          _removeFromIndexedMatrix(local);
        }
      } catch (_) {}

      // Write audit record before deleting review
      try {
        await writeAuditInfo(
          userId: userId,
          userEmail: userEmail,
          type: 'review_delete',
          target: widget.context.reviewKey ?? '',
        );
      } catch (e) {
        appLog('Failed to write audit info: $e');
      }

      // Delete review from Firebase
      await FirebaseDatabase.instance
          .ref('users/$userId/reviews/${widget.context.reviewKey}')
          .remove();
      
      // Delete photo files if requested
      if (shouldDeletePhotos && uniquePhotoPaths.isNotEmpty) {
        int deletedCount = 0;
        for (final photoPath in uniquePhotoPaths) {
          try {
            final file = File(photoPath);
            if (await file.exists()) {
              await file.delete();
              deletedCount++;
            }
          } catch (e) {
            appLog('Failed to delete photo $photoPath: $e');
          }
        }
        appLog('Deleted $deletedCount of ${uniquePhotoPaths.length} photo files');
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.reviewDeleted)));
      Navigator.pushReplacementNamed(
        context,
        '/list',
        arguments: {'newReviewKey': null},
      );
    }
  }

  void goToList() async {
    // Warn if: 1) unsaved new review (reviewKey is null), OR 2) existing review with unsaved changes
    bool shouldLeave = true;

    if (widget.context.reviewKey == null || widget.context.hasChanges) {
      final bool? result = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(AppStr.discardTitle),
            content: const Text(AppStr.discardMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                child: const Text(AppStr.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                child: const Text(AppStr.yes),
              ),
            ],
          );
        },
      );
      shouldLeave = result ?? false;
    }

    if (shouldLeave) {
      if (!mounted) {
        return;
      }
      Navigator.pushReplacementNamed(
        context,
        '/list',
        arguments: {'newReviewKey': widget.context.reviewKey},
      );
    }
  }

  void goToEditFlow() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => GeneralScreen(context: widget.context)),
    );
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

  Widget _detailSummaryRow(
    String detailKey,
    String label,
    int count,
    IconData icon,
  ) {
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
              decoration: const BoxDecoration(
                color: AppColors.ochre,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppFonts.bold,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                Text(
                  'Items: $count',
                  style: AppFonts.standard.copyWith(color: AppColors.mutedText),
                ),
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
  Widget _expandedDetailBlock(
    String detailKey,
    String label,
    List<Map<String, dynamic>> cards,
  ) {
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
                    style: AppFonts.standard.copyWith(
                      fontSize: 14,
                      color: AppColors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    '<->',
                    style: AppFonts.bold.copyWith(color: AppColors.ratingHighlight),
                  ),
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
            children: List<Widget>.generate(cards.length, (index) {
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
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenImage(path: photo),
                                ),
                              );
                            }
                          : null,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: AppColors.greyShade200,
                        ),
                        child: hasPhoto
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  File(photo),
                                  fit: BoxFit.cover,
                                  width: 72,
                                  height: 72,
                                  errorBuilder: (context, error, stackTrace) => const Icon(
                                    Icons.broken_image,
                                    color: AppColors.grey,
                                  ),
                                ),
                              )
                            : const Center(
                                child: Icon(
                                  Icons.camera_alt_outlined,
                                  color: AppColors.grey,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.greyShade200),
                        ),
                        child: Text(
                          text.isNotEmpty ? text : AppStr.detailsNoText,
                          style: AppFonts.standard,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              );
            }),
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
  Widget _alignedRatingRow(
    String label,
    dynamic value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '$label:',
              style: AppFonts.standard.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
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
              style: AppFonts.standard.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentSection(String commentText) {
    // Estimate if comment will wrap to multiple lines
    // Rough estimate: if longer than ~50 characters, it will likely wrap
    final bool isLongComment = commentText.length > 50;

    if (isLongComment) {
      // For long comments: label on top, comment text below spanning full width
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStr.commentLabel}:',
              style: AppFonts.bold,
            ),
            const SizedBox(height: 4),
            Text(
              commentText,
              style: AppFonts.standard,
            ),
          ],
        ),
      );
    } else {
      // For short comments: use standard row format
      return formatter.reviewRow(AppStr.commentLabel, commentText);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStr.copiedToClipboard)),
    );
  }

  Widget _buildAddressSection(String addressText) {
    // Estimate if address will wrap to multiple lines
    // Rough estimate: if longer than ~50 characters, it will likely wrap
    final bool isLongAddress = addressText.length > 50;

    if (isLongAddress) {
      // For long addresses: label on top, address text below spanning full width
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStr.addressLabel}:',
              style: AppFonts.bold,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    addressText,
                    style: AppFonts.standard,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: AppStr.copiedToClipboard,
                  onPressed: () => _copyToClipboard(addressText),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // For short addresses: label + value in a row with copy button at end
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text('${AppStr.addressLabel}:', style: AppFonts.bold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(addressText, style: AppFonts.standard),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: AppStr.copiedToClipboard,
              onPressed: () => _copyToClipboard(addressText),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildGoodForSection(String goodForText) {
    // Estimate if good for tags will wrap to multiple lines
    // Rough estimate: if longer than ~50 characters, it will likely wrap
    final bool isLongGoodFor = goodForText.length > 50;

    if (isLongGoodFor) {
      // For long good for text: label on top, text below spanning full width
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good for:',
              style: AppFonts.bold,
            ),
            const SizedBox(height: 4),
            Text(
              goodForText,
              style: AppFonts.standard,
            ),
          ],
        ),
      );
    } else {
      // For short good for text: use standard row format
      return formatter.reviewRow('Good for', goodForText);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (reviewData == null) {
      if (_loadFailed) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text(AppStr.reviewLoadError)),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final int totalRating =
        int.tryParse(reviewData!['restrating']?.toString() ?? '') ?? 0;
    final int michelinStars =
        int.tryParse(reviewData!['rmichlin']?.toString() ?? '0') ?? 0;
    final goodForTags = extractTags(reviewData!['goodfor'], reviewData!);
    final dateString = reviewData!['reviewdate']?.toString().trim();
    final isPending =
        widget.context.reviewKey == null && widget.context.isEditing;
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
      {
        'key': 'starters',
        'label': AppStr.starters,
        'icon': Icons.restaurant_menu,
      },
      {'key': 'wine', 'label': AppStr.wine, 'icon': Icons.wine_bar},
      {'key': 'main', 'label': AppStr.mainCourse, 'icon': Icons.set_meal},
      {'key': 'dessert', 'label': AppStr.dessert, 'icon': Icons.icecream},
      {
        'key': 'otherdrinks',
        'label': AppStr.otherDrinks,
        'icon': Icons.local_drink,
      },
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
        detailWidgets.add(
          _expandedDetailBlock(keyShort, cat['label'] as String, cards),
        );
      } else {
        detailWidgets.add(
          _detailSummaryRow(
            keyShort,
            cat['label'] as String,
            count,
            cat['icon'] as IconData,
          ),
        );
      }
    }

    final String? addressValue =
        (reviewData!['restaddress']?.toString().trim().isNotEmpty ?? false)
        ? reviewData!['restaddress']?.toString().trim()
        : null;
    final String? phoneValue =
        (reviewData!['restphone']?.toString().trim().isNotEmpty ?? false)
        ? reviewData!['restphone']?.toString().trim()
        : null;

    final bool hasDetails = detailWidgets.isNotEmpty;
    final bool hasAddressOrPhone =
        (addressValue != null && addressValue.isNotEmpty) ||
        (phoneValue != null && phoneValue.isNotEmpty);

    final String cityCountry =
        (reviewData!['restcity']?.toString().trim().isEmpty ?? true)
        ? (reviewData!['restcountry'] ?? '').toString()
        : '${reviewData!['restcity']}, ${reviewData!['restcountry']}';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.beige,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            widget.mode == 'requested' && widget.friendUsername != null && widget.friendUsername!.isNotEmpty
                ? 'RestiView \u2013 Review from ${widget.friendUsername}'
                : AppStr.previewTitle,
            style: AppFonts.bold.copyWith(color: AppColors.white),
          ),
          backgroundColor: AppColors.darkGreen,
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
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${AppStr.restaurantLabel}:',
                          style: AppFonts.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reviewData!['restname']?.toString().trim() ?? '',
                          style: AppFonts.bold.copyWith(
                            fontSize: 16,
                            color: AppColors.blue,
                          ),
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
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${AppStr.locationLabel}:',
                          style: AppFonts.bold,
                        ),
                      ),
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
                        SizedBox(
                          width: 120,
                          child: Text(
                            '${AppStr.cuisineLabel}:',
                            style: AppFonts.bold,
                          ),
                        ),
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
                  if (cuisineValue != null && cuisineValue.isNotEmpty)
                    const SizedBox(height: 4),
                  if (occasionValue != null &&
                      occasionValue.isNotEmpty &&
                      occasionValue != AppStr.defaultOccasion)
                    Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            '${AppStr.occasionLabel}:',
                            style: AppFonts.bold,
                          ),
                        ),
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
                  if (occasionValue != null &&
                      occasionValue.isNotEmpty &&
                      occasionValue != AppStr.defaultOccasion)
                    const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(AppStr.dateLabel, style: AppFonts.bold),
                      ),
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
                            _alignedRatingRow(
                              AppStr.foodLabel,
                              reviewData!['rfood'],
                            ),
                            _alignedRatingRow(
                              AppStr.serviceLabel,
                              reviewData!['rservice'],
                            ),
                            _alignedRatingRow(
                              AppStr.ambianceLabel,
                              reviewData!['rambiance'],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _alignedRatingRow(
                              AppStr.drinksLabel,
                              reviewData!['rdrinks'],
                            ),
                            _alignedRatingRow(
                              AppStr.vfmsLabel,
                              reviewData!['rvfm'],
                            ),
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
                              Flexible(
                                child: formatter.reviewRow(
                                  AppStr.dinersLabel,
                                  dinersValue,
                                ),
                              ),
                            if (costValue != null && costValue.isNotEmpty)
                              Flexible(
                                child: formatter.reviewRow(
                                  AppStr.costLabel,
                                  '${reviewData!['currency']} ${_formatCost(costValue)}',
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (photoPath != null &&
                          photoPath.toString().trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Builder(
                            builder: (context) {
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
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            FullScreenImage(path: p),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(p),
                                      height: 100,
                                      width: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Text(AppStr.photoError),
                                    ),
                                  ),
                                );
                              }

                              return Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppColors.greyShade300,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.greyShade400,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.close,
                                    color: AppColors.white70,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),
                  if (commentsValue != null && commentsValue.isNotEmpty)
                    _buildCommentSection(commentsValue),
                  if (goodForTags.isNotEmpty)
                    _buildGoodForSection(goodForTags.join(', ')),

                  // Comment photos rendered with aligned Row (left, center, right)
                  if (commentPhotos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: commentPhotos.asMap().entries.map((entry) {
                          final int index = entry.key;
                          final String path = entry.value;
                          // Determine alignment: 0=left, 1=center, 2=right
                          final Alignment align = index == 0
                              ? Alignment.centerLeft
                              : (index == 1 ? Alignment.center : Alignment.centerRight);
                          final String p = path;
                          bool exists = false;
                          try {
                            exists = File(p).existsSync();
                          } catch (_) {
                            exists = false;
                          }

                          Widget photoWidget;
                          if (exists) {
                            photoWidget = GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenImage(path: p),
                                  ),
                                );
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: 72,
                                  minHeight: 72,
                                  maxWidth: 84,
                                  maxHeight: 84,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                    File(p),
                                    width: 84,
                                    height: 84,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(
                                      Icons.broken_image,
                                      color: AppColors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          } else {
                            photoWidget = ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 72,
                                minHeight: 72,
                                maxWidth: 84,
                                maxHeight: 84,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.greyShade300,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.greyShade400),
                                ),
                                child: const Center(
                                  child: Icon(Icons.close, color: AppColors.white70),
                                ),
                              ),
                            );
                          }

                          return Align(
                            alignment: align,
                            child: photoWidget,
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

                  if (addressValue != null && addressValue.isNotEmpty)
                    _buildAddressSection(addressValue),
                  if (phoneValue != null && phoneValue.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text('${AppStr.phoneLabel}:', style: AppFonts.bold),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(phoneValue, style: AppFonts.standard),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: AppStr.copiedToClipboard,
                            onPressed: () => _copyToClipboard(phoneValue),
                          ),
                        ],
                      ),
                    ),

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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  goToList();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.grey,
                                  foregroundColor: AppColors.white,
                                  textStyle: AppFonts.bold.copyWith(
                                    fontSize: 14,
                                    letterSpacing: 0.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(
                                  AppStr.list,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  goToEditFlow();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.orange,
                                  foregroundColor: AppColors.white,
                                  textStyle: AppFonts.bold.copyWith(
                                    fontSize: 14,
                                    letterSpacing: 0.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(
                                  AppStr.change,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                              ),
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (isPending) {
                                    await saveReview();
                                  } else {
                                    await updateReview();
                                    _showSaveConfirmation();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.btnSave,
                                  foregroundColor: AppColors.btnText,
                                  textStyle: AppFonts.bold.copyWith(
                                    fontSize: 14,
                                    letterSpacing: 0.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(
                                  AppStr.save,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                              ),
                              child: ElevatedButton(
                                onPressed: () async {
                                  await deleteReview();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.btnDelete,
                                  foregroundColor: AppColors.btnText,
                                  textStyle: AppFonts.bold.copyWith(
                                    fontSize: 14,
                                    letterSpacing: 0.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: Text(
                                  AppStr.delete,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.bold,
                                ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  // exclude_back: simply return to previous screen without excluding
                                  Navigator.pop(context, null);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.btnBack,
                                  foregroundColor: AppColors.btnText,
                                  textStyle: AppFonts.bold.copyWith(
                                    fontSize: 14,
                                    letterSpacing: 0.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: const Text(
                                  AppStr.backButtonLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  // Signal to caller that the current review should be excluded
                                  Navigator.pop(context, true);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.red,
                                  foregroundColor: AppColors.white,
                                  textStyle: AppFonts.bold.copyWith(
                                    fontSize: 14,
                                    letterSpacing: 0.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: const Text(
                                  AppStr.exclude,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (widget.mode == 'requested')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Center(
                        child: SizedBox(
                          width: 200,
                          child: ElevatedButton(
                            onPressed: () {
                              // Return to requested reviews list
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.btnBack,
                              foregroundColor: AppColors.btnText,
                              textStyle: AppFonts.bold.copyWith(
                                fontSize: 14,
                                letterSpacing: 0.4,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              minimumSize: const Size(0, 44),
                            ),
                            child: const Text(
                              AppStr.backButtonLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_isSaving)
              Container(
                color: const Color(0xFF000000).withAlpha(77),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

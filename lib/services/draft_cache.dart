// services/draft_cache.dart
//
// Persists a review draft to SharedPreferences so that an in-progress edit
// can survive app crashes or kills. Only one draft is held at a time.
//
// The reviewMap stored here is in "formatted/DB" format (keys: restname,
// rfood, etc.) — the same format passed into PreviewScreen. This matches
// the output of formatReviewData() and can be passed directly into a
// ReviewContext for PreviewScreen.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/restiview_constants.dart';

class DraftCache {
  static const String _keyDraft = 'restiview_review_draft';

  /// Save a draft. [reviewKey] is null for a brand-new unsaved review.
  /// [formattedMap] is in DB/formatted format (restname, rfood, …).
  static Future<void> save(
    String? reviewKey,
    Map<String, dynamic> formattedMap,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Strip any non-JSON-serialisable values (e.g. ServerValue.timestamp)
      final clean = _sanitise(formattedMap);
      final payload = <String, dynamic>{
        'reviewKey': reviewKey,
        'reviewMap': clean,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_keyDraft, jsonEncode(payload));
    } catch (e) {
      appLog('DraftCache.save error: $e');
    }
  }

  /// Load the saved draft. Returns null if none exists or it cannot be parsed.
  static Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyDraft);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      appLog('DraftCache.load error: $e');
      return null;
    }
  }

  /// Delete the saved draft (call after a successful Firebase write).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDraft);
    } catch (e) {
      appLog('DraftCache.clear error: $e');
    }
  }

  /// Returns true if a draft is currently stored.
  static Future<bool> exists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_keyDraft);
    } catch (_) {
      return false;
    }
  }

  // Remove any values that jsonEncode cannot handle (e.g. ServerValue).
  static Map<String, dynamic> _sanitise(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final v = entry.value;
      if (v == null || v is String || v is num || v is bool) {
        result[entry.key] = v;
      } else if (v is List) {
        result[entry.key] = _sanitiseList(v);
      } else if (v is Map) {
        result[entry.key] = _sanitise(Map<String, dynamic>.from(v));
      }
      // Skip anything else (ServerValue, etc.)
    }
    return result;
  }

  static List<dynamic> _sanitiseList(List<dynamic> list) {
    return list.map((item) {
      if (item == null || item is String || item is num || item is bool) {
        return item;
      } else if (item is List) {
        return _sanitiseList(item);
      } else if (item is Map) {
        return _sanitise(Map<String, dynamic>.from(item));
      }
      return null;
    }).toList();
  }
}

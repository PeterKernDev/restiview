// sub_preview_screen/review_transform.dart
//
import 'package:intl/intl.dart';
import '/constants/restiview_constants.dart';

Map<String, dynamic> reverseFormatReviewData(Map<String, dynamic> formatted) {
  final Map<String, dynamic> result = {
    'restaurantName': formatted['restname'],
    'country': formatted['restcountry'],
    'city': formatted['restcity'],
    'cuisine': formatted['restcuisine'],
    'foodRating': int.tryParse(formatted['rfood']?.toString() ?? '0') ?? 0,
    'serviceRating': int.tryParse(formatted['rservice']?.toString() ?? '0') ?? 0,
    'ambianceRating': int.tryParse(formatted['rambiance']?.toString() ?? '0') ?? 0,
    'drinksRating': int.tryParse(formatted['rdrinks']?.toString() ?? '0') ?? 0,
    'vfmsRating': int.tryParse(formatted['rvfm']?.toString() ?? '0') ?? 0,
    'michelinStars': int.tryParse(formatted['rmichlin']?.toString() ?? '0') ?? 0,
    'numberOfDiners': (formatted['cpersons'] == '' || formatted['cpersons'] == null)
        ? ''
        : int.tryParse(formatted['cpersons'].toString()) ?? '',
    'cost': (formatted['cost'] == null || formatted['cost'].toString().trim().isEmpty)
        ? ''
        : double.tryParse(formatted['cost'].toString()) ?? '',
    'currency': formatted['currency'],
    'occasion': formatted['coccasion'],
    'comments': formatted['ccomments'],
    'dateOfReview': _parseFormattedDate(formatted['reviewdate']),
    'goodForTags': _extractTags(formatted['goodfor']),
    'photoPath': formatted['photoPath'],
    'restaddress': formatted['restaddress'],
    'restphone': formatted['restphone'],
  };

  // Include up to 3 comment photo paths
  for (int i = 0; i < 3; i++) {
    final key = 'photoPath$i';
    if (formatted[key] != null) {
      result[key] = formatted[key];
    }
  }

  // Include detail categories if present
  for (final key in [
    'details_cocktails',
    'details_starters',
    'details_wine',
    'details_main',
    'details_dessert',
    'details_otherdrinks',
  ]) {
    if (formatted[key] != null) {
      result[key] = formatted[key];
    }
  }

  return result;
}

String _parseFormattedDate(dynamic dateStr) {
  try {
    if (dateStr == null) return DateTime.now().toIso8601String();

    // If stored as a List (defensive), take first element
    if (dateStr is List && dateStr.isNotEmpty) {
      dateStr = dateStr.first;
    }

    // If the value is already a DateTime serialized (ISO), try parsing
    final s = dateStr.toString();

    // Try dd/MM/yyyy first
    try {
      final parsed = DateFormat('dd/MM/yyyy').parse(s);
      return parsed.toIso8601String();
    } catch (_) {
      // Try ISO parse
      try {
        return DateTime.parse(s).toIso8601String();
      } catch (_) {
        // As a last resort, return now
        return DateTime.now().toIso8601String();
      }
    }
  } catch (_) {
    return DateTime.now().toIso8601String();
  }
}

List<String> _extractTags(String? binary) {
  if (binary == null || binary.length != goodForTags.length) return [];

  final selected = <String>[];
  for (int i = 0; i < goodForTags.length; i++) {
    if (binary[i] == 'Y') selected.add(goodForTags[i]);
  }
  return selected;
}

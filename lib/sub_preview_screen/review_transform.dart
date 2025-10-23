// review_transform.dart
//
// Converts a formatted Firebase review record back into the editable template.
// Used when loading saved reviews into the editing flow.
// Ensures all fields are restored, including ratings, tags, and photo path.
import 'package:intl/intl.dart';
import '/constants/restiview_constants.dart';

/// Converts a formatted Firebase review record back into the editable template
Map<String, dynamic> reverseFormatReviewData(Map<String, dynamic> formatted) {
  return {
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
}

/// Parses a formatted date string like '17/09/2025' into ISO format
String _parseFormattedDate(String? dateStr) {
  try {
    final parsed = DateFormat('dd/MM/yyyy').parse(dateStr ?? '');
    return parsed.toIso8601String();
  } catch (_) {
    return DateTime.now().toIso8601String();
  }
}

/// Converts binary tag string like 'YNYNNY' into a list of selected tags
List<String> _extractTags(String? binary) {
  if (binary == null || binary.length != goodForTags.length) return [];

  final selected = <String>[];
  for (int i = 0; i < goodForTags.length; i++) {
    if (binary[i] == 'Y') selected.add(goodForTags[i]);
  }
  return selected;
}
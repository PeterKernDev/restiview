// lib/sub_friends_screen/friend_row.dart
//
// Presentation widget for a friend entry in the Friends list.
// - Two-line layout:
//   - Top left: username
//   - Top right: comment (if present and relationship not accepted OR when RV-ASKED / RV-WANTS)
//   - Bottom left: email
//   - Bottom right: status token + sharedReviewsCount
// - For RV-ASKED / RV-WANTS append rvCount in parentheses when available: "RV-WANTS (10)"
// - Status shown as canonical short tokens: FR-ASKED, FR-WANTED, FRIEND, DECLINED, RV-WANTS, RV-ASKED, UNKNOWN

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../constants/colors.dart';
import '../constants/fonts.dart';
import '../constants/strings.dart';
import '../services/review_counter.dart';
import 'friend_entry.dart';

class FriendRow extends StatelessWidget {
  const FriendRow({
    super.key,
    required this.entry,
    this.selected = false,
    this.onTap,
  });

  final FriendEntry entry;
  final bool selected;
  final VoidCallback? onTap;

  String _displayName() {
    if (entry.username.isNotEmpty) {
      return entry.username;
    }
    if (entry.email.isNotEmpty) {
      return entry.email;
    }
    return entry.uid;
  }

  // Build the base status token (no count)
  String _baseStatusToken() {
    switch (entry.status) {
      case FriendStatus.accepted:
        return AppStr.friendLabel;
      case FriendStatus.provided:
        return AppStr.rvProvidedLabel;
      case FriendStatus.requested:
        return AppStr.frWantedLabel;
      case FriendStatus.recipientPending:
        return AppStr.frAskedLabel;
      case FriendStatus.rvWants:
        return AppStr.rvWantsLabel;
      case FriendStatus.rvAsked:
        return AppStr.rvAskedLabel;
      case FriendStatus.declined:
        return AppStr.declinedLabel;
      default:
        return AppStr.unknownLabel;
    }
  }

  // Fire-and-forget resolver: when rvCount == -1, compute the count and write it back.
  Future<void> _resolveRvCountForEntry() async {
    try {
      final int? cur = entry.review?.rvCount ?? entry.rvCount;
      if (cur == null || cur != -1) {
        return;
      }

      // Read filters from nested review if present
      final Map<String, String>? filters = entry.review?.filters;
      String? country = (filters != null && filters.containsKey('country')) ? filters['country'] : null;
      String? cuisine = (filters != null && filters.containsKey('cuisine')) ? filters['cuisine'] : null;
      String? city = (filters != null && filters.containsKey('city')) ? filters['city'] : null;

      if (country == null || country.trim().isEmpty) {
        // nothing to count
        return;
      }

      final String myUidNow = FirebaseAuth.instance.currentUser?.uid ?? '';
      final int found = await countMatchingReviews(ownerUid: myUidNow, country: country, cuisine: cuisine, city: city);

      if (found < 0) {
        return;
      }

      final String nowIso = DateTime.now().toUtc().toIso8601String();
      final String reviewPath = 'users/$myUidNow/friends/${entry.uid}/review';
      final Map<String, dynamic> reviewPatch = <String, dynamic>{
        '$reviewPath/rvCount': found,
        '$reviewPath/updatedAt': nowIso,
      };

      try {
        await FirebaseDatabase.instance.ref().update(reviewPatch);
      } catch (e) {
        // Silently handle write failure
      }

      // Update local model (best-effort)
      entry.review ??= ReviewData(filters: <String, String>{});
      entry.review!.rvCount = found;
      entry.review!.updatedAt = nowIso;
      entry.rvCount = found;
      entry.rvCountLastCheckedAt = nowIso;
    } catch (e) {
      // Silently handle resolution failure
    }
  }

  // Compose final token; append rvCount/exCount for RV states when available and non-negative.
  // For RV-PROVIDED (statusCode=5), append providedRqCount.
  // If rvCount == -1, schedule resolution and return base token placeholder.
  String _statusTokenWithCounts() {
    final String base = _baseStatusToken();
    
    // For RV-PROVIDED status, show count from metadata
    if (entry.status == FriendStatus.provided) {
      final int? providedCount = entry.providedRqCount;
      if (providedCount != null && providedCount > 0) {
        return '$base ($providedCount)';
      }
      return base;
    }
    
    final int? rvCount = entry.review?.rvCount ?? entry.rvCount;
    final int exCount = entry.review?.exCount ?? 0;

    if (entry.status == FriendStatus.rvWants || entry.status == FriendStatus.rvAsked) {
      if (rvCount == null) {
        return base;
      }

      if (rvCount < 0) {
        // fire-and-forget resolution (do not await)
        _resolveRvCountForEntry();
        return base;
      }

      // rvCount >= 0
      if (exCount > 0) {
        final int visible = (rvCount - exCount).clamp(0, rvCount);
        return '$base ($visible/$rvCount)';
      } else {
        return '$base ($rvCount)';
      }
    }

    return base;
  }

  Color _statusColor() {
    switch (entry.status) {
      case FriendStatus.accepted:
        return AppColors.darkGreen;
      case FriendStatus.provided:
        return AppColors.blueAccent; // Use same color as review requests
      case FriendStatus.requested:
      case FriendStatus.recipientPending:
        return Colors.orange;
      case FriendStatus.rvWants:
      case FriendStatus.rvAsked:
        return AppColors.blueAccent;
      case FriendStatus.declined:
        return AppColors.red;
      default:
        return AppColors.mutedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = _displayName();
    final String statusToken = _statusTokenWithCounts();
    final Color statusColor = _statusColor();

    // Show comment when:
    //  - there is a non-empty comment, AND
    //  - the relationship is not accepted (we hide friend-comments after accept),
    //    OR the relationship is a review request state (RV-ASKED / RV-WANTS).
    // For RV-PROVIDED status, show the provider message instead.
    String? comment;
    if (entry.status == FriendStatus.provided) {
      // Show provider message for RV-PROVIDED
      comment = (entry.providedMessageShort != null && entry.providedMessageShort!.trim().isNotEmpty) 
          ? entry.providedMessageShort!.trim() 
          : null;
    } else {
      final String? rawComment = (entry.comment != null && entry.comment!.trim().isNotEmpty) ? entry.comment!.trim() : null;
      final bool showReviewComment = (entry.status == FriendStatus.rvAsked || entry.status == FriendStatus.rvWants);
      comment = (rawComment != null && (entry.status != FriendStatus.accepted || showReviewComment)) ? rawComment : null;
    }

    const int bgAlpha = 31;
    const int borderAlpha = 51;

    return Container(
      color: selected ? AppColors.selectedRow : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Top row: name (left) and optional comment (right)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    name,
                    style: AppFonts.bold,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (comment != null)
                  Flexible(
                    child: Text(
                      comment,
                      style: AppFonts.smallHint.copyWith(color: AppColors.mutedText),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Bottom row: email (left) and status badge + shared count (right)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    entry.email,
                    style: AppFonts.smallHint.copyWith(color: AppColors.mutedText),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(bgAlpha),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withAlpha(borderAlpha)),
                      ),
                      child: Text(statusToken, style: AppFonts.small.copyWith(color: statusColor)),
                    ),
                    const SizedBox(height: 6),
                    if (entry.sharedReviewsCount > 0)
                      Text('+${entry.sharedReviewsCount}', style: AppFonts.smallHint.copyWith(color: AppColors.mutedText)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

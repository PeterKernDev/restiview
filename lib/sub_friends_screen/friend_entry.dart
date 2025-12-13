// lib/sub_friends_screen/friend_entry.dart
// Data model for a friend entry as read from users/<me>/friends.
// - Contains canonical fields used by FriendsScreen, FriendRow, and actions.
// - Includes nested ReviewData for review-request details.

class ReviewData {
  ReviewData({
    required this.filters,
    this.comment,
    this.rvCount,
    this.exCount,
    this.exKeys,
    this.createdAt,
    this.updatedAt,
  });

  final Map<String, String> filters;
  String? comment;
  int? rvCount;
  int? exCount;
  Map<String, bool>? exKeys;
  String? createdAt;
  String? updatedAt;
}

enum FriendStatus {
  unknown,
  accepted,
  requested,
  recipientPending,
  rvWants,
  rvAsked,
  provided,
  declined,
}

class FriendEntry {
  FriendEntry({
    required this.uid,
    required this.email,
    required this.username,
    required this.fsc,
    this.sharedReviewsCount = 0,
    this.comment,
    this.mailboxReqId,
    this.mailboxNormalized,
    this.accepted,
    this.pendingDeleteBy,
    this.rvCount,
    this.rvCountLastCheckedAt,
    this.review,
    this.providedRequestId,
    this.providedRqCount,
    this.providedMessageShort,
    this.providedAt,
  });

  String uid;
  String email;
  String username;
  int fsc;
  int sharedReviewsCount;
  String? comment;
  String? mailboxReqId;
  String? mailboxNormalized;
  bool? accepted;
  String? pendingDeleteBy;

  // Convenience top-level rvCount maintained for legacy consumers
  int? rvCount;
  String? rvCountLastCheckedAt;

  // Nested review request details (nullable)
  ReviewData? review;

  // Provider metadata when this user has performed a provide operation
  String? providedRequestId;
  int? providedRqCount;
  String? providedMessageShort;
  String? providedAt;

  FriendStatus get status {
    switch (fsc) {
      case 0:
        return FriendStatus.recipientPending; // requester stub is 0 -> FR-ASKED
      case 1:
        return FriendStatus.accepted;
      case 2:
        return FriendStatus.requested; // recipient stub is 2 -> FR-WANTED
      case 3:
        return FriendStatus.rvWants;
      case 4:
        return FriendStatus.rvAsked;
      case 5:
        return FriendStatus.provided;
      case 8:
        return FriendStatus.declined;
      default:
        return FriendStatus.unknown;
    }
  }

  bool get isActionableByMe {
    // The current user can act when they are the recipient of a friend request (2)
    // or when they have an RV-WANTS/ASKED entry to resolve (3 or 4)
    // or when they need to accept provided reviews (5).
    return (fsc == 2 || fsc == 3 || fsc == 4 || fsc == 5);
  }

  static int mapStringStatusToFsc(String s) {
    final String v = s.trim().toLowerCase();
    if (v == 'friend' || v == 'accepted' || v == '1' || v == 'fr') {
      return 1;
    }
    if (v == 'fr-asked' || v == '0' || v.contains('asked') || v.contains('ask')) {
      return 0;
    }
    if (v == 'fr-wanted' || v == '2' || v.contains('want') || v.contains('wanted') || v.contains('requested')) {
      return 2;
    }
    if (v == 'rv-wants' || v == '3' || v.contains('rv-wants') || v.contains('rv-want')) {
      return 3;
    }
    if (v == 'rv-asked' || v == '4' || v.contains('rv-asked') || v.contains('rv-ask')) {
      return 4;
    }
    if (v == 'provided' || v == '5') {
      return 5;
    }
    if (v == 'declined' || v == '8') {
      return 8;
    }
    // Legacy or unknown values map to unknown
    return 9;
  }

  static bool looksLikeUid(String s) {
    return s.isNotEmpty && s.length >= 6 && !s.contains('@');
  }
}

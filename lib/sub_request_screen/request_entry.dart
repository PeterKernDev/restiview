// lib/sub_request_screen/request_entry.dart
// Data model for review request (Stage 2)

import 'package:flutter/foundation.dart';

enum RequestStatus {
  pending,
  accepted,
  rejected,
  timedOut,
}

String requestStatusToString(RequestStatus s) {
  switch (s) {
    case RequestStatus.accepted:
      return 'accepted';
    case RequestStatus.rejected:
      return 'rejected';
    case RequestStatus.timedOut:
      return 'timedOut';
    case RequestStatus.pending:
      return 'pending';
  }
}

RequestStatus requestStatusFromString(String? s) {
  switch (s) {
    case 'accepted':
      return RequestStatus.accepted;
    case 'rejected':
      return RequestStatus.rejected;
    case 'timedOut':
      return RequestStatus.timedOut;
    case 'pending':
    default:
      return RequestStatus.pending;
  }
}

@immutable
class RequestEntry {
  final String id;
  final String requesterId;
  final String requesterEmail;
  final String recipientId;
  final String recipientEmail;
  final String country;
  final String? cuisine;
  final String? city;
  final String? message;
  final String? sharedReviewId;
  final RequestStatus status;
  final int createdAt;

  // Non-const constructor so we can default createdAt to now().
  RequestEntry({
    required this.id,
    required this.requesterId,
    required this.requesterEmail,
    required this.recipientId,
    required this.recipientEmail,
    required this.country,
    this.cuisine,
    this.city,
    this.message,
    this.sharedReviewId,
    this.status = RequestStatus.pending,
    int? createdAt,
  }) : createdAt = createdAt ?? _now();

  static int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  RequestEntry copyWith({
    String? id,
    String? requesterId,
    String? requesterEmail,
    String? recipientId,
    String? recipientEmail,
    String? country,
    String? cuisine,
    String? city,
    String? message,
    String? sharedReviewId,
    RequestStatus? status,
    int? createdAt,
  }) {
    return RequestEntry(
      id: id ?? this.id,
      requesterId: requesterId ?? this.requesterId,
      requesterEmail: requesterEmail ?? this.requesterEmail,
      recipientId: recipientId ?? this.recipientId,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      country: country ?? this.country,
      cuisine: cuisine ?? this.cuisine,
      city: city ?? this.city,
      message: message ?? this.message,
      sharedReviewId: sharedReviewId ?? this.sharedReviewId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'id': id,
      'requesterId': requesterId,
      'requesterEmail': requesterEmail,
      'recipientId': recipientId,
      'recipientEmail': recipientEmail,
      'country': country,
      'status': requestStatusToString(status),
      'createdAt': createdAt,
    };
    if (cuisine != null) m['cuisine'] = cuisine;
    if (city != null) m['city'] = city;
    if (message != null) m['message'] = message;
    if (sharedReviewId != null) m['sharedReviewId'] = sharedReviewId;
    return m;
  }

  factory RequestEntry.fromMap(Map<dynamic, dynamic> m) {
    return RequestEntry(
      id: (m['id'] ?? '') as String,
      requesterId: (m['requesterId'] ?? '') as String,
      requesterEmail: (m['requesterEmail'] ?? '') as String,
      recipientId: (m['recipientId'] ?? '') as String,
      recipientEmail: (m['recipientEmail'] ?? '') as String,
      country: (m['country'] ?? '') as String,
      cuisine: m['cuisine'] as String?,
      city: m['city'] as String?,
      message: m['message'] as String?,
      sharedReviewId: m['sharedReviewId'] as String?,
      status: requestStatusFromString(m['status'] as String?),
      createdAt: (m['createdAt'] is int) ? (m['createdAt'] as int) : int.tryParse('${m['createdAt']}') ?? _now(),
    );
  }

  /// Basic client-side validation. Returns empty list when valid.
  List<String> validate() {
    final errors = <String>[];
    if (requesterId.trim().isEmpty) errors.add('requesterId required');
    if (recipientId.trim().isEmpty) errors.add('recipientId required');
    if (requesterEmail.trim().isEmpty) errors.add('requesterEmail required');
    if (recipientEmail.trim().isEmpty) errors.add('recipientEmail required');
    if (country.trim().isEmpty) errors.add('country required');
    if (message != null && message!.length > 500) errors.add('message too long (max 500)');
    return errors;
  }
}

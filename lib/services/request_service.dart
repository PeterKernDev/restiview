// lib/services/request_service.dart
// Service helpers for building and sending review request payloads (Stage 2).
// - Builds atomic RTDB update maps and performs the update.
// - Keeps errors wrapped in RequestServiceException for callers.

import 'package:firebase_database/firebase_database.dart';
import '../sub_request_screen/request_entry.dart';

class RequestService {
  final DatabaseReference _rootRef;

  RequestService({DatabaseReference? root}) : _rootRef = root ?? FirebaseDatabase.instance.ref();

  /// Build the canonical payload (same shape written under /reviewRequests/{id}).
  Map<String, dynamic> buildRequestPayload(RequestEntry r) {
    return r.toMap();
  }

  /// Build an atomic update map that writes:
  /// - /reviewRequests/{id} => payload
  /// - /users/{recipientId}/inboxRequests/{id} => small mirror
  /// - /users/{requesterId}/outboxRequests/{id} => small mirror
  Map<String, dynamic> buildRequestUpdateMap(RequestEntry r) {
    final payload = buildRequestPayload(r);
    final updates = <String, dynamic>{};
    updates['/reviewRequests/${r.id}'] = payload;
    updates['/users/${r.recipientId}/inboxRequests/${r.id}'] = {
      'requesterId': r.requesterId,
      'requesterEmail': r.requesterEmail,
      'createdAt': r.createdAt,
      'status': requestStatusToString(r.status),
    };
    updates['/users/${r.requesterId}/outboxRequests/${r.id}'] = {
      'recipientId': r.recipientId,
      'recipientEmail': r.recipientEmail,
      'createdAt': r.createdAt,
      'status': requestStatusToString(r.status),
    };
    return updates;
  }

  /// Validate the entry client-side. Returns empty list when valid.
  List<String> validateRequest(RequestEntry r) {
    return r.validate();
  }

  /// Send the request using an atomic RTDB update.
  /// Returns the requestId on success.
  Future<String> sendRequest(RequestEntry r) async {
    final errors = validateRequest(r);
    if (errors.isNotEmpty) {
      throw RequestServiceException('Validation failed: ${errors.join(', ')}');
    }

    // If id is empty, generate a push key
    final id = r.id.isNotEmpty ? r.id : _rootRef.child('reviewRequests').push().key;
    if (id == null || id.isEmpty) {
      throw RequestServiceException('Failed to generate request id');
    }

    final entryWithId = r.copyWith(id: id);
    final updates = buildRequestUpdateMap(entryWithId);

    try {
      await _rootRef.update(updates);
      return id;
    } catch (e) {
      // firebase_database throws various exception types; catch all and wrap
      throw RequestServiceException('RTDB update failed: ${e.toString()}');
    }
  }

  /// Optional helper to read a request by id.
  Future<RequestEntry?> fetchRequestById(String id) async {
    final snap = await _rootRef.child('reviewRequests/$id').get();
    if (snap.exists && snap.value is Map) {
      final m = Map<dynamic, dynamic>.from(snap.value as Map);
      return RequestEntry.fromMap(m);
    }
    return null;
  }
}

class RequestServiceException implements Exception {
  final String message;
  RequestServiceException(this.message);
  @override
  String toString() {
    return 'RequestServiceException: $message';
  }
}

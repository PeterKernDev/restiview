# Request Feature — README

Purpose
- Developer reference for Stage 2 Request feature: data model, service helpers, presentational subcomponents, and the request screen UI.
- Place this file at: lib/sub_request_screen/README.md (alongside request_entry.dart and the subcomponents).

Overview
- Adds a Review/Visit (RV) request flow so one user can send a request to another.
- Client builds atomic RTDB update maps; UI performs guards, optimistic UX, and idempotency checks.
- All user-visible strings live in lib/constants/strings.dart (class AppStr).

File map (exact paths)
- lib/request_screen.dart  
  Full-screen UI that composes the subcomponents, validates input, checks recipient mapping, enforces availability and friendship guards, builds the atomic update map, and sends the request. Uses mounted guards and braced control blocks.

- lib/sub_request_screen/request_entry.dart  
  Data model: RequestEntry, RequestStatus enum, toMap/fromMap, copyWith, and client-side validate().

- lib/services/request_service.dart  
  RequestService helper (buildRequestPayload, buildRequestUpdateMap, validateRequest, sendRequest, fetchRequestById). Wraps RTDB writes and throws RequestServiceException on failure.

- lib/sub_request_screen/recipient_picker.dart  
  Presentational recipient input widget; emits recipient id/email via callback. Pure UI (no Firebase).

- lib/sub_request_screen/location_inputs.dart  
  Presentational country/cuisine/city inputs; emits structured changes via callback. Pure UI.

- lib/sub_request_screen/request_preview.dart  
  Presentational preview card that displays a RequestEntry summary before sending. Pure UI.

- lib/constants/strings.dart  
  Centralized AppStr class with all user-visible strings used by the request feature.

RTDB structure and atomic write plan
- /reviewRequests/{requestId} (optional canonical record)  
  Canonical request record shape: { requesterId, requesterEmail, recipientId, recipientEmail, country?, cuisine?, city?, message?, sharedReviewId?, status, createdAt, clientRequestId }.

- /users_by_email/{normalized}/requests/{clientRequestId}  
  Mailbox-style per-email request storage used for idempotency and recipient discovery.

- /users/{requesterId}/friends/{recipientId} and /users/{recipientId}/friends/{requesterId}  
  Local friend mirrors updated in the atomic update to reflect pending/outgoing requests.

Key flows and responsibilities
- Recipient check (lib/request_screen.dart)  
  - Normalize email, look up users_by_email/{normalized}, prevent self-requests, detect hard-declines and existing friendship, mark the form validated and show preview.

- Send flow (lib/request_screen.dart)  
  - Re-resolve mapping, guard again for self/add/declined/already-friends, build mailbox payload + friend-mirror updates, perform atomic update with retry/backoff, and run idempotency check on failure.

- Service utilities (lib/services/request_service.dart)  
  - Provide canonical payload builder and atomic update map creator for reuse in other screens or tests.

Validation rules (client-side)
- Recipient (email) required and must map to a uid in users_by_email.  
- Prevent sending to self.  
- Prevent requests to users marked unavailable (statusCode 8 or 9) in either direction.  
- Prevent sending if already friends (statusCode 1).  
- Message/comment length limit enforced (max 500).  
- UI disables Send until recipient check passes.

Testing checklist
- Unit tests for RequestEntry.validate and RequestService.buildRequestUpdateMap (recommended).  
- Manual tests: mailbox entry created, both users' mirrors updated, duplicate send idempotency, self-send rejection, already-friends rejection, network failure handling, mounted guards behavior.

Dev notes and conventions followed
- All user-visible strings are centralized in lib/constants/strings.dart (AppStr).  
- Use controllers when needed; otherwise use initialValue (do not use deprecated value).  
- Always use braced blocks for control flow and expand short callbacks when they touch context/state. Guard async gaps with mounted checks before using context, ScaffoldMessenger, Navigator, or setState.  
- Avoid deprecated APIs (MaterialStateProperty; addScopedWillPopCallback/removeScopedWillPopCallback).  
- Every .dart file includes a top-of-file comment with filename and a short description.  
- Release build command: flutter build appbundle --release.

Next recommended tasks
1. Add unit tests for RequestService and RequestEntry.  
2. Optionally consolidate atomic update construction inside RequestService.sendRequest for centralization.  
3. Integrate presentational RecipientPicker and LocationInputs into lib/request_screen.dart for a form-driven UX (if desired).  
4. Add notification writes (e.g., /notifications/{userId}) on successful requests if in-scope.

Contact
- If you want a trimmed quick-reference cheat-sheet or a diagram of the RTDB atomic update paths, tell me which format you prefer and I will add it here.

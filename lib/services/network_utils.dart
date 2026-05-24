// services/network_utils.dart
// Lightweight connectivity check using dart:io DNS lookup.
// Does not require any additional packages.

import 'dart:io';

/// Returns true if a DNS lookup for google.com succeeds within 5 seconds.
/// This is a fast, reliable way to confirm internet access without
/// adding a dependency on connectivity_plus.
Future<bool> hasInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

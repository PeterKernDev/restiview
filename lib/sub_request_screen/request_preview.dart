// lib/sub_request_screen/request_preview.dart
// Small presentational preview of a RequestEntry before sending.
// - Pure UI: shows requester/recipient/country/cuisine/city/message summary.

import 'package:flutter/material.dart';
import '../sub_request_screen/request_entry.dart';
import '../constants/strings.dart';

class RequestPreview extends StatelessWidget {
  final RequestEntry entry;

  const RequestPreview({
    super.key,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(String label, String? value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 7,
              child: Text(
                value ?? AppStr.notProvided,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(AppStr.previewTitle, style: theme.textTheme.titleMedium),
            const Divider(),
            row(AppStr.requesterLabel, entry.requesterEmail),
            row(AppStr.recipientLabelShort, entry.recipientEmail),
            row(AppStr.countryLabel, entry.country),
            row(AppStr.cuisineLabel, entry.cuisine ?? AppStr.notProvided),
            row(AppStr.cityLabel, entry.city ?? AppStr.notProvided),
            row(AppStr.messageLabel, entry.message ?? AppStr.notProvided),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${AppStr.createdAtLabel}: ${DateTime.fromMillisecondsSinceEpoch(entry.createdAt).toLocal()}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

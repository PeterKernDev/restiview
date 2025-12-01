// lib/sub_request_screen/recipient_picker.dart
// Simple presentational recipient picker used by the request screen.
// - Pure UI widget that accepts an initial recipient (id/email) and reports changes via callbacks.
// - Does not access Firebase or app services.

import 'package:flutter/material.dart';
import '../constants/strings.dart';

typedef RecipientChanged = void Function(String recipientId, String recipientEmail);

class RecipientPicker extends StatefulWidget {
  final String? initialRecipientId;
  final String? initialRecipientEmail;
  final RecipientChanged onChanged;

  const RecipientPicker({
    super.key,
    required this.onChanged,
    this.initialRecipientId,
    this.initialRecipientEmail,
  });

  @override
  State<RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends State<RecipientPicker> {
  late final TextEditingController _emailController;
  String? _recipientId;

  @override
  void initState() {
    super.initState();
    _recipientId = widget.initialRecipientId;
    _emailController = TextEditingController(text: widget.initialRecipientEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _onEmailChanged(String email) {
    widget.onChanged(_recipientId ?? '', email.trim());
  }

  void setRecipient({required String id, required String email}) {
    setState(() {
      _recipientId = id;
      _emailController.text = email;
    });
    widget.onChanged(id, email);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(AppStr.recipientLabel, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('recipientEmailField'),
          controller: _emailController,
          decoration: InputDecoration(
            hintText: AppStr.recipientHint,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
          onChanged: (value) {
            _onEmailChanged(value);
          },
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return AppStr.recipientRequired;
            } else {
              return null;
            }
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _recipientId != null && _recipientId!.isNotEmpty ? '${AppStr.selectedIdPrefix} $_recipientId' : AppStr.noRecipientSelected,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: AppStr.clearRecipientTooltip,
              icon: const Icon(Icons.clear),
              onPressed: () {
                setRecipient(id: '', email: '');
              },
            ),
          ],
        ),
      ],
    );
  }
}

// lib/widgets/action_row.dart
// Equal-width action row wrapper used to place 1-4 buttons with consistent spacing.
// Falls back to a Wrap for more than 4 children to avoid layout overflow on very small screens.

import 'package:flutter/material.dart';

class ActionRow extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final bool compact; // reduces vertical padding when true

  const ActionRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.spacing = 6.0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // If 1-4 children: give each equal width using Expanded.
    if (children.isNotEmpty && children.length <= 4) {
      final vPad = compact ? 4.0 : 8.0;
      final widgets = children
          .map((w) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing, vertical: vPad),
                  child: w,
                ),
              ))
          .toList();

      return Padding(
        padding: padding,
        child: Row(
          children: widgets,
        ),
      );
    }

    // Fallback: use Wrap so items flow to the next line on narrow screens.
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        alignment: WrapAlignment.spaceBetween,
        children: children
            .map((w) => ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 80),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: compact ? 4.0 : 8.0),
                    child: w,
                  ),
                ))
            .toList(),
      ),
    );
  }
}

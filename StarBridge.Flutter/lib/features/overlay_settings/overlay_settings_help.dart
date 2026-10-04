import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// The same secondary explanation hierarchy for both overlay settings pages.
class OverlaySettingsHelp extends StatelessWidget {
  const OverlaySettingsHelp(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.tokens.colors.textSecondary),
  );
}

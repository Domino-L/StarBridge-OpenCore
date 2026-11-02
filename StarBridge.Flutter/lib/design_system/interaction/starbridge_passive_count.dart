import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_interaction_theme.dart';

/// Read-only statistics only. Null stays unknown, never a fabricated zero.
/// No value owner, input, write or throttling of active actions lives here.
class StarBridgePassiveCount extends StatelessWidget {
  const StarBridgePassiveCount({
    required this.value,
    this.style,
    this.valueKey,
    this.unknown = '—',
    super.key,
  });
  final int? value;
  final TextStyle? style;
  final Key? valueKey;
  final String unknown;

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        if (value == null ||
            InteractionScope.of(context).suite == InteractionSuite.standard) {
          return Text(
            value?.toString() ?? unknown,
            key: valueKey,
            style: style,
          );
        }
        return SuiteCounter(
          key: valueKey,
          value: value!,
          style: style,
          coalesceDataUpdates: true,
          source: InteractionSource.programmatic,
        );
      },
    ),
  );
}

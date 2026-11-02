import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_tooltip.dart';

/// The same compact classification tag in personal and organization hangars.
class ShipClassificationTag extends StatelessWidget {
  const ShipClassificationTag({
    required this.label,
    required this.color,
    super.key,
  });
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        border: Border.all(color: color.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: StarBridgeTooltip(
        message: label,
        consumeEscape: false,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// Shared grouping for the hangar's timing and monitoring controls.
final class ExecHangarSurface extends StatelessWidget {
  const ExecHangarSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        borderRadius: tokens.shape.medium,
        side: BorderSide(color: tokens.surfaces.panel.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(tokens.space.lg), child: child),
    );
  }
}

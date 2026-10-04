import 'package:flutter/material.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';

import '../../design_system/tokens/starbridge_tokens.dart';

/// Visible chrome for PopupMenuButton children; interaction remains with the
/// parent so keyboard focus, activation and menu semantics stay native.
class OverlayMenuTrigger extends StatelessWidget {
  const OverlayMenuTrigger({
    required this.label,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final foreground = enabled
        ? tokens.colors.textPrimary
        : tokens.colors.textDisabled;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Ink(
        decoration: BoxDecoration(
          color: tokens.surfaces.raised.fill,
          border: Border.all(color: tokens.surfaces.raised.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: foreground),
                ),
              ),
              const SizedBox(width: 8),
              StarBridgeIcon(
                StarBridgeIconSemantic.menuDown,
                size: 18,
                color: foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

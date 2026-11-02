import 'package:flutter/material.dart';

/// The SDK FormField projection depends on the native dropdown glyph's
/// baseline and sizing. Keep that geometry behind the design-system resolver,
/// rather than replacing it with a menu-navigation painter.
class NativeDropdownIndicatorIcon extends StatelessWidget {
  const NativeDropdownIndicatorIcon({super.key}) : _expandMore = false;

  /// Keeps the native ExpansionTile glyph without selecting assets in features.
  const NativeDropdownIndicatorIcon.expandMore({super.key})
    : _expandMore = true;

  final bool _expandMore;

  @override
  Widget build(BuildContext context) => _expandMore
      ? const Icon(Icons.expand_more)
      : const Icon(Icons.arrow_drop_down);
}

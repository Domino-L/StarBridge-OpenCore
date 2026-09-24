import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/brand/brand_lockup.dart';
import '../../../design_system/brand/brand_lockup_spec.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../shell_layout_mode.dart';

class BrandHomeButton extends StatelessWidget {
  const BrandHomeButton({
    required this.mode,
    required this.selected,
    required this.onPressed,
    required this.onKeyboardPressed,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final ShellLayoutMode mode;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onKeyboardPressed;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = AppStrings.of(context).text('navigation.home');
    final content = Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: tokens.surfaces.navigation.fill,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: tokens.density.topBarHeight,
            child: Align(
              alignment: mode == ShellLayoutMode.iconOnly
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: BrandLockup(
                scale: mode == ShellLayoutMode.iconOnly
                    ? BrandLockupScale.navigationCompact
                    : BrandLockupScale.navigationExpanded,
                showWordmark: mode != ShellLayoutMode.iconOnly,
              ),
            ),
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): onKeyboardPressed,
        const SingleActivator(LogicalKeyboardKey.space): onKeyboardPressed,
        const SingleActivator(LogicalKeyboardKey.arrowUp): onPrevious,
        const SingleActivator(LogicalKeyboardKey.arrowDown): onNext,
      },
      child: content,
    );
  }
}

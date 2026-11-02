import 'package:flutter/material.dart';

import '../../../design_system/brand/brand_lockup.dart';
import '../../../design_system/brand/brand_lockup_spec.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../../design_system/interaction/starbridge_navigation_target.dart';
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
    this.focusNode,
    super.key,
  });

  final ShellLayoutMode mode;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onKeyboardPressed;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final label = AppStrings.of(context).text('navigation.home');
    return StarBridgeNavigationTarget(
      brand: true,
      focusNode: focusNode,
      selected: selected,
      label: label,
      onPressed: onPressed,
      onKeyboardPressed: onKeyboardPressed,
      onPrevious: onPrevious,
      onNext: onNext,
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
    );
  }
}

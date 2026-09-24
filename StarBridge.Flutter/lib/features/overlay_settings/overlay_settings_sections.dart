import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/product_features.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/menu_preview_window_port.dart';
import 'menu_overlay_settings.dart';

class OverlaySettingsSections extends StatefulWidget {
  const OverlaySettingsSections({
    required this.child,
    this.menuPreview,
    super.key,
  });

  final Widget child;
  final MenuPreviewWindowPort? menuPreview;

  @override
  State<OverlaySettingsSections> createState() =>
      _OverlaySettingsSectionsState();
}

class _OverlaySettingsSectionsState extends State<OverlaySettingsSections> {
  bool _menu = false;

  @override
  Widget build(BuildContext context) {
    if (!menuOverlayEnabled) return widget.child;
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(tokens.space.md),
          child: Wrap(
            spacing: tokens.space.md,
            runSpacing: tokens.space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                selected: !_menu,
                label: Text(strings.text('overlay.sections.info')),
                onSelected: (_) => setState(() => _menu = false),
              ),
              ChoiceChip(
                key: const Key('overlay-menu-settings'),
                selected: _menu,
                label: Text(strings.text('overlay.sections.menu')),
                onSelected: (_) => setState(() => _menu = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _menu ? 1 : 0,
            children: [
              widget.child,
              MenuOverlaySettings(preview: widget.menuPreview),
            ],
          ),
        ),
      ],
    );
  }
}

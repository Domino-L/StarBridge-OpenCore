import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/product_features.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/menu_preview_window_port.dart';
import 'menu_overlay_settings.dart';
import 'menu_settings_draft.dart';

class OverlaySettingsSections extends StatefulWidget {
  const OverlaySettingsSections({
    required this.child,
    this.menuPreview,
    this.menuDraft,
    super.key,
  });

  final Widget child;
  final MenuPreviewWindowPort? menuPreview;
  final MenuSettingsDraft? menuDraft;

  @override
  State<OverlaySettingsSections> createState() =>
      _OverlaySettingsSectionsState();
}

class _OverlaySettingsSectionsState extends State<OverlaySettingsSections> {
  bool _menu = false;
  bool _menuVisited = false;

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
                onSelected: (_) => setState(() {
                  _menu = true;
                  _menuVisited = true;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _menu ? 1 : 0,
            children: [
              widget.child,
              if (_menuVisited)
                TickerMode(
                  enabled: _menu,
                  child: MenuOverlaySettings(
                    preview: widget.menuPreview,
                    draft: widget.menuDraft,
                  ),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

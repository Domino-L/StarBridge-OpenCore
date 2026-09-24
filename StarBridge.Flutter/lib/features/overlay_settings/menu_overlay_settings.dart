import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/window/menu_preview_window_port.dart';

class MenuOverlaySettings extends StatefulWidget {
  const MenuOverlaySettings({required this.preview, super.key});
  final MenuPreviewWindowPort? preview;

  @override
  State<MenuOverlaySettings> createState() => _MenuOverlaySettingsState();
}

class _MenuOverlaySettingsState extends State<MenuOverlaySettings> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _open({bool live = false}) async {
    final preview = widget.preview;
    if (preview == null || _opening) return;
    final strings = AppStrings.of(context);
    setState(() {
      _opening = true;
      _failed = false;
    });
    var shown = false;
    try {
      final open = live && preview is MenuLiveWindowPort
          ? preview.openLive
          : preview.open;
      shown = await open(
        contextLabel: strings.text('overlay.menu.previewTitle'),
        returnLabel: strings.text('overlay.menu.return'),
        settingsLabel: strings.text('overlay.sections.menu'),
      );
    } on Object {
      shown = false;
    }
    if (mounted) {
      setState(() {
        _opening = false;
        _failed = !shown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.space.xl),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: StarBridgeSurface(
            role: SurfaceRole.panel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('overlay.menu.previewTitle'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SizedBox(height: tokens.space.sm),
                Text(strings.text('overlay.menu.previewBody')),
                SizedBox(height: tokens.space.sm),
                Text(
                  strings.text('overlay.menu.instructions'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: tokens.space.lg),
                FilledButton(
                  key: const Key('menu-overlay-open-preview'),
                  onPressed: _opening || widget.preview == null ? null : _open,
                  child: Text(
                    strings.text(
                      _opening ? 'overlay.menu.opening' : 'overlay.menu.open',
                    ),
                  ),
                ),
                if (widget.preview case final MenuLiveWindowPort live
                    when live.liveAvailable) ...[
                  SizedBox(height: tokens.space.sm),
                  OutlinedButton(
                    key: const Key('menu-overlay-open-live'),
                    onPressed: _opening ? null : () => _open(live: true),
                    child: Text(strings.text('overlay.menu.live')),
                  ),
                  Text(strings.text('overlay.menu.liveBody')),
                ],
                if (_failed || widget.preview == null) ...[
                  SizedBox(height: tokens.space.sm),
                  Text(
                    strings.text('overlay.menu.failed'),
                    key: const Key('menu-overlay-preview-failed'),
                    style: TextStyle(color: tokens.colors.warning),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

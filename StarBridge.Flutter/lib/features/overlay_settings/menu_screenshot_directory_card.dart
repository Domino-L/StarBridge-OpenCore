import 'package:flutter/material.dart';

import 'overlay_settings_help.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import 'menu_screenshot_directory_controller.dart';

class MenuScreenshotDirectoryCard extends StatefulWidget {
  const MenuScreenshotDirectoryCard({
    super.key,
    required this.port,
    this.controller,
  });
  final MenuScreenshotDirectoryPort port;
  final MenuScreenshotDirectoryController? controller;
  @override
  State<MenuScreenshotDirectoryCard> createState() =>
      _MenuScreenshotDirectoryCardState();
}

class _MenuScreenshotDirectoryCardState
    extends State<MenuScreenshotDirectoryCard> {
  late MenuScreenshotDirectoryController controller;
  void _bind() {
    controller =
        widget.controller ?? MenuScreenshotDirectoryController(widget.port);
    if (controller.saved == null) controller.load();
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant MenuScreenshotDirectoryCard old) {
    super.didUpdateWidget(old);
    if (old.port != widget.port || old.controller != widget.controller) {
      if (old.controller == null) controller.dispose();
      _bind();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      String t(String key) =>
          AppStrings.of(context).text('menu.screenshot.directory.$key');
      final value = controller.saved;
      return StarBridgeSurface(
        role: SurfaceRole.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('title'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            OverlaySettingsHelp(t('hint')),
            const SizedBox(height: 12),
            if (value != null) ...[
              Text(
                t(
                  controller.failed
                      ? 'lastConfirmed'
                      : value.isDefault
                      ? 'default'
                      : 'custom',
                ),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              SelectableText(
                value.directory,
                key: const Key('menu-screenshot-directory-path'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('menu-screenshot-directory-choose'),
                  onPressed: controller.canAct ? controller.choose : null,
                  child: Text(t('choose')),
                ),
                OutlinedButton(
                  key: const Key('menu-screenshot-directory-open'),
                  onPressed: controller.canAct ? controller.open : null,
                  child: Text(t('open')),
                ),
                TextButton(
                  key: const Key('menu-screenshot-directory-reset'),
                  onPressed: controller.canAct && value?.isDefault == false
                      ? controller.reset
                      : null,
                  child: Text(t('reset')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t(controller.status),
              key: const Key('menu-screenshot-directory-state'),
            ),
            if (controller.failed || value == null && !controller.busy)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('menu-screenshot-directory-reload'),
                  onPressed: controller.busy ? null : controller.load,
                  child: Text(t('reload')),
                ),
              ),
            const SizedBox(height: 8),
            OverlaySettingsHelp(t('privacy')),
          ],
        ),
      );
    },
  );
}

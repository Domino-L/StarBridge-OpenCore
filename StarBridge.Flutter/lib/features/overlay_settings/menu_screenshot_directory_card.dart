import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';

import 'overlay_settings_help.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import 'menu_screenshot_directory_controller.dart';
import 'overlay_settings_command_feedback.dart';

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
  Widget build(BuildContext context) => OverlaySettingsCommandFeedback(
    owner: controller,
    builder: (context, run, source) => ListenableBuilder(
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
                  StarBridgeActionButton(
                    controlKey: const Key('menu-screenshot-directory-choose'),
                    onActivate: controller.canAct
                        ? (origin) => run(origin, controller.choose)
                        : null,
                    child: Text(t('choose')),
                  ),
                  StarBridgeActionButton(
                    controlKey: const Key('menu-screenshot-directory-open'),
                    onActivate: controller.canAct
                        ? (origin) => run(origin, controller.open)
                        : null,
                    child: Text(t('open')),
                  ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('menu-screenshot-directory-reset'),
                    onActivate: controller.canAct && value?.isDefault == false
                        ? (origin) => run(origin, controller.reset)
                        : null,
                    child: Text(t('reset')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (controller.busy)
                OverlaySettingsCommandWait(
                  key: const Key('menu-screenshot-directory-state'),
                  label: t(controller.status),
                  source: source(),
                )
              else
                Text(
                  t(controller.status),
                  key: const Key('menu-screenshot-directory-state'),
                ),
              if (controller.failed || value == null && !controller.busy)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const Key('menu-screenshot-directory-reload'),
                    onActivate: controller.busy
                        ? null
                        : (origin) => run(origin, controller.load),
                    child: Text(t('reload')),
                  ),
                ),
              const SizedBox(height: 8),
              OverlaySettingsHelp(t('privacy')),
            ],
          ),
        );
      },
    ),
  );
}

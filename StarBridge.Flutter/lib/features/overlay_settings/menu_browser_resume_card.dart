import 'package:flutter/material.dart';

import 'overlay_settings_help.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/window/menu_browser_resume.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import 'menu_browser_resume_controller.dart';

class MenuBrowserResumeCard extends StatefulWidget {
  const MenuBrowserResumeCard({super.key, required this.port, this.controller});
  final MenuBrowserResumePort port;
  final MenuBrowserResumeController? controller;
  @override
  State<MenuBrowserResumeCard> createState() => _MenuBrowserResumeCardState();
}

class _MenuBrowserResumeCardState extends State<MenuBrowserResumeCard> {
  late MenuBrowserResumeController controller;
  void _bind() {
    controller = widget.controller ?? MenuBrowserResumeController(widget.port);
    if (controller.saved == null) controller.load();
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant MenuBrowserResumeCard old) {
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
          AppStrings.of(context).text('menu.browser.resume.$key');
      final value = controller.saved;
      return StarBridgeSurface(
        role: SurfaceRole.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('title'), style: Theme.of(context).textTheme.titleMedium),
            OverlaySettingsHelp(t('privacy')),
            if (value != null)
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const Key('menu-browser-resume-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('enabled')),
                  subtitle: OverlaySettingsHelp(t('hint')),
                  value: value.enabled,
                  onChanged: controller.busy ? null : controller.setEnabled,
                ),
              ),
            Text(
              t(
                controller.busy
                    ? 'busy'
                    : controller.failed
                    ? 'failed'
                    : value == null
                    ? 'unavailable'
                    : value.enabled
                    ? 'on'
                    : 'off',
              ),
              key: const Key('menu-browser-resume-state'),
            ),
            if (controller.failed || value == null && !controller.busy)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('menu-browser-resume-reload'),
                  onPressed: controller.busy ? null : controller.load,
                  child: Text(t('reload')),
                ),
              ),
          ],
        ),
      );
    },
  );
}

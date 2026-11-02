import 'package:flutter/material.dart';

import '../../app/menu_overlay/menu_bridge_preview.dart';
import '../../app/menu_overlay/menu_local_tools.dart';
import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import '../../platform/window/menu_social_preferences.dart';
import '../../platform/window/menu_exec_hangar_summary.dart';
import '../../platform/window/menu_window_preferences.dart';
import '../tools/exec_hangar_port.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import 'menu_settings_draft.dart';

/// Synthetic presentation: no native calls, receipts or saves. The only live
/// read is the public executive hangar schedule, so its countdown matches the
/// real menu instead of a fixed sample.
class MenuSettingsPreview extends StatefulWidget {
  const MenuSettingsPreview({super.key, required this.draft, this.execHangar});
  final MenuSettingsDraft draft;
  final ExecHangarPort? Function()? execHangar;
  @override
  State<MenuSettingsPreview> createState() => _PreviewState();
}

class _PreviewState extends State<MenuSettingsPreview> {
  final tools = MenuLocalToolsController((_, _) async => null);
  late final hangar = _PreviewHangarPort(() => widget.execHangar?.call());
  bool actualSize = false;
  final transform = TransformationController();
  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (!widget.draft.ready) return;
    final settings = widget.draft.settings;
    tools.settings(
      display: MenuDisplayPreferences.fromSettings(settings),
      toolbar: MenuToolbarPreferences.parse(settings['toolbar']),
      social: MenuSocialPreferences.fromSettings(settings),
      dim: (settings['dimming'] as num?)?.toDouble(),
    );
  }

  @override
  void didUpdateWidget(MenuSettingsPreview old) {
    super.didUpdateWidget(old);
    if (old.draft != widget.draft) {
      old.draft.removeListener(_sync);
      widget.draft.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.draft.removeListener(_sync);
    tools.dispose();
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    // The actual menu fills the monitor. Do not lay it out at the settings
    // window size, or a fixed demo aspect ratio, before fitting the preview.
    final display = View.of(context).display;
    final viewport = display.size / display.devicePixelRatio;
    final media = MediaQuery.of(context).copyWith(
      size: viewport,
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
      viewInsets: EdgeInsets.zero,
    );
    final canvas = SizedBox(
      key: const Key('menu-preview-canvas'),
      width: viewport.width,
      height: viewport.height,
      child: MediaQuery(
        data: media,
        child: ExcludeSemantics(
          child: ExcludeFocus(
            child: IgnorePointer(
              child: MenuBridgePreview(
                visible: true,
                settingsPreview: true,
                initialSettings: widget.draft.ready
                    ? widget.draft.settings
                    : MenuWindowPreferences.defaults.settings,
                hangar: hangar,
                localToolsController: tools,
                onDismiss: () {},
                contextValues: [
                  strings.text('menu.workspace.sampleFleet'),
                  '4',
                  strings.text('menu.workspace.sampleShip'),
                  strings.text('menu.workspace.sampleLocation'),
                  strings.text('menu.workspace.sampleServer'),
                  'presence.online',
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return StarBridgeSurface(
      key: const Key('menu-preview-stage'),
      role: SurfaceRole.panel,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  strings.text('overlay.preview.stageTitle'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                StarBridgeActionButton(
                  controlKey: const Key('menu-preview-zoom'),
                  onActivate: (_) => setState(() {
                    actualSize = !actualSize;
                    transform.value = Matrix4.identity();
                  }),
                  child: Text(
                    actualSize ? '100%' : strings.text('overlay.preview.fit'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRect(
                child: ColoredBox(
                  color: context.tokens.surfaces
                      .resolve(SurfaceRole.panel)
                      .fill,
                  child: actualSize
                      ? InteractiveViewer(
                          key: const Key('menu-preview-actual-size'),
                          transformationController: transform,
                          constrained: false,
                          scaleEnabled: false,
                          minScale: 1,
                          maxScale: 1,
                          alignment: Alignment.topLeft,
                          child: canvas,
                        )
                      : Center(
                          child: FittedBox(fit: BoxFit.contain, child: canvas),
                        ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              strings.text('menu.workspace.previewScope'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reads the same schedule the real menu shows (exactly as the menu converts
/// it). Without a hangar capability, or when that read fails, the settings
/// illustration falls back to a sample; no native tool is ever invoked.
final class _PreviewHangarPort implements MenuExecHangarSummaryPort {
  _PreviewHangarPort(this.live);
  final ExecHangarPort? Function() live;
  @override
  Future<MenuExecHangarSummary> read() async {
    final port = live();
    if (port != null) {
      try {
        return MenuExecHangarSummary.fromSnapshot(await port.read());
      } on Object {
        // Keep the illustration; the real menu reports its own failure.
      }
    }
    final now = DateTime.now().toUtc();
    final open = now.subtract(const Duration(minutes: 45));
    final close = now.add(const Duration(minutes: 20));
    return MenuExecHangarSummary.parse({
      'now': now.toIso8601String(),
      'reliable': true,
      'fetchedAt': now.toIso8601String(),
      'phases': [
        {
          'start': open.toIso8601String(),
          'end': close.toIso8601String(),
          'open': true,
          'green': 5,
          'red': 0,
        },
      ],
      'windows': [
        {'open': open.toIso8601String(), 'close': close.toIso8601String()},
      ],
    });
  }
}

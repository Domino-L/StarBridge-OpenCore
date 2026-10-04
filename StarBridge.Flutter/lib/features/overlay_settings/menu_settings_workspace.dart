import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import 'overlay_workspace_frame.dart';
import 'overlay_workspace_group_navigation.dart';
import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_toolbar_preferences.dart';
import '../../platform/window/menu_restore_preferences.dart';
import '../../platform/window/menu_browser_preferences.dart';
import '../../platform/window/menu_image_preferences.dart';
import '../../platform/window/menu_screenshot_preferences.dart';
import '../../platform/window/menu_social_preferences.dart';
import 'menu_settings_draft.dart';
import 'menu_additional_settings_editors.dart';
import 'menu_settings_scroll.dart';
import 'overlay_settings_help.dart';
import 'overlay_settings_save_bar.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'menu_settings_preview.dart';
import 'menu_display_editor.dart';
import 'menu_toolbar_editor.dart';
import 'menu_restore_editor.dart';
import 'menu_browser_editor.dart';
import 'menu_image_editor.dart';
import 'menu_screenshot_editor.dart';
import 'menu_social_settings_card.dart';

class MenuSettingsWorkspace extends StatefulWidget {
  const MenuSettingsWorkspace({
    super.key,
    required this.draft,
    this.shortcuts,
    this.browserResume,
    this.screenshotDirectory,
  });
  final MenuSettingsDraft draft;
  final Widget? shortcuts, browserResume, screenshotDirectory;
  @override
  State<MenuSettingsWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<MenuSettingsWorkspace> {
  String section = 'display';
  bool settingsOpen = false;
  final visited = <String>{'display'};
  final settingsKey = GlobalKey();
  final previewKey = GlobalKey();

  void select(String value) => setState(() {
    section = value;
    visited.add(value);
    settingsOpen = true;
  });

  static StarBridgeIconSemantic icon(String id) => switch (id) {
    'display' => StarBridgeIconSemantic.overlay,
    'toolbar' => StarBridgeIconSemantic.tools,
    'restore' => StarBridgeIconSemantic.windowRestore,
    'social' => StarBridgeIconSemantic.friends,
    'browser' => StarBridgeIconSemantic.statusNetwork,
    'image' => StarBridgeIconSemantic.scene,
    'screenshot' => StarBridgeIconSemantic.generalData,
    _ => StarBridgeIconSemantic.settings,
  };
  static const sections = [
    'display',
    'toolbar',
    'restore',
    'social',
    'browser',
    'image',
    'screenshot',
    'shortcuts',
  ];
  @override
  void initState() {
    super.initState();
    widget.draft.initialize();
  }

  @override
  void didUpdateWidget(MenuSettingsWorkspace old) {
    super.didUpdateWidget(old);
    if (old.draft != widget.draft) widget.draft.initialize();
  }

  Widget editor(String section) {
    final data = widget.draft.settings;
    final change = widget.draft.change;
    return switch (section) {
      'toolbar' => MenuToolbarEditor(
        showTitle: false,
        value: MenuToolbarPreferences.parse(data['toolbar'])!,
        onChanged: (v) => change({'toolbar': v.toMap()}),
      ),
      'restore' => MenuRestoreEditor(
        showTitle: false,
        value: MenuRestorePreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'social' => MenuSocialEditor(
        showTitle: false,
        value: MenuSocialPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'browser' => MenuBrowserEditor(
        showTitle: false,
        value: MenuBrowserPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'image' => MenuImageEditor(
        showTitle: false,
        value: MenuImagePreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'screenshot' => MenuScreenshotEditor(
        showTitle: false,
        value: MenuScreenshotPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'shortcuts' => const SizedBox.shrink(),
      _ => MenuDisplayEditor(
        showTitle: false,
        value: MenuDisplayPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.draft,
    builder: (context, _) {
      String text(String key) =>
          AppStrings.of(context).text('menu.workspace.$key');
      final draft = widget.draft;
      Widget? independent(String section) => switch (section) {
        'shortcuts' => widget.shortcuts,
        'browser' => widget.browserResume,
        'screenshot' => widget.screenshotDirectory,
        _ => null,
      };
      final settings = Column(
        key: settingsKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              text(section),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: sections.indexOf(section),
              children: [
                for (final section in sections)
                  if (!visited.contains(section))
                    const SizedBox.shrink()
                  else
                    ExcludeFocus(
                      excluding: section != this.section,
                      child: MenuSettingsScroll(
                        key: ValueKey('menu-settings-scroll-$section'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (draft.ready)
                              AbsorbPointer(
                                absorbing: draft.busy,
                                child: ExcludeFocus(
                                  excluding: draft.busy,
                                  child: editor(section),
                                ),
                              ),
                            if (draft.busy && !draft.ready)
                              const LinearProgressIndicator(),
                            if (independent(section) case final separate?) ...[
                              const Divider(height: 32),
                              OverlaySettingsHelp(text('independent')),
                              const SizedBox(height: 8),
                              AbsorbPointer(
                                absorbing: draft.busy,
                                child: ExcludeFocus(
                                  excluding: draft.busy,
                                  child: separate,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          if (draft.failed || !draft.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(),
                  Text(
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: draft.failed
                          ? Theme.of(context).colorScheme.error
                          : context.tokens.colors.textSecondary,
                    ),
                    text(
                      draft.busy
                          ? 'loading'
                          : draft.failed
                          ? (draft.conflict
                                ? 'conflict'
                                : draft.dirty
                                ? 'failedDirty'
                                : 'failed')
                          : draft.dirty
                          ? 'dirty'
                          : 'saved',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        key: const Key('menu-workspace-reload'),
                        onPressed: !draft.dirty && !draft.busy
                            ? draft.reload
                            : null,
                        child: Text(text('reload')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: OverlayWorkspaceFrame(
              navigation: OverlayWorkspaceGroupNavigation(
                keyPrefix: 'menu-group',
                groups: sections,
                selected: section,
                onSelected: select,
                label: text,
                icon: icon,
                title: text('category'),
              ),
              selector: DropdownButtonFormField<String>(
                key: ValueKey('menu-section-$section'),
                initialValue: section,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final id in sections)
                    DropdownMenuItem(value: id, child: Text(text(id))),
                ],
                onChanged: (v) {
                  if (v != null) select(v);
                },
              ),
              preview: MenuSettingsPreview(key: previewKey, draft: draft),
              settings: StarBridgeSurface(
                key: const Key('menu-settings-right'),
                role: SurfaceRole.panel,
                padding: EdgeInsets.zero,
                child: settings,
              ),
              settingsOpen: settingsOpen,
              onToggleSettings: () =>
                  setState(() => settingsOpen = !settingsOpen),
              toggleKey: const Key('menu-settings-expand'),
            ),
          ),
          if (draft.dirty || draft.canRedo)
            OverlaySettingsSaveBar(
              key: const Key('menu-settings-save-bar'),
              busy: draft.busy,
              dirty: draft.dirty,
              onUndo: draft.canUndo ? draft.undo : null,
              onRedo: draft.canRedo ? draft.redo : null,
              onDiscard: draft.discard,
              onSave: draft.dirty
                  ? () => confirmMenuSettingsSave(context, draft)
                  : null,
              saveKey: const Key('menu-workspace-save'),
              discardKey: const Key('menu-workspace-discard'),
            ),
        ],
      );
    },
  );
}

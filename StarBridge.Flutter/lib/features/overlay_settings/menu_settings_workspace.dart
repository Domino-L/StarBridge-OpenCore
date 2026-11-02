import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/interaction/starbridge_menu_anchor.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'overlay_workspace_frame.dart';
import 'overlay_workspace_group_navigation.dart';
import '../../platform/window/menu_display_preferences.dart';
import '../../platform/window/menu_desktop_widgets.dart';
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
import 'overlay_settings_save_bar_visibility.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'menu_settings_preview.dart';
import 'menu_display_editor.dart';
import 'menu_toolbar_editor.dart';
import 'menu_restore_editor.dart';
import 'menu_browser_editor.dart';
import 'menu_image_editor.dart';
import 'menu_screenshot_editor.dart';
import 'menu_social_settings_card.dart';
import '../tools/exec_hangar_port.dart';

class MenuSettingsWorkspace extends StatefulWidget {
  const MenuSettingsWorkspace({
    super.key,
    required this.draft,
    this.shortcuts,
    this.browserResume,
    this.screenshotDirectory,
    this.execHangar,
  });
  final MenuSettingsDraft draft;
  final Widget? shortcuts, browserResume, screenshotDirectory;

  /// Public hangar schedule for the preview countdown; null shows a sample.
  final ExecHangarPort? Function()? execHangar;
  @override
  State<MenuSettingsWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<MenuSettingsWorkspace> {
  String section = 'display';
  String shownSection = 'display';
  int _selectionEpoch = 0;
  bool _waitingForPortal = false;
  bool settingsOpen = false;
  bool _reloading = false;
  int _reloadEpoch = 0;
  ValueGetter<InteractionSource> _reloadSource = () =>
      InteractionSource.programmatic;
  final visited = <String>{'display'};
  final settingsKey = GlobalKey();
  final previewKey = GlobalKey();

  Future<void> _reload(InteractionSource source) async {
    final owner = widget.draft;
    if (owner.dirty || owner.busy || _reloading) return;
    final epoch = ++_reloadEpoch;
    setState(() => _reloading = true);
    try {
      await runStarBridgeActivation(source, () {
        _reloadSource = captureStarBridgeActivationSource();
        return owner.reload();
      });
    } finally {
      if (mounted && epoch == _reloadEpoch && identical(widget.draft, owner)) {
        setState(() => _reloading = false);
      }
    }
  }

  Widget _waiting(String label) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final source = resolveStarBridgeInitialReadSource(
          context,
          _reloadSource(),
        );
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: Semantics(
            liveRegion: true,
            child: SuiteBusyFrame(busy: true, child: SuiteBusyLabel(label)),
          ),
        );
      },
    ),
  );

  void select(String value) {
    final hadMenu = dismissStarBridgeMenus(context);
    final retiring = hadMenu || _waitingForPortal;
    final epoch = ++_selectionEpoch;
    setState(() {
      section = value;
      visited.add(value);
      settingsOpen = true;
      if (!retiring) shownSection = value;
    });
    if (retiring) {
      _waitingForPortal = true;
      // The SDK portal removes its render/semantic subtree at a frame
      // boundary. Keep the old anchor laid out for that removal frame, while
      // navigation selection already reflects the latest user action.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _selectionEpoch) {
          setState(() {
            _waitingForPortal = false;
            shownSection = section;
          });
        }
      });
    }
  }

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
    if (old.draft != widget.draft) {
      ++_reloadEpoch;
      _reloading = false;
      _reloadSource = () => InteractionSource.programmatic;
      widget.draft.initialize();
    }
  }

  Widget editor(String section) {
    final data = widget.draft.settings;
    final change = widget.draft.change;
    return switch (section) {
      'toolbar' => MenuToolbarEditor(
        showTitle: false,
        enabled: !widget.draft.busy,
        value: MenuToolbarPreferences.parse(data['toolbar'])!,
        onChanged: (v) => change({'toolbar': v.toMap()}),
      ),
      'restore' => MenuRestoreEditor(
        showTitle: false,
        enabled: !widget.draft.busy,
        value: MenuRestorePreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'social' => MenuSocialEditor(
        showTitle: false,
        enabled: !widget.draft.busy,
        value: MenuSocialPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'browser' => MenuBrowserEditor(
        showTitle: false,
        enabled: !widget.draft.busy,
        value: MenuBrowserPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'image' => MenuImageEditor(
        showTitle: false,
        enabled: !widget.draft.busy,
        value: MenuImagePreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'screenshot' => MenuScreenshotEditor(
        showTitle: false,
        enabled: !widget.draft.busy,
        value: MenuScreenshotPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
      ),
      'shortcuts' => const SizedBox.shrink(),
      _ => MenuDisplayEditor(
        showTitle: false,
        enabled: !widget.draft.busy,
        value: MenuDisplayPreferences.fromSettings(data)!,
        onChanged: (v) => change(v.toSettingsPatch()),
        widgets: MenuDesktopWidgets.parse(data['widgets'])!,
        onWidgetsChanged: (v) => change({'widgets': v.toMap()}),
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
              text(shownSection),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: sections.indexOf(shownSection),
              children: [
                for (final section in sections)
                  if (!visited.contains(section))
                    const SizedBox.shrink()
                  else
                    ExcludeFocus(
                      excluding: section != shownSection,
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
                              const SizedBox(height: 4),
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
          if (draft.failed || !draft.ready || _reloading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(),
                  if (draft.busy || _reloading)
                    _waiting(text('loading'))
                  else
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
                      StarBridgeActionButton(
                        controlKey: const Key('menu-workspace-reload'),
                        kind: StarBridgeActionKind.quiet,
                        onActivate: !draft.dirty && !draft.busy && !_reloading
                            ? (source) => unawaited(_reload(source))
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
              selector: StarBridgeSelectFormField<String>(
                key: ValueKey('menu-section-$section'),
                identity: 'menu-workspace-section',
                controlKey: const Key('menu-workspace-section-command'),
                semanticLabel: text('category'),
                initialValue: section,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final id in sections)
                    DropdownMenuItem(
                      value: id,
                      child: Text(
                        text(id),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) select(v);
                },
              ),
              preview: MenuSettingsPreview(
                key: previewKey,
                draft: draft,
                execHangar: widget.execHangar,
              ),
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
          OverlaySettingsSaveBarVisibility(
            owner: draft,
            isVisible: () => draft.dirty || draft.canRedo,
            builder: (context) => OverlaySettingsSaveBar(
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
          ),
        ],
      );
    },
  );
}

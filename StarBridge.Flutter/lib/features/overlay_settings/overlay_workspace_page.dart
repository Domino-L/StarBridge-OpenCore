import '../../shared/guide/guide_scope.dart';
import 'overlay_appearance_qualification.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_select_form_field.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import 'overlay_settings_models.dart';
import 'overlay_preset_import_preview.dart';
import 'overlay_preset_transfer.dart';
import 'overlay_scene_controller.dart';
import 'overlay_source_card.dart';
import 'overlay_source_binding_field.dart';
import 'overlay_chat_sources_field.dart';
import 'overlay_source_limit_notice.dart';
import 'overlay_roster_editor.dart';
import 'overlay_workspace_appearance_center.dart';
import 'overlay_workspace_appearance_entry.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_editor_state.dart';
import 'overlay_calm_display_controls.dart';
import 'overlay_workspace_fullscreen.dart';
import 'overlay_workspace_gesture_save.dart';
import 'overlay_workspace_group_navigation.dart';
import 'overlay_workspace_frame.dart';
import 'overlay_workspace_models.dart';
import 'overlay_preset_name.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_module_style_controls.dart';
import 'overlay_workspace_preset_bar.dart';
import 'overlay_workspace_preview_stage.dart';
import 'overlay_workspace_runtime_card.dart';
import 'overlay_workspace_schema.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class OverlayWorkspacePage extends StatefulWidget {
  const OverlayWorkspacePage({
    required this.module,
    this.scenes,
    this.roster,
    super.key,
  });

  final OverlayWorkspaceModule module;
  final OverlaySceneController? scenes;
  final OverlayRosterPort? roster;

  @override
  State<OverlayWorkspacePage> createState() => _OverlayWorkspacePageState();
}

class _OverlayWorkspacePageState extends State<OverlayWorkspacePage> {
  String _group = overlayWorkspaceGroupOrder.first;
  bool _appearanceCenterOpen = false;
  bool _settingsOpen = false;
  final _editor = OverlayWorkspaceEditorState();
  final _previewKey = GlobalKey();
  bool _retrying = false;
  int _retryEpoch = 0;
  ValueGetter<InteractionSource> _retrySource = () =>
      InteractionSource.programmatic;

  @override
  void didUpdateWidget(OverlayWorkspacePage old) {
    super.didUpdateWidget(old);
    if (!identical(old.module, widget.module)) {
      ++_retryEpoch;
      _retrying = false;
      _retrySource = () => InteractionSource.programmatic;
    }
  }

  Future<void> _retry(InteractionSource source) async {
    final owner = widget.module, before = widget.module.projection.value;
    if (_retrying || before.busy) return;
    final epoch = ++_retryEpoch;
    setState(() => _retrying = true);
    try {
      await runStarBridgeActivation(source, () async {
        _retrySource = captureStarBridgeActivationSource();
        // A failed save retries the save; reading again would drop the
        // adjustments it still holds.
        if (before.dirty) {
          await owner.save();
          return;
        }
        if (!mounted ||
            epoch != _retryEpoch ||
            !identical(owner, widget.module) ||
            owner.projection.value.busy) {
          return;
        }
        await owner.refresh();
      });
    } finally {
      if (mounted && epoch == _retryEpoch && identical(owner, widget.module)) {
        setState(() => _retrying = false);
      }
    }
  }

  Widget _waiting() => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        final source = resolveStarBridgeInitialReadSource(
          context,
          _retrySource(),
        );
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: Semantics(
            liveRegion: true,
            child: SuiteBusyFrame(
              busy: true,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SuiteBusyLabel(_copy(context, 'overlay.loading')),
              ),
            ),
          ),
        );
      },
    ),
  );

  @override
  void initState() {
    super.initState();
    _editor.addListener(_selectionChanged);
  }

  @override
  void dispose() {
    _editor.removeListener(_selectionChanged);
    _editor.dispose();
    super.dispose();
  }

  Widget get _fullscreenButton =>
      OverlayWorkspaceFullscreenButton(module: widget.module, editor: _editor);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OverlayWorkspaceProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) {
        if (projection.operation == OverlayWorkspaceOperation.reading) {
          return LoadingContentProbe(
            route: '/overlay',
            status: LoadingContentStatus.waiting,
            child: Center(child: _waiting()),
          );
        }
        if (!projection.available) {
          return LoadingContentProbe(
            route: '/overlay',
            status: LoadingContentStatus.unavailable,
            child: _Unavailable(
              failure: projection.failure,
              onRetry: _retrying || projection.busy
                  ? null
                  : (source) => unawaited(_retry(source)),
            ),
          );
        }
        return LoadingContentProbe(
          route: '/overlay',
          status: LoadingContentStatus.data,
          items: 1,
          child: OverlayWorkspaceGestureSave(
            module: widget.module,
            child: _content(context, projection),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, OverlayWorkspaceProjection projection) {
    final snapshot = projection.snapshot!;
    final active = snapshot.presets.singleWhere(
      (preset) => preset.id == snapshot.activePresetId,
    );
    final fields = overlayWorkspaceFieldSpecs
        .where(
          (field) =>
              field.group == _group &&
              (widget.scenes == null || field.field != 'scenePreference'),
        )
        .toList(growable: false);
    // Edits save on their own (OverlayWorkspaceModule); there is no save bar.
    return ValueListenableBuilder<bool>(
      valueListenable: widget.module.appearanceQualificationUnknown,
      builder: (_, unknown, child) =>
          OverlayAppearanceQualification(unknown: unknown, child: child!),
      child: _appearanceCenterOpen
          ? OverlayWorkspaceAppearanceCenter(
              projection: projection,
              module: widget.module,
              onBack: () => setState(() => _appearanceCenterOpen = false),
            )
          : _workspace(context, projection, active, fields),
    );
  }

  Widget _settings(
    OverlayWorkspaceProjection projection,
    List<OverlayWorkspaceFieldSpec> fields,
  ) => SingleChildScrollView(
    key: const Key('overlay-settings-dock'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverlayWorkspaceSettingsGroup(
          group: _group,
          editOwner: (widget.module, projection.snapshot),
          currentEditOwner: () =>
              (widget.module, widget.module.projection.value.snapshot),
          fields: fields,
          settings: projection.settings!,
          appearances: projection.snapshot!.appearances,
          onChanged: widget.module.updateSetting,
          onExperiencePreset: widget.module.applyExperiencePreset,
          footer: _moduleStyleControls(projection),
          // Appearance Center stays the full appearance page; this group keeps
          // the quick fields and links to it.
          header: _group == 'appearance'
              ? OverlayWorkspaceAppearanceEntry(
                  projection: projection,
                  onPressed: () => setState(() => _appearanceCenterOpen = true),
                )
              : _sourceField(projection),
        ),
        if (_group == 'startup')
          OverlayWorkspaceHotkeyCard(
            hotkey: projection.hotkey!,
            onBindingChanged: (value) =>
                widget.module.updateHotkey(binding: value),
            onEnabledChanged: (value) =>
                widget.module.updateHotkey(enabled: value),
          ),
      ],
    ),
  );

  Widget? _sourceField(OverlayWorkspaceProjection projection) {
    final module = switch (_group) {
      'notice' => OverlaySourceModule.notice,
      'fleetOverview' => OverlaySourceModule.overview,
      'members' => OverlaySourceModule.members,
      'chat' => OverlaySourceModule.chat,
      'events' => OverlaySourceModule.events,
      _ => null,
    };
    if (module == null ||
        projection.snapshot?.sourcePresetsEnabled != true ||
        projection.sources == null) {
      return null;
    }
    if (module == OverlaySourceModule.chat) {
      return OverlayChatSourcesField(
        value: projection.sources!,
        scenes: widget.scenes,
        onChanged: projection.busy ? null : widget.module.updateChatSources,
        onSingleChanged: projection.busy
            ? null
            : (value) => widget.module.updateModuleSource(module, value),
      );
    }
    return OverlaySourceBindingField(
      key: Key('overlay-module-source-${module.name}'),
      value: projection.sources!.forModule(module),
      scenes: widget.scenes,
      onChanged: projection.busy
          ? null
          : (value) => widget.module.updateModuleSource(module, value),
    );
  }

  Widget _workspace(
    BuildContext context,
    OverlayWorkspaceProjection projection,
    OverlayWorkspacePreset active,
    List<OverlayWorkspaceFieldSpec> fields,
  ) {
    final preview = OverlayWorkspacePreviewStage(
      key: _previewKey,
      projection: projection,
      fullscreenButton: _fullscreenButton,
      editor: _editor,
      module: widget.module,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            key: const Key('overlay-workspace-toolbar'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = Text(
                    _copy(context, 'overlay.title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  );
                  final runtime = GuideAnchor(
                    id: 'overlay.runtime',
                    child: OverlayWorkspaceRuntimeCard(
                      projection: projection,
                      compact: true,
                      onAction: () => _runRuntimeAction(projection),
                    ),
                  );
                  return constraints.maxWidth >= 760
                      ? Row(
                          children: [
                            Expanded(child: title),
                            runtime,
                          ],
                        )
                      : Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [title, runtime],
                        );
                },
              ),
              const SizedBox(height: 4),
              Text(
                _copy(context, 'overlay.workspace.description'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              GuideAnchor(
                id: 'overlay.presets',
                child: OverlayWorkspacePresetBar(
                  scenes: widget.scenes,
                  compact: true,
                  showLegacyScene: widget.scenes == null,
                  projection: projection,
                  module: widget.module,
                  onImport: () => _importPreset(projection),
                  onImportSource: (source) =>
                      _importPreset(projection, source: source),
                  onExport: () => _exportPreset(active),
                  onExportSource: (source) =>
                      _exportPreset(active, source: source),
                  onOpenAppearance: () =>
                      setState(() => _appearanceCenterOpen = true),
                ),
              ),
              if (widget.scenes case final scenes?
                  when projection.snapshot?.sourcePresetsEnabled == true) ...[
                const SizedBox(height: 12),
                GuideAnchor(
                  id: 'overlay.sources',
                  child: OverlaySourceCard(
                    scenes: scenes,
                    workspace: widget.module,
                  ),
                ),
              ],
            ],
          ),
          if (projection.failure case final failure?)
            _Failure(
              failure: failure,
              onRetry: _retrying || projection.busy
                  ? null
                  : (source) => unawaited(_retry(source)),
              onDiscard: projection.dirty && !_retrying && !projection.busy
                  ? widget.module.discardChanges
                  : null,
            ),
          // A failed save is more urgent; the introduction waits for it.
          if (projection.settings?['calmDisplay'] == 'Unset' &&
              projection.failure == null)
            OverlayCalmDisplayIntro(
              onChoose: (value) =>
                  widget.module.updateSetting('calmDisplay', value),
            ),
          if (projection.runtime.failureCode ==
              'overlay.sources_limit_exceeded')
            OverlaySourceLimitNotice(
              module: widget.module,
              scenes: widget.scenes,
            ),
          const SizedBox(height: 12),
          Expanded(
            key: const Key('overlay-workspace-content'),
            child: OverlayWorkspaceFrame(
              navigation: GuideAnchor(
                id: 'overlay.groups',
                child: OverlayWorkspaceGroupNavigation(
                  selected: _group,
                  onSelected: _selectGroup,
                  mark: (group) => overlayWorkspaceGroupMark(projection, group),
                ),
              ),
              selector: StarBridgeSelectFormField<String>(
                key: ValueKey('overlay-group-compact-$_group'),
                identity: 'overlay-workspace-group',
                controlKey: const Key('overlay-workspace-group-command'),
                semanticLabel: _copy(context, 'overlay.workspace.sections'),
                initialValue: _group,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final group in overlayWorkspaceNavigationGroupOrder)
                    DropdownMenuItem(
                      value: group,
                      child: Text(
                        overlayWorkspaceGroupName(context, group),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _selectGroup(value);
                },
              ),
              preview: GuideAnchor(id: 'overlay.preview', child: preview),
              settings: _settings(projection, fields),
              settingsOpen: _settingsOpen,
              onToggleSettings: () =>
                  setState(() => _settingsOpen = !_settingsOpen),
              toggleKey: const Key('overlay-settings-expand'),
            ),
          ),
        ],
      ),
    );
  }

  static const _keyByGroup = {
    'notice': 'Notice',
    'fleetOverview': 'Squads',
    'members': 'Members',
    'chat': 'Chat',
    'events': 'Events',
    'crosshair': 'Crosshair',
  };

  void _selectGroup(String group) {
    setState(() {
      _group = group;
      _settingsOpen = true;
    });
    _editor.change(() => _editor.selectedKey = _keyByGroup[group]);
  }

  void _selectionChanged() {
    final group = _keyByGroup.entries
        .where((entry) => entry.value == _editor.selectedKey)
        .firstOrNull
        ?.key;
    if (mounted && group != null && (group != _group || !_settingsOpen)) {
      setState(() {
        _group = group;
        _settingsOpen = true;
      });
    }
  }

  Widget? _moduleStyleControls(OverlayWorkspaceProjection projection) {
    if (!const {
      'notice',
      'fleetOverview',
      'members',
      'chat',
      'events',
    }.contains(_group)) {
      return null;
    }
    final controls = OverlayWorkspaceModuleStyleControls(
      group: _group,
      layout: projection.layout,
      settings: projection.settings!,
      onLayoutChanged: (item, coalesce) =>
          widget.module.updateLayoutItem(item, coalesce: coalesce),
      onSettingChanged: widget.module.updateSetting,
    );
    return _group == 'members' && widget.roster != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              controls,
              OverlayRosterButton(port: widget.roster!),
            ],
          )
        : controls;
  }

  Future<void> _runRuntimeAction(OverlayWorkspaceProjection projection) async {
    final language = Localizations.localeOf(context).toLanguageTag();
    switch (projection.runtime.windowState) {
      case 'open':
      case 'suppressed':
      case 'opening':
        await widget.module.closeRuntime(language);
        return;
      case 'failed':
        await widget.module.retryRuntime(language);
        return;
      case 'unavailable':
        await widget.module.refreshRuntime(language);
        return;
      default:
        await widget.module.openRuntime(language);
        return;
    }
  }

  Future<void> _exportPreset(
    OverlayWorkspacePreset preset, {
    InteractionSource? source,
  }) async {
    source ??= currentStarBridgeActivationSource;
    final package = OverlayPresetTransfer(
      name: preset.shownName(AppStrings.of(context)),
      settings: preset.settings,
      layout: preset.layout,
      sources: preset.sources,
    ).serialize();
    await Clipboard.setData(ClipboardData(text: package));
    if (!mounted) return;
    showStarBridgeSnackBar(
      context,
      starBridgeTimedSnackBar(
        content: Text(_copy(context, 'overlay.workspace.exported')),
      ),
      source: source,
    );
  }

  Future<void> _importPreset(
    OverlayWorkspaceProjection projection, {
    InteractionSource? source,
  }) => runStarBridgeActivation<void>(
    source ?? currentStarBridgeActivationSource,
    () => _inspectAndImportPreset(projection, source: source),
  );

  Future<void> _inspectAndImportPreset(
    OverlayWorkspaceProjection projection, {
    InteractionSource? source,
  }) async {
    var importText = '';
    var inspectSource = source;
    final payload = await showStarBridgeDialog<String>(
      context,
      source: source,
      builder: (context) => AlertDialog(
        title: Text(_copy(context, 'overlay.workspace.importTitle')),
        scrollable: true,
        content: SizedBox(
          width: 560,
          child: StarBridgeFieldFrame(
            builder: (_, focus) => TextField(
              key: const Key('overlay-preset-import-text'),
              focusNode: focus,
              onChanged: (value) => importText = value,
              minLines: 8,
              maxLines: 14,
              decoration: InputDecoration(
                labelText: _copy(context, 'overlay.workspace.importLabel'),
                helperText: _copy(context, 'overlay.workspace.importHelp'),
              ),
            ),
          ),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog<String>(context, source: source),
            child: Text(_copy(context, 'overlay.workspace.cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            onActivate: (source) {
              inspectSource = source;
              dismissStarBridgeDialog(
                context,
                source: source,
                result: importText,
              );
            },
            child: Text(_copy(context, 'overlay.importPreview.inspect')),
          ),
        ],
      ),
    );
    if (payload == null || payload.trim().isEmpty) return;
    try {
      final package = OverlayPresetTransfer.parse(payload);
      // A legacy Host must not silently import a v2 package while losing its sources.
      if (package.sources != null &&
          projection.snapshot?.sourcePresetsEnabled != true) {
        throw const FormatException();
      }
      if (!mounted) return;
      final confirmed = await showStarBridgeDialog<bool>(
        context,
        source: inspectSource,
        builder: (_) => OverlayPresetImportPreview(
          name: package.name,
          settings: package.settings,
          layout: package.layout,
          sources: package.sources,
          removedOrganizationBindings: package.removedOrganizationBindings,
          currentSettings: projection.settings,
        ),
      );
      if (!mounted || confirmed != true) return;
      await widget.module.importPreset(
        name: package.name,
        settings: package.settings,
        layout: package.layout,
        sources: package.sources,
      );
    } on Object {
      if (!mounted) return;
      showStarBridgeSnackBar(
        context,
        starBridgeTimedSnackBar(
          content: Text(_copy(context, 'overlay.workspace.importInvalid')),
        ),
        source: currentStarBridgeActivationSource,
      );
    }
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.failure, required this.onRetry});

  final OverlaySettingsFailure? failure;
  final ValueChanged<InteractionSource>? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _copy(context, 'overlay.unavailable.title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(_failureText(context, failure)),
          const SizedBox(height: 16),
          StarBridgeActionButton(
            controlKey: const Key('overlay-workspace-reload'),
            kind: StarBridgeActionKind.primary,
            onActivate: onRetry,
            child: Text(_copy(context, 'overlay.retry')),
          ),
        ],
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.failure,
    required this.onRetry,
    required this.onDiscard,
  });

  final OverlaySettingsFailure failure;
  final ValueChanged<InteractionSource>? onRetry;

  /// Only while unsaved adjustments are held after a failed save.
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(_failureText(context, failure)),
    actions: [
      if (onDiscard case final discard?)
        StarBridgeActionButton(
          controlKey: const Key('overlay-workspace-discard-failed'),
          kind: StarBridgeActionKind.quiet,
          onActivate: (_) => discard(),
          child: Text(_copy(context, 'overlay.workspace.discard')),
        ),
      StarBridgeActionButton(
        controlKey: const Key('overlay-workspace-retry-failure'),
        kind: StarBridgeActionKind.quiet,
        onActivate: onRetry,
        child: Text(_copy(context, 'overlay.retry')),
      ),
    ],
  );
}

String _failureText(BuildContext context, OverlaySettingsFailure? failure) =>
    _copy(context, switch (failure) {
      OverlaySettingsFailure.writeConflict => 'overlay.error.writeConflict',
      OverlaySettingsFailure.invalidValue => 'overlay.error.invalidValue',
      OverlaySettingsFailure.writeFailed => 'overlay.error.writeFailed',
      OverlaySettingsFailure.readFailed => 'overlay.error.readFailed',
      OverlaySettingsFailure.versionUnsupported =>
        'overlay.error.versionUnsupported',
      _ => 'overlay.error.hostUnavailable',
    });

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);

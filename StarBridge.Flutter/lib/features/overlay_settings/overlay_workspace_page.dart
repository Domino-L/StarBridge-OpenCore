import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_settings_models.dart';
import 'overlay_preset_import_preview.dart';
import 'overlay_preset_transfer.dart';
import 'overlay_scene_controller.dart';
import 'overlay_scene_picker.dart';
import 'overlay_source_binding_field.dart';
import 'overlay_chat_sources_field.dart';
import 'overlay_source_limit_notice.dart';
import 'overlay_roster_editor.dart';
import 'overlay_workspace_appearance_center.dart';
import 'overlay_workspace_controls.dart';
import 'overlay_workspace_editor_state.dart';
import 'overlay_workspace_fullscreen.dart';
import 'overlay_workspace_group_navigation.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_module.dart';
import 'overlay_workspace_module_style_controls.dart';
import 'overlay_workspace_preset_bar.dart';
import 'overlay_workspace_preview_stage.dart';
import 'overlay_workspace_runtime_card.dart';
import 'overlay_workspace_schema.dart';

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
          return const Center(child: CircularProgressIndicator());
        }
        if (!projection.available) {
          return _Unavailable(
            failure: projection.failure,
            onRetry: widget.module.refresh,
          );
        }
        return _content(context, projection);
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
    return Stack(
      children: [
        if (_appearanceCenterOpen)
          OverlayWorkspaceAppearanceCenter(
            projection: projection,
            module: widget.module,
            onBack: () => setState(() => _appearanceCenterOpen = false),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 1280
                ? _wideWorkspace(context, projection, active, fields)
                : _compactWorkspace(context, projection, active, fields),
          ),
        Align(
          alignment: AlignmentDirectional.bottomCenter,
          child: MediaQuery.disableAnimationsOf(context)
              ? (projection.dirty
                    ? _SaveBar(projection: projection, module: widget.module)
                    : const SizedBox.shrink())
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  reverseDuration: const Duration(milliseconds: 100),
                  switchInCurve: const Cubic(0.16, 1, 0.3, 1),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, .15),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: projection.dirty
                      ? _SaveBar(projection: projection, module: widget.module)
                      : const SizedBox.shrink(),
                ),
        ),
      ],
    );
  }

  Widget _wideWorkspace(
    BuildContext context,
    OverlayWorkspaceProjection projection,
    OverlayWorkspacePreset active,
    List<OverlayWorkspaceFieldSpec> fields,
  ) => _workspace(context, projection, active, fields, wide: true);

  Widget _compactWorkspace(
    BuildContext context,
    OverlayWorkspaceProjection projection,
    OverlayWorkspacePreset active,
    List<OverlayWorkspaceFieldSpec> fields,
  ) => _workspace(context, projection, active, fields, wide: false);

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
          fields: fields,
          settings: projection.settings!,
          appearances: projection.snapshot!.appearances,
          onChanged: widget.module.updateSetting,
          onExperiencePreset: widget.module.applyExperiencePreset,
          footer: _moduleStyleControls(projection),
          header: _sourceField(projection),
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
    List<OverlayWorkspaceFieldSpec> fields, {
    required bool wide,
  }) {
    final tokens = context.tokens;
    final preview = OverlayWorkspacePreviewStage(
      key: _previewKey,
      projection: projection,
      fullscreenButton: _fullscreenButton,
      editor: _editor,
      module: widget.module,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, projection.dirty ? 76 : 12),
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
                  final runtime = OverlayWorkspaceRuntimeCard(
                    projection: projection,
                    compact: true,
                    onAction: () => _runRuntimeAction(projection),
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
              OverlayWorkspacePresetBar(
                scenes: widget.scenes,
                compact: true,
                showLegacyScene: widget.scenes == null,
                projection: projection,
                module: widget.module,
                onImport: () => _importPreset(projection),
                onExport: () => _exportPreset(active),
                onOpenAppearance: () =>
                    setState(() => _appearanceCenterOpen = true),
                sourceSelector: widget.scenes == null
                    ? null
                    : OverlayScenePicker(
                        controller: widget.scenes!,
                        compact: true,
                      ),
              ),
            ],
          ),
          if (projection.failure case final failure?)
            _Failure(failure: failure, onRetry: widget.module.refresh),
          if (projection.runtime.failureCode ==
              'overlay.sources_limit_exceeded')
            OverlaySourceLimitNotice(
              module: widget.module,
              scenes: widget.scenes,
            ),
          const SizedBox(height: 12),
          Expanded(
            key: const Key('overlay-workspace-content'),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 190,
                        child: OverlayWorkspaceGroupNavigation(
                          selected: _group,
                          onSelected: _selectGroup,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: preview),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 380,
                        child: _settings(projection, fields),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('overlay-group-compact-$_group'),
                              initialValue: _group,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true),
                              items: [
                                for (final group
                                    in overlayWorkspaceNavigationGroupOrder)
                                  DropdownMenuItem(
                                    value: group,
                                    child: Text(
                                      overlayWorkspaceGroupName(context, group),
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) _selectGroup(value);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            key: const Key('overlay-settings-expand'),
                            onPressed: () =>
                                setState(() => _settingsOpen = !_settingsOpen),
                            child: Text(
                              _copy(
                                context,
                                _settingsOpen
                                    ? 'overlay.workspace.hideSettings'
                                    : 'overlay.workspace.showSettings',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(child: preview),
                            if (_settingsOpen)
                              Align(
                                alignment: Alignment.centerRight,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 380,
                                  ),
                                  child: Material(
                                    elevation: 8,
                                    color: tokens.surfaces.panel.fill,
                                    child: _settings(projection, fields),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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

  Future<void> _exportPreset(OverlayWorkspacePreset preset) async {
    final package = OverlayPresetTransfer(
      name: preset.name,
      settings: preset.settings,
      layout: preset.layout,
      sources: preset.sources,
    ).serialize();
    await Clipboard.setData(ClipboardData(text: package));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_copy(context, 'overlay.workspace.exported'))),
    );
  }

  Future<void> _importPreset(OverlayWorkspaceProjection projection) async {
    var importText = '';
    final payload = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_copy(context, 'overlay.workspace.importTitle')),
        scrollable: true,
        content: SizedBox(
          width: 560,
          child: TextField(
            onChanged: (value) => importText = value,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              labelText: _copy(context, 'overlay.workspace.importLabel'),
              helperText: _copy(context, 'overlay.workspace.importHelp'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_copy(context, 'overlay.workspace.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, importText),
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
      final confirmed = await showDialog<bool>(
        context: context,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_copy(context, 'overlay.workspace.importInvalid')),
        ),
      );
    }
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.projection, required this.module});

  final OverlayWorkspaceProjection projection;
  final OverlayWorkspaceModule module;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      elevation: 12,
      color: tokens.surfaces.floating.fill,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.xl,
            vertical: tokens.space.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (projection.busy) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: tokens.space.sm),
              ],
              Text(
                _copy(
                  context,
                  projection.dirty
                      ? 'overlay.workspace.dirty'
                      : 'overlay.workspace.saved',
                ),
              ),
              SizedBox(width: tokens.space.md),
              IconButton(
                tooltip: _copy(context, 'overlay.workspace.undo'),
                onPressed: module.canUndo && !projection.busy
                    ? module.undo
                    : null,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.undo),
              ),
              IconButton(
                tooltip: _copy(context, 'overlay.workspace.redo'),
                onPressed: module.canRedo && !projection.busy
                    ? module.redo
                    : null,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.redo),
              ),
              SizedBox(width: tokens.space.xs),
              TextButton(
                onPressed: projection.dirty && !projection.busy
                    ? module.discardChanges
                    : null,
                child: Text(_copy(context, 'overlay.workspace.discard')),
              ),
              SizedBox(width: tokens.space.xs),
              FilledButton(
                key: const Key('overlay-workspace-save'),
                onPressed: projection.dirty && !projection.busy
                    ? module.save
                    : null,
                child: Text(_copy(context, 'overlay.workspace.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.failure, required this.onRetry});

  final OverlaySettingsFailure? failure;
  final VoidCallback onRetry;

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
          FilledButton(
            onPressed: onRetry,
            child: Text(_copy(context, 'overlay.retry')),
          ),
        ],
      ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.failure, required this.onRetry});

  final OverlaySettingsFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(_failureText(context, failure)),
    actions: [
      TextButton(
        onPressed: onRetry,
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
      _ => 'overlay.error.hostUnavailable',
    });

String _copy(BuildContext context, String key) =>
    AppStrings.of(context).text(key);
